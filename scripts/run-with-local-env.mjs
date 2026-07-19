import { existsSync } from "node:fs";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const repositoryRoot = fileURLToPath(new URL("../", import.meta.url));
const localEnvironmentFile = fileURLToPath(
  new URL("../.env.local", import.meta.url),
);
const [executable, ...arguments_] = process.argv.slice(2);

if (executable === undefined) {
  throw new TypeError("A child executable is required.");
}

if (existsSync(localEnvironmentFile)) {
  process.loadEnvFile(localEnvironmentFile);
}

const child = spawn(executable, arguments_, {
  cwd: process.cwd(),
  env: process.env,
  stdio: "inherit",
  windowsHide: true,
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.once(signal, () => {
    if (!child.killed) {
      child.kill(signal);
    }
  });
}

child.once("error", (error) => {
  process.stderr.write(
    `Unable to start the local process from ${repositoryRoot}: ${error.message}\n`,
  );
  process.exitCode = 1;
});

child.once("exit", (code, signal) => {
  if (signal !== null) {
    process.kill(process.pid, signal);
    return;
  }
  process.exitCode = code ?? 1;
});
