# Website/listing provider

Interface:

```text
validateMapping
createDraftListing
updateListing
publishListing
unpublishListing
uploadAsset
reorderAssets if supported
getListing/getAsset
listChanges or reconcile
```

A mapping records provider site/channel, resource IDs, locale IDs, source fields, transformations, required values, dropdown mappings, empty-value rules, and publication behavior.

All writes are background jobs. A mapping snapshot is stored with each sync. Remote conflicts are visible to admins. Provider-specific identifiers do not belong in inventory rows.
