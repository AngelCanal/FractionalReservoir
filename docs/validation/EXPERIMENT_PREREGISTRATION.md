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

## 2. Factorial design (complete table stored before outcomes)

| Factor | Levels |
|---|---|
| Adaptation | `off` (`n_a_E=n_a_I=0`); `one_timescale` (`n_a_E=n_a_I=1`); `three_timescales` (`n_a_E=3`, `n_a_I=1`) |
| STD | `off` (`n_b_E=n_b_I=0`); `on` (`n_b_E=n_b_I=1`) |
| Delay | `ode_off` (`lags=[]`); `dde_on` (scalar inhibitory `lags=0.03`) |
| Readout features | `x`; `r`; standardized `all` |

Cartesian product: **36 cells** per base seed.

### Fairness rule for adaptation (T35)

- Fixed totals: `c_total_E = 0.1/7`, `c_total_I = 0.1/4`.
- One-timescale: `c_a_E = [c_total_E]`, `c_a_I = [c_total_I]`.
- Three-timescales: `c_a_E = ones(1,3)*(c_total_E/3)`, `c_a_I = [c_total_I]`.
- Do **not** triple total coupling merely by adding filters.
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
cfg = mechanism_ablation_config('pilot');  % or 'full'
% cfg.cells is the complete frozen table (36 cells)
```

Pilot / full runners (T101–T103) write under `results/revalidated/` with
`manifest.mat` / `manifest.json` and never overwrite legacy results.
