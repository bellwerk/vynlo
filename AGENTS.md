# AGENTS.md — Mandatory implementation rules

These rules apply to Codex, developers, reviewers, CI, migrations, scripts, and automation working in the single `vynlo` repository.

## 1. Product and tenant boundary

- A tenant is a database workspace and versioned configuration, not a repository, deployment, or code fork.
- Never add a branch such as `if (workspace.slug === "drivven")`.
- Never place Drivven, Auto BS, Montreal, Sherbrooke, RTB, the 70/30 split, GoCardless, `P###`, Drivven folders, or Drivven export columns in reusable platform source.
- Drivven-specific artifacts belong under `tenant-seeds/drivven`, `docs/tenants/drivven`, or encrypted runtime configuration.
- Platform packages may expose generic capabilities used by Drivven, but package names, core schemas, and platform test fixtures must remain tenant-neutral.
- A future dealership normally receives no Git folder. It is created through workspace onboarding and database configuration.

## 2. Architecture

- Build a modular monolith in a pnpm workspace; do not create microservices or a plugin marketplace without an approved ADR.
- `apps/web` is the Next.js web application and installable PWA.
- `apps/worker` handles PDFs, images, integrations, reconciliation, and scheduled jobs.
- Business rules belong in application/domain packages, never React components or route handlers.
- Server Actions may improve web UX but must call the same application services used by `/api/v1`.
- External work uses the transactional outbox and durable jobs; no provider call is an untracked side effect of a user save.

## 3. Tenancy and authorization

- `organization_id` is the commercial account boundary.
- `workspace_id` is the operational data and Row-Level Security boundary.
- Every workspace-owned row, job, file, cache key, export, event, and external mapping must preserve workspace context.
- Row-Level Security is mandatory on every exposed table.
- Permission checks use immutable permission keys, not role labels.
- Never trust a workspace ID supplied in an arbitrary request body; derive and verify context from authenticated membership.

## 4. UI, mobile, and accessibility

- Use Next.js App Router, strict TypeScript, Tailwind CSS, and shadcn/ui source components.
- Build mobile-first from a 360 px viewport.
- Every core workflow must have a phone-usable form; a desktop table cannot be the only interaction.
- Inventory uses card/list views on mobile and tables on desktop.
- Use step-based forms, visible save state, upload progress, job status, and retry actions.
- No hover-only action or unlabeled control.
- Target WCAG 2.2 AA.
- UI text uses translation keys; French and English infrastructure is required from the first release.
- Camera-based VIN scanning is out of scope. VIN is typed or pasted from registration or deal paperwork.

## 5. Media

- Image normalization and derivatives are Release 1 platform capabilities.
- Vehicle marketing photos and legal documents use different processing policies.
- Vehicle photos: validate, orient, convert HEIC when supported, strip public GPS metadata, create normalized master, 1080 px WebP, and thumbnails.
- Legal, registration, purchase, identity, and signed files preserve their originals; previews are separate derivatives.
- File processing is asynchronous, idempotent, observable, and retryable.

## 6. Financial and configuration safety

- Store money as integer minor units plus ISO currency code.
- Use exact decimal arithmetic for taxes, rates, percentages, and intermediate values; never use binary floating point for money.
- Vynlo ships no tenant contract formula. Tenant calculations use the safe declarative runtime.
- Arbitrary tenant JavaScript, SQL, shell, filesystem, module imports, and unrestricted network calls are prohibited.
- Active formula, tax, workflow, template, numbering, export, and configuration versions are immutable.
- Corrections create new versions or reversal events; they do not rewrite history.

## 7. Documents

- The Document Engine owns schemas, template rendering, numbering, lifecycle, files, checksums, signing status, voiding, and supersession.
- Templates use versioned HTML/CSS and sandboxed Liquid-style variables/conditions/loops; no template JavaScript.
- Preview documents are watermarked and never consume official numbers.
- Official numbers allocate transactionally and are never reused.
- Preserve template source, assets, field schema, renderer version, input snapshot, generated checksum, and signed files.
- Placeholder legal templates remain feature-disabled in production.

## 8. Integrations and jobs

- Commit the authoritative database change and outbox record first.
- Jobs use idempotency keys, bounded retries, exponential backoff with jitter, and dead-letter/admin review.
- The database is the operational source of truth.
- Provider drift is detected and surfaced; do not silently overwrite external or internal changes.
- Tenant credentials are encrypted runtime records and never appear in Git or global environment files.

## 9. Authentication and security

- Normal session maximum is 14 days.
- MFA is mandatory for workspace administrators and all Drivven users.
- Sensitive actions require recent step-up authentication when strong authentication is older than 15 minutes.
- Shared user accounts are prohibited.
- Audit records are append-only from application roles.
- Never expose service-role credentials to the browser.
- Never place real customer data, signed documents, secrets, or production exports in tests, logs, screenshots, fixtures, or commits.

## 10. Quality gates

Every applicable change must include:

- requirement and acceptance IDs;
- schema migration and compatibility notes;
- RLS and authorization tests;
- unit, invariant, failure, concurrency, and idempotency tests;
- API contract changes;
- mobile and desktop UI tests;
- accessibility and localization handling;
- audit-event assertions;
- job telemetry and operational notes;
- documentation and traceability updates.

A happy-path implementation alone is not complete. Failure, retry, authorization, concurrency, audit, accessibility, tenant isolation, and rollback behavior are part of the feature.
