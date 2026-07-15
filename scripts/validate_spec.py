#!/usr/bin/env python3
"""Validate the Vynlo v2.1 specification bundle.

This script validates syntax, JSON Schemas, configuration artifacts, OpenAPI
internal references, Markdown file links, workflow references, manifest file
paths, and Drivven candidate calculation invariants. It intentionally does not
approve legal, accounting, tax, or business rules.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass, asdict
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP, getcontext
from pathlib import Path
from typing import Any, Iterable

import yaml
from jsonschema import Draft202012Validator

getcontext().prec = 60

@dataclass
class Result:
    name: str
    status: str
    details: list[str]


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


def round_minor(value: Decimal) -> int:
    return int(value.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def calculate_rtb(inputs: dict[str, Any]) -> dict[str, Any]:
    initial = inputs["initial_payment_total_minor"]
    brokerage = round_minor(Decimal(initial) * Decimal("0.70"))
    down = initial - brokerage
    taxable_fees = sum(
        row["amount_minor"] for row in inputs.get("fees", [])
        if row.get("taxable") and row.get("financed")
    )
    non_taxable_fees = sum(
        row["amount_minor"] for row in inputs.get("fees", [])
        if not row.get("taxable") and row.get("financed")
    )
    vehicle_after = max(
        inputs["vehicle_cash_price_minor"]
        - down
        - inputs.get("eligible_trade_in_credit_minor", 0),
        0,
    )
    consideration = vehicle_after + taxable_fees
    vehicle_gst = round_minor(Decimal(consideration) * Decimal("0.05"))
    vehicle_qst = round_minor(Decimal(consideration) * Decimal("0.09975"))
    brokerage_gst = round_minor(Decimal(brokerage) * Decimal("0.05"))
    brokerage_qst = round_minor(Decimal(brokerage) * Decimal("0.09975"))
    principal = (
        vehicle_after
        + taxable_fees
        + vehicle_gst
        + vehicle_qst
        + non_taxable_fees
        + inputs.get("trade_in_lien_payoff_minor", 0)
        + brokerage_gst
        + brokerage_qst
    )

    frequency = inputs["payment_frequency"]
    periods = 52 if frequency == "weekly" else 26
    period_days = 7 if frequency == "weekly" else 14
    count = inputs["duration_months"] * periods // 12
    periodic_rate = Decimal(inputs["annual_rate_bps"]) / Decimal(10000) / Decimal(periods)
    if periodic_rate == 0:
        regular = round_minor(Decimal(principal) / Decimal(count))
    else:
        regular = round_minor(
            Decimal(principal)
            * periodic_rate
            / (Decimal(1) - (Decimal(1) + periodic_rate) ** (-count))
        )

    opening = principal
    schedule: list[dict[str, Any]] = []
    signature = date.fromisoformat(inputs["signature_date"])
    total_interest = 0
    total_payments = 0
    for number in range(1, count + 1):
        interest = round_minor(Decimal(opening) * periodic_rate)
        if number == count:
            principal_part = opening
            payment = principal_part + interest
        else:
            payment = regular
            principal_part = payment - interest
            if principal_part > opening:
                principal_part = opening
                payment = principal_part + interest
        opening -= principal_part
        total_interest += interest
        total_payments += payment
        schedule.append(
            {
                "payment_number": number,
                "due_date": (signature + timedelta(days=period_days * number)).isoformat(),
                "payment_minor": payment,
                "principal_minor": principal_part,
                "interest_minor": interest,
                "remaining_balance_minor": opening,
            }
        )

    return {
        "brokerage_fee_base_minor": brokerage,
        "capital_down_payment_minor": down,
        "taxable_financed_fees_minor": taxable_fees,
        "non_taxable_financed_fees_minor": non_taxable_fees,
        "vehicle_price_after_capital_and_trade_in_minor": vehicle_after,
        "vehicle_taxable_consideration_minor": consideration,
        "vehicle_gst_minor": vehicle_gst,
        "vehicle_qst_minor": vehicle_qst,
        "brokerage_gst_minor": brokerage_gst,
        "brokerage_qst_minor": brokerage_qst,
        "net_capital_financed_minor": principal,
        "periods_per_year": periods,
        "number_of_payments": count,
        "first_payment_date": schedule[0]["due_date"],
        "regular_payment_minor": regular,
        "total_schedule_payments_minor": total_payments,
        "total_interest_minor": total_interest,
        "first_three_schedule_rows": schedule[:3],
        "final_schedule_row": schedule[-1],
        "final_payment_adjustment_minor": schedule[-1]["payment_minor"] - regular,
        "ending_balance_minor": opening,
    }


def check_parse(root: Path) -> Result:
    errors: list[str] = []
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix not in {".json", ".yaml", ".yml"}:
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
        ((root / "tenant-seeds/drivven/workflows").glob("*.yaml"), "workflow.schema.json"),
        ((root / "packs/starter-retail-dealer/documents").glob("*.yaml"), "document-type.schema.json"),
        ((root / "tenant-seeds/drivven/documents").glob("*/document-type.yaml"), "document-type.schema.json"),
        ((root / "tenant-seeds/drivven/formulas").glob("*/formula.v1.json"), "calculation.schema.json"),
        (iter([root / "packs/starter-retail-dealer/exports/inventory-summary.yaml"]), "export-definition.schema.json"),
        (iter([root / "tenant-seeds/drivven/exports/accounting-v1.yaml"]), "export-definition.schema.json"),
        (iter([root / "packs/tax/ca-qc/manifest.yaml"]), "tax-pack.schema.json"),
        (iter([root / "tenant-seeds/drivven/manifest.yaml"]), "workspace-config-package.schema.json"),
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

    seed_root = root / "tenant-seeds/drivven"
    seed = load(seed_root / "manifest.yaml")
    for values in seed.get("artifacts", {}).values():
        for item in values:
            if not (seed_root / item).exists():
                errors.append(f"missing Drivven artifact: {item}")
    return Result("manifest_artifact_paths", "pass" if not errors else "fail", errors)


def check_workflows(root: Path) -> Result:
    errors: list[str] = []
    paths = list((root / "packs/starter-retail-dealer/workflows").glob("*.yaml")) + list(
        (root / "tenant-seeds/drivven/workflows").glob("*.yaml")
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
    for path in root.rglob("*.md"):
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


def check_rtb_fixtures(root: Path) -> Result:
    errors: list[str] = []
    for path in sorted((root / "tenant-seeds/drivven/formulas/rtb/tests").glob("*.json")):
        data = load(path)
        actual = calculate_rtb(data["input"])
        for key, expected in data["expected"].items():
            if actual.get(key) != expected:
                errors.append(
                    f"{path.relative_to(root)}: {key} expected {expected!r}, calculated {actual.get(key)!r}"
                )
        if actual["brokerage_fee_base_minor"] + actual["capital_down_payment_minor"] != data["input"]["initial_payment_total_minor"]:
            errors.append(f"{path.relative_to(root)}: initial payment split invariant failed")
        if actual["ending_balance_minor"] != 0:
            errors.append(f"{path.relative_to(root)}: ending balance is not zero")
    return Result("drivven_candidate_formula_invariants", "pass" if not errors else "fail", errors)


def check_repository_boundaries(root: Path) -> Result:
    errors: list[str] = []
    forbidden = re.compile(r"\b(drivven|auto bs|sherbrooke|montreal|gocardless|rent[- ]?to[- ]?buy|\brtb\b|70/30|p###)\b", re.I)
    for sub in ["apps", "packages"]:
        base = root / sub
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.is_file() and path.suffix in {".ts", ".tsx", ".js", ".jsx", ".json", ".yaml", ".yml", ".md"}:
                match = forbidden.search(path.read_text(encoding="utf-8", errors="ignore"))
                if match:
                    errors.append(f"{path.relative_to(root)}: platform source contains workspace-specific term {match.group(0)!r}")
    return Result("platform_workspace_boundary", "pass" if not errors else "fail", errors)


def check_no_secret_like_values(root: Path) -> Result:
    errors: list[str] = []
    patterns = [
        re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
        re.compile(r"\bsk_(?:live|test)_[A-Za-z0-9]{16,}"),
        re.compile(r"\b(?:ghp|github_pat)_[A-Za-z0-9_]{20,}"),
        re.compile(r"\bya29\.[A-Za-z0-9_-]{20,}"),
    ]
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix.lower() in {".png", ".jpg", ".jpeg", ".pdf", ".zip"}:
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
    for path in sorted(p for p in root.rglob("*") if p.is_file() and p.name not in excluded):
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
        check_openapi(root),
        check_markdown_links(root),
        check_rtb_fixtures(root),
        check_repository_boundaries(root),
        check_no_secret_like_values(root),
    ]
    overall = "pass" if all(check.status == "pass" for check in checks) else "fail"
    payload = {
        "specification_version": "2.1.0",
        "validation_scope": "development specification structure and candidate mathematical invariants; not legal/accounting approval",
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
