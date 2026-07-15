# Drivven requirement traceability

| Requirement | Summary | Configuration/spec | Verification |
|---|---|---|---|
| DRV-AUTH-001 | Three users, admin/sales/sales-office, both locations | `tenant-seeds/drivven/roles/roles.yaml` | Role/RLS/E2E |
| DRV-LOC-001 | Montreal and Sherbrooke | `tenant-seeds/drivven/locations/` | Seed/config test |
| DRV-STOCK-001 | `P###`, permanent global sequence | `tenant-seeds/drivven/numbering/stock.yaml` | Concurrency/invariant |
| DRV-STOCK-002 | Direct trade-in `a/b/c`, no nested suffix | stock definition | Workspace-config/domain tests |
| DRV-INV-001 | VIN manual/paste, decode, duplicate review | pilot/platform inventory | E2E |
| DRV-DRV-001 | Create/move/reconcile Shared Drive folders | `tenant-seeds/drivven/integrations/google-drive.yaml` | Staging adapter tests |
| DRV-WEB-001 | Webflow Inventory mapping and immediate queue | `tenant-seeds/drivven/integrations/webflow.yaml` | Staging mapping tests |
| DRV-MEDIA-001 | Drive/master plus 1080px WebP channel images | platform media + Webflow config | Golden image/E2E |
| DRV-CRM-001 | Customer/deal history and timeline | platform CRM/deals | E2E |
| DRV-RTB-001 | Private RTB document type and lifecycle | `tenant-seeds/drivven/documents/rtb/` | Document/PDF/E2E |
| DRV-RTB-002 | 70/30 private split and amortization | `tenant-seeds/drivven/formulas/rtb/` | Approved golden cases |
| DRV-RTB-003 | RTB number/filenames/signature scan | numbering/document config | Concurrency/lineage |
| DRV-PAY-001 | Initial payment must be fully settled | RTB workflow + platform one-time payments | Financial/E2E |
| DRV-EXP-001 | Private accounting export | `tenant-seeds/drivven/exports/accounting-v1.yaml` | Export snapshot/approval |
| DRV-MIG-001 | Link existing Drive/Webflow inventory | `tenant-seeds/drivven/migration/` | Dry-run/reconciliation |
| DRV-DOC-OTHER-001 | Five additional document scaffolds disabled | `tenant-seeds/drivven/documents/*` | Schema/feature flag |
| DRV-SVC-FUT-001 | GoCardless/Gmail/collections later | `tenant-seeds/drivven/future/` and integration stubs | Future module gate |
| DRV-MKT-FUT-001 | Marketplace/Telegram automation later | future product backlog, not pilot | Future spec required |

Every implementation PR references the applicable DRV requirement and Vynlo platform requirement. A Drivven requirement must not be satisfied by hardcoding the workspace identity in platform code.
