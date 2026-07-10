# Future expert task: DDE continuation (bifurcation analysis)

## Status

Not implemented. Current mean-field outputs are **dynamical regime sweeps** from
time integration (`dde23`). They classify post-transient variance / range and
must not be labeled bifurcation diagrams.

## What a bifurcation diagram requires

1. Equilibrium and/or periodic-orbit **continuation** in one or more parameters.
2. **Branch detection** (folds, Hopf, period-doubling, etc.).
3. **Stability** information along each branch (eigenvalues / Floquet multipliers).

A variance heatmap or min/max envelope from forward simulation is insufficient.

## Recommended package

Use [DDE-BIFTOOL](https://github.com/DDE-BIFTOOL/DDE-BIFTOOL) (or an equivalent
delay-equation continuation package) against the existing RHS:

- `src/models/meanfield_EI_STD_DDE.m`
- `src/models/meanfield_EI_STD_DDE_rhs.m`

`scripts/run_bifurcation_meanfield.m` already prepares a minimal `sys_funcs`
scaffold when DDE-BIFTOOL is on the MATLAB path; it does not run continuation.

## Independent verification gate

Before trusting MESN mean-field continuation results, reproduce a known delayed
equation with a published bifurcation diagram (for example a scalar delayed
logistic or Mackey–Glass equilibrium/Hopf continuation) using the same
toolchain, and archive the verification under `results/revalidated/`.

## Ownership

This task is reserved for an expert familiar with delay-equation continuation.
Do not fabricate branch diagrams from regime-sweep heatmaps.
