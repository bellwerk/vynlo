export const foundationTokens = Object.freeze({
  color: {
    ink: "#17251f",
    line: "color-mix(in srgb, #17251f 20%, transparent)",
    muted: "#5b6761",
    paper: "#f4f1e8",
    rust: "#9a432c",
    signal: "#d9ff5b",
    surface: "#fbfaf5",
  },
  focus: {
    offset: "3px",
    width: "3px",
  },
  motion: {
    deliberate: "500ms",
    fast: "120ms",
  },
  radius: {
    brand: "50% 50% 10% 50%",
    control: "0px",
  },
  spacing: {
    pageMax: "1440px",
    section: "clamp(40px, 8vw, 104px)",
  },
  touchTarget: "44px",
  typography: {
    display: 'Georgia, "Times New Roman", serif',
    interface: '"Avenir Next", "Segoe UI", sans-serif',
    machine: "monospace",
  },
} as const);

export type FoundationTokens = typeof foundationTokens;

export const packageName = "@vynlo/design-tokens" as const;
