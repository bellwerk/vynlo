# Drivven workspace bootstrap package

**Package version:** 1.0.0  
**Platform specification:** Vynlo Product & Engineering Specification v2.1  
**Visibility:** Private configuration owned by Drivven / Auto BS Inc.  
**Purpose:** Repeatable development, migration, staging, UAT, and initial production provisioning.

This directory is not a separate repository and is not the runtime source of truth. Importing it creates versioned draft configuration records inside a Drivven workspace. Approved versions are activated through Vynlo and remain auditable in the database.

## Boundary

Vynlo supplies generic inventory, CRM, deal, document, workflow, calculation, tax, export, media, and integration capabilities. This seed owns Drivven-specific definitions, including:

- Montreal and Sherbrooke locations;
- Drivven roles and permissions;
- `P###` and direct trade-in suffix stock numbering;
- Google Shared Drive folder rules;
- Webflow mapping and marketing daily-payment formula;
- Drivven document types and French template source;
- private RTB, 70/30, schedule, and future servicing rules;
- private accounting export;
- migration instructions and Drivven acceptance fixtures.

Nothing in this directory is a Vynlo default for another dealership. Reusable platform packages may not import it or branch on its workspace key.

## Security

Do not commit:

- provider credentials or OAuth refresh tokens;
- real customers, leads, deals, or payment data;
- signed contracts or identity documents;
- production exports;
- service-account files or private keys;
- unredacted fixtures.

## Production gates

The RTB flow may be built and tested with synthetic fixtures, but cannot be enabled for customer use until the final French template, legal wording, seller identifiers, tax/accounting approval, and exact golden cases are approved.

Other Drivven document types remain disabled until their templates and field catalogues are individually approved.

## Read first

1. `../../docs/tenants/drivven/DRIVVEN_PILOT_SCOPE.md`
2. `../../docs/tenants/drivven/DECISIONS.md`
3. `../../docs/tenants/drivven/ACCEPTANCE_CRITERIA.md`
4. `../../docs/tenants/drivven/LAUNCH_GATES.md`
5. `manifest.yaml`
