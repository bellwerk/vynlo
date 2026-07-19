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


def check_starter_configuration_artifacts(root: Path) -> Result:
    """Validate starter roles and deal types against immutable platform contracts."""
    errors: list[str] = []
    starter_root = root / "packs/starter-retail-dealer"
    manifest = load(starter_root / "manifest.yaml")
    deal_workflow_path = starter_root / "workflows/deal.yaml"
    deal_workflow = load(deal_workflow_path)["workflow"]
    deal_workflow_checksum = hashlib.sha256(deal_workflow_path.read_bytes()).hexdigest()

    expected_deal_types = {
        "deal-types/cash-retail.yaml": {
            "key": "retail.cash",
            "participants": ["buyer", "seller", "trade_in_owner", "authorized_representative"],
            "inventory": ["sold", "trade_in"],
            "required": ["buyer_party_id", "sold_inventory_unit_id", "currency_code"],
            "optional": [
                "trade_in_owner_party_id",
                "trade_in_inventory_unit_id",
                "authorized_representative_party_id",
                "notes",
            ],
            "behavior": {
                "inventory_direction": "outbound",
                "inventory_creation": "none",
                "finance_mode": "none",
                "money_mode": "one_time",
                "one_time_event_types": ["deposit", "receipt", "balance_received", "trade_in_credit"],
            },
        },
        "deal-types/third-party-financed-retail.yaml": {
            "key": "retail.third_party_financed",
            "participants": ["buyer", "seller", "lender", "trade_in_owner", "authorized_representative"],
            "inventory": ["sold", "trade_in"],
            "required": ["buyer_party_id", "sold_inventory_unit_id", "lender_party_id", "currency_code"],
            "optional": [
                "trade_in_owner_party_id",
                "trade_in_inventory_unit_id",
                "authorized_representative_party_id",
                "notes",
            ],
            "behavior": {
                "inventory_direction": "outbound",
                "inventory_creation": "none",
                "finance_mode": "external_lender_tracking",
                "money_mode": "one_time",
                "one_time_event_types": [
                    "deposit",
                    "receipt",
                    "balance_received",
                    "trade_in_credit",
                    "lender_proceeds",
                ],
            },
        },
        "deal-types/wholesale.yaml": {
            "key": "wholesale.sale",
            "participants": ["buyer", "seller", "authorized_representative"],
            "inventory": ["wholesale"],
            "required": ["buyer_party_id", "wholesale_inventory_unit_id", "currency_code"],
            "optional": ["authorized_representative_party_id", "notes"],
            "behavior": {
                "inventory_direction": "outbound",
                "inventory_creation": "none",
                "finance_mode": "none",
                "money_mode": "one_time",
                "one_time_event_types": ["deposit", "receipt", "balance_received"],
            },
        },
        "deal-types/vehicle-purchase.yaml": {
            "key": "purchase.vehicle",
            "participants": ["seller", "dealer_buyer", "authorized_representative"],
            "inventory": ["purchased"],
            "required": ["seller_party_id", "purchased_inventory_unit_id", "currency_code"],
            "optional": [
                "authorized_representative_party_id",
                "ownership_details",
                "condition",
                "odometer",
                "notes",
            ],
            "behavior": {
                "inventory_direction": "inbound",
                "inventory_creation": "explicit_confirmation",
                "finance_mode": "none",
                "money_mode": "one_time",
                "one_time_event_types": ["receipt", "balance_received"],
            },
        },
        "deal-types/trade-in-acquisition.yaml": {
            "key": "acquisition.trade_in",
            "participants": ["trade_in_owner", "dealer_buyer", "lender", "authorized_representative"],
            "inventory": ["trade_in"],
            "required": ["trade_in_owner_party_id", "trade_in_inventory_unit_id", "currency_code"],
            "optional": [
                "lender_party_id",
                "lien_payoff_minor",
                "lien_payoff_currency",
                "authorized_representative_party_id",
                "ownership_details",
                "condition",
                "odometer",
                "tax_eligibility_inputs",
                "notes",
            ],
            "behavior": {
                "inventory_direction": "inbound",
                "inventory_creation": "explicit_confirmation",
                "finance_mode": "none",
                "money_mode": "one_time",
                "one_time_event_types": ["trade_in_credit", "balance_received"],
            },
        },
    }

    manifest_deal_types = manifest["pack"].get("files", {}).get("deal_types", [])
    if manifest_deal_types != list(expected_deal_types):
        errors.append("packs/starter-retail-dealer/manifest.yaml: deal type manifest entries drifted")

    prohibited_behavior = re.compile(
        r"recurring|servicing|collections|repossession",
        re.IGNORECASE,
    )
    key_pattern = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$")
    field_pattern = re.compile(r"^[a-z][a-z0-9_]*$")
    configured_key_pattern = re.compile(r"^[a-z][a-z0-9_.-]{0,127}$")
    allowed_top_level = {"schema_version", "deal_type"}
    allowed_deal_fields = {
        "key",
        "version",
        "labels",
        "option_labels",
        "workflow",
        "allowed_participant_roles",
        "allowed_inventory_roles",
        "fields",
        "behavior",
    }
    for relative_path, expected in expected_deal_types.items():
        path = starter_root / relative_path
        if not path.exists():
            errors.append(f"{path.relative_to(root)}: missing deal type artifact")
            continue
        artifact = load(path)
        relative = path.relative_to(root)
        if set(artifact) != allowed_top_level or artifact.get("schema_version") != "1.0":
            errors.append(f"{relative}: invalid deal type schema envelope")
            continue
        deal_type = artifact.get("deal_type")
        if not isinstance(deal_type, dict) or set(deal_type) != allowed_deal_fields:
            errors.append(f"{relative}: invalid deal type schema fields")
            continue
        if deal_type.get("key") != expected["key"] or not key_pattern.fullmatch(deal_type.get("key", "")):
            errors.append(f"{relative}: deal type key drifted")
        if deal_type.get("version") != "1.0.0":
            errors.append(f"{relative}: deal type version must be 1.0.0")
        labels = deal_type.get("labels")
        if not isinstance(labels, dict) or set(labels) != {"en", "fr"} or not all(labels.values()):
            errors.append(f"{relative}: English and French labels are required")
        option_labels = deal_type.get("option_labels")
        expected_option_keys = {
            "participant_roles": expected["participants"],
            "inventory_roles": expected["inventory"],
            "one_time_event_types": expected["behavior"]["one_time_event_types"],
        }
        if not isinstance(option_labels, dict) or set(option_labels) != set(expected_option_keys):
            errors.append(f"{relative}: deal option label groups must be exact")
        else:
            for group, expected_keys in expected_option_keys.items():
                localized_options = option_labels.get(group)
                if not isinstance(localized_options, dict) or set(localized_options) != set(expected_keys):
                    errors.append(f"{relative}: {group} labels must exactly match configured keys")
                    continue
                for option_key, localized in localized_options.items():
                    if not configured_key_pattern.fullmatch(option_key):
                        errors.append(f"{relative}: {group} contains an invalid option key")
                    if (
                        not isinstance(localized, dict)
                        or set(localized) != {"en", "fr"}
                        or any(
                            not isinstance(value, str)
                            or not value.strip()
                            or len(value) > 200
                            for value in localized.values()
                        )
                    ):
                        errors.append(
                            f"{relative}: {group}.{option_key} requires exact bounded English and French labels"
                        )
        workflow = deal_type.get("workflow")
        expected_workflow = {
            "key": deal_workflow.get("key"),
            "version": deal_workflow.get("version"),
            "checksum": deal_workflow_checksum,
        }
        if workflow != expected_workflow:
            errors.append(f"{relative}: workflow version/checksum reference drifted")
        for field, expected_values in (
            ("allowed_participant_roles", expected["participants"]),
            ("allowed_inventory_roles", expected["inventory"]),
        ):
            values = deal_type.get(field)
            if values != expected_values or len(values or []) != len(set(values or [])):
                errors.append(f"{relative}: {field} drifted or contains duplicates")
        fields = deal_type.get("fields")
        if not isinstance(fields, dict) or set(fields) != {"required", "optional"}:
            errors.append(f"{relative}: fields must declare required and optional keys")
        else:
            required = fields.get("required")
            optional = fields.get("optional")
            if required != expected["required"] or optional != expected["optional"]:
                errors.append(f"{relative}: configured fields drifted")
            configured_fields = (required or []) + (optional or [])
            if len(configured_fields) != len(set(configured_fields)) or any(
                not isinstance(field, str) or not field_pattern.fullmatch(field)
                for field in configured_fields
            ):
                errors.append(f"{relative}: field keys must be unique snake_case keys")
        if deal_type.get("behavior") != expected["behavior"]:
            errors.append(f"{relative}: finance/payment/inventory behavior drifted")
        if prohibited_behavior.search(path.read_text(encoding="utf-8")):
            errors.append(f"{relative}: prohibited tenant or servicing behavior detected")

    required_exclusions = {
        "recurring_payment_servicing",
        "in_house_financing",
        "leasing",
        "short_term_rental",
        "collections",
        "repossession",
    }
    if set(manifest["pack"].get("excludes", [])) != required_exclusions:
        errors.append("packs/starter-retail-dealer/manifest.yaml: safety exclusions drifted")

    permission_source = (root / "packages/auth/src/permissions.ts").read_text(encoding="utf-8")
    permission_array = re.search(
        r"PLATFORM_PERMISSION_KEYS\s*=\s*Object\.freeze\(\[(.*?)\]\s*as const\)",
        permission_source,
        re.DOTALL,
    )
    platform_permissions = set(
        re.findall(r'"([a-z][a-z0-9_]*\.[a-z][a-z0-9_]*)"', permission_array.group(1))
    ) if permission_array else set()
    if not platform_permissions:
        errors.append("packages/auth/src/permissions.ts: immutable permission catalogue could not be read")

    roles_path = starter_root / "roles.yaml"
    roles_artifact = load(roles_path)
    roles = roles_artifact.get("roles", [])
    role_map = {role.get("key"): role for role in roles if isinstance(role, dict)}
    expected_role_keys = {"owner_admin", "manager", "sales", "inventory", "read_only"}
    if roles_artifact.get("schema_version") != "1.0" or set(role_map) != expected_role_keys:
        errors.append("packs/starter-retail-dealer/roles.yaml: role schema or role keys drifted")
    for role_key, role in role_map.items():
        permissions = role.get("permissions")
        if not isinstance(permissions, list) or not permissions:
            errors.append(f"packs/starter-retail-dealer/roles.yaml: {role_key} has no permissions")
            continue
        if len(permissions) != len(set(permissions)):
            errors.append(f"packs/starter-retail-dealer/roles.yaml: {role_key} has duplicate permissions")
        invalid = set(permissions) - platform_permissions
        if invalid or any("*" in permission for permission in permissions):
            errors.append(
                f"packs/starter-retail-dealer/roles.yaml: {role_key} has non-platform permissions {sorted(invalid)}"
            )

    owner_permissions = set(role_map.get("owner_admin", {}).get("permissions", []))
    if owner_permissions != platform_permissions - {"support.access"}:
        errors.append("packs/starter-retail-dealer/roles.yaml: owner_admin must grant every non-support platform permission")
    required_operational_grants = {
        "finance_applications.read",
        "finance_applications.create",
        "finance_applications.update",
        "payments.read",
        "payments.record",
        "payments.settle",
        "workflow.read",
    }
    for role_key in ("manager", "sales"):
        permissions = set(role_map.get(role_key, {}).get("permissions", []))
        if not required_operational_grants <= permissions:
            errors.append(f"packs/starter-retail-dealer/roles.yaml: {role_key} lacks finance/payment/workflow grants")
    if {"payments.reverse", "payments.refund", "workflow.activate"} & set(
        role_map.get("sales", {}).get("permissions", [])
    ):
        errors.append("packs/starter-retail-dealer/roles.yaml: sales has unsafe correction or activation grants")

    seed = (root / "supabase/seed.sql").read_text(encoding="utf-8")
    role_seed_region = seed.partition("-- M3-STARTER-ROLES-BEGIN")[2].partition(
        "-- M3-STARTER-ROLES-END"
    )[0]
    if not role_seed_region:
        errors.append("supabase/seed.sql: starter role fixture markers are missing")
    else:
        seeded_role_pattern = re.compile(
            r"\(\s*'([a-z][a-z0-9_]*)'::text,\s*"
            r"'((?:''|[^'])*)'::text,\s*'((?:''|[^'])*)'::text,\s*"
            r"(true|false),\s*'([^']*)'::text\s*\)",
            re.DOTALL | re.IGNORECASE,
        )
        seeded_roles = {
            match.group(1): {
                "names": {
                    "en": match.group(2).replace("''", "'"),
                    "fr": match.group(3).replace("''", "'"),
                },
                "requires_mfa": match.group(4).lower() == "true",
                "permissions": match.group(5).split(",") if match.group(5) else [],
            }
            for match in seeded_role_pattern.finditer(role_seed_region)
        }
        if set(seeded_roles) != expected_role_keys:
            errors.append("supabase/seed.sql: starter role keys drifted from roles.yaml")
        for role_key, role in role_map.items():
            seeded_role = seeded_roles.get(role_key, {})
            if seeded_role.get("names") != role.get("names"):
                errors.append(f"supabase/seed.sql: {role_key} localized role names drifted")
            if seeded_role.get("permissions") != role.get("permissions"):
                errors.append(f"supabase/seed.sql: {role_key} permission grants drifted")
            if seeded_role.get("requires_mfa") != (role_key == "owner_admin"):
                errors.append(f"supabase/seed.sql: {role_key} MFA policy drifted")
        for workspace_id in (
            "10000000-0000-4000-8000-000000000001",
            "20000000-0000-4000-8000-000000000002",
        ):
            if role_seed_region.count(f"'{workspace_id}'::uuid") < 1:
                errors.append(f"supabase/seed.sql: starter roles are not bound to {workspace_id}")
        if "source = excluded.source" not in role_seed_region or "'pack'" not in role_seed_region:
            errors.append("supabase/seed.sql: starter roles must retain pack provenance")

    expected_entitlements = [
        "crm",
        "deals",
        "third_party_finance",
        "one_time_payments",
        "custom_workflows",
    ]
    entitlement_region = seed.partition("-- M3-STARTER-ENTITLEMENTS-BEGIN")[2].partition(
        "-- M3-STARTER-ENTITLEMENTS-END"
    )[0]
    fixture_region = entitlement_region.partition(
        "entitlement_fixture(entitlement_key) as ("
    )[2].partition("insert into public.workspace_feature_entitlements")[0]
    seeded_entitlements = re.findall(r"\('([a-z][a-z0-9_]*)'::text\)", fixture_region)
    if seeded_entitlements != expected_entitlements:
        errors.append("supabase/seed.sql: M3 entitlement keys drifted")
    if not all(entitlement in manifest["pack"].get("modules", []) for entitlement in expected_entitlements):
        errors.append("packs/starter-retail-dealer/manifest.yaml: M3 entitlement module reference drifted")
    if entitlement_region.count("app.entitlement_payload_checksum(true, '{}'::jsonb)") != 1:
        errors.append("supabase/seed.sql: M3 entitlements lack the canonical exact checksum")
    if "insert into public.feature_flags" in entitlement_region.lower():
        errors.append("supabase/seed.sql: a feature flag cannot replace an M3 entitlement")
    for workspace_id in (
        "10000000-0000-4000-8000-000000000001",
        "20000000-0000-4000-8000-000000000002",
    ):
        if entitlement_region.count(f"'{workspace_id}'::uuid") != 1:
            errors.append(f"supabase/seed.sql: M3 entitlements are not bound once to {workspace_id}")

    return Result(
        "starter_configuration_artifacts",
        "pass" if not errors else "fail",
        errors,
    )


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


