import { getWorkerHealth } from "./health";

process.stdout.write(`${JSON.stringify(getWorkerHealth())}\n`);
