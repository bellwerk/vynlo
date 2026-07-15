import { createLogger } from "@vynlo/observability";
import { getWorkerHealth } from "./health";

const logger = createLogger("worker");
logger.info("worker foundation started", getWorkerHealth());
