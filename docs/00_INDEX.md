# Specification index

## Status legend

- **Approved:** implementation may proceed.
- **Activation gate:** implementation/testing may proceed; production use requires the listed approval or external input.
- **Future:** outside Release 1.

## Start here

- [Development handoff](../DEVELOPMENT_HANDOFF.md)
- `../README.md`
- `../AGENTS.md`
- `VYNLO_PRODUCT_ENGINEERING_SPEC_V2_1.md`
- `architecture/PRINCIPLES.md`
- `implementation/TOOLCHAIN_BASELINE.md`
- `implementation/IMPLEMENTATION_PLAN.md`
- `implementation/EPICS_AND_STORIES.md`
- `implementation/ENGINEERING_HANDOFF_CHECKLIST.md`
- `implementation/MILESTONE_1_TENANCY_FOUNDATION.md`

## Milestone 1 delivery records

- [End-to-end source integration](implementation/MILESTONE_1_END_TO_END.md)
- [Tenancy and identity foundation](implementation/MILESTONE_1_TENANCY_FOUNDATION.md)
- [Configuration and entitlement foundation](implementation/MILESTONE_1_CONFIGURATION_ENTITLEMENTS.md)
- [Transactional outbox and durable jobs](implementation/MILESTONE_1_OUTBOX_JOBS.md)
- [First vertical slice](implementation/MILESTONE_1_FIRST_VERTICAL_SLICE.md)
- [Invite-only authentication](implementation/MILESTONE_1_INVITE_ONLY_AUTH.md)
- [Document-preview pipeline](implementation/MILESTONE_1_DOCUMENT_PREVIEW_PIPELINE.md)
- [Document-preview worker](implementation/MILESTONE_1_PREVIEW_WORKER.md)
- [Invitation-delivery worker](implementation/MILESTONE_1_INVITATION_DELIVERY_WORKER.md)
- [PWA and localization shell](implementation/MILESTONE_1_PWA_SHELL.md)

## Milestone 2 delivery records

- [Inventory and workflow database foundation](implementation/MILESTONE_2_INVENTORY_WORKFLOW_FOUNDATION.md)
- [Durable VIN pipeline](implementation/MILESTONE_2_VIN_PIPELINE.md)
- [Inventory cost and search slice](implementation/MILESTONE_2_COST_SEARCH.md)
- [Media and managed-storage pipeline](implementation/MILESTONE_2_MEDIA_PIPELINE.md)
- [VIN-backed inventory intake](implementation/MILESTONE_2_VIN_INVENTORY_INTAKE.md)
- [Inventory operations](implementation/MILESTONE_2_INVENTORY_OPERATIONS.md)
- [Vehicle media management](implementation/MILESTONE_2_VEHICLE_MEDIA_MANAGEMENT.md)

## Governance

- `01_GLOSSARY.md`
- `02_DECISION_REGISTER.md`
- `03_REQUIREMENTS_TRACEABILITY.md`
- `04_DEFINITION_OF_READY_AND_DONE.md`
- `SOURCE_PROVENANCE.md`
- `V2_TO_V2_1_CHANGELOG.md`
- `SPEC_READINESS_REPORT.md`

## Product

- `platform/PRODUCT_VISION.md`
- `platform/PERSONAS_AND_JOBS.md`
- `platform/MVP_SCOPE.md`
- `platform/NON_GOALS.md`
- `platform/ACCEPTANCE_CRITERIA.md`
- `platform/NON_FUNCTIONAL_REQUIREMENTS.md`

## Architecture

- `architecture/PRINCIPLES.md`
- `architecture/SYSTEM_ARCHITECTURE.md`
- `architecture/REPOSITORY_STRUCTURE.md`
- `architecture/MULTI_TENANCY.md`
- `architecture/WORKSPACE_CONFIGURATION.md`
- `architecture/WORKSPACE_CONFIGURATION_PACKAGES.md`
- `architecture/CONFIGURATION_AND_FEATURE_FLAGS.md`
- `architecture/API_AND_JOBS.md`
- `architecture/API_ENDPOINT_CATALOG.md`
- `architecture/adr/`

## Data

- `data/ERD.md`
- `data/DATA_DICTIONARY.md`
- `data/POSTGRES_SCHEMA_SPEC.md`
- `data/STATE_MACHINES.md`
- `data/EVENT_CATALOG.md`
- `data/PERMISSION_CATALOG.md`
- `data/RLS_AND_PERMISSIONS.md`
- `data/RLS_POLICY_MATRIX.md`

## Modules

- `modules/AUTH_AND_USERS.md`
- `modules/INVENTORY.md`
- `modules/MEDIA_PIPELINE.md`
- `modules/LISTINGS_AND_MERCHANDISING.md`
- `modules/CRM_AND_LEADS.md`
- `modules/DEALS_AND_TRADE_INS.md`
- `modules/THIRD_PARTY_FINANCE.md`
- `modules/PAYMENTS_ONE_TIME.md`
- `modules/DOCUMENT_ENGINE.md`
- `modules/CALCULATION_RUNTIME.md`
- `modules/TAX_ENGINE.md`
- `modules/WORKFLOW_AND_CUSTOM_FIELDS.md`
- `modules/NUMBERING_ENGINE.md`
- `modules/APPROVALS_AND_ACTIVATION.md`
- `modules/SEARCH_AND_FILTERING.md`
- `modules/EXPORTS_AND_REPORTING.md`

## Integrations

- `integrations/PROVIDER_CONTRACTS.md`
- `integrations/STORAGE_PROVIDER.md`
- `integrations/WEBSITE_PROVIDER.md`
- `integrations/VIN_PROVIDER.md`

## UX

- `ux/MOBILE_PWA_SHADCN.md`
- `ux/SCREEN_SPECIFICATIONS.md`
- `ux/FORM_BEHAVIOR_AND_ERRORS.md`
- `ux/ACCESSIBILITY.md`

## Security, operations, and testing

- `security/SECURITY_PRIVACY_RETENTION.md`
- `security/THREAT_MODEL.md`
- `operations/LOCAL_DEVELOPMENT.md`
- `operations/ENVIRONMENTS_DEPLOYMENT.md`
- `operations/TENANT_ONBOARDING.md`
- `operations/PACK_AND_SCHEMA_COMPATIBILITY.md`
- `operations/OBSERVABILITY_BACKUP_INCIDENTS.md`
- `operations/RUNBOOK_CATALOG.md`
- `testing/TEST_STRATEGY.md`
- `testing/TEST_CASE_CATALOG.md`
- `testing/PERFORMANCE_AND_SECURITY_GATES.md`
- `testing/UAT_AND_LAUNCH.md`
- `roadmap/RELEASES.md`

## Machine-readable contracts and configuration

- `../schemas/*.schema.json`
- `../contracts/openapi.v1.yaml`
- `../packs/starter-retail-dealer/`
- `../packs/tax/ca-qc/`
- `../tenant-seeds/drivven/`

## Drivven first workspace

- `tenants/drivven/README.md`

Drivven's specifications are under `tenants/drivven/`; its non-secret bootstrap/migration/test definitions are under `../tenant-seeds/drivven/`. They are part of the same repository but are not imported by reusable platform packages. Runtime behavior is installed into versioned workspace configuration records.
