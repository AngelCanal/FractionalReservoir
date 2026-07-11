# MESN claim–evidence gate

**Purpose:** Every manuscript/README claim must map to required evidence, an
exact result path (or gate test), a status, and allowed wording.

**Rule:** Unsupported rows must be removed or rewritten before publication.
Pilot runs (`pilot_not_for_publication=true`) are **not** publication evidence.

| claim | required evidence | result path | status | allowed wording |
|---|---|---|---|---|
| Can learn (readout pipeline) | Held-out synthetic temporal target NRMSE < 0.5 and ≥0.4 better than shuffled control across 3 seeds (G5) | `tests/scientific/test_esn_can_learn.m` (no results write); commit `d2e3824` | **supported** (gate G5) | “Corrected readout protocol can learn a temporal control task in synthetic tests” |
| Improves memory (multi-timescale vs fair single-timescale) | Paired seed differences with 95% bootstrap CI and effect size; equal total `c_a_*` coupling; ≥30 seeds (G7) | `results/revalidated/20260711_014438_mechanism_ablation_full_8026f16/aggregate_paired.mat` | **supported structurally (G7)**; lengths are reduced — qualify publication inference | “Paired multi-timescale SFA changed held-out MC relative to single-timescale control (CI…); reduced-length protocol” |
| Mechanism benefit (any ablation superiority) | Complete paired ≥30-seed table, no missing cells, provenance (G7) | `results/revalidated/20260711_014438_mechanism_ablation_full_8026f16/` (1080/1080 cells) | **supported structurally (G7)**; note reduced lengths | Report paired CIs/effect sizes with length caveat; no overclaim from pilot |
| Echo State Property | Full incremental-stability theorem for the equations used, **or** finite empirical convergence evidence | Empirical: ablation/ESP cells under `results/revalidated/`; theorem: none | **empirical only** | “Empirical state-convergence on the test set”; never “ESP proven” for DDE |
| Edge of chaos | ODE Lyapunov / continuum diagnostics only | ODE LLE controls + ODE-only grids under revalidated paths | **ODE-only** | “ODE edge-of-chaos diagnostics”; DDE edge-of-chaos **unsupported** |
| Predictive coding / prediction | Future-target held-out decoding on structured input + AR/persistence baselines | Benchmark aggregates with baselines in revalidated run | **unsupported / rewrite** until G7 benchmarks with baselines reported | Do not call response lag “prediction”; use “response lag” |
| Bifurcation | Continuation (equilibria/periodic orbits, branches, stability) | `docs/validation/FUTURE_DDEBIFTOOL_CONTINUATION.md` | **unsupported** | “Dynamical regime sweep by time integration” only |
| Fractional dynamics | Fractional operator + approximation weights + convergence order + error bound | none | **unsupported — remove** | Call multi-timescale exponential SFA/STD delayed reservoir (MESN) |
| Novelty as first SFA+STD+delay ESN | Literature review establishing priority | none in-repo | **rewrite** | “Evaluated combination/integration of mechanisms in a MESN reservoir” |
| Dale signs preserved | Zero sign violations on newly generated W | cell manifests `dale_violations==0` | **supported in new runs** | “Presynaptic Dale signs enforced; zero violations in revalidated runs” |
| ODE Jacobian correct | Dense/fast FD gate G3 | `tests/scientific/test_jacobian_finite_difference.m` + optional revalidated diagnostics | **supported** (gate G3) | “ODE Jacobians validated by finite differences for supported SFA/STD combinations” |
| ODE Lyapunov validated | Known linear controls (G4) | `tests/scientific/test_ode_lyapunov_controls.m` | **supported** (gate G4) | “ODE Lyapunov spectrum recovers known linear exponents” |
| DDE Lyapunov / DDE finite Jacobian | Valid DDE variational method | n/a | **unsupported** | Report `unsupported_not_computed`; never substitute ODE values |
| Fisher memory | Validated Fisher information or renamed sensitivity with noise model | quarantined | **invalid / excluded** | Do not report; see `FISHER_MEMORY_STATUS.md` |

## Manuscript actions required (T111)

1. Remove or qualify any “ESP holds”, “fractional”, or “bifurcation diagram” language.
2. Replace mechanism-advantage claims with “preregistered; awaiting G7” or delete.
3. Point figures to `scripts/make_paper_figures.m` requiring explicit
   `result_paths.ablation_aggregate` / `ablation_run_dir` (no latest-file lookup).
4. Keep ODE and DDE stability statements in separate sentences.

## Status legend

- **supported** — evidence exists and matches the claim scope
- **pending** — test/artifact expected but not yet green in this checkout
- **unsupported** — claim must not appear as established
- **rewrite** — claim may appear only with the allowed wording
