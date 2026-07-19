# Milestone 2 vehicle-media management

**Status:** Implemented with static and focused application verification
**Requirements:** `VYN-MEDIA-001`, `VYN-TEN-001`, `VYN-SEC-001`, `VYN-AUD-001`, `VYN-API-001`
**Acceptance:** `M2-MEDIA-MGMT-AC-001` through `M2-MEDIA-MGMT-AC-010`

## Delivered slice

- `app.list_inventory_vehicle_media` returns one ordered, versioned active vehicle-photo collection.
- `app.get_vehicle_media_asset` returns one active or archived vehicle-photo aggregate.
- Both read contracts expose immutable file IDs, current processing-run provenance, checksums, dimensions, media status, caption, cover, order, and aggregate versions. They never expose storage bucket, object key, provider generation, credentials, or legal/signed originals.
- Authenticated direct `SELECT` access to `media_files` and `media_upload_sessions` is revoked. Browser reads use exact application projections and audited short-lived download grants; vehicle Storage INSERT calls a boolean-only exact-intent predicate instead of reading upload-session rows.
- `app.update_vehicle_media_caption` is permission scoped, idempotent, normalized, bounded, audit recorded, outbox recorded, and fenced by the expected media version.
- `app.archive_vehicle_media` requires `media.archive`, the expected media version, and the expected collection version. It atomically archives the aggregate, compacts active order, promotes a cover when required, advances both aggregate versions, and records audit/outbox evidence.
- Archive is logical only. It never deletes or mutates immutable file provenance, legal originals, signed originals, or retention state.
- The web surface implements `GET /api/v1/inventory-units/{id}/media`, `GET/PATCH /api/v1/media/{id}`, and `POST /api/v1/media/{id}/archive` with strict application schemas and safe error mapping.
- The phone-first English/French manager uses only exact signed thumbnail grants, accessible move controls, visible status/save/retry state, caption editing, cover selection, reprocessing, logical archive, and the existing quarantine upload pipeline for additional photos.

## Interface and compatibility notes

- Migrations: `20260716250000_m2_vehicle_media_management.sql` intentionally revokes authenticated `SELECT` on provider-bearing media tables; `20260716320000_vehicle_upload_storage_policy_hardening.sql` removes the stale SELECT policy and restores exact vehicle upload eligibility through a boolean-only helper. Worker/service-role access remains unchanged.
- API: media collection and asset reads are new exact envelopes. Existing upload, verification, reprocess, reorder, set-cover, and download-grant command contracts remain compatible.
- Storage: the browser receives an opaque short-lived signed URL only after audited database authorization and provider byte verification. It receives no service-role credential or persistent provider coordinate field.
- Localization: all manager text has English and French keys. No tenant label or tenant-specific workflow is present.
- Accessibility: controls have visible text or exact `aria-label` values, touch targets are at least 44 px, status changes use live regions, archive confirmation is keyboard usable, and no action is hover only.

## Verification map

| Acceptance | Evidence |
| --- | --- |
| `M2-MEDIA-MGMT-AC-001` exact ordered read | `015_m2_vehicle_media_management.test.sql`; `m2-media-api.test.ts`; route tests |
| `M2-MEDIA-MGMT-AC-002` exact one-asset read | pgTAP, application, and API route tests |
| `M2-MEDIA-MGMT-AC-003` no provider coordinates | direct-table privilege probes, boolean-only vehicle Storage policy in `022`, JSON projection probes, strict application/browser parsers |
| `M2-MEDIA-MGMT-AC-004` legal-original isolation | pgTAP legal-kind negative read probe |
| `M2-MEDIA-MGMT-AC-005` caption concurrency/idempotency | pgTAP stale/replay/conflict tests and application mapping tests |
| `M2-MEDIA-MGMT-AC-006` archive concurrency/idempotency | dual-version stale/replay/conflict pgTAP probes |
| `M2-MEDIA-MGMT-AC-007` cover/order invariants | archive promotion and compaction pgTAP probes; manager move/cover actions |
| `M2-MEDIA-MGMT-AC-008` audit/outbox | exact event/action/version pgTAP assertions |
| `M2-MEDIA-MGMT-AC-009` mobile/a11y/localization | manager E2E mobile/desktop, overflow, touch-target, French, and axe coverage |
| `M2-MEDIA-MGMT-AC-010` retry/additional upload | manager reprocess action and reused exact upload/verification pipeline |

Focused TypeScript, lint, unit, application-route, OpenAPI, and static Supabase checks run without a live database. Live pgTAP execution still requires the documented local Supabase/Docker runtime; static success is not a substitute for that runtime result.

## Operational behavior

- Transient `awaiting_upload`, `quarantined`, and `processing` states refresh automatically.
- Failed processing remains visible and exposes an explicit durable retry action.
- A `409` reloads the newest collection and asks the operator to review before retrying.
- Thumbnail grant failures fail closed to an unavailable placeholder; no unsigned storage fallback exists.
- Audit/outbox payloads contain aggregate IDs and versions only, never storage coordinates or credentials.
