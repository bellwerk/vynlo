# Pack and workspace-configuration compatibility

## Artifact types

```text
starter pack
- Vynlo-maintained editable defaults

tax pack
- Vynlo-maintained jurisdiction logic

workspace configuration package
- optional import/export/bootstrap artifact for a specific workspace
```

The runtime source of truth is versioned database configuration, not the package file or Git path.

## Semantic versions

- Patch: backward-compatible fixes.
- Minor: additive compatible behavior.
- Major: breaking schema/runtime contract.

Each artifact declares its schema version, platform compatibility range, dependencies, checksums, and activation gates.

## Install/upgrade process

1. Upload or select an artifact in non-active state.
2. Validate manifest, schema, dependencies, checksums, and prohibited content.
3. Produce an impact report: fields, states, documents, formulas, mappings, active instances, and data migrations.
4. Run fixtures and compatibility tests in staging.
5. Obtain required approval.
6. Install new draft database versions.
7. Activate explicitly for new operations at an effective time.
8. Preserve prior exact versions for historical records.
9. Monitor and retain a compatible rollback activation path.

## Breaking changes

Use expand/migrate/contract:

- add new schema/fields/read paths;
- migrate or dual-read/write with checks;
- activate new configuration/runtime;
- retire the old creation path;
- remove only after compatibility/retention window and ADR.

Never rewrite historical snapshots to match a new schema.

## Validation

CI/import validation verifies:

- schema and platform compatibility;
- no credentials, customer data, signed documents, or unrestricted executable code;
- referenced artifacts and checksums;
- JSON/YAML/JSON Schema validity;
- workflow state/transition references;
- calculation limits and fixtures;
- template sandbox/static analysis;
- export source references;
- integration mapping contract;
- activation gates.

## Dependency rule

Reusable platform packages define schemas and import services but never import `tenant-seeds/drivven` or inspect workspace identity. Provisioning reads validated artifacts through the configuration import interface and stores runtime versions in Postgres/object storage.
