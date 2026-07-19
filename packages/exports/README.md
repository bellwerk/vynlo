# @vynlo/exports

Tenant-neutral, deterministic export-domain primitives for Milestone 4.

The package compiles immutable versioned definitions against caller-supplied
entity, source-path, filter, and permission allowlists. It resolves localized
labels, makes explicit permission/recent-step-up decisions, and produces
deterministic UTF-8 CSV or genuine Open XML `.xlsx` bytes without executing
formulas or tenant code.

Money is supplied as integer minor units (`bigint`, safe integers, or canonical
integer strings) plus an ISO currency column. Decimal columns reject binary
floating-point inputs. Text cells are protected from CSV formula injection and
XLSX cells are emitted as inline strings.

Run metadata pins the definition version and checksum, normalized filters,
workspace, actor, locale, row/byte counts, artifact checksum, audit requirement,
and mandatory download expiry. Database persistence, query execution, object
storage, job orchestration, API routes, and UI remain outside this domain
package.
