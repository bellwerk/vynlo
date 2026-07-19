# Standard retail dealer starter pack

**Pack ID:** `starter-retail-dealer`  
**Status:** Installable example configuration  
**Production legal status:** No customer-facing template is enabled until tenant approval.

This pack gives a conventional small or medium dealership a practical starting configuration without turning the defaults into platform code. It targets dealers that mostly sell vehicles for cash and sometimes arrange financing through an outside lender.

## Included defaults

- Owner/admin, manager, sales, inventory, and read-only roles.
- Inventory, lead, and deal workflows.
- Versioned cash retail, third-party-financed retail, wholesale, vehicle-purchase,
  and trade-in-acquisition deal types bound to the immutable deal workflow.
- Cash retail, third-party-financed retail, wholesale, vehicle-purchase, trade-in, and generic-invoice document schemas.
- Inventory summary export.
- No recurring payment servicing, non-sale use, rental, collection, or repossession rules.

A workspace may clone and version these definitions. Platform code must operate identically when the pack is not installed.

Deal-type artifacts are declarative configuration. They constrain participant
roles, inventory roles, fields, workflow versions, external-lender tracking, and
one-time money event types. They do not install provider calls, schedules, or
tenant-specific formulas into platform code. Inbound vehicle creation always
requires an explicit confirmation.
