# ADR 0006 — Runtime workspace configuration is authoritative

**Status:** Accepted  
**Date:** 2026-07-15

## Decision

Activated workspace behavior is stored in versioned database records and secure object storage. Git seed/configuration packages are import/export/bootstrap artifacts only.

The runtime source of truth includes:

- workspace settings and feature entitlements;
- workflow, field, document, template, numbering, formula, export, and provider-mapping versions;
- approval and activation records;
- encrypted integration credentials;
- checksums and provenance.

## Rationale

This permits normal tenants to configure Vynlo through the admin application, avoids code forks, supports immediate activation/rollback without deployment, and preserves audit history.

## Constraints

- Activated versions are immutable.
- Changes create new draft versions and explicit activation records.
- Credentials are never included in portable packages.
- Exported packages redact secrets and customer data.
- Configuration import must produce a validated diff and require appropriate approval.
