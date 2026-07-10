# Fisher memory status (quarantined)

## Current status

`compute_fisher_memory_curve` is **not scientifically validated** and must not
be reported as Fisher information in figures, tables, or manuscript claims.

- **Default call** raises `MESN:FisherMemoryNotValidated`.
- **Legacy reproduction only** with `options.allow_legacy_invalid = true`.
- Legacy outputs are prefixed `legacy_*`, set `scientifically_valid = false`,
  and list known defects.

## Known defects of the legacy routine

1. Wrong historical Jacobian usage relative to a proper information metric.
2. Euler transition approximation (`A ≈ I + dt J`) without validated discrete map.
3. Product-order ambiguity in the sensitivity chain.
4. Lag-offset ambiguity in impulse indexing.
5. No noise / statistical observation model (so not Fisher information).
6. No DDE support (`MESN:DelayedSensitivityUnsupported` when delays are present).

## Future expert task (out of scope for this repair series)

A future derivation must:

1. Specify a stochastic observation model for the reservoir features.
2. Either derive a true Fisher information curve **or** rename the quantity as
   deterministic input-sensitivity energy (and never call it Fisher).
3. Derive the discrete/continuous transition correctly (no ad-hoc Euler product
   without error analysis).
4. Validate on a known linear system with an analytical memory/sensitivity curve.
5. Decide whether delayed (DDE) MESN is in scope and, if so, use a delay-aware
   sensitivity theory rather than an ODE Jacobian substitute.

Agents in this repair series must **not** implement that derivation.
