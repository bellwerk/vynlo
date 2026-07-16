# Threat model

## Assets

- authentication sessions and MFA;
- workspace membership/permissions;
- customer identity and contact data;
- government identifiers;
- inventory costs/prices and internal notes;
- deals, financial events, tax/calculation snapshots;
- legal templates, generated documents, signed files;
- provider credentials and remote resources;
- audit, approvals, exports, backups.

## Trust boundaries

```text
browser/PWA
<-> Next.js API
<-> Supabase Auth/Postgres/storage
<-> worker
<-> external providers
<-> public listing destinations

single Vynlo repository
<-> optional workspace seed/configuration packages
<-> runtime encrypted configuration
```

No trust crosses a boundary solely because an ID is syntactically valid.

## Priority threats and mitigations

### Cross-workspace data access

Threat: IDOR, bad join, job/cache/search leakage, provider mapping mix-up.  
Mitigation: RLS, explicit workspace scope, composite ownership validation, opaque IDs, negative tests, workspace-tagged jobs/files/logs, inaccessible-style 404.

### Privilege escalation

Threat: role spoofing, stale claims, unprotected admin endpoint.  
Mitigation: membership/permission lookup server-side, step-up, RLS, no client-only auth, audit, session revocation.

### Credential theft

Threat: secrets in repo/browser/logs, broad OAuth scopes, compromised token.  
Mitigation: secret manager/encrypted records, server-only access, least privilege, rotation, redaction, health/revocation, no tenant secrets in `.env` or packs.

### Document/template injection and SSRF

Threat: tenant HTML/script reads environment/files/network or executes code.  
Mitigation: no script, sandboxed Liquid, allowlisted helpers/assets, blocked network/filesystem, container limits, CSP, adversarial tests.

### Formula abuse

Threat: arbitrary code, cycles, huge rows/depth, overflow, division by zero, floating-point errors.  
Mitigation: typed AST, schema validation, resource limits, decimal arithmetic, approved fixtures, immutable versions, fail closed.

### Malicious uploads

Threat: executable spoofed as image/PDF, malware, pixel/decompression bomb, metadata leak.  
Mitigation: quarantine, file-signature/MIME/size/pixel checks, malware scan, safe renderer, metadata stripping, separate originals/derivatives, short-lived URLs.

### Number duplication or reuse

Threat: concurrency, retry, manual deletion, import collision.  
Mitigation: DB transaction/locking/unique constraints, idempotency, immutable allocation, import validation, no pool return.

### Financial/document tampering

Threat: edit settled payment, formula/version swap, overwrite signed PDF.  
Mitigation: append/reversal model, immutable snapshots/checksums, exact references, approvals, lineage, restricted storage, step-up/audit.

### Provider replay and duplicate side effects

Threat: duplicate webhook/job/API request creates multiple folders/items/payments.  
Mitigation: signature verification, event/provider IDs, idempotency keys, unique mappings, outbox, attempt history.

### Sensitive data leakage in observability/exports

Threat: logs/traces/errors/support/export expose PII/secrets.  
Mitigation: structured allowlists/redaction, restricted export definitions, expiring links, step-up, audit, no raw provider payloads.

### Session abuse on shared devices

Threat: long session left unattended.  
Mitigation: MFA, session list/revocation, tenant-configurable local lock later, step-up for sensitive actions, no shared accounts, lost-device runbook.

### Supply-chain/deployment compromise

Threat: malicious dependency/action/container or unauthorized production change.  
Mitigation: lockfiles, review, dependency/container/action pinning/scans, protected branches/environments, signed provenance where available, minimal deployment identities.

## Abuse cases to test

- user changes body `workspace_id`;
- enumerate another workspace's UUID;
- upload HTML renamed `.jpg`;
- template requests metadata service/local file;
- formula with circular 10,000-node graph;
- replay official-generation request;
- parallel sequence allocation;
- provider sends same webhook repeatedly;
- stale browser overwrites newer price;
- sales user activates tax/template;
- signed file replacement attempts;
- export hidden restricted identifier;
- worker receives forged workspace/entity pair.

Threat model is reviewed when adding a provider, public endpoint, payment servicing, digital signature, native app, or visual builder.
