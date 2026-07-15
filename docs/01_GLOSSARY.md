# Glossary

| Term | Definition |
|---|---|
| Vynlo | The independent SaaS platform and product. |
| Organization | Commercial account/billing owner; may contain one or more workspaces. |
| Workspace | Operational data-isolation boundary. Database records use `workspace_id`. |
| Tenant | Informal synonym for a workspace/customer configuration; avoid as a database column name. |
| Legal entity | Registered company that buys/sells vehicles or signs documents. |
| Brand | Public operating name that may differ from the legal entity. |
| Location | Physical or operational dealership branch. |
| Vehicle | Physical identity identified primarily by VIN and specifications. |
| Inventory unit | One workspace's acquisition/holding episode for a vehicle, including stock number, cost, prices, status, and location. |
| Party | A person or organization participating in leads, deals, purchases, sales, trade-ins, or lending. |
| Lead | An inquiry before a deal is created. |
| Deal | A commercial transaction involving one or more parties and inventory units. |
| Workspace configuration | Versioned runtime settings, definitions, mappings, and approvals that customize one workspace. |
| Workspace configuration package | Optional portable seed/import/export artifact; not the runtime source of truth and not required for every tenant. |
| Starter pack | Editable default configuration for a typical retail dealership. |
| Tax pack | Versioned jurisdiction-specific tax rules, rates, rounding, and tests. |
| Document type | Tenant-configured schema, workflow, numbering, template, and optional calculation/tax linkage. |
| Calculation definition | Versioned declarative formula owned by a tenant or pack; executed by Vynlo's safe runtime. |
| Canonical category | Neutral platform grouping for tenant-defined workflow states: draft, active, pending, closed, archived. |
| External resource | Provider-side object linked to a Vynlo entity. |
| Outbox | Durable record created in the same transaction as a business change and later processed by a worker. |
| Step-up authentication | Reauthentication or recent MFA required for a sensitive operation. |
