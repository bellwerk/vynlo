# Inventory module

## Core records

- `vehicle`: physical identity/specification.
- `inventory_unit`: one workspace acquisition/holding episode.
- `inventory_cost_entry`: cost ledger.
- `stock_number_allocation`: permanent transactional number history.

## Create inventory unit

1. Staff enters or pastes VIN; no camera scan.
2. Vynlo validates format and searches existing records.
3. Staff may decode through the configured VIN provider.
4. Decoder values are suggestions; manual overrides retain provenance and audit.
5. Staff enters acquisition, odometer, location, and pricing information.
6. On `Create`, Vynlo transactionally allocates a stock number and creates the inventory unit.
7. Storage/listing setup is queued; failure does not recycle the number.

## Duplicate VIN

- Active duplicate in the same workspace is blocked by default.
- Prior closed holding episode is shown and can be linked to a new inventory unit after confirmation.
- Data-error override requires manager permission and reason.

## Stock numbering

Supported versioned strategies: numeric sequence, prefix/padded sequence, yearly sequence, manual import allocation, and validated derived suffix strategy. Numbers are never reused. Abandoned drafts do not consume numbers.

## Generic fields

VIN, stock, year/make/model, odometer value/unit, location, condition, acquisition date/source, currency, cost ledger, asking price, internal/public notes, workflow state.

## Location transfers and reacquisition

Transfers preserve from/to, time, actor, reason, and listing side effects. A sold vehicle reacquired later gets a new inventory unit. A pack may retain the stock number through a return within the same holding episode.
