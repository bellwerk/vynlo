// VYN-NUM-001, T-NUM-001
// Run only against a disposable local or staging database after all migrations
// and synthetic seeds. The probe intentionally commits permanent numbers.
import { randomUUID } from "node:crypto";

import pg from "pg";

const { Pool } = pg;

function required(name, fallback) {
  const value = process.env[name]?.trim() || fallback;
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function integer(name, fallback) {
  const value = Number(process.env[name] ?? fallback);
  if (!Number.isSafeInteger(value) || value < 100 || value > 500) {
    throw new Error(`${name} must be an integer between 100 and 500`);
  }
  return value;
}

const connectionString = required("SUPABASE_TEST_DATABASE_URL");
const workspaceId = required(
  "VYNLO_TEST_WORKSPACE_ID",
  "10000000-0000-4000-8000-000000000001",
);
const stockDefinitionId = required(
  "VYNLO_TEST_STOCK_DEFINITION_ID",
  "71000000-0000-4000-8000-000000000001",
);
const actorUserId = required(
  "VYNLO_TEST_ACTOR_USER_ID",
  "31000000-0000-4000-8000-000000000001",
);
const currencyCode = required("VYNLO_TEST_CURRENCY_CODE", "CAD");
const allocationCount = integer("VYNLO_STOCK_CONCURRENCY", 100);
const runId = randomUUID();
const keyPrefix = `t-num-001:${runId}`;
const startedAt = Date.now();

const pool = new Pool({
  allowExitOnIdle: true,
  connectionString,
  connectionTimeoutMillis: 30_000,
  idleTimeoutMillis: 10_000,
  max: allocationCount + 2,
  maxLifetimeSeconds: 120,
  ssl:
    process.env.SUPABASE_TEST_DATABASE_SSL === "disable"
      ? false
      : { rejectUnauthorized: false },
});

const claims = JSON.stringify({
  aal: "aal2",
  amr: [{ method: "totp", timestamp: Math.floor(Date.now() / 1000) }],
  role: "authenticated",
  sub: actorUserId,
});

function syntheticVin() {
  return randomUUID().replaceAll("-", "").slice(0, 17).toUpperCase();
}

async function allocate({ idempotencyKey, shouldCommit }) {
  const client = await pool.connect();
  const allocationStartedAt = Date.now();
  try {
    await client.query("begin");
    await client.query("set local statement_timeout = '30s'");
    await client.query(
      `select
         pg_catalog.set_config('request.jwt.claim.sub', $1, true),
         pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true),
         pg_catalog.set_config('request.jwt.claims', $2, true)`,
      [actorUserId, claims],
    );
    const result = await client.query(
      `select inventory_unit_id, stock_number
       from app.create_inventory_unit(
         $1::uuid, $2::uuid, $3::text, $4::text, 2026,
         'Synthetic', 'Concurrency probe', null, null, null,
         $5::text, null, null, $6::text, $7::uuid
       )`,
      [
        workspaceId,
        stockDefinitionId,
        idempotencyKey,
        syntheticVin(),
        currencyCode,
        `request:${idempotencyKey}`,
        randomUUID(),
      ],
    );
    const row = result.rows[0];
    if (
      result.rowCount !== 1 ||
      typeof row?.inventory_unit_id !== "string" ||
      typeof row.stock_number !== "string"
    ) {
      throw new Error("allocation returned an invalid result");
    }
    await client.query(shouldCommit ? "commit" : "rollback");
    return {
      durationMs: Date.now() - allocationStartedAt,
      inventoryUnitId: row.inventory_unit_id,
      stockNumber: row.stock_number,
    };
  } catch (error) {
    await client.query("rollback").catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

try {
  const attempts = Array.from({ length: allocationCount }, (_, index) =>
    allocate({
      idempotencyKey: `${keyPrefix}:parallel:${String(index + 1).padStart(3, "0")}`,
      shouldCommit: true,
    }),
  );
  const settled = await Promise.allSettled(attempts);
  const failures = settled.flatMap((result, index) =>
    result.status === "rejected"
      ? [
          {
            index: index + 1,
            message:
              result.reason instanceof Error
                ? result.reason.message
                : "unknown allocation failure",
          },
        ]
      : [],
  );
  if (failures.length > 0) {
    throw new AggregateError(
      failures.map(({ message }) => new Error(message)),
      `${failures.length} concurrent allocations failed`,
    );
  }

  const allocations = settled.map((result) => {
    if (result.status !== "fulfilled") {
      throw new Error("unreachable rejected allocation");
    }
    return result.value;
  });
  const resultStockNumbers = new Set(
    allocations.map(({ stockNumber }) => stockNumber),
  );
  const resultInventoryIds = new Set(
    allocations.map(({ inventoryUnitId }) => inventoryUnitId),
  );
  if (
    resultStockNumbers.size !== allocationCount ||
    resultInventoryIds.size !== allocationCount
  ) {
    throw new Error("concurrent allocation results were not unique");
  }

  const persisted = await pool.query(
    `select
       pg_catalog.count(*)::integer as allocation_count,
       pg_catalog.count(distinct formatted_value)::integer as stock_count,
       pg_catalog.max(sequence_value) - pg_catalog.min(sequence_value) as span
     from public.stock_number_allocations
     where workspace_id = $1::uuid
       and definition_id = $2::uuid
       and idempotency_key like $3 escape '\\'`,
    [workspaceId, stockDefinitionId, `${keyPrefix}:parallel:%`],
  );
  const persistedRow = persisted.rows[0];
  if (
    persistedRow?.allocation_count !== allocationCount ||
    persistedRow.stock_count !== allocationCount ||
    BigInt(persistedRow.span) !== BigInt(allocationCount - 1)
  ) {
    throw new Error(
      "persisted allocation sequence is not unique and contiguous",
    );
  }

  const rolledBack = await allocate({
    idempotencyKey: `${keyPrefix}:rollback`,
    shouldCommit: false,
  });
  const afterRollback = await allocate({
    idempotencyKey: `${keyPrefix}:after-rollback`,
    shouldCommit: true,
  });
  if (afterRollback.stockNumber !== rolledBack.stockNumber) {
    throw new Error("rolled-back allocation burned a permanent stock number");
  }

  const durations = allocations.map(({ durationMs }) => durationMs);
  process.stdout.write(
    `${JSON.stringify(
      {
        allocationCount,
        elapsedMs: Date.now() - startedAt,
        maxAllocationLatencyMs: Math.max(...durations),
        minAllocationLatencyMs: Math.min(...durations),
        result: "pass",
        rollbackReusedStockNumber: afterRollback.stockNumber,
        runId,
      },
      null,
      2,
    )}\n`,
  );
} finally {
  await pool.end();
}
