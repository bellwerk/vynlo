# RTB golden-case approval

Candidate exact fixtures are stored under `tenant-seeds/drivven/formulas/rtb/tests/`.

Before production:

1. Engineering verifies the runtime reproduces each expected cent and date.
2. Drivven admin verifies inputs match intended business rules.
3. The designated accounting reviewer verifies tax, trade-in, brokerage, interest, and rounding results.
4. Legal review confirms displayed terminology where required.
5. Approval records reference formula `drivven-rtb@1.0.0`, tax-pack version, fixture checksums, and date.
6. The approved files are immutable; corrections create a new formula/fixture version.

No production activation is permitted while any fixture status remains `candidate_requires_approval`.
