# Future expert task: full incremental-stability derivation

**Status:** human/expert-only. Not part of the automated validation repair series.

## Goal

Derive a rigorous incremental-stability / Echo State Property statement for the
full MESN, including:

1. Current and delayed operators (ODE and scalar-inhibitory DDE).
2. Dynamic SFA and STD blocks (not frozen `a`, `b`).
3. A uniform bound over a reachable set for the state-dependent gain
   `b_j phi'(q_j)`, not only trajectory-sampled peaks.

## Non-goals for the present codebase

- Do not treat `||W||_2 * g_max < 1` with trajectory-sampled `g_max` as a
  theorem for the full MESN or DDE.
- Do not report finite-dimensional LLE or Jacobian contours as DDE ESP proofs.
- Empirical classifications remain:
  `empirically_contracting_on_test_set`,
  `not_contracting_on_test_set`,
  `inconclusive`.

## References in-repo

- `src/algorithms/Jacobian/J_eff_notes.md` — quasi-static fast-gain diagnostic scope
- `src/algorithms/stability/verify_echo_state_property.m` — empirical rates
- `docs/validation/SUPPORT_MATRIX.md` — supported modes
