export type ThemeMode = "system" | "light" | "dark";

export const semanticColorTokenNames = [
  "background",
  "foreground",
  "card",
  "card-foreground",
  "popover",
  "popover-foreground",
  "primary",
  "primary-foreground",
  "secondary",
  "secondary-foreground",
  "muted",
  "muted-foreground",
  "accent",
  "accent-foreground",
  "destructive",
  "destructive-foreground",
  "success",
  "success-foreground",
  "warning",
  "warning-foreground",
  "border",
  "input",
  "ring",
] as const;

export type SemanticColorTokenName = (typeof semanticColorTokenNames)[number];
export type CssVariableReference<Name extends string = string> =
  `var(--${Name})`;

function cssVariable<const Name extends string>(
  name: Name,
): CssVariableReference<Name> {
  return `var(--${name})`;
}

/**
 * Framework-neutral references to the canonical values in `tokens.css`.
 * Keeping values in CSS prevents application code from creating a parallel
 * colour system while still giving TypeScript consumers stable names.
 */
export const foundationTokens = Object.freeze({
  color: Object.freeze({
    accent: cssVariable("accent"),
    background: cssVariable("background"),
    border: cssVariable("border"),
    destructive: cssVariable("destructive"),
    foreground: cssVariable("foreground"),
    ink: cssVariable("foreground"),
    input: cssVariable("input"),
    line: cssVariable("border"),
    muted: cssVariable("muted-foreground"),
    paper: cssVariable("background"),
    primary: cssVariable("primary"),
    ring: cssVariable("ring"),
    signal: cssVariable("primary"),
    success: cssVariable("success"),
    surface: cssVariable("card"),
    warning: cssVariable("warning"),
  }),
  focus: Object.freeze({
    offset: cssVariable("focus-offset"),
    width: cssVariable("focus-width"),
  }),
  motion: Object.freeze({
    deliberate: cssVariable("duration-long"),
    fast: cssVariable("duration-fast"),
  }),
  radius: Object.freeze({
    control: cssVariable("radius-control"),
    overlay: cssVariable("radius-overlay"),
    panel: cssVariable("radius-panel"),
  }),
  spacing: Object.freeze({
    pageMax: cssVariable("page-max"),
    section: cssVariable("space-8"),
  }),
  touchTarget: cssVariable("touch-target"),
  typography: Object.freeze({
    display: cssVariable("font-display"),
    interface: cssVariable("font-body"),
    machine: cssVariable("font-mono"),
  }),
} as const);

export type FoundationTokens = typeof foundationTokens;

export const packageName = "@vynlo/design-tokens" as const;
