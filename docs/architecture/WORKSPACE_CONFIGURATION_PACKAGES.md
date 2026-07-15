# Portable configuration packages

This document replaces the earlier repository-per-tenant model.

A portable configuration package is an optional, versioned import/export artifact for a workspace. It is useful for repeatable provisioning, migration, test fixtures, or source-reviewed configuration. It is **not** the ordinary runtime source of truth and does not imply a separate repository.

See [`WORKSPACE_CONFIGURATION.md`](WORKSPACE_CONFIGURATION.md) for the normative lifecycle.

## Package classes

```text
starter pack
- Vynlo-maintained editable defaults, such as starter-retail-dealer

tax pack
- Vynlo-maintained jurisdiction logic with sources, effective dates, tests, and approvals

workspace configuration package
- a workspace's non-secret definitions, templates, formulas, mappings, and fixtures
```

## Compatibility

Each package declares:

- package schema version;
- compatible platform schema range;
- dependencies;
- artifact checksums;
- required feature entitlements;
- activation gates.

Installation validates and stores database versions. Runtime code does not read package files.

## Security

Packages cannot contain credentials, customer records, signed documents, identity documents, production exports, arbitrary executable code, or unrestricted template behavior.

## Normal tenants

Most tenants are configured through the admin application and never receive a workspace package in Git. An export may be generated for backup or migration when authorized.
