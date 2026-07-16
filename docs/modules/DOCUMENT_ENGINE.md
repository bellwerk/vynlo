# Generic document engine

Vynlo owns rendering, field schemas, versioning, numbering, files, and lineage. Tenants own legal wording, branding, types, optional formulas, and approval.

## Technology

- HTML/CSS source bundle.
- Sandboxed Liquid-style variables, loops, and conditions.
- No JavaScript, SQL, shell, filesystem, or unrestricted network access.
- Allowlisted formatting helpers.
- Playwright/Chromium worker rendering.

## Field library

Legal entity/brand/location, party/customer, vehicle/inventory, deal, trade-in, price/fees/taxes, lender, dates, notes, signatures, initials, and custom fields.

## Preview

Watermarked `DRAFT / NON-PRODUCTION`, unnumbered, freely regenerable.

## Official generation

1. Validate activation/approvals/data/permissions.
2. Resolve exact template, schema, tax, calculation, numbering, locale, and renderer versions.
3. Allocate a permanent number transactionally.
4. Store immutable input/version snapshot and queue render.
5. Render, checksum, store, and mark generated.
6. Retry idempotently without allocating another number.

Corrections with changed data create a new document and supersede the old. Signed scans are separate immutable file versions. Preserve source bundle/assets/schema/renderer/checksums/snapshots; do not preserve an editable generated PDF.

Production legal documents remain unavailable until exact-version approval is recorded.
