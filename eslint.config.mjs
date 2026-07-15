import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTypeScript from "eslint-config-next/typescript";

export default defineConfig([
  ...nextVitals,
  ...nextTypeScript,
  {
    rules: {
      "@next/next/no-html-link-for-pages": "off",
    },
    settings: {
      next: { rootDir: "apps/web" },
    },
  },
  globalIgnores([
    "**/.next/**",
    "**/coverage/**",
    "**/dist/**",
    "contracts/**",
    "docs/**",
    "packs/**",
    "schemas/**",
    "tenant-seeds/**",
    "**/playwright-report/**",
    "**/test-results/**",
  ]),
]);
