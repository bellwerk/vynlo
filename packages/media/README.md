# @vynlo/media

Tenant-neutral media domain and application policy for the Vynlo modular
monolith.

The package owns vehicle-photo upload validation, immutable processing
profiles, deterministic derivative planning, processor and completion receipts,
retention policy, lifecycle and retry invariants, collection ordering, and
workspace-scoped object-key construction. It also defines provider-neutral
ports for managed object storage, malware scanning, and image processing.

It deliberately contains no storage, image-library, scanner, queue, database,
web, or tenant implementation. Application services must authorize workspace
membership before calling these policies; a workspace identifier by itself is
not authorization.

Vehicle photos accept only JPEG, PNG, WebP, HEIC, and HEIF. Upload intent is
checked before storage and the observed file signature, byte size, dimensions,
pixel count, and checksum are checked before processing. The processing profile
normalizes orientation and color space, strips EXIF/GPS/IPTC/XMP metadata, and
generates a WebP master plus 1080, 640, and 320 pixel derivatives without
upscaling. Processor and storage receipts are validated before a job may be
completed.

Vehicle-photo raw originals are eligible for deletion seven days after a
verified master exists. Originals for legal documents are preserved; previews
are separate derivatives. Persistence and scheduled deletion remain the
responsibility of application adapters.

Legal and signed originals accept a bounded PDF or supported source image. The
domain owns exact intent normalization, MIME signature detection, strict clean
verification receipts, and minimized durable verification/cleanup job
contracts. Application adapters scan before parsing or accepting bytes and
preserve accepted originals without transformation. Only expired or terminally
rejected unaccepted upload objects may enter the separate legal quarantine
cleanup contract.

## Traceability

| Requirement                              | Acceptance coverage                                                                  |
| ---------------------------------------- | ------------------------------------------------------------------------------------ |
| `VYN-MEDIA-001` / `T-MED-001`            | Immutable profile; orientation-aware JPEG, PNG, WebP, HEIC, and HEIF derivative plan |
| `VYN-MEDIA-001` / `T-MED-002`            | Enforced metadata/GPS receipt and original-preservation policy                       |
| `VYN-MEDIA-001` / `T-MED-003`            | Signature spoof, byte, pixel, checksum, and dimension rejection                      |
| `VYN-MEDIA-001` / `T-MED-004`            | Exact job payload, retries, reprocess, completion, and worker-lease replay checks    |
| `VYN-MEDIA-001` / `T-MED-005`            | One-cover, contiguous-order, and optimistic-concurrency invariants                   |
| `VYN-STOR-001` / `T-STOR-001`            | Workspace-scoped opaque object keys and managed-storage port                         |
| `VYN-MEDIA-001` / `M2-MEDIA-AC-021..025` | Exact legal-original verification, preservation, and unaccepted-quarantine cleanup   |

## Integration notes

- This package introduces no schema migration or API contract change.
- Database adapters must apply workspace RLS and permission checks. Object keys
  and workspace IDs are scoping inputs, not authorization evidence.
- Profile changes require a new immutable profile key or version; historical
  jobs retain their checksum.
- A worker must validate processor and completion receipts before marking a job
  successful. Retry, dead-letter, lease, duration, byte-count, scan, and
  retention telemetry belongs to the worker/application integration.
- Storage adapters must keep uploads private, use bounded grants, and verify
  size and checksum. `ManagedObjectStorage.delete` requires one atomic
  checksum-preconditioned provider operation; an adapter without that proven
  primitive must fail closed and must never emulate it with HEAD then DELETE.
- `media.delete_legal_original_quarantine` is declared but remains unclaimable
  with the other physical-deletion jobs until the configured provider proves
  one atomic conditional-delete operation.
