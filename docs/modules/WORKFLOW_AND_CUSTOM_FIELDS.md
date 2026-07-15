# Workflow and custom fields

Workspaces install versioned state machines. States have translated labels, canonical category, order, behavior flags, required fields, and optional UI token. Transitions have source/target, permission, guards, reason requirement, and outbox actions.

Active versions are immutable for existing instances. New instances use the active version; migration requires an explicit tool/history record.

MVP custom-field types:

```text
short/long text, integer, decimal, money, boolean,
date, datetime, single select, multi-select,
party/location/user reference
```

Definitions include entity type, labels, validation, required/visibility, default, sensitivity, searchability, and display section.

Critical fields—workspace ownership, VIN, stock, currency, official number, workflow state, provider IDs—remain typed relational fields. Custom fields cannot execute code or bypass permissions.

MVP includes basic admin configuration, not a full low-code builder.
