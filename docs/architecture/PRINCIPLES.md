# Vynlo engineering principles

**Status:** Normative  
**Purpose:** Prevent architectural drift while Vynlo evolves from the Drivven pilot into a multi-tenant SaaS.

## 1. A tenant is data and configuration

A dealership is represented by an organization, workspace, legal entities, locations, members, entitlements, and versioned configuration in the database. A normal tenant is not a Git repository, code fork, dedicated branch, or separate deployment.

## 2. Platform code is tenant-neutral

Reusable source code may not reference Drivven, Auto BS, a location name, RTB, a private formula, a private stock convention, or a tenant-specific provider mapping. Runtime behavior is resolved through permissioned configuration and stable provider interfaces.

## 3. Build a modular monolith first

Clear domain boundaries are required; independent services are not. Vynlo starts as one repository, one web/API application, one worker deployment, and one Postgres database. Split services only after measurable scale, reliability, compliance, or ownership needs justify the cost.

## 4. Configuration is versioned and constrained

Workflows, document types, templates, numbering, formulas, tax assignments, exports, and provider mappings are typed, schema-validated, versioned, approval-aware, and auditable. “Configurable” never means arbitrary code execution or weakening tenant isolation.

## 5. Official history is immutable

Activated formulas/templates and generated official documents are immutable. Number allocations are never reused. Corrections create reversals, replacement versions, or superseding documents; they do not rewrite history.

## 6. Financial math is exact

Money uses integer minor units and ISO currency. Rates and intermediate calculations use exact decimal arithmetic. Every financial calculation records the definition version, inputs, outputs, rounding rules, and checksums.

## 7. External systems are eventually consistent

The database transaction is authoritative. Storage, listing channels, PDF generation, image processing, and email operate through durable jobs. Provider outages produce visible retry/action states rather than lost work or rolled-back business records.

## 8. Security is enforced below the UI

Permissions are checked in application services and Postgres RLS. UI hiding is never authorization. Jobs, exports, caches, files, and logs preserve workspace context. Sensitive actions require recent strong authentication and produce append-only audit records.

## 9. Mobile is a primary interface

Core sales and inventory tasks must work comfortably on a phone. Desktop tables are enhancements, not the only workflow. shadcn/ui components must be accessible, responsive, touch-friendly, localized, and backed by stable server behavior.

## 10. Files are handled by purpose

Marketing images may be normalized and optimized. Legal, identity, purchase, registration, and signed documents preserve their originals. Every file has explicit classification, retention, access, checksum, and derivative rules.

## 11. Tax and legal content require explicit ownership

The platform supplies engines and approval gates. Tax packs are separately sourced and tested. Tenants own legal wording and business formulas. Engineering does not invent tax, accounting, enforcement, or contractual content.

## 12. The API is the reusable product boundary

Web-specific features call the same application services and `/api/v1` rules used by future native or partner clients. No critical business behavior exists only inside a React component or Server Action.

## 13. Do not build speculative platforms inside the platform

Visual formula builders, workflow builders, document designers, AI-agent frameworks, multiple industry starter packs, and microservices are deferred until validated demand exists. Release 1 prioritizes complete dealership workflows.

## 14. Every important behavior is testable and traceable

A normative requirement has an ID, acceptance criterion, implementation reference, permission/audit behavior, and automated test. Platform tests remain tenant-neutral; Drivven tests remain in the Drivven seed/test area.

## 15. Production activation is separate from development readiness

A module can be implemented against synthetic fixtures while its legal template, credentials, provider IDs, or professional approvals are pending. The feature remains disabled until activation gates pass; unrelated platform development continues.
