import { describe, expect, it } from "vitest";

import { MediaPolicyError } from "./errors";
import {
  VEHICLE_PHOTO_UPLOAD_VERIFICATION_JOB_TYPE,
  VEHICLE_PHOTO_PROCESSING_JOB_TYPE,
  buildVehiclePhotoUploadVerificationJobPayload,
  buildVehiclePhotoProcessingJobPayload,
  parseVehiclePhotoUploadVerificationJob,
  parseVehiclePhotoProcessingJob,
  type VehiclePhotoProcessingJobEnvelope,
} from "./job-contract";
import {
  assertVehicleMediaTransition,
  canTransitionVehicleMediaStatus,
  planMediaProcessingFailure,
  planVehiclePhotoReprocess,
} from "./lifecycle";

const WORKSPACE_ID = "10000000-0000-4000-8000-000000000001";
const MEDIA_ID = "20000000-0000-4000-8000-000000000001";
const RUN_ID = "30000000-0000-4000-8000-000000000001";
const SOURCE_ID = "40000000-0000-4000-8000-000000000001";
const CHECKSUM = "a".repeat(64);

function expectCode(operation: () => unknown, code: string): void {
  expect(operation).toThrowError(MediaPolicyError);
  try {
    operation();
  } catch (error) {
    expect(error).toMatchObject({ code });
  }
}

function envelope(payload: unknown): VehiclePhotoProcessingJobEnvelope {
  return {
    workspaceId: WORKSPACE_ID,
    jobType: VEHICLE_PHOTO_PROCESSING_JOB_TYPE,
    entityType: "vehicle_media",
    entityId: MEDIA_ID,
    payloadSchemaVersion: 1,
    payload,
  };
}

describe("M2-MEDIA minimized processing job contract", () => {
  it("VYN-MEDIA-001 / T-MED-004 builds and parses the exact payload", () => {
    const payload = buildVehiclePhotoProcessingJobPayload({
      mediaId: MEDIA_ID,
      processingRunId: RUN_ID,
      profileChecksumSha256: CHECKSUM,
      source: { kind: "upload_session", id: SOURCE_ID },
    });

    expect(payload).toEqual({
      media_id: MEDIA_ID,
      processing_run_id: RUN_ID,
      profile_checksum: CHECKSUM,
      source: { kind: "upload_session", id: SOURCE_ID },
    });
    expect(Object.isFrozen(payload.source)).toBe(true);
    expect(parseVehiclePhotoProcessingJob(envelope(payload))).toEqual({
      workspaceId: WORKSPACE_ID,
      mediaId: MEDIA_ID,
      processingRunId: RUN_ID,
      profileChecksumSha256: CHECKSUM,
      source: { kind: "upload_session", id: SOURCE_ID },
    });
  });

  it("VYN-MEDIA-001 / T-MED-004 supports a stored media source for reprocessing", () => {
    const payload = buildVehiclePhotoProcessingJobPayload({
      mediaId: MEDIA_ID,
      processingRunId: RUN_ID,
      profileChecksumSha256: CHECKSUM,
      source: { kind: "media_file", id: SOURCE_ID },
    });
    expect(parseVehiclePhotoProcessingJob(envelope(payload)).source).toEqual({
      kind: "media_file",
      id: SOURCE_ID,
    });
  });

  it("VYN-MEDIA-001 / T-MED-004 rejects paths, filenames, tokens, and extra fields", () => {
    const payload = buildVehiclePhotoProcessingJobPayload({
      mediaId: MEDIA_ID,
      processingRunId: RUN_ID,
      profileChecksumSha256: CHECKSUM,
      source: { kind: "upload_session", id: SOURCE_ID },
    });

    for (const unexpected of [
      { ...payload, object_key: "workspace/private/file" },
      { ...payload, filename: "customer-photo.jpg" },
      { ...payload, provider_token: "secret" },
      { ...payload, workspace_id: WORKSPACE_ID },
    ]) {
      expectCode(
        () => parseVehiclePhotoProcessingJob(envelope(unexpected)),
        "invalid_job_contract",
      );
    }
    expectCode(
      () =>
        parseVehiclePhotoProcessingJob(
          envelope({
            ...payload,
            source: { ...payload.source, objectKey: "private/path" },
          }),
        ),
      "invalid_job_payload",
    );
  });

  it("VYN-MEDIA-001 / T-MED-004 binds entity, schema, and workspace", () => {
    const payload = buildVehiclePhotoProcessingJobPayload({
      mediaId: MEDIA_ID,
      processingRunId: RUN_ID,
      profileChecksumSha256: CHECKSUM,
      source: { kind: "upload_session", id: SOURCE_ID },
    });
    for (const invalid of [
      { ...envelope(payload), entityId: RUN_ID },
      { ...envelope(payload), entityType: "document" },
      { ...envelope(payload), payloadSchemaVersion: 2 },
      { ...envelope(payload), workspaceId: "untrusted" },
    ]) {
      expectCode(
        () => parseVehiclePhotoProcessingJob(invalid),
        "invalid_job_contract",
      );
    }
  });
});

