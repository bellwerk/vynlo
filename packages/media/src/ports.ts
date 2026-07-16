import type {
  PlannedVehiclePhotoDerivative,
  VehiclePhotoProcessingProfileSnapshot,
} from "./processing-profile";
import type { VehiclePhotoProcessorReceipt } from "./processor-receipt";
import type { ValidatedVehiclePhotoSource } from "./upload-policy";

/** A bounded byte stream supplied by an application adapter. */
export type MediaBinarySource = Uint8Array | AsyncIterable<Uint8Array>;

export interface ManagedObjectIdentity {
  readonly bucket: string;
  readonly objectKey: string;
}

export interface ManagedObjectMetadata extends ManagedObjectIdentity {
  readonly byteSize: number;
  readonly mimeType: string;
  readonly checksumSha256: string;
}

export interface ManagedObjectUploadGrant extends ManagedObjectIdentity {
  readonly url: string;
  readonly expiresAt: string;
  readonly requiredHeaders: Readonly<Record<string, string>>;
}

export interface ManagedObjectDownloadGrant extends ManagedObjectIdentity {
  readonly url: string;
  readonly expiresAt: string;
}

export interface LegalOriginalObjectRead {
  readonly generation: string;
  readonly providerMimeType: string;
  readonly source: MediaBinarySource;
}

/** Exact-key storage read that preserves provider generation provenance. */
export interface LegalOriginalObjectStorage {
  readLegalOriginal(input: {
    readonly object: ManagedObjectIdentity;
    readonly signal?: AbortSignal;
  }): Promise<LegalOriginalObjectRead>;
}

/**
 * Provider-neutral object storage boundary. Implementations must keep bucket and
 * object-key authorization in the application layer and must not accept a
 * workspace identifier as a substitute for an authorized object key.
 */
export interface ManagedObjectStorage {
  createUploadGrant(input: {
    readonly object: ManagedObjectIdentity;
    readonly expectedByteSize: number;
    readonly expectedMimeType: string;
    readonly expectedChecksumSha256: string;
    readonly expiresInSeconds: number;
    readonly signal?: AbortSignal;
  }): Promise<ManagedObjectUploadGrant>;

  createDownloadGrant(input: {
    readonly object: ManagedObjectIdentity;
    readonly expectedByteSize: number;
    readonly expectedChecksumSha256: string;
    readonly expectedGeneration: string | null;
    readonly expectedMimeType: string;
    readonly expiresInSeconds: number;
    readonly signal?: AbortSignal;
  }): Promise<ManagedObjectDownloadGrant>;

  head(input: {
    readonly object: ManagedObjectIdentity;
    readonly signal?: AbortSignal;
  }): Promise<ManagedObjectMetadata | null>;

  read(input: {
    readonly object: ManagedObjectIdentity;
    readonly signal?: AbortSignal;
  }): Promise<MediaBinarySource>;

  putIfAbsent(input: {
    readonly object: ManagedObjectIdentity;
    readonly body: MediaBinarySource;
    readonly byteSize: number;
    readonly mimeType: string;
    readonly checksumSha256: string;
    readonly signal?: AbortSignal;
  }): Promise<ManagedObjectMetadata>;

  /**
   * Deletes only if the provider can enforce the checksum precondition in the
   * same atomic operation. Implementations without a proven conditional-delete
   * primitive must fail closed and must not emulate this with HEAD then DELETE.
   */
  delete(input: {
    readonly object: ManagedObjectIdentity;
    readonly ifChecksumSha256: string;
    readonly signal?: AbortSignal;
  }): Promise<"deleted" | "not_found" | "precondition_failed">;
}

export type MalwareScanVerdict = "clean" | "infected";

export interface MalwareScanReceipt {
  readonly scanner: Readonly<{
    name: string;
    version: string;
  }>;
  readonly sourceChecksumSha256: string;
  readonly verdict: MalwareScanVerdict;
  readonly signatureVersion: string;
}

/** Scanner adapters return a receipt and never make persistence decisions. */
export interface MediaMalwareScanner {
  scan(input: {
    readonly source: MediaBinarySource;
    readonly sourceChecksumSha256: string;
    readonly signal?: AbortSignal;
  }): Promise<MalwareScanReceipt>;
}

/** Image adapters execute an immutable plan and return an auditable receipt. */
export interface VehiclePhotoProcessor {
  process(input: {
    readonly source: MediaBinarySource;
    readonly validatedSource: ValidatedVehiclePhotoSource;
    readonly profile: VehiclePhotoProcessingProfileSnapshot;
    readonly derivativePlan: readonly PlannedVehiclePhotoDerivative[];
    readonly signal?: AbortSignal;
  }): Promise<VehiclePhotoProcessorReceipt>;
}
