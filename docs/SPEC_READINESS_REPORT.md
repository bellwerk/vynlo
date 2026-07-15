# Vynlo v2.1 specification readiness report

**Generated:** 2026-07-15  
**Specification:** 2.1.0  
**Result:** Ready for development. Customer-facing legal, tax, financial, and production-provider behavior remains subject to explicit activation gates.

## Final architecture decision

```text
one repository: vynlo
normal tenant: runtime workspace + versioned configuration
first workspace bootstrap: tenant-seeds/drivven
separate tenant repository: exceptional only
```

This resolves the final architecture inconsistency from v2. Normal dealership onboarding does not create Git repositories or application forks.

## Decisions completed

- Vynlo is independent from Drivven and inventory-first.
- The target customer primarily performs cash sales and occasionally arranges third-party financing.
- Drivven RTB, 70/30, recurring payments, collections, return/repossession behavior, stock, provider mappings, and accounting exports remain workspace-specific.
- One canonical modular-monolith repository and runtime workspace configuration are defined.
- Vehicle versus inventory holding episode, cost ledger, generalized parties, CRM, deals, trade-ins, external finance, one-time transactions, media, listings, documents, workflows, tax, calculations, exports, jobs, audit, and approvals are modeled.
- Mobile-first PWA, shadcn/ui, English/French infrastructure, image resizing, no camera VIN scanning, and 14-day session/step-up policies are locked.
- API, database, RLS, background jobs, provider contracts, errors, security, operations, testing, implementation milestones, and traceability are specified.
- Drivven roles, locations, stock, Drive, Webflow, RTB development flow, migration, and activation gates are specified without becoming platform defaults.

## Automated specification validation

The repository-level validator completed with an overall `pass`. The machine-readable result is stored in `../VALIDATION_RESULTS.json`, and the tamper-evident file inventory is stored in `../FILE_MANIFEST.sha256`. Checks cover:

- JSON/YAML parsing and Draft 2020-12 schema validity;
- configuration artifacts against their schemas;
- referenced artifact paths and workflow transitions;
- OpenAPI internal references, path parameters, and operation identifiers;
- Markdown file links;
- candidate Drivven mathematical invariants;
- reusable-platform versus Drivven workspace source boundaries;
- obvious secret-pattern scanning.

This validation proves specification consistency and candidate arithmetic invariants. It does not replace legal, accounting, privacy, penetration, provider, or production UAT approval.

## Development authorization

Development may begin with:

1. repository/CI and environment scaffolding;
2. tenancy/auth/RLS/audit/configuration foundation;
3. the first inventory-to-preview vertical slice;
4. inventory/media/search and provider foundations;
5. CRM/deals/external finance/one-time transactions;
6. document/calculation/tax/export engines;
7. Drivven staging import, integration setup, migration dry run, and UAT.

Codex and developers must use the root `AGENTS.md`, `docs/architecture/PRINCIPLES.md`, the consolidated v2.1 spec, and the implementation plan as governing instructions.

## Production activation inputs

These do not block unrelated engineering:

### Vynlo/public SaaS

- final commercial branding/domain/trademark review;
- final jurisdiction-specific privacy/retention policies;
- commercial subscription/billing product, outside the first pilot;
- approved providers/tax packs for additional markets.

### Québec tax pack

- professional approval of supported transaction contexts;
- exact trade-in and fee classifications;
- signed exact golden fixtures;
- approval record on the immutable version.

### Drivven

- exact Auto BS Inc. legal/tax/permit identifiers;
- production Shared Drive and Webflow IDs/credentials/mappings;
- inventory/CMS migration inventory and approved reconciliation;
- final approved French RTB template, legal wording, notices, annex, and signature/initial fields;
- accounting/legal approval of RTB tax, trade-in, brokerage, fee, and interest behavior;
- approved exact RTB fixtures;
- production numbering starting values;
- final branding/font licensing;
- approved non-RTB templates before enabling each one.

Missing inputs produce disabled or preview-only behavior with an explicit gate error. Engineering must never substitute guessed legal/accounting content.

## Deliberately deferred

- lender-network submission;
- standard recurring payment servicing;
- GoCardless/Gmail reconciliation and collections automation;
- digital signatures;
- visual document/formula/workflow builders;
- appraisal/market/sourcing intelligence;
- marketplace automation;
- native mobile application;
- offline writes;
- service/parts/payroll/general-ledger modules.

## Final readiness statement

The v2.1 set is suitable as the development authority. The application can be implemented and tested with synthetic workspaces and the retail starter pack. Drivven can be provisioned from its seed into staging and production runtime configuration. Production legal, tax, financial, and provider actions remain correctly gated until responsible approvals and external inputs are supplied.
