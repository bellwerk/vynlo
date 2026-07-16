import { rm } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";

const entryPoint = fileURLToPath(new URL("./src/index.ts", import.meta.url));
const outputDirectory = new URL("./dist/", import.meta.url);
const outputFile = new URL("./dist/index.js", import.meta.url);

await rm(outputDirectory, { force: true, recursive: true });
await build({
  bundle: true,
  entryPoints: [entryPoint],
  format: "esm",
  logLevel: "info",
  outfile: fileURLToPath(outputFile),
  packages: "bundle",
  platform: "node",
  sourcemap: true,
  target: "node24",
});

const builtWorker = await import(`${outputFile.href}?smoke=${Date.now()}`);
if (
  !Array.isArray(builtWorker.WORKER_JOB_TYPES) ||
  builtWorker.WORKER_JOB_TYPES.length !== 2 ||
  builtWorker.WORKER_JOB_TYPES[0] !== "documents.render_preview" ||
  builtWorker.WORKER_JOB_TYPES[1] !== "auth.invitation.deliver"
) {
  throw new Error("The bundled worker failed its import-safe smoke assertion.");
}
