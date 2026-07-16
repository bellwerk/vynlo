# Listings and merchandising

Vynlo maps inventory and media to configured channels without hardcoding a provider.

A channel listing stores provider connection, inventory unit, remote ID, locale/channel, publish state, mapped snapshot, asset mappings, etag/version, sync timestamps, and drift/error.

```text
unpublished
queued_publish
publishing
published
queued_update
queued_unpublish
retrying
sync_failed
conflict
```

Rules:

- Business save commits before provider work.
- Required listing fields are validated before publish.
- Media must be provider-ready before final publication unless drafts are supported.
- Manual provider edits become drift; admin chooses overwrite or supported-field adoption.
- Normal sync target: within 60 seconds excluding provider outage/rate limits.

MVP descriptions use deterministic templates. Generative AI copy is future work and always reviewable.
