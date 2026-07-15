# Drivven pilot scope

## Objective

Replace fragmented inventory, Drive, Webflow, and contract work with a mobile-friendly Vynlo workspace while preserving Drivven's private business rules.

## Pilot users and locations

- Three users: one administrator, one sales user, and one sales/office user.
- Both sales users may operate across Montreal and Sherbrooke.
- Shared workspace; stock numbers are not location-specific.

## Required pilot vertical slice

1. Invite/login with MFA and Drivven role seed.
2. Create or import an inventory unit.
3. Enter/paste VIN, decode basic vehicle facts, and review duplicate warnings.
4. Allocate stock number on confirmed creation.
5. Create/link the Google Shared Drive folder.
6. Add costs, price, notes, and optimized vehicle photos.
7. Publish or update the listing in Webflow through an asynchronous job.
8. Create customer/deal information.
9. Record full initial payment through one or more settled transactions.
10. Preview and finalize a Drivven RTB document using a private formula/template version.
11. Print, manually mark signed, and upload signed scan.
12. Mark delivered; unpublish Webflow item and move Drive folder to Sold structure.
13. Preserve audit, formula snapshot, template version, file checksums, and document lineage.

## In-scope private capabilities

- Drivven stock-number rule.
- Drivven Google Drive and Webflow adapters/mappings.
- Drivven marketing daily-payment calculation.
- RTB formula and immutable original schedule.
- RTB PDF lifecycle.
- Existing inventory migration tool.
- Drivven-specific inventory workflow, including later return/repossessed intake states.

## Explicitly deferred

- Automatic OCR from purchase/registration documents.
- GoCardless payment-status synchronization and recurring payment servicing.
- Gmail/e-transfer reconciliation.
- Automated collection letters and repossession actions.
- Digital signatures.
- Marketplace automation.
- Production activation of the five non-RTB document types before their templates are approved.
