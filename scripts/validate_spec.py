#!/usr/bin/env python3
"""Validate the Vynlo v2.1 specification bundle.

This script validates syntax, JSON Schemas, configuration artifacts, OpenAPI
internal references, Markdown file links, workflow references, manifest file
paths, repository boundaries, and tenant-owned validation hooks. It
intentionally does not approve legal, accounting, tax, or business rules.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Iterable

import yaml
from jsonschema import Draft202012Validator

EXCLUDED_DIRECTORIES = {
    ".git",
    ".next",
    ".supabase",
    ".turbo",
    "coverage",
    "dist",
    "node_modules",
    "playwright-report",
    "test-results",
}

@dataclass
class Result:
    name: str
    status: str
    details: list[str]


def repository_files(root: Path) -> Iterable[Path]:
    """Yield repository source files without generated dependency/build trees."""
    for directory, names, files in os.walk(root):
        names[:] = [name for name in names if name not in EXCLUDED_DIRECTORIES]
        base = Path(directory)
        for name in files:
            yield base / name


def load(path: Path) -> Any:
    if path.suffix == ".json":
        return json.loads(path.read_text(encoding="utf-8"))
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def resolve_json_pointer(document: Any, pointer: str) -> Any:
    if not pointer.startswith("#/"):
        raise KeyError(f"unsupported external ref: {pointer}")
    node = document
    for raw in pointer[2:].split("/"):
        part = raw.replace("~1", "/").replace("~0", "~")
        if isinstance(node, list):
            node = node[int(part)]
        else:
            node = node[part]
    return node


def walk(obj: Any) -> Iterable[Any]:
    if isinstance(obj, dict):
        yield obj
        for value in obj.values():
            yield from walk(value)
    elif isinstance(obj, list):
        for value in obj:
            yield from walk(value)


def check_parse(root: Path) -> Result:
    errors: list[str] = []
    for path in repository_files(root):
        if path.suffix not in {".json", ".yaml", ".yml"}:
            continue
        try:
            load(path)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{path.relative_to(root)}: {exc}")
    return Result("structured_file_parse", "pass" if not errors else "fail", errors)


def check_schemas(root: Path) -> Result:
    errors: list[str] = []
    for path in (root / "schemas").glob("*.json"):
        try:
            Draft202012Validator.check_schema(json.loads(path.read_text()))
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{path.relative_to(root)}: {exc}")
    return Result("json_schema_validity", "pass" if not errors else "fail", errors)


def validate_against(path: Path, schema: dict[str, Any]) -> list[str]:
    errors = sorted(Draft202012Validator(schema).iter_errors(load(path)), key=lambda e: list(e.path))
    return [f"{path}: {'/'.join(map(str, error.path))}: {error.message}" for error in errors]


def check_artifact_schemas(root: Path) -> Result:
    errors: list[str] = []
    schemas = {path.name: json.loads(path.read_text()) for path in (root / "schemas").glob("*.json")}

    groups = [
        ((root / "packs/starter-retail-dealer/workflows").glob("*.yaml"), "workflow.schema.json"),
        ((root / "packs/starter-retail-dealer/documents").glob("*.yaml"), "document-type.schema.json"),
        (iter([root / "packs/starter-retail-dealer/exports/inventory-summary.yaml"]), "export-definition.schema.json"),
        ((root / "packs/tax").glob("*/manifest.yaml"), "tax-pack.schema.json"),
        ((root / "tenant-seeds").glob("*/workflows/*.yaml"), "workflow.schema.json"),
        ((root / "tenant-seeds").glob("*/documents/*/document-type.yaml"), "document-type.schema.json"),
        ((root / "tenant-seeds").glob("*/formulas/*/formula.v1.json"), "calculation.schema.json"),
        ((root / "tenant-seeds").glob("*/exports/*.yaml"), "export-definition.schema.json"),
        ((root / "tenant-seeds").glob("*/manifest.yaml"), "workspace-config-package.schema.json"),
    ]
    for paths, schema_name in groups:
        for path in paths:
            errors.extend(validate_against(path, schemas[schema_name]))
    return Result("artifact_schema_validation", "pass" if not errors else "fail", errors)


def check_manifest_paths(root: Path) -> Result:
    errors: list[str] = []
    starter_root = root / "packs/starter-retail-dealer"
    starter = load(starter_root / "manifest.yaml")
    files = starter["pack"].get("files", {})
    for value in files.values():
        paths = value if isinstance(value, list) else [value]
        for item in paths:
            if not (starter_root / item).exists():
                errors.append(f"missing starter artifact: {item}")

    for seed_root in sorted(path.parent for path in (root / "tenant-seeds").glob("*/manifest.yaml")):
        seed = load(seed_root / "manifest.yaml")
        for values in seed.get("artifacts", {}).values():
            for item in values:
                if not (seed_root / item).exists():
                    errors.append(f"{seed_root.relative_to(root)}: missing tenant artifact: {item}")
    return Result("manifest_artifact_paths", "pass" if not errors else "fail", errors)


def check_workflows(root: Path) -> Result:
    errors: list[str] = []
    paths = list((root / "packs/starter-retail-dealer/workflows").glob("*.yaml")) + list(
        (root / "tenant-seeds").glob("*/workflows/*.yaml")
    )
    for path in paths:
        data = load(path)
        workflow = data.get("workflow", data)
        states = {state["key"] for state in workflow.get("states", [])}
        initial = workflow.get("initial_state")
        if initial not in states:
            errors.append(f"{path.relative_to(root)}: invalid initial_state {initial}")
        keys: set[str] = set()
        for transition in workflow.get("transitions", []):
            key = transition["key"]
            if key in keys:
                errors.append(f"{path.relative_to(root)}: duplicate transition {key}")
            keys.add(key)
            if transition.get("from") not in states:
                errors.append(f"{path.relative_to(root)}: transition {key} invalid from")
            if transition.get("to") not in states:
                errors.append(f"{path.relative_to(root)}: transition {key} invalid to")
    return Result("workflow_reference_integrity", "pass" if not errors else "fail", errors)


def check_starter_inventory_seed_binding(root: Path) -> Result:
    """Prove the synthetic runtime seed matches the shipped inventory workflow."""
    errors: list[str] = []
    artifact_path = root / "packs/starter-retail-dealer/workflows/inventory.yaml"
    seed_path = root / "supabase/seed.sql"
    artifact = load(artifact_path)
    workflow = artifact.get("workflow", {})
    seed = seed_path.read_text(encoding="utf-8")
    digest = hashlib.sha256(artifact_path.read_bytes()).hexdigest()

    definition_region = seed.partition("insert into public.workflow_definitions")[2].partition(
        "insert into public.workflow_versions"
    )[0]
    version_region = seed.partition("insert into public.workflow_versions")[2].partition(
        "with version_fixture"
    )[0]
    if not definition_region or not version_region:
        errors.append("supabase/seed.sql: starter inventory workflow fixture is missing")
        return Result("starter_inventory_seed_binding", "fail", errors)

    workflow_key = workflow.get("key")
    workflow_version = workflow.get("version")
    initial_state = workflow.get("initial_state")
    if definition_region.count(f"'{workflow_key}'") != 2:
        errors.append("supabase/seed.sql: starter inventory workflow key is not bound in both workspaces")
    if version_region.count(f"'{workflow_version}'") < 2:
        errors.append("supabase/seed.sql: starter inventory workflow version is not bound in both workspaces")
    if version_region.count(f"'{initial_state}'") < 2:
        errors.append("supabase/seed.sql: starter inventory initial state drifted")
    if version_region.count(f"'{digest}'") != 2:
        errors.append(
            "supabase/seed.sql: starter inventory checksum does not match exact artifact bytes"
        )

    state_region = seed.partition("state_fixture(")[2].partition(
        "insert into public.workflow_states"
    )[0]
    state_pattern = re.compile(
        r"\(\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*"
        r"'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*"
        r"(true|false)\s*,\s*(true|false)\s*,\s*(true|false)\s*,\s*(\d+)\s*\)",
        re.IGNORECASE,
    )
    seeded_states = {
        (
            match.group(1).replace("''", "'"),
            match.group(2).replace("''", "'"),
            match.group(3).replace("''", "'"),
            match.group(4).replace("''", "'"),
            match.group(5).lower() == "true",
            match.group(6).lower() == "true",
            match.group(7).lower() == "true",
            int(match.group(8)),
        )
        for match in state_pattern.finditer(state_region)
    }
    artifact_states = {
        (
            state["key"],
            state["category"],
            state["labels"]["en"],
            state["labels"]["fr"],
            bool(state["flags"].get("publishable", False)),
            bool(state["flags"].get("available", False)),
            bool(state["flags"].get("terminal", False)),
            int(state["order"]),
        )
        for state in workflow.get("states", [])
    }
    if seeded_states != artifact_states:
        errors.append("supabase/seed.sql: starter inventory state graph drifted from the pack")

    transition_region = seed.partition("transition_fixture(")[2].partition(
        "insert into public.workflow_transitions"
    )[0]
    transition_pattern = re.compile(
        r"\(\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*"
        r"'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*"
        r"(null|'(?:''|[^'])*')\s*,\s*(true|false)\s*,\s*"
        r"'((?:''|[^'])*)'::jsonb\s*\)",
        re.IGNORECASE,
    )
    seeded_transitions = set()
    for match in transition_pattern.finditer(transition_region):
        guard_token = match.group(5)
        guard = None if guard_token.lower() == "null" else guard_token[1:-1].replace("''", "'")
        effects = tuple(json.loads(match.group(7).replace("''", "'")))
        seeded_transitions.add(
            (
                match.group(1).replace("''", "'"),
                match.group(2).replace("''", "'"),
                match.group(3).replace("''", "'"),
                match.group(4).replace("''", "'"),
                guard,
                match.group(6).lower() == "true",
                effects,
            )
        )
    artifact_transitions = {
        (
            transition["key"],
            transition["from"],
            transition["to"],
            transition["permission"],
            transition.get("guard"),
            bool(transition.get("reason_required", False)),
            tuple(transition.get("effects", [])),
        )
        for transition in workflow.get("transitions", [])
    }
    if seeded_transitions != artifact_transitions:
        errors.append("supabase/seed.sql: starter inventory transition graph drifted from the pack")

    return Result(
        "starter_inventory_seed_binding",
        "pass" if not errors else "fail",
        errors,
    )


def check_openapi(root: Path) -> Result:
    errors: list[str] = []
    path = root / "contracts/openapi.v1.yaml"
    doc = load(path)
    operation_ids: dict[str, str] = {}
    for node in walk(doc):
        if isinstance(node, dict) and isinstance(node.get("$ref"), str):
            ref = node["$ref"]
            if ref.startswith("#/"):
                try:
                    resolve_json_pointer(doc, ref)
                except Exception as exc:  # noqa: BLE001
                    errors.append(f"unresolved OpenAPI ref {ref}: {exc}")
    for route, path_item in doc.get("paths", {}).items():
        placeholders = set(re.findall(r"{([^}]+)}", route))
        for method, operation in path_item.items():
            if method not in {"get", "post", "put", "patch", "delete"}:
                continue
            op_id = operation.get("operationId")
            if not op_id:
                errors.append(f"{method.upper()} {route}: missing operationId")
            elif op_id in operation_ids:
                errors.append(f"duplicate operationId {op_id}: {operation_ids[op_id]} and {method.upper()} {route}")
            else:
                operation_ids[op_id] = f"{method.upper()} {route}"
            names = {
                param.get("name")
                for param in operation.get("parameters", [])
                if isinstance(param, dict) and param.get("in") == "path"
            }
            # Resolve component path params.
            for param in operation.get("parameters", []):
                if isinstance(param, dict) and isinstance(param.get("$ref"), str):
                    try:
                        resolved = resolve_json_pointer(doc, param["$ref"])
                    except Exception:  # already reported
                        continue
                    if resolved.get("in") == "path":
                        names.add(resolved.get("name"))
            if placeholders != names:
                errors.append(
                    f"{method.upper()} {route}: path params {sorted(placeholders)} != declared {sorted(x for x in names if x)}"
                )
            for code in operation.get("responses", {}):
                if not re.fullmatch(r"[1-5](?:\d{2}|XX)|default", str(code)):
                    errors.append(f"{method.upper()} {route}: invalid response code {code}")
    return Result("openapi_internal_contract", "pass" if not errors else "fail", errors)


def check_markdown_links(root: Path) -> Result:
    errors: list[str] = []
    pattern = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")
    for path in (path for path in repository_files(root) if path.suffix == ".md"):
        text = path.read_text(encoding="utf-8")
        for raw in pattern.findall(text):
            target = raw.strip().split(" ")[0].strip("<>")
            if not target or target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            target = target.split("#", 1)[0]
            if not target:
                continue
            resolved = (path.parent / target).resolve()
            try:
                resolved.relative_to(root.resolve())
            except ValueError:
                errors.append(f"{path.relative_to(root)}: link leaves repository: {raw}")
                continue
            if not resolved.exists():
                errors.append(f"{path.relative_to(root)}: missing link target {raw}")
    return Result("markdown_file_links", "pass" if not errors else "fail", errors)


def check_test_traceability(root: Path) -> Result:
    """Require every automated test suite to cite a catalogued stable test ID."""
    errors: list[str] = []
    catalog_path = root / "docs/testing/TEST_CASE_CATALOG.md"
    id_pattern = re.compile(r"\bT-[A-Z0-9]+-\d{3}\b")
    catalog_ids = set(id_pattern.findall(catalog_path.read_text(encoding="utf-8")))
    test_suffixes = (".test.ts", ".test.tsx", ".spec.ts", ".spec.tsx", ".test.sql")

    for path in repository_files(root):
        if not path.name.endswith(test_suffixes):
            continue
        referenced_ids = set(
            id_pattern.findall(path.read_text(encoding="utf-8", errors="ignore"))
        )
        relative_path = path.relative_to(root)
        if not referenced_ids:
            errors.append(f"{relative_path}: missing stable test ID metadata")
            continue
        for test_id in sorted(referenced_ids - catalog_ids):
            errors.append(f"{relative_path}: unknown stable test ID {test_id}")

    return Result("automated_test_traceability", "pass" if not errors else "fail", errors)


def check_tenant_validators(root: Path) -> Result:
    errors: list[str] = []
    validators = sorted((root / "tenant-seeds").glob("*/tests/validate_*.py"))
    for path in validators:
        try:
            completed = subprocess.run(
                [sys.executable, str(path), str(root)],
                cwd=root,
                capture_output=True,
                text=True,
                check=False,
                timeout=60,
            )
        except subprocess.TimeoutExpired:
            errors.append(f"{path.relative_to(root)}: validator exceeded 60 seconds")
            continue
        if completed.returncode != 0:
            output = completed.stdout.strip() or completed.stderr.strip() or "validator failed without output"
            errors.append(f"{path.relative_to(root)}: {output}")
            continue
        try:
            payload = json.loads(completed.stdout)
        except json.JSONDecodeError as exc:
            errors.append(f"{path.relative_to(root)}: validator returned invalid JSON: {exc}")
            continue
        if not isinstance(payload, dict) or payload.get("status") != "pass":
            errors.append(f"{path.relative_to(root)}: validator did not report pass")
    return Result("tenant_owned_validators", "pass" if not errors else "fail", errors)


def check_no_secret_like_values(root: Path) -> Result:
    errors: list[str] = []
    patterns = [
        re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
        re.compile(r"\bsk_(?:live|test)_[A-Za-z0-9]{16,}"),
        re.compile(r"\b(?:ghp|github_pat)_[A-Za-z0-9_]{20,}"),
        re.compile(r"\bya29\.[A-Za-z0-9_-]{20,}"),
    ]
    for path in repository_files(root):
        if path.suffix.lower() in {".png", ".jpg", ".jpeg", ".pdf", ".zip"}:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for pattern in patterns:
            if pattern.search(text):
                errors.append(f"{path.relative_to(root)}: possible committed credential")
                break
    return Result("secret_pattern_scan", "pass" if not errors else "fail", errors)


def sha_manifest(root: Path) -> list[str]:
    lines: list[str] = []
    excluded = {"FILE_MANIFEST.sha256", "VALIDATION_RESULTS.json"}
    for path in sorted(p for p in repository_files(root) if p.name not in excluded):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        lines.append(f"{digest}  {path.relative_to(root).as_posix()}")
    return lines


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--write-results", action="store_true")
    args = parser.parse_args()
    root = Path(args.root).resolve()

    checks = [
        check_parse(root),
        check_schemas(root),
        check_artifact_schemas(root),
        check_manifest_paths(root),
        check_workflows(root),
        check_starter_inventory_seed_binding(root),
        check_openapi(root),
        check_markdown_links(root),
        check_test_traceability(root),
        check_tenant_validators(root),
        check_no_secret_like_values(root),
    ]
    overall = "pass" if all(check.status == "pass" for check in checks) else "fail"
    payload = {
        "specification_version": "2.1.0",
        "validation_scope": "development specification structure and tenant-owned validation hooks; not legal/accounting approval",
        "overall": overall,
        "checks": [asdict(check) for check in checks],
    }
    if args.write_results:
        (root / "VALIDATION_RESULTS.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        (root / "FILE_MANIFEST.sha256").write_text("\n".join(sha_manifest(root)) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2))
    return 0 if overall == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
