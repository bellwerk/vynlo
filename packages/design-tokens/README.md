# @vynlo/design-tokens

Framework-neutral ownership boundary for the Vynlo System. This package is
part of the modular monolith, not an independently deployed service.

It defines semantic color, typography, spacing, geometry, focus, motion,
elevation, z-index, chart, sidebar, and touch-target contracts. Web code uses
the CSS variables; TypeScript code uses stable names and variable references.

## Sources of truth

| File              | Responsibility                                                                                         |
| ----------------- | ------------------------------------------------------------------------------------------------------ |
| `src/tokens.css`  | Canonical runtime values for light, dark, system preference, focus, motion, geometry, and shadcn roles |
| `src/tokens.json` | Portable DTCG representation of the same public token contract                                         |
| `src/index.ts`    | `ThemeMode`, semantic token names, and `var(--token)` references; no copied values                     |

The package exports these as `@vynlo/design-tokens/tokens.css`,
`@vynlo/design-tokens/tokens.json`, and `@vynlo/design-tokens` respectively.
The repository-root `tokens.css` is a convenience entry point, not a second
value source.

`ThemeMode` is `system | light | dark`. Theme persistence is local web
presentation state and does not create a user, workspace, or tenant database
preference.

## Semantic rules

- Prefer an existing role such as `background`, `card`, `primary`, `muted`,
  `destructive`, `border`, `input`, `ring`, `chart`, or `sidebar` before adding
  a new token.
- Name a new token for meaning, not a route, tenant, milestone, fixture, or
  literal color.
- Define both light and dark values. System mode resolves to one of those two
  contracts; it is not a third palette.
- The primary accent is for actions, links, selection, and focus. It is not
  ambient decoration.
- Success, warning, destructive, offline, and processing states require text or
  an icon in addition to color.
- Keep spacing on the four-point grid, controls at 10 px radius, panels at
  14–16 px, overlays at 20 px, and interactive targets at least 44 px.
- Motion tokens stay within 120–220 ms and may drive opacity or transform only.

## Adding or changing a token

1. Write down the semantic job and the consumers. Reuse an existing role when
   its meaning matches.
2. Change `src/tokens.css` first, including light and dark values and any shadcn
   role mapping. Do not place the value in application CSS.
3. Mirror the portable value and type in `src/tokens.json`.
4. Add a TypeScript name/reference in `src/index.ts` only when consumers need a
   stable programmatic handle. The export must remain a CSS-variable reference.
5. Update token invariant and contrast tests. Add the token to the
   non-production `/dev/design-system` gallery when it has a visual role.
6. Search for duplicated values and remove only declarations proven redundant.

Run at minimum:

```text
pnpm --filter @vynlo/design-tokens typecheck
pnpm test
pnpm check:ui-system
pnpm test:ui-system
```

For a visible change, also run the Vynlo System Playwright accessibility,
responsive, dark-mode, localization, and screenshot gates. A baseline image is
updated only for an approved visual change.
