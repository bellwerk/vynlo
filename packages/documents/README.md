# @vynlo/documents

Tenant-neutral document-engine domain boundary.

This package is an ownership boundary inside the modular monolith, not an
independently deployed service. It contains no database, web, worker, storage,
or tenant-specific behavior.

Milestone 4 adds dependency-free domain contracts for:

- immutable document-type, template, numbering, approval, and activation
  versions with canonical SHA-256 integrity checks;
- bounded Liquid-style HTML/CSS templates supporting escaped values,
  `if`/`else`, `for`, and the allowlisted `default`, `date`, and `money`
  filters;
- fail-closed rejection of script, executable markup, remote/local-network or
  filesystem resources, dynamic CSS/markup attributes, unknown helpers,
  unsafe assets, and excessive source, AST, loop, iteration, or output sizes;
- checksummed template assets normalized to immutable hexadecimal bytes so a
  validated source bundle cannot drift through a mutable typed-array alias;
- versioned numeric document-number definitions, deterministic formatting,
  explicit period/timezone policy, and permanent-allocation guards;
- preview/official snapshots, PDF file versions, replay-safe rendering,
  signed-file selection, mark-signed, failure-preserving void recovery, and
  supersession invariants.

The template runtime emits sanitized HTML. Playwright/Chromium PDF generation,
durable jobs, transactional number allocation, RLS, and storage remain adapters
owned by the worker/application/database layers. Preview and official records
must use those adapters; this package never performs side effects.

The Milestone 1 exports remain available from `first-vertical-slice.ts` for
backward compatibility.
