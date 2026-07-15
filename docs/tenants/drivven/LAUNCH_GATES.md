# Drivven production launch gates

## Workspace and integrations

- Exact legal entity name and required registration/tax/permit identifiers verified.
- Production Montreal/Sherbrooke location data verified.
- Drivven administrators and users invited with MFA.
- Shared Drive, Active/Sold/Archived parent folder IDs connected and tested.
- Webflow staging mapping approved; production collection/field/locale IDs verified.
- Production secrets exist only in the approved secret store.
- Existing folder/CMS migration dry-run and reconciliation approved.

## RTB activation

- Final French legal template and annex supplied.
- Page-by-page field catalogue approved.
- Legal reviewer approves contract, fee, notice, signature, and enforcement wording.
- Accountant approves tax, trade-in, brokerage, initial-payment, and export treatment.
- Exact formula version passes all signed golden cases.
- Numbering start value approved.
- PDF visual regression set approved.
- Non-production watermark removed only from the approved template version.
- Feature flag enabled only after all approval records are attached.

## Operational readiness

- Backup restore test passed.
- Incident and provider-outage runbooks exercised.
- Support/admin can review failed jobs, drift, audit, and document lineage.
- Mobile and desktop UAT passed.
- User training and rollback plan approved.
- No real customer data appears in development or fixture repositories.
