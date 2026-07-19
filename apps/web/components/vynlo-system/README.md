# Vynlo System compositions

These app-level compositions assemble reviewed `@vynlo/ui-web` primitives. They
remain domain-neutral: callers supply translated copy, permission-aware actions,
and workflow state.

- `PageHeader` and `ResponsiveDataView` establish consistent page hierarchy and
  mobile-card/desktop-table layouts.
- `MoneyInput` forwards the exact display string. Application services retain
  responsibility for decimal validation and integer minor-unit conversion.
- `EntityCombobox` provides a generic, searchable, keyboard-operable entity
  picker.
- `StatusBadge`, `EmptyState`, `ErrorState`, `SaveState`, and `JobStatus` make
  operational state visible without relying on color alone.
- `ConfirmDestructiveAction` preserves focus trapping, announces failures, and
  keeps the dialog open when its asynchronous action rejects.

Import the public surface from `@/components/vynlo-system`.
