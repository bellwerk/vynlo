import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import {
  assessNginxTag,
  findViolations,
  scanNginxVersions,
} from "./check-nginx-versions.mjs";

test("accepts nginx releases with the nginx2root fixes", () => {
  for (const tag of [
    "1.30.7",
    "1.30.7-alpine",
    "1.30.10",
    "1.31.9",
    "1.31.9-alpine-slim",
    "1.32.0",
    "2.0.0",
  ])
    assert.equal(assessNginxTag(tag), null, tag);
});

test("rejects vulnerable, floating and unpinned nginx tags", () => {
  for (const tag of [
    "1.30.6",
    "1.31.8",
    "1.29.9",
    "1.28.3",
    "1.18.0",
    "latest",
    "alpine",
    "1.30",
    "stable",
    undefined,
  ])
    assert.notEqual(assessNginxTag(tag), null, String(tag));
});

test("finds image references in Dockerfiles and compose files", () => {
  const dockerfile = [
    "FROM node:24 AS build",
    "FROM nginx:1.30.6-alpine",
    "FROM docker.io/library/nginx:1.31.9",
    "FROM nginxinc/nginx-unprivileged:1.31.8",
  ].join("\n");
  const violations = findViolations(dockerfile);
  assert.deepEqual(
    violations.map(({ line, image }) => [line, image]),
    [
      [2, "nginx:1.30.6-alpine"],
      [4, "nginxinc/nginx-unprivileged:1.31.8"],
    ],
  );

  const compose = "services:\n  proxy:\n    image: nginx\n";
  assert.equal(findViolations(compose).length, 1);
});

test("rejects OpenResty and Kong until a fixed release is reviewed", () => {
  const source = "image: kong/kong:3.9.1\nFROM openresty/openresty:1.27.1.2\n";
  assert.equal(findViolations(source).length, 2);
});

test("ignores prose and unrelated identifiers", () => {
  const source = [
    "# nginx is not used by this workspace",
    'name = "nginx-docs"',
    "description: Kong is the local Supabase gateway",
  ].join("\n");
  assert.deepEqual(findViolations(source), []);
});

test("scans a repository tree and skips dependency folders", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "nginx-check-"));
  try {
    await mkdir(path.join(root, "deploy"), { recursive: true });
    await mkdir(path.join(root, "node_modules", "pkg"), { recursive: true });
    await writeFile(
      path.join(root, "deploy", "Dockerfile"),
      "FROM nginx:1.31.8\n",
    );
    await writeFile(
      path.join(root, "node_modules", "pkg", "Dockerfile"),
      "FROM nginx:1.18.0\n",
    );
    const result = await scanNginxVersions(root);
    assert.deepEqual(
      result.violations.map(({ file, line }) => [file, line]),
      [["deploy/Dockerfile", 1]],
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