def check_starter_m3_workflow_seed_binding(root: Path) -> Result:
    """Prove exact lead/deal pack parity in both synthetic workspaces."""
    errors: list[str] = []
    starter_root = root / "packs/starter-retail-dealer"
    seed = (root / "supabase/seed.sql").read_text(encoding="utf-8")
    seed_region = seed.partition("-- M3-STARTER-WORKFLOWS-BEGIN")[2].partition(
        "-- M3-STARTER-WORKFLOWS-END"
    )[0]
    if not seed_region:
        return Result(
            "starter_m3_workflow_seed_binding",
            "fail",
            ["supabase/seed.sql: M3 starter workflow fixture markers are missing"],
        )

    workflows: dict[str, dict[str, Any]] = {}
    for filename in ("lead.yaml", "deal.yaml"):
        path = starter_root / "workflows" / filename
        workflow = load(path)["workflow"]
        workflows[workflow["key"]] = {
            "path": path,
            "workflow": workflow,
            "checksum": hashlib.sha256(path.read_bytes()).hexdigest(),
        }

    definition_region = seed_region.partition(
        "insert into public.workflow_definitions"
    )[2].partition("insert into public.workflow_versions")[0]
    definition_pattern = re.compile(
        r"\(\s*'([0-9a-f-]{36})',\s*'([0-9a-f-]{36})',\s*"
        r"'([a-z][a-z0-9_.]*)',\s*'([a-z][a-z0-9_]*)',\s*"
        r"'([a-z][a-z0-9_]*)',\s*'(active|retired)'\s*\)",
        re.IGNORECASE,
    )
    seeded_definitions = {
        match.group(1): {
            "workspace_id": match.group(2),
            "key": match.group(3),
            "entity_type": match.group(4),
            "purpose_key": match.group(5),
            "status": match.group(6).lower(),
        }
        for match in definition_pattern.finditer(definition_region)
    }
    if len(seeded_definitions) != 4:
        errors.append("supabase/seed.sql: expected four M3 starter workflow definitions")

    version_region = seed_region.partition(
        "insert into public.workflow_versions"
    )[2].partition("with version_fixture")[0]
    version_pattern = re.compile(
        r"\(\s*'([0-9a-f-]{36})',\s*'([0-9a-f-]{36})',\s*"
        r"'([0-9a-f-]{36})',\s*'(\d+\.\d+\.\d+)',\s*(\d+),\s*"
        r"'([a-z][a-z0-9_]*)',\s*'(draft)',\s*'([a-f0-9]{64})',\s*"
        r"'(starter_pack)',\s*null\s*\)",
        re.IGNORECASE,
    )
    seeded_versions = [
        {
            "id": match.group(1),
            "workspace_id": match.group(2),
            "definition_id": match.group(3),
            "version": match.group(4),
            "schema_version": int(match.group(5)),
            "initial_state": match.group(6),
            "status": match.group(7).lower(),
            "checksum": match.group(8),
            "source": match.group(9).lower(),
        }
        for match in version_pattern.finditer(version_region)
    ]
    if len(seeded_versions) != 4:
        errors.append("supabase/seed.sql: expected four M3 starter workflow versions")

    expected_workspaces = {
        "10000000-0000-4000-8000-000000000001",
        "20000000-0000-4000-8000-000000000002",
    }
    for workflow_key, binding in workflows.items():
        workflow = binding["workflow"]
        definitions = {
            definition_id: definition
            for definition_id, definition in seeded_definitions.items()
            if definition["key"] == workflow_key
        }
        if {definition["workspace_id"] for definition in definitions.values()} != expected_workspaces:
            errors.append(f"supabase/seed.sql: {workflow_key} definition workspace parity drifted")
        if any(
            definition["entity_type"] != workflow["entity_type"]
            or definition["purpose_key"] != "primary"
            or definition["status"] != "active"
            for definition in definitions.values()
        ):
            errors.append(f"supabase/seed.sql: {workflow_key} definition contract drifted")
        versions = [
            version
            for version in seeded_versions
            if version["definition_id"] in definitions
        ]
        if {version["workspace_id"] for version in versions} != expected_workspaces:
            errors.append(f"supabase/seed.sql: {workflow_key} version workspace parity drifted")
        if any(
            version["version"] != workflow["version"]
            or version["schema_version"] != 1
            or version["initial_state"] != workflow["initial_state"]
            or version["status"] != "draft"
            or version["checksum"] != binding["checksum"]
            or version["source"] != "starter_pack"
            for version in versions
        ):
            errors.append(f"supabase/seed.sql: {workflow_key} version/checksum binding drifted")

    state_region = seed_region.partition("state_fixture(")[2].partition(
        "insert into public.workflow_states"
    )[0]
    state_pattern = re.compile(
        r"\(\s*'((?:''|[^'])*)',\s*'((?:''|[^'])*)',\s*"
        r"'((?:''|[^'])*)',\s*'((?:''|[^'])*)',\s*"
        r"'((?:''|[^'])*)',\s*'((?:''|[^'])*)'::jsonb,\s*(\d+),\s*"
        r"'\{\}'::text\[\]\s*\)",
        re.IGNORECASE,
    )
    seeded_states = {
        (
            match.group(1).replace("''", "'"),
            match.group(2).replace("''", "'"),
            match.group(3).replace("''", "'"),
            match.group(4).replace("''", "'"),
            match.group(5).replace("''", "'"),
            tuple(sorted(json.loads(match.group(6).replace("''", "'")).items())),
            int(match.group(7)),
            (),
        )
        for match in state_pattern.finditer(state_region)
    }
    artifact_states: set[tuple[Any, ...]] = set()
    allowed_state_flags = {
        "terminal",
        "conversion_eligible",
        "conversion_target",
        "loss_terminal",
        "cancellation",
    }
    for workflow_key, binding in workflows.items():
        for state in binding["workflow"].get("states", []):
            state_flags = state.get("flags", {})
            if (
                "terminal" not in state_flags
                or not set(state_flags).issubset(allowed_state_flags)
                or any(not isinstance(value, bool) for value in state_flags.values())
            ):
                errors.append(
                    f"{binding['path'].relative_to(root)}: M3 state flags must use allowlisted booleans and include terminal"
                )
            artifact_states.add(
                (
                    workflow_key,
                    state["key"],
                    state["category"],
                    state["labels"]["en"],
                    state["labels"]["fr"],
                    tuple(sorted(state_flags.items())),
                    int(state["order"]),
                    (),
                )
            )
    if seeded_states != artifact_states:
        errors.append("supabase/seed.sql: M3 starter workflow state graphs drifted")

    transition_region = seed_region.partition("transition_fixture(")[2].partition(
        "insert into public.workflow_transitions"
    )[0]
    transition_pattern = re.compile(
        r"\(\s*'((?:''|[^'])*)',\s*'((?:''|[^'])*)',\s*"
        r"'((?:''|[^'])*)',\s*'((?:''|[^'])*)',\s*"
        r"'((?:''|[^'])*)',\s*(null|'(?:''|[^'])*'),\s*"
        r"(true|false),\s*'\{\}'::text\[\],\s*"
        r"'((?:''|[^'])*)'::jsonb\s*\)",
        re.IGNORECASE,
    )
    seeded_transitions: set[tuple[Any, ...]] = set()
    for match in transition_pattern.finditer(transition_region):
        guard_token = match.group(6)
        guard = None if guard_token.lower() == "null" else guard_token[1:-1].replace("''", "'")
        effects = tuple(json.loads(match.group(8).replace("''", "'")))
        seeded_transitions.add(
            (
                match.group(1).replace("''", "'"),
                match.group(2).replace("''", "'"),
                match.group(3).replace("''", "'"),
                match.group(4).replace("''", "'"),
                match.group(5).replace("''", "'"),
                guard,
                match.group(7).lower() == "true",
                (),
                effects,
            )
        )
    artifact_transitions = {
        (
            workflow_key,
            transition["key"],
            transition["from"],
            transition["to"],
            transition["permission"],
            transition.get("guard"),
            bool(transition.get("reason_required", False)),
            tuple(transition.get("required_fields", [])),
            tuple(transition.get("effects", [])),
        )
        for workflow_key, binding in workflows.items()
        for transition in binding["workflow"].get("transitions", [])
    }
    if seeded_transitions != artifact_transitions:
        errors.append("supabase/seed.sql: M3 starter workflow transition graphs drifted")

    prohibited_behavior = re.compile(
        r"recurring|servicing|collections|repossession",
        re.IGNORECASE,
    )
    if prohibited_behavior.search(seed_region):
        errors.append("supabase/seed.sql: M3 starter workflows contain tenant or servicing behavior")

    return Result(
        "starter_m3_workflow_seed_binding",
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
        check_starter_configuration_artifacts(root),
        check_starter_inventory_seed_binding(root),
        check_starter_m3_workflow_seed_binding(root),
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
