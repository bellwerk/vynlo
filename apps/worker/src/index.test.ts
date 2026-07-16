import { pathToFileURL } from "node:url";

import { describe, expect, it } from "vitest";

import { isDirectWorkerEntrypoint, WORKER_JOB_TYPES } from "./index";

describe("worker entrypoint", () => {
  it("registers the preview and invitation delivery job types", () => {
    expect(WORKER_JOB_TYPES).toEqual([
      "documents.render_preview",
      "auth.invitation.deliver",
    ]);
  });

  it("starts only when the module is the direct process entry", () => {
    const entry = "C:\\workspace\\apps\\worker\\dist\\index.js";
    expect(isDirectWorkerEntrypoint(pathToFileURL(entry).href, entry)).toBe(
      true,
    );
    expect(
      isDirectWorkerEntrypoint(
        "file:///workspace/apps/worker/dist/index.js",
        "C:\\workspace\\vitest.js",
      ),
    ).toBe(false);
    expect(
      isDirectWorkerEntrypoint(
        "file:///workspace/apps/worker/dist/index.js",
        undefined,
      ),
    ).toBe(false);
  });
});
