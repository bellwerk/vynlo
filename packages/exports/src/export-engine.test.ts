import { describe, expect, it } from "vitest";

import {
  EXPORT_STEP_UP_MAX_AGE_MS,
  ExportDefinitionError,
  authorizeExportRun,
  compileExportDefinition,
  createExportRunMetadata,
  generateExportArtifact,
  normalizeExportFilters,
  resolveLocalizedLabel,
  sha256Hex,
  type CompiledExportDefinition,
  type ExportDefinitionPolicy,
} from "./export-engine";

const NOW = Date.parse("2026-07-16T18:00:00.000Z");
const textDecoder = new TextDecoder();

const policy: ExportDefinitionPolicy = {
  allowedSourcesByEntity: {
    inventory_unit: [
      "inventory_unit.stock_number",
      "inventory_unit.currency_code",
      "vehicle.vin",
      "metrics.total_cost_minor",
      "metrics.estimated_gross",
      "notes.internal",
    ],
  },
  allowedFiltersByEntity: {
    inventory_unit: ["include_archived", "location_id", "states"],
  },
  allowedPermissions: [
    "exports.run",
    "exports.run_sensitive",
    "exports.read",
    "inventory.read_internal",
  ],
  maxRows: 10,
};

function definitionInput(options: { sensitive?: boolean } = {}): unknown {
  return {
    schema_version: "1.1",
    export: {
      key: "inventory_summary",
      version: "1.2.3",
      labels: { en: "Inventory summary", fr: "Sommaire d’inventaire" },
      entity: "inventory_unit",
      formats: ["csv", "xlsx"],
      columns: [
        {
          key: "stock_number",
          labels: { en: "Stock number", fr: "Numéro de stock" },
          source: "inventory_unit.stock_number",
          format: "text",
        },
        {
          key: "total_cost_minor",
          labels: {
            en: "Total cost (minor units)",
            fr: "Coût total (unités mineures)",
          },
          source: "metrics.total_cost_minor",
          format: "minor_units",
          sensitive: options.sensitive ?? false,
          ...(options.sensitive
            ? { permission: "inventory.read_internal" }
            : {}),
        },
        {
          key: "currency_code",
          labels: { en: "Currency", fr: "Devise" },
          source: "inventory_unit.currency_code",
          format: "currency_code",
        },
        {
          key: "internal_note",
          labels: { en: "Internal note", fr: "Note interne" },
          source: "notes.internal",
          format: "text",
          nullable: true,
        },
      ],
      default_filters: { include_archived: false },
      available_filters: ["location_id", "states"],
      security: {
        permission: "exports.read",
        audit_required: true,
        links_expire: true,
      },
      activation_gate: "approved_export",
    },
  };
}

function compile(
  options: { sensitive?: boolean } = {},
): CompiledExportDefinition {
  return compileExportDefinition(definitionInput(options), policy);
}

function permissions(sensitive = false): readonly string[] {
  return sensitive
    ? [
        "exports.run",
        "exports.run_sensitive",
        "exports.read",
        "inventory.read_internal",
      ]
    : ["exports.run", "exports.read"];
}

function rows(note = "Ready"): readonly Readonly<Record<string, unknown>>[] {
  return [
    {
      "inventory_unit.stock_number": "P042",
      "metrics.total_cost_minor": 9_007_199_254_740_993_123_456n,
      "inventory_unit.currency_code": "CAD",
      "notes.internal": note,
    },
  ];
}

function generate(
  definition: CompiledExportDefinition,
  format: "csv" | "xlsx",
  options: { note?: string; sensitive?: boolean } = {},
) {
  return generateExportArtifact({
    definition,
    format,
    locale: "fr-CA",
    rows: rows(options.note),
    authorization: {
      grantedPermissions: permissions(options.sensitive),
      strongAuthAt: NOW - 1_000,
      now: NOW,
    },
  });
}

function zipEntries(bytes: Uint8Array): Readonly<Record<string, Uint8Array>> {
  const entries: Record<string, Uint8Array> = {};
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let offset = 0;
  while (
    offset + 4 <= bytes.length &&
    view.getUint32(offset, true) === 0x04034b50
  ) {
    const compression = view.getUint16(offset + 8, true);
    const size = view.getUint32(offset + 18, true);
    const nameLength = view.getUint16(offset + 26, true);
    const extraLength = view.getUint16(offset + 28, true);
    expect(compression).toBe(0);
    const nameStart = offset + 30;
    const contentStart = nameStart + nameLength + extraLength;
    const name = textDecoder.decode(
      bytes.slice(nameStart, nameStart + nameLength),
    );
    entries[name] = bytes.slice(contentStart, contentStart + size);
    offset = contentStart + size;
  }
  expect(view.getUint32(offset, true)).toBe(0x02014b50);
  return entries;
}

