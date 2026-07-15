# Engineering epics and implementation stories

This catalogue converts the specification into actionable work. Teams may split stories further, but must preserve requirement IDs and acceptance criteria.

## EPIC VYN-E00 — Repository and developer experience

Dependencies: none.

- **VYN-E00-S01:** Scaffold pnpm workspace, `apps/web`, `apps/worker`, and shared packages.
- **VYN-E00-S02:** Add strict TypeScript, lint, format, unit, integration, E2E, schema, Markdown-link, secret, and dependency checks.
- **VYN-E00-S03:** Add local Supabase lifecycle and synthetic two-workspace seed.
- **VYN-E00-S04:** Add CI build artifacts, migration checks, and protected-branch requirements.
- **VYN-E00-S05:** Document local setup, test commands, and troubleshooting.

Done when Milestone 0 exit criteria pass.

## EPIC VYN-E01 — Tenancy, identity, permissions, and sessions

Requirements: VYN-AUTH-001, VYN-AUTH-002, VYN-TEN-001, VYN-SEC-001.

- organization/workspace/legal entity/brand/location models;
- user profiles and workspace memberships;
- invite, activation, deactivation, password reset, Google OAuth and controlled fallback;
- roles, permission keys, assignments, service helpers;
- RLS policies and negative cross-workspace tests;
- MFA enforcement and assurance inspection;
- 14-day session maximum and step-up commands;
- active-device/session revocation behavior.

## EPIC VYN-E02 — Audit, approvals, configuration, and entitlements

Requirements: VYN-AUD-001, VYN-WF-001, VYN-FIELD-001.

- append-only audit events and correlation IDs;
- approval records;
- feature entitlements;
- workspace settings/configuration versions;
- import/export package validation and impact diff;
- activation/rollback commands;
- admin UI for safe Release 1 settings.

## EPIC VYN-E03 — PWA shell and design system

Requirements: VYN-UX-001, VYN-I18N-001.

- shadcn/ui source component registry and tokens;
- responsive application shell;
- workspace switcher and permission-aware navigation;
- installable manifest and PWA update behavior;
- French/English translation infrastructure;
- form, error, loading, empty, offline, sync, and retry patterns;
- accessibility automated checks and manual test checklist.

## EPIC VYN-E04 — Jobs, outbox, and observability

Requirements: VYN-JOB-001, VYN-OPS-001.

- outbox transaction API;
- worker claiming/leases/idempotency;
- retry classification/backoff/dead-letter;
- job/attempt tables and admin views;
- structured logs, traces, metrics, and correlation IDs;
- job replay/cancel controls and runbooks.

## EPIC VYN-E05 — Inventory and numbering

Requirements: VYN-INV-001, VYN-INV-002, VYN-NUM-001, VYN-COST-001.

- physical vehicle and inventory-unit persistence;
- VIN normalization, decode adapter, duplicates, override audit;
- stock definitions and transactional allocations;
- location, odometer, prices, notes, acquisition/closure dates;
- cost ledger and reversal entries;
- inventory workflow integration;
- mobile list/cards, desktop table, detail and create/edit flows;
- search/filter/saved-view support.

## EPIC VYN-E06 — Media and file handling

Requirements: VYN-MEDIA-001.

- upload sessions and quarantine;
- MIME/signature/pixel/size validation;
- HEIC conversion and orientation;
- normalized master, WebP derivatives, thumbnails;
- checksum/dedupe, sort, cover, caption;
- raw retention job;
- original-preserving legal/document policy;
- mobile upload progress and retry.

## EPIC VYN-E07 — CRM and tasks

Requirements: VYN-CRM-001.

- person/organization party model;
- contacts, addresses, restricted identifiers;
- leads, sources, assignments and workflow;
- activities, notes, tasks, appointments;
- conversion to deal;
- timeline and permission-aware search.

## EPIC VYN-E08 — Deals, trade-ins, external finance, one-time payments

Requirements: VYN-DEAL-001, VYN-FIN-001, VYN-PAY-001.

- configurable deal types and participant roles;
- line items and inventory associations;
- trade-in facts, allowance, lien/payoff, resulting inventory;
- lender directory/application/conditions/status/funding;
- one-time payment transaction lifecycle;
- reversal/refund approvals and audit;
- mobile step-based deal flow.

## EPIC VYN-E09 — Workflows and custom fields

Requirements: VYN-WF-001, VYN-FIELD-001.

- workflow schema/version/state/transition storage;
- guard/permission/reason/required-field validation;
- atomic transitions and events;
- neutral category/behavior flags;
- typed custom field definitions and values;
- safe Release 1 admin controls;
- config validation and migration compatibility.

## EPIC VYN-E10 — Document and numbering engine

Requirements: VYN-DOC-001, VYN-NUM-001.

- field schema and reusable field library;
- sandboxed template compile/render;
- source-bundle/assets/font/checksum storage;
- preview generation and watermarking;
- official validation and number allocation;
- immutable document snapshot and asynchronous PDF;
- signed file versions;
- void/supersede lineage;
- visual regression and security tests.

## EPIC VYN-E11 — Calculation and tax runtime

Requirements: VYN-CALC-001, VYN-TAX-001.

- typed AST parser/validator;
- exact decimal execution and resource limits;
- safe core operations, rows, conditions, dates, tax invocation;
- version lifecycle and fixture runner;
- calculation snapshots;
- tax pack schema, effective dates, context, sources, rounding and golden tests;
- activation gates and approval UI.

Drivven's RTB definition is a seed/test consumer, not platform code.

## EPIC VYN-E12 — Listings and provider adapters

Requirements: VYN-LIST-001.

- generic storage and website provider ports;
- external resources and listing mappings;
- publish/update/unpublish jobs;
- asset upload and media mapping;
- drift detection/resolution;
- connection health/scopes/rate limits;
- provider staging smoke contract.

## EPIC VYN-E13 — Exports and reporting

Requirements: VYN-EXP-001.

- versioned export definition/columns;
- permission-aware filters and fields;
- CSV/XLSX generation in worker;
- expiring download links;
- inventory aging/cost/gross/lead/deal starter reports;
- audit and workspace isolation.

## EPIC DRV-E01 — Drivven workspace provisioning

Requirements: Drivven decision and acceptance documents.

- import `tenant-seeds/drivven` into a staging workspace;
- legal entity and two locations;
- roles/permissions and MFA policy;
- `P###` and direct trade-in suffix numbering;
- Drivven inventory and RTB workflow candidates;
- feature activation states and approval gates.

## EPIC DRV-E02 — Google Drive and Webflow

- Shared Drive OAuth connection and folder mappings;
- idempotent folder creation/move/reconcile;
- Webflow staging/production mapping and asset flow;
- location/price/publishing-page behavior;
- unavailable/delivered handling;
- sync status, drift, retry, and support views.

## EPIC DRV-E03 — Drivven RTB development flow

- field catalogue and form wizard;
- initial-payment transaction guard;
- private calculation definition and fixtures;
- candidate Québec tax invocation;
- official numbering and filename rules;
- watermarked development template;
- signed scan and delivery guard;
- production feature flag blocked until approvals.

## EPIC DRV-E04 — Existing inventory migration

- inventory/folder/CMS discovery report;
- deterministic mapping and duplicate review;
- staging dry run;
- reconciliation by counts, stock, VIN, folder, CMS item, and media;
- approved production run and rollback/retry plan.
