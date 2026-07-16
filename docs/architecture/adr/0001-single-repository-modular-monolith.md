# ADR 0001 — Single repository and runtime tenant configuration

**Status:** Accepted  
**Date:** 2026-07-15

## Context

Vynlo must serve many dealerships from one maintained SaaS while supporting Drivven's unusually customized first-workspace requirements. A repository per tenant would multiply maintenance, deployments, migrations, security patches, and configuration drift.

## Decision

Use one canonical repository, `vynlo`, containing the modular-monolith application, reusable packs, schemas, and optional non-secret bootstrap seeds. Normal tenant configuration lives in versioned database records and secure storage.

`tenant-seeds/drivven` is retained only to bootstrap and test the first complex workspace. Runtime application code never imports or branches on it.

## Consequences

Positive:

- one security and release stream;
- one migration history;
- normal tenant onboarding requires no Git work;
- easier SaaS operations and testing;
- Drivven remains configuration rather than platform behavior.

Costs:

- strict access controls and configuration versioning are required;
- sensitive Drivven legal assets may need separate secure object storage or restricted repository paths;
- CI must verify that platform packages do not import tenant seeds.

## Exceptions

A separate tenant repository or deployment requires an ADR and a contractual, regulatory, on-premises, customer-owned-code, or materially different access-control reason. It is never the default onboarding model.
