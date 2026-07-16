# @vynlo/ui-web

Reviewed shadcn/ui source components shared by Vynlo web applications.

This package is an ownership boundary inside the modular monolith, not an independently deployed service. Stage 0 exposes only compile-safe foundations.

## Source layout

- `src/components`: shared shadcn/ui source components.
- `src/lib/utils.ts`: the standard `cn` class-composition utility.
- `src/hooks`: shared web-only hooks when a reviewed component requires one.

Run shadcn commands from `apps/web`. Its `components.json` routes registry UI files into this package while keeping app-specific composed components in `apps/web/components`. Import shared components through explicit subpaths such as `@vynlo/ui-web/components/button`; the root export remains available for compatibility.
