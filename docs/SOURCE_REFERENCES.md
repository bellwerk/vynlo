# External source references

**Retrieved:** 2026-07-15  
**Policy:** Prefer official primary documentation. Re-check provider behavior and API versions during implementation and before production activation.

## Node.js

- Release schedule: https://github.com/nodejs/Release

Design implications:

- use an active LTS line for local development, CI, workers, and container images;
- pin the exact runtime version and container image digest in the first scaffold pull request;
- review major-runtime upgrades through compatibility tests rather than allowing ambient developer-machine drift.

## pnpm

- Installation and version pinning: https://pnpm.io/installation

Design implications:

- use one root workspace and one committed lockfile;
- pin pnpm through `packageManager`;
- prohibit mixed npm/yarn lockfiles;
- run install with a frozen lockfile in CI.

## shadcn/ui

- Documentation: https://ui.shadcn.com/docs

Design implications:

- generated component source becomes Vynlo-owned application code and is reviewed, tested, and upgraded like other source;
- store web components in the web UI package rather than treating shadcn/ui as a runtime plugin system;
- share design tokens, not React DOM components, with a future native application.

## Next.js

- PWA guide: https://nextjs.org/docs/app/guides/progressive-web-apps
- App Router documentation index: https://nextjs.org/docs/app

Design implications:

- use App Router manifest support;
- serve production over HTTPS;
- test install/update behavior across target browsers;
- treat service-worker caching as security-sensitive and do not cache restricted customer data by default.

## Supabase

- Sessions: https://supabase.com/docs/guides/auth/sessions
- MFA: https://supabase.com/docs/guides/auth/auth-mfa
- Row-Level Security: https://supabase.com/docs/guides/database/postgres/row-level-security

Design implications:

- configure the 14-day time-box explicitly rather than assuming a provider default;
- use authentication assurance for MFA/step-up enforcement;
- enable RLS on every exposed table and test both `USING` and `WITH CHECK` behavior;
- service-role credentials never reach the browser.

## Google Drive

- Shared Drive support: https://developers.google.com/workspace/drive/api/guides/enable-shareddrives

Design implications:

- Drivven adapter is Shared Drive-aware;
- relevant file, permission, and change requests include Shared Drive support parameters;
- Shared Drive list/search/change calls use the configured drive ID and required inclusion/corpora settings.

## Webflow

- Data API CMS create items: https://developers.webflow.com/data/reference/cms/collection-items/staged-items/create-items

Design implications:

- store exact site/collection/field/option/locale mappings per environment;
- treat locale identifiers explicitly;
- stage, publish, update, unpublish, assets, errors, and rate limits through the provider adapter and job system.

## Revenu Québec

- Basic GST/QST rules: https://www.revenuquebec.ca/en/businesses/consumption-taxes/gsthst-and-qst/basic-rules-for-applying-the-gsthst-and-qst/
- Used road vehicle trade-in guidance: https://www.revenuquebec.ca/en/businesses/consumption-taxes/gsthst-and-qst/special-cases-gsthst-and-qst/transportation-applying-the-gst-and-qst/road-vehicles-businesses/trade-ins-of-used-road-vehicles/purchaser-not-required-to-collect-the-gst-or-calculate-or-collect-the-qst/

Design implications:

- `tax-ca-qc` is a candidate effective-dated tax pack;
- rates, transaction contexts, trade-in eligibility, estimated-value/SAAQ behavior, fee classification, and rounding require exact approved fixtures before activation;
- the pack is not universal legal/accounting advice.
