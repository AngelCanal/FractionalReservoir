# MESN mechanism-ablation experiment preregistration

**Status:** frozen before outcome generation (T100)  
**Config source of truth:** `experiments/revalidated/mechanism_ablation_config.m`  
**Result root:** `results/revalidated/<run_id>/` (never overwrite legacy `results/*`)

This document freezes the mechanism matrix, fairness rules, endpoints, seeds,
exclusions, and analysis plan **before** pilot or full outcomes are inspected
for mechanism superiority.

---

## 1. Scientific question

Under matched recurrent/input seeds and identical input realizations, which
combinations of multi-timescale SFA, STD, and scalar inhibitory delay change
held-out temporal capacity and learning benchmarks relative to paired controls,
without claiming unsupported DDE Lyapunov/ESP theorems or invalid Fisher memory?

Terminology: multi-timescale SFA/STD delayed reservoir (MESN). Do not call the
finite exponential adaptation bank a fractional derivative.

---

## 2. Factorial design (analysis sets; frozen before outcomes)

`protocol_tier` remains only `smoke | pilot | publication`. Analysis families are
orthogonal via `cfg.active_analysis_set`.

### Confirmatory architecture set (`analysis_set = confirmatory`) — **24 cells / seed**

| Factor | Levels |
|---|---|
| Adaptation | `off`; `single_moment_matched` (`tau_a_E=9.25`); `three_timescales` (`tau_a_E=[0.25,2.5,25]`) |
| STD | `off` (`n_b_E=n_b_I=0`); `on` (`n_b_E=n_b_I=1`) |
| Delay | `ode_off` (`lags=[]`); `dde_on` (scalar inhibitory `lags=0.03`) |
| Readout features | `x`; `r` (fixed dimension `n`; confirmatory) |

Cartesian product: **3 × 2 × 2 × 2 = 24 cells** per base seed.

### SFA sensitivity set (`analysis_set = sfa_sensitivity`) — **12 cells / seed**

Restricted mechanism context (documented choice; `off` not included):

| Factor | Levels |
|---|---|
| Adaptation | `single_fast`, `single_middle`, `single_slow`, `single_moment_matched`, `three_timescales`, `three_identical_dimension_control` |
| STD | `off` only |
| Delay | `ode_off` only |
| Features | `x`; `r` |

Count: **6 × 1 × 1 × 2 = 12**. Do **not** merge sensitivity cells into the confirmatory multiple-comparison family.

### Feature exploratory (`feature_exploratory`)

`all` features are exploratory, mechanism-dependent raw dimension, unmatched.
They must never receive a confirmatory role. Any future training-only projection
is deferred.

### Explicit adaptation profiles

Every publication profile stores: `label`, `n_a_E`, `n_a_I`, `tau_a_E`,
`tau_a_I`, `c_a_E`, `c_a_I`, `analysis_role`, `analysis_set`,
`scientific_description`. Publication profiles do **not** use
`default_MESN_config` logspace for `tau_a`.

Manipulated multiscale mechanism:
**multi-timescale excitatory SFA with a common single-timescale inhibitory SFA**
(I frozen at `tau_a_I = 0.25`, `c_total_I` on every non-off profile). Do not call
this fully multiscale E/I adaptation.

### Fairness rule for adaptation (T35 + moment match)

- Fixed totals: `c_total_E = 0.1/7`, `c_total_I = 0.1/4`.
- Non-off: `sum(c_a_E)=c_total_E`, `sum(c_a_I)=c_total_I`.
- Equal-weight three-timescale bank: `c_a_E = ones(1,3)*(c_total_E/3)`.
- Moment-matched single E filter (first temporal moment of equal-weight bank):

```text
tau_eff = sum(c_k * tau_k) / sum(c_k) = (0.25 + 2.5 + 25) / 3 = 9.25
```

Matches total DC coupling and first temporal moment only — **not** exact
equivalence at every frequency.

