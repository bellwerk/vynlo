# Provider contracts

Provider types:

```text
StorageProvider
WebsiteProvider
VinProvider
TransactionalEmailProvider
FinanceProvider (future submissions)
AccountingProvider (future sync)
MarketplaceProvider (future)
```

Each connection is workspace-scoped, environment-scoped, encrypted, health-checked, and revocable.

Common requirements:

- OAuth preferred where available;
- least-privilege scopes;
- token refresh and expiry handling;
- rate-limit awareness;
- normalized permanent/transient errors;
- idempotency and correlation IDs;
- remote version/etag storage where supported;
- staging/sandbox before production;
- drift and reconciliation.
