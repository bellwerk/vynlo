# Media and image pipeline

Release 1 includes upload, validation, normalization, derivative generation, ordering, cover selection, storage, and provider publication for vehicle images. Legal/customer documents follow a non-destructive policy.

## Inputs

JPEG, PNG, WebP, HEIC/HEIF where worker codecs support them. Validate file signatures rather than extensions.

## Default vehicle-photo profile

```text
normalized master: max long edge 2560 px, high-quality JPEG or WebP
website derivative: max width 1080 px, WebP
thumbnails: 640 px and 320 px, WebP
```

Profiles are configurable.

## Pipeline

1. upload to quarantine;
2. validate type, size, and pixel limits;
3. malware scan where applicable;
4. correct orientation;
5. convert HEIC;
6. strip GPS metadata from public derivatives;
7. generate master/derivatives using Sharp/libvips;
8. checksum and deduplicate;
9. persist dimensions/state;
10. publish/mirror through jobs.

## Retention and UX

- Raw vehicle-photo original: default seven days after verified master creation; configurable.
- Legal and signed documents: preserve original, generate preview separately.
- Mobile multi-upload, visible progress, accessible reorder, first image as cover by default, actionable retry states.
