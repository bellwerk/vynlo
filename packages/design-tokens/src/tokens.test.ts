// Stable test IDs: T-UX-002. Migration evidence: UI-MIG-02, WCAG-2.2-AA.
import { describe, expect, it } from "vitest";

import tokenDocument from "./tokens.json";

type LinearRgb = readonly [red: number, green: number, blue: number];

function parseOklch(value: string): LinearRgb {
  const match = /^oklch\(([\d.]+) ([\d.]+) ([\d.]+)\)$/.exec(value);
  if (!match) throw new Error(`Unsupported color token: ${value}`);

  const lightness = Number(match[1]);
  const chroma = Number(match[2]);
  const hue = (Number(match[3]) * Math.PI) / 180;
  const a = chroma * Math.cos(hue);
  const b = chroma * Math.sin(hue);

  const lPrime = lightness + 0.3963377774 * a + 0.2158037573 * b;
  const mPrime = lightness - 0.1055613458 * a - 0.0638541728 * b;
  const sPrime = lightness - 0.0894841775 * a - 1.291485548 * b;
  const l = lPrime ** 3;
  const m = mPrime ** 3;
  const s = sPrime ** 3;
  const clamp = (channel: number) => Math.max(0, Math.min(1, channel));

  return [
    clamp(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
    clamp(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
    clamp(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s),
  ];
}

function relativeLuminance([red, green, blue]: LinearRgb): number {
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

function contrastRatio(first: string, second: string): number {
  const firstLuminance = relativeLuminance(parseOklch(first));
  const secondLuminance = relativeLuminance(parseOklch(second));
  return (
    (Math.max(firstLuminance, secondLuminance) + 0.05) /
    (Math.min(firstLuminance, secondLuminance) + 0.05)
  );
}

describe("Vynlo System portable tokens", () => {
  it("preserves a 44 CSS pixel touch target", () => {
    expect(tokenDocument.dimension.touchTarget.$value).toEqual({
      value: 44,
      unit: "px",
    });
  });

  it.each(["light", "dark"] as const)(
    "%s primary buttons pass WCAG AA text contrast",
    (mode) => {
      const colors = tokenDocument.color[mode];
      expect(
        contrastRatio(colors.primary.$value, colors.primaryForeground.$value),
      ).toBeGreaterThanOrEqual(4.5);
    },
  );
});
