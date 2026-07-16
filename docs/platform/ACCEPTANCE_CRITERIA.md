# Platform MVP acceptance criteria

A configured workspace can complete this flow without code changes:

1. Admin invites staff and assigns roles.
2. Staff creates an inventory unit from a manually entered VIN.
3. Vynlo decodes available specifications and records overrides.
4. A stock number is allocated only when creation is confirmed.
5. Staff records acquisition and additional costs.
6. Staff uploads phone photos; Vynlo normalizes them, creates derivatives, preserves order, and sets a cover image.
7. Staff publishes through a configured website adapter.
8. A lead is captured, assigned, followed up, and converted to a deal.
9. The deal records cash or external-lender terms and one-time transactions.
10. An approved tenant document is previewed and officially generated.
11. Generated and signed files are linked and auditable.
12. The inventory unit is closed/sold through the configured workflow.
13. Reports and exports include the transaction.

Cross-cutting:

- The same platform build runs with the fictional starter workspace and the Drivven pack.
- No Drivven-specific condition exists in platform code.
- Cross-workspace access fails at API and database layers.
- Provider failure does not roll back the business record; sync status and retry are visible.
- Core tasks work at 360 px and desktop widths.
- Preview never consumes an official number.
- Sensitive changes produce audit records.
