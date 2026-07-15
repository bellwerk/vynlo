# Drivven decision register

| ID | Final decision |
|---|---|
| DRV-DEC-001 | Workspace/operating brand is Drivven; legal entity is configured separately as Auto BS Inc., subject to exact-record verification. |
| DRV-DEC-002 | Locations are Montreal and Sherbrooke; both users may access both. |
| DRV-DEC-003 | Regular stock numbers use global `P` plus a non-reused numeric sequence; no location prefix. |
| DRV-DEC-004 | A trade-in directly received in the source deal may use `a`, `b`, `c` suffixes. A later trade-in against a suffixed unit receives the next regular `P###`, avoiding nested suffixes. |
| DRV-DEC-005 | Stock allocates transactionally only when Create Vehicle is confirmed; VIN entry/decoding does not consume it. |
| DRV-DEC-006 | Google Shared Drive is Drivven's external document store; Vynlo remains operational source of truth. |
| DRV-DEC-007 | Webflow CMS is the Drivven website channel. Vynlo queues sync immediately and displays provider status. |
| DRV-DEC-008 | Drive is source of original vehicle media; Vynlo creates a normalized master and Webflow derivatives through the media pipeline. |
| DRV-DEC-009 | The marketing daily-payment formula is private Drivven configuration and not a contractual RTB payment. |
| DRV-DEC-010 | Drivven RTB, 70/30 split, brokerage/tax treatment, amortization, late fees, GoCardless, collections, statuses, and accounting export are private tenant property. |
| DRV-DEC-011 | The RTB sequence is global, never reset or reused, starts from an activation-time value, and allocates upon official PDF generation. |
| DRV-DEC-012 | Preview PDFs are unnumbered/watermarked. Changed official data requires a new RTB number and superseding relationship. |
| DRV-DEC-013 | Official signing date is selected when finalizing. If the customer does not sign on that date, the unsigned official document is voided/superseded and regenerated with a new number. |
| DRV-DEC-014 | Weekly first payment is signature date + 7 days; biweekly is +14 days; no sales override in pilot. |
| DRV-DEC-015 | Contract cannot be finalized until the required initial payment is fully settled. |
| DRV-DEC-016 | Initial payment split is fixed by an activated formula version: brokerage is 70%, capital down payment is the exact remainder. |
| DRV-DEC-017 | Brokerage base is paid from the initial payment; its applicable tax is added to financed capital under the approved private formula. |
| DRV-DEC-018 | The original amortization schedule is immutable. Recurring servicing and GoCardless event reconciliation are deferred. |
| DRV-DEC-019 | One vehicle/inventory unit may have only one active Drivven RTB deal at a time. It may have unlimited historical deals. |
| DRV-DEC-020 | Delivered moves to Sold Drive hierarchy and marks Webflow unavailable. Returned/repossessed units retain stock number and require review before republishing. |
| DRV-DEC-021 | French is the Drivven default UI and RTB output language; Vynlo UI also supports English. |
| DRV-DEC-022 | All Drivven users use MFA. Maximum session is 14 days; sensitive actions require recent step-up authentication. |
| DRV-DEC-023 | No camera VIN scanning. VIN is entered/pasted from registration or sales/purchase documents. |
| DRV-DEC-024 | Vehicle image resizing is required from day one. Raw marketing-photo originals default to seven-day retention after verified normalization; legal documents retain originals. |
| DRV-DEC-025 | RTB is the first production document. Five other Drivven document flows are scaffolded but remain disabled until individually approved. |
