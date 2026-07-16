# Decision register

**Specification version:** 2.1.0  
**Status:** Approved unless explicitly marked as a production activation gate.

## Product decisions

| ID | Decision |
|---|---|
| VYN-DEC-001 | Vynlo is an independent, inventory-first dealership platform; Drivven is the first configured workspace. |
| VYN-DEC-002 | The initial market is small and medium independent vehicle dealerships, especially used-vehicle dealers. The data model may also represent new vehicles. |
| VYN-DEC-003 | “Similar to vAuto” means centralized inventory operations, merchandising, CRM, deals, workflow, and reporting. Licensed market data, appraisal intelligence, sourcing, and price-to-market recommendations are future products. |
| VYN-DEC-004 | The standard tenant primarily performs cash sales and may arrange third-party financing. In-house loan servicing, leasing, RTB, rentals, collections, and repossession are not default workflows. |
| VYN-DEC-005 | Vynlo supplies a safe expression/calculation runtime but no preset tenant contract formula. Versioned jurisdiction tax packs are the only platform-maintained business calculation packs. |
| VYN-DEC-006 | Customer-facing legal templates are tenant-owned and tenant-approved. Starter templates are demonstrations until explicitly activated. |
| VYN-DEC-007 | Vynlo begins as a modular monolith. New services or plugin infrastructure require demonstrated need and an ADR. |

## Repository and tenant decisions

| ID | Decision |
|---|---|
| VYN-DEC-010 | Use one canonical private repository named `vynlo`. |
| VYN-DEC-011 | A tenant is a database workspace with versioned configuration and secure assets, not a repository or code fork. |
| VYN-DEC-012 | Drivven bootstrap artifacts live under `tenant-seeds/drivven` only for migration, repeatable provisioning, and tests. Future tenants normally require no source-control folder. |
| VYN-DEC-013 | Real tenant credentials, customer data, signed documents, production exports, and unredacted identity files never enter Git. |
| VYN-DEC-014 | Portable workspace configuration packages are optional import/export artifacts, not the runtime source of truth. Activated configuration is stored in versioned database records. |
| VYN-DEC-015 | Platform code must not branch on workspace identity. No `if drivven` conditions or tenant imports are permitted. |

## Technical architecture decisions

| ID | Decision |
|---|---|
| VYN-DEC-020 | Use a pnpm monorepo with `apps/web` and `apps/worker` inside the single repository. |
| VYN-DEC-021 | Use Next.js App Router, strict TypeScript, Tailwind CSS, and shadcn/ui for the web/PWA reference implementation. |
| VYN-DEC-022 | Use Supabase Postgres/Auth/RLS as the reference database and identity platform; `workspace_id` is the operational isolation key. |
| VYN-DEC-023 | Use `/api/v1` as the stable client contract. Server Actions call the same application services. |
| VYN-DEC-024 | Use a transactional outbox and durable Postgres-backed jobs. External calls are asynchronous, idempotent, retryable, and observable. |
| VYN-DEC-025 | Use provider adapters for storage, website/listing channels, VIN decoding, email, lender services, accounting, and future marketplaces. |
| VYN-DEC-026 | Vynlo-managed storage is available by default; a workspace may connect an external storage provider. |

## UI decisions

| ID | Decision |
|---|---|
| VYN-DEC-030 | Release 1 is a mobile-first installable PWA, not a native App Store/Play Store application. |
| VYN-DEC-031 | Target WCAG 2.2 AA and support core workflows from a 360 px viewport. |
| VYN-DEC-032 | UI localization architecture supports English and French from day one. Workspace and user preferences select defaults. |
| VYN-DEC-033 | Offline writes are not supported in MVP. The UI shows connectivity and requires server-confirmed saves. |
| VYN-DEC-034 | Camera-based VIN scanning is excluded. VIN is typed or pasted from registration or transaction paperwork; OCR is future work. |
| VYN-DEC-035 | Mobile inventory uses cards/lists and detail editing; desktop may additionally use dense tables and safe inline editing. |

## Domain decisions

