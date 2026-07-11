# Quasi-static fast-subsystem Jacobian for the non-delayed ODE

This note documents `compute_J_eff.m`: the `dx/dt`-by-`x` block of the full
non-delayed MESN ODE Jacobian, with adaptation `a` and synaptic resources `b`
frozen at the current state.

**Canonical name for analytical output:** `quasi_static_fast_gain_diagnostic`.

## Scope and non-claims

- Valid only for the **non-delayed ODE** (`params.lags = []`).
- `a` and `b` are **frozen**; the result is **local and trajectory-dependent**.
- It is **not** a theorem for the full ODE (which also evolves `a` and `b`).
- It is **not** a DDE ESP proof; delayed systems raise
  `MESN:DelayedJacobianUnsupported`.
- Never plot or label `||W|| * g_max < 1` as a full MESN/DDE ESP theorem.
- Adaptation shifts the operating point `q` and can **increase or decrease**
  `phi'(q)` depending on state. Gain reduction by SFA is conditional, not universal.

## Definition

State order: `S = [a_E(:); a_I(:); b_E(:); b_I(:); x(:)]`.

```
q = compute_effective_q(state, params)   % per-timescale c_a_E / c_a_I
r = phi(q)
g = phi'(q)
b_full_j = b_j if STD enabled else 1

J_eff = (-I + W * diag(b_full .* g)) / tau_d
```

By construction this equals `J(layout.idx_x, layout.idx_x)` from
`compute_Jacobian.m` for the same ODE state.

## Diagnostic use

`J_eff` may be used as a **quasi_static_fast_gain_diagnostic** along sampled
ODE trajectories (spectral abscissa, non-normality of the continuous-time
generator). Any contour such as `||W|| * g_max < 1` is at most a sufficient
condition for the **frozen** `a,b` subsystem at the sampled gain, unless a
uniform reachable-set bound is supplied separately.

Empirical state convergence for driven reservoirs (ODE or DDE) must be
reported with the classifications from the empirical ESP experiment:

- `empirically_contracting_on_test_set`
- `not_contracting_on_test_set`
- `inconclusive`

Do **not** use labels such as `ESP holds` / `ESP proven` from this matrix alone.
DDE plots report those empirical diagnostics only; no finite-dimensional LLE
or Jacobian contour.

## Future expert task

A full incremental-stability derivation for the delayed system would need
current and delayed operators, dynamic SFA/STD blocks, and a uniform
reachable-set bound. See `docs/validation/FUTURE_INCREMENTAL_STABILITY.md`.
That work is out of scope for this repair series.
