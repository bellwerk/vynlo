import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, test } from "node:test";

import {
  countsByRuleAndFile,
  evaluateFindings,
  formatReport,
  inspectSource,
  scanUiSystem,
} from "./check-ui-system.mjs";

const temporaryDirectories = [];

afterEach(async () => {
  await Promise.all(
    temporaryDirectories
      .splice(0)
      .map((directory) => rm(directory, { force: true, recursive: true })),
  );
});

test("identifies raw controls, colors, transition-all, and direct Radix imports", () => {
  const findings = inspectSource(
    "apps/web/components/example.tsx",
    `
      import { Slot } from "@radix-ui/react-slot";
      export function Example() {
        return <button className="text-red-500 transition-all" style={{ color: "#fff" }}><input /></button>;
      }
    `,
  );

  assert.deepEqual(countsByRuleAndFile(findings), {
    "direct-radix": { "apps/web/components/example.tsx": 1 },
    "raw-color": { "apps/web/components/example.tsx": 2 },
    "raw-interactive": { "apps/web/components/example.tsx": 2 },
    "transition-all": { "apps/web/components/example.tsx": 1 },
  });
  assert.ok(findings.every((finding) => finding.line > 0));
});

test("rejects motion outside opacity and transform", () => {
  const findings = inspectSource(
    "apps/web/components/motion.tsx",
    `export const Motion = () => <div className="transition-colors" style={{ transition: "background-color 120ms" }} />;`,
  );

  assert.deepEqual(countsByRuleAndFile(findings), {
    "disallowed-transition": { "apps/web/components/motion.tsx": 2 },
  });
});

test("rejects Hallmark thick side-stripe cards", () => {
  const findings = inspectSource(
    "apps/web/components/status.tsx",
    `export const Status = () => <div className="border-l-4 border-destructive" />;`,
  );
  const cssFindings = inspectSource(
    "apps/web/app/globals.css",
    `.legacy-card { border-left: 4px solid var(--destructive); }`,
  );

  assert.deepEqual(countsByRuleAndFile(findings), {
    "side-stripe": { "apps/web/components/status.tsx": 1 },
  });
  assert.deepEqual(countsByRuleAndFile(cssFindings), {
    "side-stripe": { "apps/web/app/globals.css": 1 },
  });
});

test("ignores commented examples and permits primitive implementation details in ui-web", () => {
  const commented = inspectSource(
    "apps/web/components/example.tsx",
    `
      // <button className="text-red-500 transition-all" />
      /* import { Slot } from "@radix-ui/react-slot"; */
      const documentation = "Use <button> only inside the primitive package.";
      export const Example = () => <Card description={documentation} />;
    `,
  );
  assert.deepEqual(commented, []);

  const sharedPrimitive = inspectSource(
    "packages/ui-web/src/components/button.tsx",
    `
      import { Slot } from "@radix-ui/react-slot";
      export const Button = () => <button className="bg-primary" />;
    `,
  );
  assert.deepEqual(sharedPrimitive, []);

  const serializableMetadata = inspectSource(
    "apps/web/app/manifest.ts",
    `export const manifest = { background_color: "#f5f5f7", theme_color: "#0b0b0c" };`,
  );
  assert.deepEqual(serializableMetadata, []);

  const duplicatedMilestoneShell = inspectSource(
    "apps/web/components/m3-operator-shell.tsx",
    `export const Shell = () => <aside><nav /></aside>;`,
  );
  assert.deepEqual(countsByRuleAndFile(duplicatedMilestoneShell), {
    "milestone-shell-duplication": {
      "apps/web/components/m3-operator-shell.tsx": 2,
    },
  });

  const delegatedMilestoneShell = inspectSource(
    "apps/web/components/m4-operator-shell.tsx",
    `import { OperatorShell } from "./operator-shell"; export const Shell = () => <OperatorShell />;`,
  );
  assert.deepEqual(delegatedMilestoneShell, []);
});

test("the evaluator supports a per-rule, per-file ceiling without weakening the repository policy", () => {
  const source = `<button /><input />`;
  const findings = inspectSource("apps/web/components/legacy.tsx", source);
  const exactBaseline = {
    "raw-interactive": { "apps/web/components/legacy.tsx": 2 },
  };

  const exact = evaluateFindings(findings, exactBaseline);
  assert.equal(exact.regressions.length, 0);
  assert.equal(exact.improvements.length, 0);

  const reduced = evaluateFindings(
    inspectSource("apps/web/components/legacy.tsx", `<button />`),
    exactBaseline,
  );
  assert.equal(reduced.regressions.length, 0);
  assert.deepEqual(reduced.improvements, [
    {
      actual: 1,
      allowed: 2,
      file: "apps/web/components/legacy.tsx",
      rule: "raw-interactive",
    },
  ]);

  const regression = evaluateFindings(
    inspectSource(
      "apps/web/components/legacy.tsx",
      `<button /><input /><textarea />`,
    ),
    exactBaseline,
  );
  assert.equal(regression.regressions.length, 1);
  assert.equal(regression.regressions[0].actual, 3);
  assert.equal(regression.regressions[0].findings.length, 1);
  assert.match(formatReport(regression), /3 found, 2 allowed/u);
});

test("new application files receive zero allowance while shared primitives remain approved", async () => {
  const rootDirectory = await mkdtemp(path.join(tmpdir(), "vynlo-ui-check-"));
  temporaryDirectories.push(rootDirectory);
  const appDirectory = path.join(rootDirectory, "apps/web/components");
  const uiDirectory = path.join(
    rootDirectory,
    "packages/ui-web/src/components",
  );
  await mkdir(appDirectory, { recursive: true });
  await mkdir(uiDirectory, { recursive: true });
  await writeFile(
    path.join(appDirectory, "new-control.tsx"),
    `export const NewControl = () => <select className="transition-all" />;`,
  );
  await writeFile(
    path.join(uiDirectory, "select.tsx"),
    `import * as SelectPrimitive from "@radix-ui/react-select"; export const Select = () => <select />;`,
  );

  const report = await scanUiSystem({ baseline: {}, rootDirectory });
  assert.deepEqual(
    report.regressions.map(({ file, rule }) => ({ file, rule })),
    [
      {
        file: "apps/web/components/new-control.tsx",
        rule: "raw-interactive",
      },
      {
        file: "apps/web/components/new-control.tsx",
        rule: "transition-all",
      },
    ],
  );
});
