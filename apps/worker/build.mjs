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
  external: ["sharp"],
  format: "esm",
  logLevel: "info",
  outfile: fileURLToPath(outputFile),
  packages: "bundle",
  platform: "node",
  sourcemap: true,
  target: "node24",
});

const builtWorker = await import(`${outputFile.href}?smoke=${Date.now()}`);
const enabledMediaJobTypes = builtWorker.enabledWorkerJobTypes({
  mediaProcessing: { enabled: true },
});
if (
  !Array.isArray(builtWorker.WORKER_JOB_TYPES) ||
  builtWorker.WORKER_JOB_TYPES.length !== 9 ||
  builtWorker.WORKER_JOB_TYPES[0] !== "documents.render_preview" ||
  builtWorker.WORKER_JOB_TYPES[1] !== "auth.invitation.deliver" ||
  builtWorker.WORKER_JOB_TYPES[2] !== "inventory.vin_decode" ||
  builtWorker.WORKER_JOB_TYPES[3] !== "media.verify_vehicle_photo_upload" ||
  builtWorker.WORKER_JOB_TYPES[4] !== "media.verify_legal_original" ||
  builtWorker.WORKER_JOB_TYPES[5] !== "media.process_vehicle_photo" ||
  builtWorker.WORKER_JOB_TYPES[6] !== "media.delete_retained_raw" ||
  builtWorker.WORKER_JOB_TYPES[7] !== "media.delete_quarantine_upload" ||
  builtWorker.WORKER_JOB_TYPES[8] !==
    "media.delete_legal_original_quarantine" ||
  enabledMediaJobTypes.includes("media.delete_retained_raw") ||
  enabledMediaJobTypes.includes("media.delete_quarantine_upload") ||
  enabledMediaJobTypes.includes("media.delete_legal_original_quarantine")
) {
  throw new Error("The bundled worker failed its import-safe smoke assertion.");
}
