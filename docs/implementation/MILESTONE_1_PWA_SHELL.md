# Milestone 1 PWA and localization shell

**Recorded:** 2026-07-16

**Status:** Shell plus subsequent authenticated operations source integration
implemented; live end-to-end acceptance pending

## Scope

This increment advances `VYN-E03`, `VYN-UX-001`, and `VYN-I18N-001`. It keeps
the application operational and mobile-first. Subsequent source work now
connects invitation/login, MFA, verified workspaces/permissions, and the first
inventory-to-preview workflow; it does not claim live completion of Milestone
1.

## Acceptance IDs

| Acceptance ID | Behavior | Evidence |
|---|---|---|
| `M1-PWA-AC-001` | The web application exposes a standalone manifest with 192 px and maskable 512 px icons plus a root-scoped service worker. | Manifest route and Playwright contract checks. |
| `M1-PWA-AC-002` | The service worker does not cache authenticated or workspace data; connectivity loss is visible and offline writes are explicitly unsupported. | Fetch-handler-free `public/sw.js`, lifecycle banner, mobile/desktop Playwright checks. |
| `M1-PWA-AC-003` | A waiting service worker produces an explicit reload action rather than silently replacing an active shell. | `PwaLifecycle` update-state and `SKIP_WAITING` message contract. |
| `M1-I18N-AC-001` | English and French catalogs have identical structures and preserve Unicode accents and language-independent machine keys. | Recursive catalog-shape unit test and locale policy tests. |
| `M1-I18N-AC-002` | Locale selection persists safely and cannot be used as an external redirect. | HTTP-only same-site locale cookie and return-path failure tests. |
| `M1-UX-AC-001` | The shell works at 360 px and desktop widths without horizontal overflow or automatically detectable WCAG violations. | Playwright mobile/desktop layout and axe checks. |
| `M1-UX-AC-002` | Navigation destinations are filtered by immutable permission keys before rendering. | `filterNavigation` unit tests. |
| `M1-UX-AC-003` | Shared tokens define color, typography, focus, motion, and a 44 px minimum touch target without coupling future native clients to React DOM. | `@vynlo/design-tokens` contracts and tests. |

## Security and data behavior

- The locale action accepts only `en` and `fr`, writes a secure cookie in
  production, and rejects protocol-relative, absolute, backslash, and null-byte
  return targets.
- The service worker intentionally has no `fetch` handler. It cannot cache API,
  authentication, or workspace responses and provides no background-sync or
  offline-write path.
- Restricted navigation entries declare stable permission keys from
  `@vynlo/auth`. The anonymous foundation shell receives no product grants;
  the authenticated operations view loads effective grants before enabling
  invitation, inventory, party, deal, or preview actions.
- Response headers add clickjacking, MIME-sniffing, referrer, and browser
  capability protections. A production CSP remains part of the authenticated
  application hardening increment.

## UI and accessibility behavior

- The shell begins at 360 CSS pixels, uses native controls, provides a skip
  link, retains 44 px touch targets, exposes visible focus, and has no
  hover-only command.
- English and French strings are selected server-side so the document `lang`
  attribute, accessible names, and rendered copy change together.
- Entrance motion uses translation only. Foreground opacity does not animate
  through low-contrast states, and reduced-motion users receive no entrance
  animation.
- The anonymous home-page selector remains illustrative. The authenticated
  operations selector now loads active membership workspaces and uses the
  selected ID only as verified command-header context. A request body or query
  parameter is never treated as authorization.

## Compatibility and operations

This increment has no database, API-contract, or rollback migration. Removing
the service-worker registration and manifest icons returns to the Stage 0 shell
without affecting stored data. Deployments must serve `/sw.js` with `no-cache`
and `Service-Worker-Allowed: /`; Playwright verifies both headers.

## Remaining Milestone 1 integration

Authenticated workspace selection, effective-grant action gating, and
translated invitation/MFA/denial/loading/empty/retry/save states now exist in
source. Remaining acceptance work is:

1. Run the complete invited-user and inventory-to-private-preview journey
   against live Auth, database, worker, and Storage services at mobile and
   desktop widths.
2. Add deployed recent-step-up/session-revocation and provider-failure recovery
   coverage beyond the current source UI.
3. Exercise the service-worker waiting-state prompt with a deployed-version E2E
   fixture and complete the manual iOS/Android installation checklist.
