# Requirements traceability

| Requirement | Class | Summary | Normative source | Primary verification |
|---|---|---|---|---|
| VYN-AUTH-001 | Platform | Invite-only identity and memberships | `modules/AUTH_AND_USERS.md` | E2E auth/membership |
| VYN-AUTH-002 | Platform | 14-day session, MFA, step-up | Auth/security specs | Session/assurance tests |
| VYN-TEN-001 | Platform | Workspace isolation and legal-entity separation | `architecture/MULTI_TENANCY.md` | RLS/API/job isolation; cross-actor command-key isolation in `021` pgTAP |
| VYN-INV-001 | Platform | Vehicle plus inventory-unit model | Inventory/data specs; `implementation/MILESTONE_2_INVENTORY_OPERATIONS.md` | DB/domain/application/route/E2E tests; `016`, `021` pgTAP |
| VYN-INV-002 | Platform | Manual VIN, decode, duplicate review | Inventory spec; `implementation/MILESTONE_2_VIN_PIPELINE.md`; `implementation/MILESTONE_2_VIN_INVENTORY_INTAKE.md` | Provider/application/worker/route/E2E tests; `008`, `011`, `018` pgTAP |
| VYN-NUM-001 | Platform | Transactional permanent numbering | `modules/NUMBERING_ENGINE.md` | Concurrency/invariant |
| VYN-COST-001 | Platform | Inventory cost ledger | Inventory/data specs; `implementation/MILESTONE_2_COST_SEARCH.md`; `implementation/MILESTONE_2_INVENTORY_OPERATIONS.md` | Ledger/reversal/application/route tests; `010`, `016`, `021` pgTAP |
| VYN-MEDIA-001 | Platform | Async image normalization/derivatives and byte-preserved legal originals | Media spec; `implementation/MILESTONE_2_MEDIA_PIPELINE.md`; `implementation/MILESTONE_2_VEHICLE_MEDIA_MANAGEMENT.md` | Golden/adversarial image tests; `009`, `012`, `013`, `014`, `015`, `019`, `021`, `023`, `024` pgTAP; worker, legal and vehicle status/retry routes, and responsive media-manager tests |
| VYN-LIST-001 | Platform | Generic channel listing and sync state | Listings/provider specs | Adapter/job/drift tests |
| VYN-CRM-001 | Platform | Leads, activities, tasks, appointments | CRM spec | E2E lead conversion |
| VYN-DEAL-001 | Platform | Configurable retail deal records | Deal spec | State/invariant tests |
| VYN-FIN-001 | Platform | Third-party lender tracking only | Finance spec | Application lifecycle |
| VYN-PAY-001 | Platform | One-time transactions and reversals | Payment spec | Financial invariant tests |
| VYN-DOC-001 | Platform | Generic immutable document engine | Document spec | PDF/lineage/sandbox |
| VYN-CALC-001 | Platform | Safe declarative tenant calculations | Calculation spec | AST/property/resource tests |
| VYN-TAX-001 | Platform | Versioned tax-pack runtime | Tax spec | Pack golden tests |
| VYN-WF-001 | Platform | Configurable state machines | Workflow/data specs | Transition/version tests |
| VYN-FIELD-001 | Platform | Typed custom fields | Workflow/field spec | Schema/permission tests |
| VYN-EXP-001 | Platform | Versioned CSV/XLSX exports | Export spec | Snapshot/security tests |
| VYN-API-001 | Platform | Stable `/api/v1` | API catalogue/OpenAPI; Milestone delivery records | Strict application/route response tests and OpenAPI lint |
| VYN-JOB-001 | Platform | Outbox, retry, idempotency, dead letter | API/jobs spec; `implementation/MILESTONE_2_MEDIA_PIPELINE.md` | Failure/retry tests; legal-original copied-policy, causation/replay, and actor-idempotency coverage in `023` pgTAP |
| VYN-SEC-001 | Platform | RLS and permission isolation | RLS matrix; `implementation/MILESTONE_2_INVENTORY_OPERATIONS.md` | Negative matrix, strict route errors, forced-RLS/authorization pgTAP |
| VYN-AUD-001 | Platform | Append-only audit and approvals | Event/approval specs; Milestone delivery records | Immutability and audit/outbox parity tests |
| VYN-UX-001 | Platform | Mobile-first PWA/shadcn | UX specs; `implementation/MILESTONE_2_INVENTORY_OPERATIONS.md` | 360/tablet/desktop E2E, overflow, controls, axe |
| VYN-I18N-001 | Platform | English/French localization architecture | UX/NFR; Milestone delivery records | Locale-key and English/French E2E tests |
| VYN-OPS-001 | Platform | Environments, observability, recovery | Operations specs | Staging exercises |
| VYN-CFG-001 | Platform | Versioned runtime workspace configuration, entitlements, import/export, activation | Workspace configuration specs | T-CFG-001..006 |
| VYN-STOR-001 | Platform | Managed/external storage and authorized file access | Storage/media/security specs; `implementation/MILESTONE_2_MEDIA_PIPELINE.md` | T-STOR-001; exact private intent/read/delete-boundary tests; opaque authorization and service-loader coverage in `017`, `019`, and boolean-only vehicle policy coverage in `022` pgTAP |
| VYN-SEARCH-001 | Platform | Bounded search, filters, and saved views | Search/API/UX specs; `implementation/MILESTONE_2_COST_SEARCH.md`; `implementation/MILESTONE_2_INVENTORY_OPERATIONS.md` | Query/application/route/E2E tests; `010`, `016` pgTAP |
| VYN-APP-001 | Platform | Approval records and exact-version activation gates | Approval/config specs | T-CFG-003..004 |
| STD-INV-001 | Starter | Conventional retail inventory workflow | `packs/starter-retail-dealer/workflows/inventory.yaml`; `implementation/MILESTONE_2_INVENTORY_WORKFLOW_FOUNDATION.md` | Schema/reference validation plus exact seed checksum and state/transition parity in `scripts/validate_spec.py` |
| STD-DEAL-001 | Starter | Cash/external-finance deal defaults | Starter pack | Pack/E2E tests |
| TAX-CA-QC-001 | Tax pack | Candidate Québec tax profile | Tax pack | Professional approval/golden tests |

## Traceability rule

Every implemented requirement must connect to:

```text
requirement ID
data/API/UI/config implementation
permission and audit behavior
acceptance criterion
automated test ID
release/activation state
```

New normative behavior requires updating this table. Workspace-specific requirements use their own prefix and traceability table, such as `DRV-RTB-001`; they remain runtime configuration or first-workspace seed artifacts inside the single repository.
