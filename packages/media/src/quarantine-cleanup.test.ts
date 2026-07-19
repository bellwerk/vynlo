import { describe, expect, it } from "vitest";

import { MediaPolicyError } from "./errors";
import {
  buildMediaQuarantineCleanupJobPayload,
  parseMediaQuarantineCleanupJob,
} from "./job-contract";

const ids = {
  media: "a9000000-0000-4000-8000-000000000002",
  session: "a9000000-0000-4000-8000-000000000003",
  workspace: "10000000-0000-4000-8000-000000000001",
} as const;

describe("T-MED-003 / T-MED-004 media quarantine cleanup job contract", () => {
  it("round-trips the exact workspace/session/generation/checksum fence", () => {
    const payload = buildMediaQuarantineCleanupJobPayload({
      checksumSha256: "A".repeat(64),
      generation: 2,
      mediaId: ids.media,
      reason: "verified_raw_copy",
      uploadSessionId: ids.session,
    });

    expect(
      parseMediaQuarantineCleanupJob({
        entityId: ids.session,
        entityType: "media_upload_session",
        jobType: "media.delete_quarantine_upload",
        payload,
        payloadSchemaVersion: 1,
        workspaceId: ids.workspace,
      }),
    ).toEqual({
      checksumSha256: "a".repeat(64),
      generation: 2,
      mediaId: ids.media,
      reason: "verified_raw_copy",
      uploadSessionId: ids.session,
      workspaceId: ids.workspace,
    });
  });

  it("allows an unknown checksum only for the durable worker to fence later", () => {
    expect(
      buildMediaQuarantineCleanupJobPayload({
        checksumSha256: null,
        generation: 1,
        mediaId: ids.media,
        reason: "expired_intent",
        uploadSessionId: ids.session,
      }).checksum_sha256,
    ).toBeNull();
  });

  it("rejects extra keys, invalid reasons, and entity/session substitution", () => {
    const payload = {
      ...buildMediaQuarantineCleanupJobPayload({
        checksumSha256: "b".repeat(64),
        generation: 1,
        mediaId: ids.media,
        reason: "terminal_rejection",
        uploadSessionId: ids.session,
      }),
      storage_key: "must-not-be-in-a-job",
    };

    expect(() =>
      parseMediaQuarantineCleanupJob({
        entityId: ids.media,
        entityType: "media_upload_session",
        jobType: "media.delete_quarantine_upload",
        payload,
        payloadSchemaVersion: 1,
        workspaceId: ids.workspace,
      }),
    ).toThrow(MediaPolicyError);

    expect(() =>
      buildMediaQuarantineCleanupJobPayload({
        checksumSha256: null,
        generation: 1,
        mediaId: ids.media,
        reason: "other" as never,
        uploadSessionId: ids.session,
      }),
    ).toThrow(MediaPolicyError);
  });
});
