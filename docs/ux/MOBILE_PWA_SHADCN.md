# Mobile-first PWA and shadcn/ui

## Technology

- Next.js App Router and TypeScript strict mode.
- Tailwind CSS.
- shadcn/ui source components maintained in `packages/ui-web`.
- Shared design tokens.
- Installable manifest and standalone PWA display.

## Responsive rules

- Design at 360 px first, then tablet and desktop.
- Minimum 44 × 44 CSS-pixel touch targets where practical.
- No hover-only actions.
- Sticky actions must not cover content or browser controls.
- Tables require mobile card/list alternatives.
- Complex forms use steps and correct input modes.

## PWA scope

Included: installability, icons, manifest, update prompt, connectivity indication, app-like navigation. Excluded: offline writes, sensitive background sync, native push, App Store packaging.

Use accessible shadcn primitives for forms, dialogs, sheets, comboboxes, calendars, tabs, badges, tables, cards, toasts, and menus. Extend through tokens/variants.

A future native app shares API contracts, domain logic, validation, portable tax/calculation packages, and design tokens—not web components.
