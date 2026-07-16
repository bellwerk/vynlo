import { describe, expect, it } from "vitest";
import { getWorkerHealth } from "./health";

describe("worker health", () => {
  it("reports a deterministic healthy status", () => {
    expect(getWorkerHealth()).toEqual({ service: "worker", status: "ok" });
  });
});
