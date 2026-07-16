import { describe, expect, it } from "vitest";

import { MediaPolicyError } from "./errors";
import {
  documentOriginalObjectKey,
  vehiclePhotoDerivativeObjectKey,
  vehiclePhotoQuarantineObjectKey,
  vehiclePhotoRawObjectKey,
} from "./object-keys";
import {
  LEGAL_ORIGINAL_RETENTION_POLICY,
  VEHICLE_RAW_RETENTION_POLICY,
  assertOriginalDeletionDue,
  planOriginalRetention,
} from "./retention";

const WORKSPACE_ID = "10000000-0000-4000-8000-000000000001";
const MEDIA_ID = "20000000-0000-4000-8000-000000000001";
const RUN_ID = "30000000-0000-4000-8000-000000000001";
const SESSION_ID = "40000000-0000-4000-8000-000000000001";
const DOCUMENT_ID = "50000000-0000-4000-8000-000000000001";
const FILE_ID = "60000000-0000-4000-8000-000000000001";
const CHECKSUM = "a".repeat(64);

function expectCode(operation: () => unknown, code: string): void {
  expect(operation).toThrowError(MediaPolicyError);
  try {
    operation();
  } catch (error) {
    expect(error).toMatchObject({ code });
  }
}

describe("M2-MEDIA original retention policies", () => {
  it("VYN-MEDIA-001 / T-MED-002 schedules vehicle raw deletion seven days after verified master", () => {
    const plan = planOriginalRetention({
      fileClass: "vehicle_photo_raw",
      verifiedMasterAt: "2026-07-16T23:59:59.000Z",
    });

    expect(plan).toEqual({
      fileClass: "vehicle_photo_raw",
      policy: VEHICLE_RAW_RETENTION_POLICY,
      deleteAfter: "2026-07-23T23:59:59.000Z",
    });
    expect(Object.isFrozen(plan)).toBe(true);
    expect(() =>
      assertOriginalDeletionDue({
        plan,
        now: "2026-07-23T23:59:59.000Z",
        verifiedMasterAvailable: true,
        retentionHold: false,
      }),
    ).not.toThrow();
  });

  it("VYN-MEDIA-001 / T-MED-002 blocks early deletion, holds, and missing masters", () => {
    const plan = planOriginalRetention({
      fileClass: "vehicle_photo_raw",
      verifiedMasterAt: "2026-07-16T00:00:00.000Z",
    });
    for (const options of [
      {
        now: "2026-07-22T23:59:59.999Z",
        verifiedMasterAvailable: true,
        retentionHold: false,
      },
      {
        now: "2026-07-23T00:00:00.000Z",
        verifiedMasterAvailable: false,
        retentionHold: false,
      },
      {
        now: "2026-07-23T00:00:00.000Z",
        verifiedMasterAvailable: true,
        retentionHold: true,
      },
    ]) {
      expectCode(
        () => assertOriginalDeletionDue({ plan, ...options }),
        "retention_prohibited",
      );
    }
  });

  it("VYN-MEDIA-001 / T-MED-002 preserves legal-document originals", () => {
    const plan = planOriginalRetention({
      fileClass: "legal_document_original",
    });
    expect(plan).toEqual({
      fileClass: "legal_document_original",
      policy: LEGAL_ORIGINAL_RETENTION_POLICY,
      deleteAfter: null,
    });
    expectCode(
      () =>
        assertOriginalDeletionDue({
          plan,
          now: "2099-01-01T00:00:00.000Z",
          verifiedMasterAvailable: true,
          retentionHold: false,
        }),
      "retention_prohibited",
    );
  });
});

describe("M2-MEDIA workspace-scoped object keys", () => {
  it("VYN-STOR-001 / T-STOR-001 constructs deterministic keys without filenames", () => {
    expect(
      vehiclePhotoQuarantineObjectKey({
        workspaceId: WORKSPACE_ID,
        uploadSessionId: SESSION_ID,
      }),
    ).toBe(`workspaces/${WORKSPACE_ID}/uploads/${SESSION_ID}/source`);
    expect(
      vehiclePhotoRawObjectKey({
        workspaceId: WORKSPACE_ID,
        mediaId: MEDIA_ID,
        checksumSha256: CHECKSUM.toUpperCase(),
        mimeType: "image/jpeg",
      }),
    ).toBe(`workspaces/${WORKSPACE_ID}/media/${MEDIA_ID}/raw/${CHECKSUM}.jpg`);
    expect(
      vehiclePhotoDerivativeObjectKey({
        workspaceId: WORKSPACE_ID,
        mediaId: MEDIA_ID,
        processingRunId: RUN_ID,
        variant: "thumbnail_320",
        checksumSha256: CHECKSUM,
      }),
    ).toBe(
      `workspaces/${WORKSPACE_ID}/media/${MEDIA_ID}/runs/${RUN_ID}/thumbnail_320/${CHECKSUM}.webp`,
    );
    expect(
      documentOriginalObjectKey({
        workspaceId: WORKSPACE_ID,
        documentId: DOCUMENT_ID,
        fileId: FILE_ID,
        checksumSha256: CHECKSUM,
        mimeType: "application/pdf",
      }),
    ).toBe(
      `workspaces/${WORKSPACE_ID}/documents/${DOCUMENT_ID}/files/${FILE_ID}/${CHECKSUM}.pdf`,
    );
  });

  it("VYN-STOR-001 / T-STOR-001 isolates identical content by workspace", () => {
    const otherWorkspace = "10000000-0000-4000-8000-000000000002";
    const first = vehiclePhotoRawObjectKey({
      workspaceId: WORKSPACE_ID,
      mediaId: MEDIA_ID,
      checksumSha256: CHECKSUM,
      mimeType: "image/png",
    });
    const second = vehiclePhotoRawObjectKey({
      workspaceId: otherWorkspace,
      mediaId: MEDIA_ID,
      checksumSha256: CHECKSUM,
      mimeType: "image/png",
    });

    expect(first).not.toBe(second);
    expect(first).toContain(`/raw/${CHECKSUM}.png`);
    expect(second).toContain(`/raw/${CHECKSUM}.png`);
  });

  it("VYN-STOR-001 / T-STOR-001 rejects malformed scope and content identities", () => {
    expectCode(
      () =>
        vehiclePhotoRawObjectKey({
          workspaceId: "not-a-workspace",
          mediaId: MEDIA_ID,
          checksumSha256: CHECKSUM,
          mimeType: "image/jpeg",
        }),
      "invalid_object_key_input",
    );
    expectCode(
      () =>
        vehiclePhotoDerivativeObjectKey({
          workspaceId: WORKSPACE_ID,
          mediaId: MEDIA_ID,
          processingRunId: RUN_ID,
          variant: "unrecognized" as "thumbnail_320",
          checksumSha256: CHECKSUM,
        }),
      "invalid_object_key_input",
    );
  });
});