| ID | Decision |
|---|---|
| VYN-DEC-040 | Separate physical `vehicles` from tenant `inventory_units` so reacquisition and multiple holding episodes are represented correctly. |
| VYN-DEC-041 | Store inventory costs as ledger entries rather than fixed purchase/repair/transport columns. |
| VYN-DEC-042 | Use generalized person/organization parties and role-based deal participants. |
| VYN-DEC-043 | Core money records cover one-time deposits, receipts, refunds, trade-in credits, and lender proceeds; recurring servicing is optional. |
| VYN-DEC-044 | Third-party finance MVP tracks applications and lender-returned terms but does not submit to lender networks or service loans. |
| VYN-DEC-045 | Workflow labels and transitions are workspace-configured and mapped to neutral canonical categories. |
| VYN-DEC-046 | Custom fields support safe typed scalar and option values in MVP. Full visual builders are future work. |
| VYN-DEC-047 | Feature availability is controlled by workspace entitlements/configuration, not separate deployments. |

## Documents, calculations, tax, and exports

| ID | Decision |
|---|---|
| VYN-DEC-050 | Primary document rendering uses versioned HTML/CSS with sandboxed Liquid-style templates and Playwright PDF output. |
| VYN-DEC-051 | Preview PDFs are watermarked and unnumbered. Official generation allocates a permanent number and creates an immutable document. |
| VYN-DEC-052 | Preserve template source, assets, schemas, renderer version, input snapshots, and checksums. Do not retain an editable generated PDF. |
| VYN-DEC-053 | Tenant calculations are declarative, typed, versioned definitions. Arbitrary JavaScript and executable code are prohibited. |
| VYN-DEC-054 | Tax packs are independent, effective-dated, tested, and approval-gated. Québec is the first candidate production tax pack. |
| VYN-DEC-055 | Accounting/export column definitions are workspace configuration. Vynlo owns only the generic versioned CSV/XLSX export engine. |

## Media decisions

| ID | Decision |
|---|---|
| VYN-DEC-060 | Image normalization and resizing are Release 1 platform capabilities. |
| VYN-DEC-061 | Default vehicle-photo outputs are a 2560 px normalized master, 1080 px web derivative, and 640/320 px thumbnails; profiles are configurable. |
| VYN-DEC-062 | Public derivatives strip GPS metadata. Legal and signed documents preserve originals and use separate previews. |
| VYN-DEC-063 | Raw vehicle-photo originals are retained for seven days after verified processing by default; workspace policy may retain them longer. |

## Authentication and security

| ID | Decision |
|---|---|
| VYN-DEC-070 | Maximum normal session lifetime is 14 days. Access tokens remain short-lived and refresh automatically. |
| VYN-DEC-071 | MFA is mandatory for workspace administrators. A workspace may require all users; Drivven does. |
| VYN-DEC-072 | Sensitive operations require step-up authentication when strong authentication is older than 15 minutes. |
| VYN-DEC-073 | MVP has no short platform-wide idle logout. A future optional local screen lock may protect shared terminals without ending the 14-day session. |
| VYN-DEC-074 | Audit logs are append-only and include workspace, actor, action, entity, change, reason, request context, timestamp, and authentication assurance. |

## Drivven boundary decisions

| ID | Decision |
|---|---|
| DRV-DEC-001 | Drivven/Auto BS RTB documents, 70/30 formula, payment servicing, late-fee policy, collections, return/repossession states, stock convention, integrations, and accounting export are workspace-specific configuration. |
| DRV-DEC-002 | Drivven seed files may exist in Git for development and repeatable provisioning, but production secrets and customer records remain encrypted runtime data. |
| DRV-DEC-003 | Drivven uses manual/pasted VIN entry and basic decoding; no camera VIN scanner. |
| DRV-DEC-004 | Drivven requires day-one image processing and 14-day sessions with MFA for all users. |

## Production activation gates

| ID | Gate |
|---|---|
| VYN-GATE-001 | A tax pack cannot activate until its jurisdiction rules, sources, approvals, and exact golden tests are accepted. |
| VYN-GATE-002 | A customer-facing legal document cannot activate until the workspace approves its text, field catalogue, template rendering, and signer requirements. |
| VYN-GATE-003 | A tenant calculation cannot activate without approved numerical fixtures and versioned approval records. |
| VYN-GATE-004 | Production integrations require encrypted credentials, least-privilege scopes, staging validation, and operational runbooks. |
| VYN-GATE-005 | Public commercial launch requires final privacy/retention policies and Vynlo name/domain/trademark review. |
| DRV-GATE-001 | Drivven RTB remains disabled until final French wording/template, seller identifiers, tax/accounting/legal approvals, and golden calculations are approved. |
