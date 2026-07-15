import { readFile, readdir } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const packageRoot = path.join(root, "packages");
const forbidden = [
  /tenant-seeds[\\/]+drivven/i,
  /workspace\s*(?:===|==)\s*["']drivven["']/i,
];
const extensions = new Set([".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"]);
const failures = [];

async function walk(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isSymbolicLink() || entry.name === "node_modules") continue;
    if (entry.isDirectory()) await walk(fullPath);
    else if (extensions.has(path.extname(entry.name))) {
      const source = await readFile(fullPath, "utf8");
      if (forbidden.some((pattern) => pattern.test(source)))
        failures.push(path.relative(root, fullPath));
    }
  }
}

await walk(packageRoot);
if (failures.length > 0) {
  console.error(
    `Forbidden tenant dependency or identity branch in:\n${failures.join("\n")}`,
  );
  process.exit(1);
}
console.log("package_boundaries: pass");