describe("@vynlo/exports definition compiler", () => {
  it("T-EXP-001 compiles an immutable exact version with a canonical checksum", () => {
    const first = compile();
    const reordered = compileExportDefinition(
      {
        export: (definitionInput() as { export: unknown }).export,
        schema_version: "1.1",
      },
      policy,
    );

    expect(first).toMatchObject({
      key: "inventory_summary",
      version: "1.2.3",
      entity: "inventory_unit",
      formats: ["csv", "xlsx"],
    });
    expect(first.definitionChecksum).toBe(reordered.definitionChecksum);
    expect(Object.isFrozen(first)).toBe(true);
    expect(Object.isFrozen(first.columns)).toBe(true);
  });

  it("T-EXP-001 rejects unknown properties and ambiguous column modes", () => {
    const unknown = definitionInput() as {
      export: Record<string, unknown>;
    };
    unknown.export.query = "select * from secrets";
    expect(() => compileExportDefinition(unknown, policy)).toThrowError(
      /EXPORT_UNKNOWN_PROPERTY/,
    );

    const ambiguous = definitionInput() as {
      export: Record<string, unknown>;
    };
    ambiguous.export.profiles = {
      default_profile: { columns: ambiguous.export.columns },
    };
    expect(() => compileExportDefinition(ambiguous, policy)).toThrowError(
      /EXPORT_COLUMN_MODE_INVALID/,
    );
  });

  it("T-EXP-001 permits only exact allowlisted source paths", () => {
    const malicious = definitionInput() as {
      export: { columns: Array<Record<string, unknown>> };
    };
    malicious.export.columns[0]!.source = "inventory_unit.constructor";
    expect(() => compileExportDefinition(malicious, policy)).toThrowError(
      /EXPORT_SOURCE_NOT_ALLOWED/,
    );

    malicious.export.columns[0]!.source =
      "inventory_unit.stock_number);DROP_TABLE";
    expect(() => compileExportDefinition(malicious, policy)).toThrowError(
      /EXPORT_STRING_INVALID/,
    );
  });

  it("T-EXP-001 rejects formula formats and non-allowlisted permissions", () => {
    const formula = definitionInput() as {
      export: { columns: Array<Record<string, unknown>> };
    };
    formula.export.columns[0]!.format = "formula";
    expect(() => compileExportDefinition(formula, policy)).toThrowError(
      /EXPORT_FORMAT_NOT_ALLOWED/,
    );

    const permission = definitionInput() as {
      export: { columns: Array<Record<string, unknown>> };
    };
    permission.export.columns[0]!.permission = "tenant.execute_anything";
    expect(() => compileExportDefinition(permission, policy)).toThrowError(
      /EXPORT_PERMISSION_NOT_ALLOWED/,
    );
  });

  it("T-EXP-001 validates profile selection independently", () => {
    const input = definitionInput() as {
      export: Record<string, unknown>;
    };
    const columns = input.export.columns;
    delete input.export.columns;
    input.export.profiles = {
      accounting: {
        labels: { en: "Accounting", fr: "Comptabilité" },
        columns,
        security: {
          permission: "inventory.read_internal",
          step_up_required: true,
        },
      },
    };
    const definition = compileExportDefinition(input, policy);
    expect(() =>
      authorizeExportRun(definition, {
        grantedPermissions: permissions(true),
        strongAuthAt: NOW,
        now: NOW,
      }),
    ).toThrowError(/EXPORT_PROFILE_REQUIRED/);
    expect(
      authorizeExportRun(
        definition,
        {
          grantedPermissions: permissions(true),
          strongAuthAt: NOW,
          now: NOW,
        },
        "accounting",
      ).allowed,
    ).toBe(true);
  });

  it("T-EXP-001 resolves exact, language, fallback, and deterministic labels", () => {
    expect(
      resolveLocalizedLabel(
        { en: "Inventory", fr: "Inventaire" },
        "fr-CA",
        "inventory_summary",
      ),
    ).toBe("Inventaire");
    expect(resolveLocalizedLabel({ en: "Inventory" }, "de", "fallback")).toBe(
      "Inventory",
    );
  });

  it("T-EXP-001 rejects audit or expiry bypass in a definition", () => {
    for (const [key, expected] of [
      ["audit_required", "EXPORT_AUDIT_REQUIRED"],
      ["links_expire", "EXPORT_EXPIRY_REQUIRED"],
    ] as const) {
      const input = definitionInput() as {
        export: { security: Record<string, unknown> };
      };
      input.export.security[key] = false;
      expect(() => compileExportDefinition(input, policy)).toThrowError(
        new RegExp(expected),
      );
    }
  });
});

