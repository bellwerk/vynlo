# Source provenance

**Specification:** Vynlo Product & Engineering Specification v2.1  
**Decision date:** 2026-07-15

## User-supplied discovery sources

The specification consolidates:

- the original DEH/Vynlo questionnaire and detailed answers;
- DEH Answers 2;
- the subsequent remaining-decision answers;
- the uploaded rent-to-buy PDFs, supplied as layout/field references rather than final approved production contracts;
- the Vynlo v1 discovery documentation;
- the July 14, 2026 specification audit;
- later decisions that separate reusable Vynlo behavior from Drivven workspace configuration;
- the correction to use one canonical repository and runtime workspace configuration;
- the removal of camera-based VIN scanning;
- the day-one image-normalization requirement;
- the 14-day session and sensitive-action step-up policy.

The unrelated Year-End Pack Assistance banking material is excluded.

## External technical references

The implementation assumptions were checked against official documentation current at the decision date:

- Next.js App Router PWA guidance, including manifests, installation, service workers, and security considerations;
- Supabase Auth session controls, MFA/authenticator assurance, and Postgres Row-Level Security guidance;
- Google Drive API Shared Drive requirements, including `supportsAllDrives` and Shared Drive search/change parameters;
- Webflow Data API CMS item and locale behavior;
- Revenu Québec GST/QST rates and used-road-vehicle trade-in guidance for the candidate Québec tax pack.

Exact URLs and retrieval notes are recorded in `SOURCE_REFERENCES.md`.

These references support technical design and candidate tax-pack metadata. They do not replace professional legal or accounting approval for a production tenant transaction.

## Conflict-resolution priority

When historical sources conflict, apply this order:

1. `docs/VYNLO_PRODUCT_ENGINEERING_SPEC_V2_1.md`.
2. `docs/02_DECISION_REGISTER.md`.
3. Normative module/data/API/security/UX/operations specifications.
4. `docs/tenants/drivven/DECISIONS.md` for Drivven-owned behavior.
5. The exact activated immutable workflow/template/formula/tax/export/configuration version.
6. Earlier discovery answers and example PDFs.

No example PDF overrides a later approved decision or activated production artifact.
