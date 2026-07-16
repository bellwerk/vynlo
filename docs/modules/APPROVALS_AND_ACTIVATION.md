# Approvals and activation

Versioned configuration separates “implemented” from “allowed in production.”

## Artifacts requiring activation lifecycle

- workspace configuration packages, starter packs, and tax packs;
- tax rules;
- tenant calculations;
- document templates and field schemas;
- workflows;
- numbering definitions;
- export definitions;
- provider mappings where customer-facing effects occur.

Lifecycle:

```text
draft
-> validated
-> test passed
-> approved
-> scheduled/active
-> retired
```

An active version is immutable. Changes create a new version.

## Approval record

```text
workspace
artifact type/key/version/checksum
approval type
decision
approver identity
professional role/organization
date/time
conditions/exclusions
attachment/reference
expiry/review date if applicable
```

Engineering approval confirms implementation/testing, not legal or accounting validity.

## Activation command

Activation is a privileged command requiring:

1. effective membership and permission;
2. recent step-up authentication;
3. exact checksum;
4. compatible platform/pack schema;
5. required fixtures/tests passed;
6. all declared activation gates satisfied;
7. no conflicting active version;
8. audit reason;
9. optional effective date/time.

The transaction records approval linkage, activates the version, retires/replaces prior version as defined, writes audit, and queues affected reconciliation jobs.

## Rollback

Do not mutate an active version. Activate a previously approved compatible version or create a corrective new version. Historical documents/calculations continue to reference the exact version they used.

## Feature availability

UI/API must distinguish:

```text
not installed
installed but disabled
missing approval/input
available for preview
available for official production use
retired for new use
```

An activation-gated feature returns a stable validation code and gate list; it never silently falls back to a draft template or formula.