describe("@vynlo/exports generation", () => {
  it("T-EXP-001 emits deterministic localized CSV with exact money and currency", () => {
    const definition = compile();
    const first = generate(definition, "csv");
    const second = generate(definition, "csv");
    const csv = textDecoder.decode(first.bytes);

    expect(first.bytes).toEqual(second.bytes);
    expect(first.checksum).toBe(second.checksum);
    expect([...first.bytes.slice(0, 3)]).toEqual([0xef, 0xbb, 0xbf]);
    expect(csv).toContain('"Numéro de stock"');
    expect(csv).toContain('"9007199254740993123456"');
    expect(csv).toContain('"CAD"');
    expect(csv.endsWith("\r\n")).toBe(true);
  });

  it.each(['=HYPERLINK("https://evil.invalid")', "+1+1", "-2+3", "@SUM(A1)"])(
    "T-EXP-001 neutralizes CSV formula payload %s",
    (payload) => {
      const csv = textDecoder.decode(
        generate(compile(), "csv", { note: payload }).bytes,
      );
      expect(csv).toContain(`"'${payload.replaceAll('"', '""')}"`);
    },
  );

  it("T-EXP-001 rejects binary-float and unsafe-number money inputs", () => {
    const definition = compile();
    for (const invalid of [12.34, Number.MAX_SAFE_INTEGER + 1]) {
      expect(() =>
        generateExportArtifact({
          definition,
          format: "csv",
          locale: "en",
          rows: [
            {
              "inventory_unit.stock_number": "P001",
              "metrics.total_cost_minor": invalid,
              "inventory_unit.currency_code": "CAD",
              "notes.internal": null,
            },
          ],
          authorization: { grantedPermissions: permissions() },
        }),
      ).toThrowError(/EXPORT_EXACT_INTEGER_REQUIRED/);
    }
  });

  it("T-EXP-001 emits deterministic genuine XLSX Open XML bytes without formulas", () => {
    const definition = compile();
    const first = generate(definition, "xlsx", {
      note: '=HYPERLINK("https://evil.invalid")',
    });
    const second = generate(definition, "xlsx", {
      note: '=HYPERLINK("https://evil.invalid")',
    });
    const entries = zipEntries(first.bytes);

    expect([...first.bytes.slice(0, 4)]).toEqual([0x50, 0x4b, 0x03, 0x04]);
    expect(first.bytes).toEqual(second.bytes);
    expect(Object.keys(entries).sort()).toEqual([
      "[Content_Types].xml",
      "_rels/.rels",
      "xl/_rels/workbook.xml.rels",
      "xl/workbook.xml",
      "xl/worksheets/sheet1.xml",
    ]);
    const contentTypes = textDecoder.decode(entries["[Content_Types].xml"]);
    const sheet = textDecoder.decode(entries["xl/worksheets/sheet1.xml"]);
    expect(contentTypes).toContain(
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
    );
    expect(sheet).toContain('t="inlineStr"');
    expect(sheet).toContain("9007199254740993123456");
    expect(sheet).toContain("=HYPERLINK");
    expect(sheet).not.toContain("<f>");
  });

  it("T-EXP-001 rejects accessors instead of executing row getters", () => {
    const row: Record<string, unknown> = {
      "metrics.total_cost_minor": "100",
      "inventory_unit.currency_code": "CAD",
      "notes.internal": null,
    };
    let called = false;
    Object.defineProperty(row, "inventory_unit.stock_number", {
      enumerable: true,
      get() {
        called = true;
        return "P001";
      },
    });
    expect(() =>
      generateExportArtifact({
        definition: compile(),
        format: "csv",
        locale: "en",
        rows: [row],
        authorization: { grantedPermissions: permissions() },
      }),
    ).toThrowError(/EXPORT_ACCESSOR_FORBIDDEN/);
    expect(called).toBe(false);
  });

  it("T-EXP-001 enforces the bounded row limit", () => {
    expect(() =>
      generateExportArtifact({
        definition: compile(),
        format: "csv",
        locale: "en",
        rows: Array.from({ length: 11 }, () => rows()[0]!),
        authorization: { grantedPermissions: permissions() },
      }),
    ).toThrowError(/EXPORT_ROW_LIMIT_EXCEEDED/);
  });
});

