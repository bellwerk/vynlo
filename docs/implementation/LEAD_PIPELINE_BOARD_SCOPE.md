<!-- Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5 -->

# Lead pipeline board scope

- **Status:** Planned follow-on CRM/UI slice; enabling foundations are delivered
- **Scope date:** 2026-07-19
- **Requirements:** `VYN-CRM-002`, `VYN-WF-001`, `VYN-SEARCH-001`,
  `VYN-UX-001`, `VYN-I18N-001`, `VYN-TEN-001`, `VYN-SEC-001`, and
  `VYN-AUD-001`

Vynlo will adopt the useful operating model of a configurable sales pipeline:
leads grouped by workflow stage, a dense list alternative, stage-aware cards,
and direct stage movement. This is a Vynlo workbench informed by the documented
Kommo pipeline pattern, not a copy of Kommo source, pixels, branding, or product
terminology. Reference behavior: [pipeline usage](https://support.kommo.com/docs/pipeline-usage),
[lead-card layout](https://support.kommo.com/docs/customize-your-lead-card-layout),
and [lead management](https://support.kommo.com/docs/manage-leads-in-kommo).

## Current delivery state

| Capability | Status | Existing evidence |
|---|---|---|
| Workspace-owned leads, assignment, prospect, inventory interest, source, next action, and optimistic version | Delivered | Milestone 3 lead aggregate and `/api/v1/leads` contracts |
| Versioned lead states and ordered, permissioned transitions | Delivered | Active immutable workflow versions and starter `lead_standard` workflow |
| Reason-required loss and conversion-eligible deal creation | Delivered | Lead transition/conversion services, audit events, and pgTAP/application/route tests |
| RLS, immutable permission keys, audit/outbox parity, and actor idempotency | Delivered | Milestone 3 security and end-to-end acceptance record |
| English/French phone-usable lead list, detail, tasks, appointments, and timeline | Delivered | M3 operator workbench and browser/localization tests |
| Shared Vynlo System shell, shadcn primitives, themes, responsive rules, and UI enforcement | Delivered | `VYNLO_SYSTEM_UI_MIGRATION.md` |
| Pipeline selector, stage-grouped board projection, board/list toggle, filters, and per-column pagination | Planned | This scope |
| Drag/keyboard stage movement, terminal outcome flows, mobile stage view, and deterministic board visuals | Planned | This scope |

The existing Milestone 3 completion remains valid. The board is a new projection
and interaction surface over delivered workflow behavior; it does not retroactively
become a missing Milestone 3 acceptance condition.

## Product and data decisions

- A Vynlo organization remains the commercial account boundary and a workspace
  remains the RLS/data boundary. A pipeline is configuration inside one
  workspace; it is never a tenant, repository, deployment, or code branch.
- A lead `workflow_definition` with `entity_type = lead` is the pipeline identity.
  Its active immutable workflow version supplies ordered columns, translated
  state labels, terminal flags, transition permissions, guards, and reasons.
  Do not add a parallel hard-coded pipeline/stage model.
- Add translated pipeline labels to versioned workflow configuration. Exactly
  one active lead pipeline remains the workspace default (`purpose_key = primary`);
  additional active lead definitions may be selected explicitly.
- Existing leads keep their pinned workflow version and derive their pipeline
  from that version's definition. No historical lead, workflow event, audit
  record, or terminal result is rewritten.
- New-lead input accepts an optional `pipelineKey`; the application service
  resolves and pins the authorized active version. Omitting it preserves current
  behavior by selecting the primary pipeline.
- Stage movement uses the existing lead-transition command with
  `expectedVersion`. A drag is a presentation gesture, not a new mutation path.
- Cards are ordered by next action ascending with nulls last, then update time
  descending and lead ID. Dragging changes stage only; arbitrary Trello-style
  card ranking is not persisted in this slice.
- Cross-pipeline transfer is not included. A future transfer command must define
  field compatibility, target initial state, permission, reason, audit, and
  history semantics before it can be enabled.

## API and application scope

- Add a bounded `GET /api/v1/lead-pipelines` projection returning the permitted
  active pipelines, translated labels, active version identity, ordered states,
  canonical categories, terminal flags, and counts. Workspace context continues
  to come from authenticated membership.
- Extend `GET /api/v1/leads` with strict query parameters for `pipelineKey`, one
  `stateKey`, assignee, source, inventory interest, next-action window, created
  range, search, cursor, and limit. The board loads and paginates each visible
  state independently instead of returning one unfiltered 500-row payload.
- Extend the list/card projection with the bounded display data needed by the
  workbench: prospect name, interested-vehicle label, assignee label, source,
  next action, created/update timestamps, state, version, and attention flags.
  Sensitive party fields are not copied into the projection.
- Add optional `pipelineKey` to lead creation while retaining backward
  compatibility and the primary-pipeline default. Transition and conversion
  endpoints remain authoritative and keep their existing idempotency, audit,
  outbox, authorization, and concurrency contracts.
- Filters, selected pipeline, and list/board mode use allowlisted URL state so
  locale changes, detail navigation, and development preview context remain
  stable. Workspace changes abort or ignore stale column requests and clear all
  prior-workspace cards before new data is shown.

## Workbench behavior

- Desktop offers `Board | List`. The board renders non-terminal workflow states
  as restrained operational columns with counts and independent load-more
  controls. Converted and Lost are outcome targets and filters rather than
  permanently expanded card columns.
- Cards show only decision-useful information: lead/prospect, interested vehicle,
  owner, source, next action, age/overdue attention, and a clear detail action.
  Avoid decorative card grids, excessive badges, colored stage walls, and
  nested floating containers.
- Droppable states come only from the lead's currently allowed transitions.
  Unauthorized or invalid destinations are not presented as valid affordances.
  A stale-version rejection restores the prior card, announces the conflict,
  refreshes the affected columns, and offers retry after review.
- Lost opens a shadcn confirmation/dialog flow and requires the configured reason.
  Converted opens the existing deal-conversion workflow for its required deal
  data; it never silently changes state from a drag.
- Every drag action has an equivalent keyboard and `Move to…` menu path. Focus
  remains on the moved card or a deterministic neighboring card, and successful
  movement is announced without celebratory animation.
- At 320–414 px, Vynlo uses a stage picker/tabs plus one vertical card list. It
  does not compress the desktop board or require horizontal page scrolling.
  List mode remains available at every width.
- Loading skeletons preserve column dimensions. Empty, no-match, offline, stale,
  partial-column failure, permission-denied, conflict, success, and retry states
  are explicit. Motion follows the locked 120–220 ms opacity/transform contract;
  reduced motion removes spatial card movement.

## Acceptance and verification

| Acceptance ID | Condition |
|---|---|
| `LPB-AC-001` | Pipelines and columns derive from authorized active workflow configuration, remain workspace-scoped, and preserve every existing lead's pinned version and history. |
| `LPB-AC-002` | Board/list queries are bounded, cursor-paginated, deterministically sorted, strictly validated, and return no cross-workspace or unauthorized data. |
| `LPB-AC-003` | Pointer, touch, keyboard, and menu movement call the same transition service; disallowed, stale, and concurrent moves fail safely and restore truthful UI state. |
| `LPB-AC-004` | Lost requires its configured reason; Converted completes the existing actor-idempotent conversion flow and cannot create two deals. |
| `LPB-AC-005` | Workspace and pipeline changes discard stale requests; filters, locale, safe query context, focus, and scroll position follow documented navigation rules. |
| `LPB-AC-006` | Board and list are complete in English/French, light/dark, 320/375/414/768/1280 px, coarse pointer, reduced motion, offline, empty, loading, partial-error, and retry states. |
| `LPB-AC-007` | WCAG 2.2 AA checks cover names, focus visibility/restoration, live announcements, 44 px targets, drag alternatives, no color-only state, no page overflow, and no serious/critical axe violations. |
| `LPB-AC-008` | Domain/application/route/OpenAPI, RLS/authorization, audit/outbox, idempotency, concurrency, localization, component, Playwright, deterministic 375/1440 screenshots, and production-build gates pass. |

## Compatibility, rollout, and exclusions

- The schema/API changes are additive. Existing API clients that omit
  `pipelineKey` continue to use the primary pipeline. Existing lead transition,
  conversion, audit, outbox, and workflow contracts are not bypassed.
- Roll out behind a workspace entitlement: first read-only board/list parity,
  then stage movement, then optional additional pipelines. Rollback disables the
  board entitlement and retains the current list/detail experience and all data.
- Monitor board query latency, per-column failures, conflict/rollback rate,
  transition denial, conversion replay, and workspace-switch stale-response
  suppression. No new background job is required for the board itself.
- Out of scope: copying Kommo visual design or branding, chat-channel ingestion,
  arbitrary automation builders, persistent manual card ranking, cross-pipeline
  transfer, analytics/scoring, and tenant-specific pipeline code.
