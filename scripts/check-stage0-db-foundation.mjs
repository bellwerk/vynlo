import { readFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const seed = await readFile(path.join(root, "supabase", "seed.sql"), "utf8");
const fixtureIds =
  seed.match(/["'(]([12]0000000-0000-4000-8000-00000000000[12])["')]/g) ?? [];

if (new Set(fixtureIds).size !== 2) {
  throw new Error(
    "Stage 0 seed must contain exactly two stable synthetic workspace IDs.",
  );
}
console.log("stage0_supabase_foundation: pass");
