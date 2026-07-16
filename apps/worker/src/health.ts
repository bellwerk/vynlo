export interface WorkerHealth {
  readonly service: "worker";
  readonly status: "ok";
}

export function getWorkerHealth(): WorkerHealth {
  return { service: "worker", status: "ok" };
}
