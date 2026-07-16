# Search, filtering, and saved views

## MVP search

Workspace-scoped search covers permitted:

- stock number and VIN;
- year/make/model/trim;
- party/customer/organization name;
- phone/email normalized values;
- deal/document number;
- lead subject;
- selected provider references.

Restricted identifiers are not included in broad autocomplete unless the user has the dedicated permission.

## Implementation

PostgreSQL normalized columns, trigram/full-text indexes, and explicit ranking are the first implementation. A separate search service is not required for MVP.

Queries always include workspace scope and permission-aware projections. Search results never reveal that a cross-workspace entity exists.

## Inventory filters

```text
state/category
location
year/make/model
price range
days in stock
media/listing readiness
publication/sync state
cost/gross range
created/acquired/available date
missing/incomplete fields
```

## Lead/deal/task filters

State, assignee, source/type, location, date/next action/due, interested inventory, lender/funding, and owner.

## Saved views

A saved view stores owner/workspace, entity type, filters, sorting, visible columns, density/layout, share scope, version, and timestamps. It cannot grant access to fields the viewer lacks.

## Pagination and sorting

Cursor pagination uses deterministic stable sort plus ID. Maximum page size is 100. Expensive aggregates are precomputed or query-planned; arbitrary user SQL is prohibited.