describe("M2-MEDIA minimized upload-verification job contract", () => {
  it("VYN-MEDIA-001 / T-MED-004 binds the exact workspace, session, and media identifiers", () => {
    const payload = buildVehiclePhotoUploadVerificationJobPayload({
      mediaId: MEDIA_ID,
      uploadSessionId: SOURCE_ID,
    });
    expect(
      parseVehiclePhotoUploadVerificationJob({
        workspaceId: WORKSPACE_ID,
        jobType: VEHICLE_PHOTO_UPLOAD_VERIFICATION_JOB_TYPE,
        entityType: "media_upload_session",
        entityId: SOURCE_ID,
        payloadSchemaVersion: 1,
        payload,
      }),
    ).toEqual({
      workspaceId: WORKSPACE_ID,
      mediaId: MEDIA_ID,
      uploadSessionId: SOURCE_ID,
    });
  });

  it("VYN-MEDIA-001 / T-MED-004 rejects extra object paths and entity mismatches", () => {
    const payload = buildVehiclePhotoUploadVerificationJobPayload({
      mediaId: MEDIA_ID,
      uploadSessionId: SOURCE_ID,
    });
    for (const invalid of [
      { ...payload, object_key: "private/path" },
      { ...payload, access_token: "secret" },
    ]) {
      expectCode(
        () =>
          parseVehiclePhotoUploadVerificationJob({
            workspaceId: WORKSPACE_ID,
            jobType: VEHICLE_PHOTO_UPLOAD_VERIFICATION_JOB_TYPE,
            entityType: "media_upload_session",
            entityId: SOURCE_ID,
            payloadSchemaVersion: 1,
            payload: invalid,
          }),
        "invalid_job_contract",
      );
    }
    expectCode(
      () =>
        parseVehiclePhotoUploadVerificationJob({
          workspaceId: WORKSPACE_ID,
          jobType: VEHICLE_PHOTO_UPLOAD_VERIFICATION_JOB_TYPE,
          entityType: "media_upload_session",
          entityId: RUN_ID,
          payloadSchemaVersion: 1,
          payload,
        }),
      "invalid_job_contract",
    );
  });
});

describe("M2-MEDIA lifecycle, retry, and reprocess invariants", () => {
  it("VYN-MEDIA-001 / T-MED-004 permits only explicit state transitions", () => {
    expect(
      canTransitionVehicleMediaStatus("awaiting_upload", "quarantined"),
    ).toBe(true);
    expect(canTransitionVehicleMediaStatus("quarantined", "processing")).toBe(
      true,
    );
    expect(canTransitionVehicleMediaStatus("processing", "ready")).toBe(true);
    expect(canTransitionVehicleMediaStatus("ready", "processing")).toBe(true);
    expect(canTransitionVehicleMediaStatus("failed", "processing")).toBe(true);
    expect(canTransitionVehicleMediaStatus("archived", "processing")).toBe(
      false,
    );
    expect(canTransitionVehicleMediaStatus("ready", "quarantined")).toBe(false);
    expectCode(
      () => assertVehicleMediaTransition("ready", "quarantined"),
      "invalid_media_transition",
    );
  });

  it("VYN-MEDIA-001 / T-MED-004 retries only retryable failures within budget", () => {
    for (const classification of [
      "transient",
      "rate_limited",
      "unknown",
      "lease_expired",
    ] as const) {
      expect(
        planMediaProcessingFailure({
          classification,
          failedAttemptNumber: 1,
          maximumAttempts: 3,
        }),
      ).toEqual({
        disposition: "retry",
        mediaStatus: "processing",
        recordTerminalFailure: false,
      });
    }
    for (const classification of [
      "validation",
      "permission",
      "provider_auth",
      "permanent",
    ] as const) {
      expect(
        planMediaProcessingFailure({
          classification,
          failedAttemptNumber: 1,
          maximumAttempts: 3,
        }).disposition,
      ).toBe("terminal_failure");
    }
    expect(
      planMediaProcessingFailure({
        classification: "transient",
        failedAttemptNumber: 3,
        maximumAttempts: 3,
      }).disposition,
    ).toBe("terminal_failure");
  });

  it("VYN-MEDIA-001 / T-MED-004 replans failed media with optimistic versioning", () => {
    expect(
      planVehiclePhotoReprocess({
        status: "failed",
        currentMediaVersion: 4,
        expectedMediaVersion: 4,
        currentGeneration: 2,
        source: { kind: "upload_session", id: SOURCE_ID },
      }),
    ).toEqual({
      nextGeneration: 3,
      nextMediaVersion: 5,
      nextStatus: "processing",
      source: { kind: "upload_session", id: SOURCE_ID },
    });
    expect(
      planVehiclePhotoReprocess({
        status: "ready",
        currentMediaVersion: 8,
        expectedMediaVersion: 8,
        currentGeneration: 3,
        source: { kind: "media_file", id: SOURCE_ID },
      }).nextGeneration,
    ).toBe(4);
  });

  it("VYN-MEDIA-001 / T-MED-004 blocks stale, active, archived, and unsafe reprocess requests", () => {
    expectCode(
      () =>
        planVehiclePhotoReprocess({
          status: "failed",
          currentMediaVersion: 4,
          expectedMediaVersion: 3,
          currentGeneration: 2,
          source: { kind: "media_file", id: SOURCE_ID },
        }),
      "stale_media_version",
    );
    for (const status of ["processing", "archived"] as const) {
      expectCode(
        () =>
          planVehiclePhotoReprocess({
            status,
            currentMediaVersion: 4,
            expectedMediaVersion: 4,
            currentGeneration: 2,
            source: { kind: "media_file", id: SOURCE_ID },
          }),
        "reprocess_not_allowed",
      );
    }
    expectCode(
      () =>
        planVehiclePhotoReprocess({
          status: "ready",
          currentMediaVersion: 4,
          expectedMediaVersion: 4,
          currentGeneration: 2,
          source: { kind: "upload_session", id: SOURCE_ID },
        }),
      "reprocess_not_allowed",
    );
  });
});
