# Existing Drivven inventory migration

## Purpose

Link existing Active Inventory folders and Webflow CMS items to Vynlo without creating duplicates or changing production data unexpectedly.

The quantity of existing folders/items is an execution input, not an architecture decision.

## Preparation

1. Freeze or schedule a controlled editing window.
2. Export Webflow Inventory collection data and asset references.
3. List Google Shared Drive Active Inventory folders and file counts.
4. Record the current highest regular `P###` stock number.
5. Back up mappings and verify staging integrations.
6. Prepare an admin-only migration user and audit correlation ID.

## Dry-run algorithm

For every eligible Drive folder:

1. Parse folder title with the Drivven stock rule.
2. Reject or flag names that do not match `P###` or `P###a`.
3. Locate an existing Vynlo inventory unit by stock, if any.
4. Search Webflow export for an exact stock reference or use an admin mapping screen.
5. Ask the administrator to enter/confirm VIN and acquisition cost manually.
6. Decode VIN and show differences as suggestions.
7. Detect duplicate physical-vehicle and active-holding records.
8. Produce proposed vehicle, inventory unit, external resource, media, and listing mappings.
9. Do not write Drive/Webflow or allocate a new stock number during dry run.

## Commit

- Commit only administrator-approved rows.
- Preserve existing Drive folder IDs.
- Preserve existing Webflow item IDs.
- Mark missing VIN, cost, location, price, or media as incomplete.
- Advance the regular stock sequence above the highest approved imported regular stock.
- Create an immutable migration batch and row-level audit results.
- Never recreate or rename an existing folder/item merely to satisfy the importer.

## Reconciliation report

The batch report must contain:

```text
source folder
parsed stock
VIN
Vynlo vehicle ID
Vynlo inventory unit ID
Drive folder ID
Webflow item ID
result
warnings
missing fields
manual decisions
```

## Rollback

Migration creates links and records; it does not delete source data. A failed batch may disable or reverse newly created Vynlo mappings before users begin editing. Once normal production activity starts, corrections use audited administrative tools rather than database rollback.
