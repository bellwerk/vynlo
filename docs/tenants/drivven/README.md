# Drivven workspace specification

**Classification:** Workspace-specific, private Drivven / Auto BS Inc. requirements  
**Repository model:** Stored in the single `vynlo` repository for the pilot handoff; not a separate application or tenant repository  
**Runtime source of truth:** Activated, versioned workspace configuration records and secure assets

## Purpose

These documents define how the reusable Vynlo platform is configured for its first workspace, Drivven. They do not define Vynlo defaults for another dealership.

The related non-secret bootstrap, migration, synthetic fixture, and staging definitions are under `../../../tenant-seeds/drivven/`. Importing that package creates draft configuration records; an authorized approval flow activates immutable versions. Platform packages may not import this directory or branch on the Drivven workspace key.

## Governing files

1. `DRIVVEN_PILOT_SCOPE.md`
2. `DECISIONS.md`
3. `ACCEPTANCE_CRITERIA.md`
4. `TRACEABILITY.md`
5. `LAUNCH_GATES.md`
6. `../../../tenant-seeds/drivven/README.md`

## Security boundary

No production credentials, real customer data, signed contracts, identity documents, production exports, or unredacted fixtures belong here or elsewhere in Git. Provider credentials and production identifiers are stored through encrypted workspace integration records and secret-management facilities.

## Activation rule

Drivven-only behavior may be implemented and tested with synthetic data, preview templates, and candidate fixtures. Customer-facing legal, tax, accounting, payment, and provider behavior remains disabled until the corresponding launch gate records an explicit approval and required external input.