- `three_identical_dimension_control` uses three identical `tau=9.25` filters
  (same adaptation-state dimension as `three_timescales`) with
  `adaptation_initialization_mode = 'paired_weighted_match'` so weighted
  initial adaptation matches the single-filter control.
- Publication input masks use `input_mask_mode = 'fixed_count'` (legacy
  Bernoulli retained under that explicit option).
- Pair every mechanism condition by identical base recurrent/input seeds and
  input realizations whenever dimensions permit.

---

## 3. Seeds

| Stage | Seeds | Tag |
|---|---|---|
| Pilot (G6) | exactly `1729`, `2718`, `31415` | `pilot_not_for_publication=true` |
| Full (G7) | at least **30** independent base seeds (pilot seeds first, then the fixed list in `mechanism_ablation_config`) | publication candidate only after G7 |

Pilot uses **reduced** sequence lengths sufficient for pipeline QA, not
publication inference.

---

## 4. Primary endpoints (declared before running)

1. Held-out linear memory-capacity curve and area on a **fixed** lag range
   (`compute_memory_capacity`; chance-corrected).
2. NARMA test NRMSE (`narma_benchmark`).
3. One-step Mackey–Glass test NRMSE (`mackey_glass_benchmark`).
4. Empirical convergence rate / classification
   (`verify_echo_state_property`; not “ESP proven”).
5. Wall-clock compute time per cell.

## 5. Secondary endpoints

Nonlinear capacity, frequency discrimination, stimulus counting, effective
rank, and ODE autonomous horizon. Secondary family uses Holm–Bonferroni at
α=0.05 with paired effect sizes (median difference and Cliff’s δ).

## 6. Explicit exclusions

| Excluded | Reason |
|---|---|
| Invalid Fisher-memory metric | Quarantined (`MESN:FisherMemoryNotValidated`) |
| DDE LLE / DDE finite Jacobian | Unsupported; status `unsupported_not_computed` |
| DDE autonomous rollout | `SRNN_ESN:DDEAutonomousUnsupported` |
| Uncorrected “phase advance” | Use response-lag convention only |
| Bifurcation claims | Regime sweeps ≠ continuation bifurcation diagrams |

---

## 7. Operating-point calibration (T102; no outcome fishing)

- Calibrate **only** on training/validation calibration seeds
  (`1729`, `2718`), never final test seeds.
- Acceptable bands (preregistered): mean rate ∈ `[0.05, 0.85]`;
  saturation fraction ≤ `0.35`; silent fraction ≤ `0.35`.
- Apply the **same** shared `(input_scaling, level_of_chaos)` rule to all
  paired mechanism conditions.
- Do **not** pick each mechanism’s scale from final task test performance.
- Save every tried configuration, including failures, in the calibration
  manifest.

---

## 8. Analysis plan (T103)

- Per-seed paired differences vs mechanism-matched control.
- Report median, mean, 95% bootstrap CI over seeds, and individual seed points.
- Effect sizes, not only p-values.
- Keep ODE and DDE stability evidence separate; never attach an ODE LLE to a
  delayed task result.
- Aggregate tables by reading immutable per-seed result files; never silently
  recompute missing cells.

---

## 9. Gates

| Gate | Requirement |
|---|---|
| G5 | Synthetic readout learning + shuffled-target control (prerequisite) |
| G6 | Three-seed pilot completes; structural assertions pass |
| G7 | Full ≥30-seed paired table with provenance and CI from raw cells |

Do not generate manuscript figures from pilot data. Figures require explicit
validated result paths (no “latest file” lookup).

---

## 10. Reproducible entry points

```matlab
addpath(genpath(pwd));
cfg = mechanism_ablation_config('pilot');  % confirmatory, 24 cells
% cfg = mechanism_ablation_config('publication', 'sfa_sensitivity');  % 12 cells
% cfg.cells is the frozen table for the active analysis_set
```

Pilot / full runners (T101–T103) write under `results/revalidated/` with
`manifest.mat` / `manifest.json` and never overwrite legacy results.
