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
| Temporal learning gate (`temporal_learning_gate_v1`) | Reconstruct `y(t)=u(t-k)` from MESN features with `include_input=false`; beat current-input and no-recurrence controls; shuffled high NRMSE; exact-history near zero (see §9.1) |
| Instantaneous readout pipeline check (legacy G5) | Ridge plumbing with direct input — **not** reservoir memory evidence; never satisfies publication readiness |
| G6 | Three-seed pilot completes; structural assertions pass |
| G7 | Full ≥30-seed paired table with provenance and CI from raw cells |

### 9.1 Temporal learning gate (Phase 4B; implementation validity)

**Why the old direct-input check is insufficient.** A readout of the form
`y_hat = Wout * [features; u(t); 1]` can solve instantaneous or near-lag targets
through `u(t)` even if reservoir states carry no useful memory. That check is
reclassified as an instantaneous readout-pipeline test only.

**Task.** i.i.d. uniform input on `[-1, 1]`; strictly delayed target
`y(t)=u(t-k)` with fixed `k=10` (`target_lag_time = k * dt`). Raw input is
**excluded** from the MESN readout (`feature_mode=r`, `include_input=false`).

**Splits.** Independent train / validation / test realizations (distinct seeds,
not slices of one sequence). Each split carries its own washout + lag prefix.
Reservoir (and DDE history) reset to the same canonical IC before every split.

**Reference MESN.** Confirmatory cell
`adapt-three_timescales__std-on__delay-dde_on__feat-r`: multi-timescale
excitatory SFA, frozen single-timescale inhibitory SFA, STD on, inhibitory
delay on. Only the network seed varies across replicates. No tuning against
gate scores.

**Controls.**

1. `current_input_only_control` — design `X=u(t)` (near chance for i.i.d. lag task).
2. `no_recurrent_coupling_control` — fresh `SRNN_ESN` with `W=0` rebuilt
   (preserves `W_in` and biological params; not “memoryless”).
3. `shuffled_target_control` — destroy time alignment (near chance).
4. `exact_history_control` — `X=[u(t),…,u(t-k)]` (noise-free sanity; MESN need
   not beat it).

**Metrics (test split).** RMSE; NRMSE = RMSE / `std(y,1)`; R²; optional Pearson.

**Publication lengths / seeds.** washout 200; train 4000; val 1000; test 2000;
five model seeds `[1729, 2718, 31415, 10007, 10009]`. Smoke/pilot may shorten
lengths and use three seeds but keep the same target, controls, metrics, and
thresholds and can never set `publication_ready=true`.

**Fixed thresholds (not to be altered after seeing MESN results).**

| Rule | Threshold |
|---|---|
| median MESN NRMSE | ≤ 0.90 |
| median MESN R² | ≥ 0.15 |
| median Δ NRMSE vs current-input | ≥ 0.10 |
| fraction beating current-input | ≥ 0.80 (≥4/5) |
| median Δ NRMSE vs no-recurrence | ≥ 0.02 |
| fraction beating no-recurrence | ≥ 0.60 (≥3/5) |
| shuffled median NRMSE | ≥ 0.95 |
| exact-history median NRMSE | ≤ 1e-6 |

Ridge fits use Phase 4A economy-SVD solvers with absolute λ (not λ/n) and
deterministic larger-λ tie-break (`tie_tolerance=1e-12`).

This gate is **not** a confirmatory paper endpoint. Matched NARMA / Mackey–Glass
one-step baselines are Phase **4C-A** (below). Autonomous Mackey–Glass rollout
repair is Phase **4C-B**. Aggregation/statistics remain later.

### 9.2 Matched one-step benchmark baselines (Phase 4C-A)

Protocol version: `matched_task_baselines_v1` (`cfg.benchmark_baselines`,
fingerprinted).

**Shared seed baseline unit (Phase 4C-A-R).** Simple and conventional baselines
are a scientific unit of (final protocol + protocol fingerprint + base seed +
task + deterministic task seed + task data/split + matched `W_in` + reservoir
size + candidate grids + ridge-λ grid). They are computed **once per base seed**
into an immutable artifact

`baselines/seed_<seed>_matched_task_baselines.mat`

and reused by all paired mechanism cells for that seed. Sharing is valid because
these baselines do **not** depend on adaptation on/off, STD on/off, delay mode,
or MESN feature mode `x`/`r`. Cell results store a bundle id, compact test
metrics, and **cell-specific** model-vs-baseline comparisons recomputed from
that cell’s MESN NRMSE. Full conventional candidate tables and heavy ridge
diagnostics live only in the seed artifact.

Dale-only MESN references remain **feature-specific** (`feat-x` / `feat-r`
keys) with status `pending_paired_aggregation`. Pending references are never
counted as computed baselines and must not produce superiority claims.
Publication reuse requires provenance `executed_shared_seed_bundle`. Injected,
fixture, override, mutated, or cell-local provenance fails closed for shared
publication validation. Standalone `run_ablation_cell` may compute
`executed_cell_local` baselines for diagnostics only (never publication shared).

Identity gates before reuse: protocol fingerprint, base/task seeds, `W_in`
hash, task-data hash, and split hash. Mismatch rejects the bundle; runners do
not silently recompute. If any required baseline is failed, missing, or
nonfinite, the benchmark status is `failed_required_baseline` with machine-
readable reasons; publication readiness cannot pass; values are never replaced
by means/zeros/Inf/other baselines. Negative finite R² is allowed.

This repair changes execution/storage/provenance only — not MESN equations,
conventional ESN equations, or preregistered baseline grids.

**Conventional leaky tanh ESN** (not Dale-only MESN; never labeled “standard
ESN” interchangeably):

```
h(t) = (1-α) h(t-1) + α tanh(W_res h(t-1) + W_in u(t))
```

- `α` = leak rate; `W_res` dense unconstrained Gaussian; spectral radius set to
  the candidate value; zero initial state; readout features = reservoir only
  (`include_input=false`).
- Candidate grids (listed order): spectral radius `{0.5, 0.9, 1.2}` × leak
  `{0.1, 0.3, 1.0}` × input scaling `{0.25, 0.5, 1.0}`.
- Within-candidate λ via Phase 4A absolute ridge + larger-λ tie-break
  (`1e-12`). Across candidates: lowest finite validation NRMSE; ties within
  `1e-12` take the earliest enumerated candidate.
- Reservoir seed = `base_seed + 2000` (distinct from task seeds).
- Input: reuse MESN `W_in` nonzero support and direction; normalize by mean
  absolute nonzero; then apply candidate input scaling.

**NARMA baselines:** training-target mean (train only); linear input-history
(Phase 4A ridge, history length = NARMA order); conventional leaky ESN;
Dale-only MESN paired-cell reference (metric pending aggregation).

**Mackey–Glass one-step baselines:** persistence `y_hat(t)=u(t)`; linear AR
(Phase 4A ridge, frozen `ar_lags`); conventional leaky ESN (selected
independently of NARMA); Dale-only MESN reference.

**Comparison convention:**
`improvement_nrmse = baseline_nrmse - model_nrmse` (>0 ⇒ MESN better);
`ratio_nrmse = model_nrmse / baseline_nrmse` (<1 ⇒ MESN better).

Dale-only reference keys:
`adapt-off__std-off__delay-ode_off__feat-x` /
`adapt-off__std-off__delay-ode_off__feat-r`. Status
`pending_paired_aggregation` — not fabricated inside non-control cells.

No benchmark-superiority claim yet. Smoke/pilot results are pipeline evidence
only and never publication-ready. Autonomous rollout unchanged in 4C-A
(deferred to Phase 4C-B).

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
