import { readFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const seed = await readFile(path.join(root, "supabase", "seed.sql"), "utf8");
const fixtureIds =
  seed.match(/["'(]([12]0000000-0000-4000-8000-00000000000[12])["')]/g) ?? [];
const prohibited = [/drivven/i, /auto\s*bs/i, /@(?:drivven|autobs)\./i];

if (new Set(fixtureIds).size !== 2) {
  throw new Error(
    "Stage 0 seed must contain exactly two stable synthetic workspace IDs.",
  );
}
if (prohibited.some((pattern) => pattern.test(seed))) {
  throw new Error("Stage 0 seed contains a tenant-specific identifier.");
}
console.log("stage0_supabase_foundation: pass");
