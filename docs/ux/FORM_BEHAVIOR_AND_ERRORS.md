# Form, draft, validation, and error behavior

## Drafts

Long inventory/deal/document forms save server-side drafts. A successful save updates a visible “saved” state and version. The client never claims saved while offline or before server confirmation.

Autosave:
- debounced only for non-destructive draft fields;
- pauses on validation conflict/offline state;
- never finalizes, allocates a number, settles money, or triggers publication;
- protects against stale overwrite with expected version.

## Validation layers

1. Input format and accessible client feedback.
2. API schema validation.
3. permission and state/activation guards.
4. domain invariants.
5. database constraints.
6. provider validation in asynchronous jobs.

Server errors are authoritative. Field errors link to the input and focus the first invalid step/field.

## Destructive/sensitive confirmation

Archive, cancel, void, refund, reverse, deactivate, activate configuration, and credential change require clear impact summary. Sensitive actions require step-up and reason. Confirmation buttons name the action; avoid generic “OK.”

## Conflicts

On `409 VERSION_CONFLICT`, show the server's current version, preserve the user's unsaved values, and allow refresh/compare/reapply where safe. Financial/document official records are never merged automatically.

## Asynchronous state

After accepted work, UI shows job state, entity remains navigable, and reload does not lose progress. Notifications/toasts supplement—never replace—persistent status.

## Error language

- concise localized user message;
- stable machine code and correlation ID;
- actionable next step;
- retry only when safe;
- no credentials, raw provider payloads, stack traces, or other-tenant existence.

## Navigation protection

Warn when local unsaved changes exist. Server-saved drafts need no unload warning. Mobile back navigation must not accidentally finalize or discard.

## Currency and numbers

Display locale-aware values; editing uses unambiguous normalized parsing. API transports integer minor units and exact rates, not formatted strings. Review screens show currency and all material totals before official action.