describe("@vynlo/exports authorization and metadata", () => {
  it("T-EXP-002 reports missing permissions without silently dropping columns", () => {
    const definition = compile({ sensitive: true });
    const decision = authorizeExportRun(definition, {
      grantedPermissions: ["exports.run", "exports.read"],
      strongAuthAt: NOW,
      now: NOW,
    });
    expect(decision).toMatchObject({
      allowed: false,
      code: "EXPORT_PERMISSION_REQUIRED",
      requiresStepUp: true,
      stepUpSatisfied: true,
    });
    expect(decision.missingPermissions).toEqual([
      "exports.run_sensitive",
      "inventory.read_internal",
    ]);
  });

  it("T-EXP-002 rejects stale assurance and accepts exactly fifteen minutes", () => {
    const definition = compile({ sensitive: true });
    expect(
      authorizeExportRun(definition, {
        grantedPermissions: permissions(true),
        strongAuthAt: NOW - EXPORT_STEP_UP_MAX_AGE_MS - 1,
        now: NOW,
      }).code,
    ).toBe("EXPORT_STEP_UP_REQUIRED");
    expect(
      authorizeExportRun(definition, {
        grantedPermissions: permissions(true),
        strongAuthAt: NOW - EXPORT_STEP_UP_MAX_AGE_MS,
        now: NOW,
      }).allowed,
    ).toBe(true);
    expect(
      authorizeExportRun(definition, {
        grantedPermissions: permissions(true),
        strongAuthAt: NOW + 1,
        now: NOW,
      }).code,
    ).toBe("EXPORT_STEP_UP_REQUIRED");
  });

  it("T-EXP-002 prevents generation when authorization fails", () => {
    expect(() =>
      generateExportArtifact({
        definition: compile({ sensitive: true }),
        format: "csv",
        locale: "en",
        rows: rows(),
        authorization: {
          grantedPermissions: permissions(true),
          strongAuthAt: NOW - EXPORT_STEP_UP_MAX_AGE_MS - 1,
          now: NOW,
        },
      }),
    ).toThrowError(/EXPORT_STEP_UP_REQUIRED/);
  });

  it("T-EXP-001 normalizes only allowlisted and definition-available filters", () => {
    const definition = compile();
    expect(
      normalizeExportFilters(definition, {
        states: ["available", "reserved"],
        location_id: "loc_001",
      }),
    ).toEqual({
      include_archived: false,
      location_id: "loc_001",
      states: ["available", "reserved"],
    });
    expect(() =>
      normalizeExportFilters(definition, { include_archived: true }),
    ).toThrowError(/EXPORT_FILTER_NOT_AVAILABLE/);
    expect(() =>
      normalizeExportFilters(definition, { sql: "1=1" }),
    ).toThrowError(/EXPORT_FILTER_NOT_AVAILABLE/);
  });

  it("T-EXP-001 pins checksums, filters, actor, row count, and expiry in run metadata", () => {
    const definition = compile();
    const artifact = generate(definition, "csv");
    const metadata = createExportRunMetadata(definition, artifact, {
      workspaceId: "workspace_001",
      actorId: "actor_001",
      filters: { location_id: "location_002" },
      createdAt: NOW,
      expiresAt: NOW + 60_000,
    });
    expect(metadata).toMatchObject({
      definitionKey: "inventory_summary",
      definitionVersion: "1.2.3",
      definitionChecksum: definition.definitionChecksum,
      artifactChecksum: artifact.checksum,
      rowCount: 1,
      byteCount: artifact.byteCount,
      filters: { include_archived: false, location_id: "location_002" },
      auditRequired: true,
      createdAt: "2026-07-16T18:00:00.000Z",
      expiresAt: "2026-07-16T18:01:00.000Z",
    });
    expect(metadata.filtersChecksum).toMatch(/^[a-f0-9]{64}$/);
  });

  it("T-EXP-002 requires an expiring authorized download metadata record", () => {
    const definition = compile();
    const artifact = generate(definition, "csv");
    expect(() =>
      createExportRunMetadata(definition, artifact, {
        workspaceId: "workspace_001",
        actorId: "actor_001",
        createdAt: NOW,
      }),
    ).toThrowError(/EXPORT_EXPIRY_REQUIRED/);
    expect(() =>
      createExportRunMetadata(definition, artifact, {
        workspaceId: "workspace_001",
        actorId: "actor_001",
        createdAt: NOW,
        expiresAt: NOW,
      }),
    ).toThrowError(/EXPORT_EXPIRY_INVALID/);
  });

  it("T-EXP-001 verifies the dependency-free SHA-256 implementation", () => {
    expect(sha256Hex("abc")).toBe(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    );
  });

  it("exposes structured errors for adapters without leaking row data", () => {
    try {
      compileExportDefinition({ schema_version: "9.9", export: {} }, policy);
      throw new Error("expected compile failure");
    } catch (error) {
      expect(error).toBeInstanceOf(ExportDefinitionError);
      expect(error).toMatchObject({
        code: "EXPORT_SCHEMA_VERSION_UNSUPPORTED",
        path: "$.schema_version",
      });
      expect(String(error)).not.toContain("customer");
    }
  });
});
