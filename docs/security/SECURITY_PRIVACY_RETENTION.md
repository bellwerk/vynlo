# Security, privacy, and retention

## Classification

- Public: published listing data.
- Internal: costs, internal notes, workflow.
- Confidential: customer contact, deals, documents, lender details.
- Restricted: government identifiers, auth factors, credentials, signed legal files.

## Controls

- RLS and permission checks for all workspace data.
- Encryption in transit/at rest through platform/providers.
- Credentials encrypted with an application-managed key and never returned after storage.
- Field masking and separate permission for restricted identifiers.
- Time-limited file downloads.
- Upload quarantine, type/size/pixel validation, malware scan, safe preview generation.
- PII scrubbing in logs, traces, analytics, errors, fixtures.
- Rate limiting for auth, search, exports, uploads, and expensive jobs.

## Audit

Append-only events include workspace, actor/type, action, entity, structured diff, reason, request/correlation ID, IP, user agent, time, and auth assurance.

## Retention

MVP retains signed documents, financial snapshots, and audit history until an approved policy exists. Raw vehicle photos use the seven-day default. Temporary previews/exports expire.

Before public SaaS launch: workspace export, legal hold, retention by entity/jurisdiction, controlled deletion/anonymization, support-access policy, breach response, privacy request process.
