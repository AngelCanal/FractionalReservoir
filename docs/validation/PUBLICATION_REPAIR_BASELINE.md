# MESN publication repair baseline (Phase 0)

Immutable record of the repository state at the start of the MESN publication repair program. No scientific code was modified in this phase.

## Source

| Field | Value |
|---|---|
| Parent branch | `fix/mesn-validation-foundation` |
| Repair branch | `fix/mesn-publication-repair` |
| Starting SHA | `c83054cd332fab635a68cc56fee4b5b65208c8c5` |
| Starting SHA (short) | `c83054c` |
| Original audited source branch | `Membrane-Echo-State-Network` |
| Previous reduced run commit | `8026f16c2f5bf984137a4bc243791916213c256c` |
| Previous reduced run ID | `20260711_014438_mechanism_ablation_full_8026f16` |
| Classification of previous run | `reduced_structural_smoke_run_not_publication_evidence` |
| Date (local) | 2026-07-14 |
| Hostname | `DELL-D9SJ034` |

## Worktree status before Phase 0 edits

| Field | Value |
|---|---|
| Branch at inspection | `fix/mesn-validation-foundation` |
| `git status` | working tree clean (nothing to commit) |
| Dirty tracked files before work | none |
| Untracked tracked-relevant dirty files | none |

Note: local ignored/untracked result artifacts under `results/` may exist and must be preserved; they were not modified.

## Test baseline (executed, unmodified code)

| Field | Value |
|---|---|
| MATLAB version | `26.1.0.3234472 (R2026a) Update 1` |
| Computer / OS architecture | `PCWIN64` |
| Operating system | Microsoft Windows NT 10.0.26100.0 (win32) |
| Command | `addpath(genpath(pwd)); results = run_all_tests;` via `matlab -batch` |
| Suites | `tests/unit`, `tests/integration`, `tests/scientific` |
| Total tests | 222 |
| Passed | 222 |
| Failed | 0 |
| Incomplete | 0 |
| Overall | PASS |
| Elapsed (MATLAB `toc`) | 1270.312 s (~21.2 min) |
| Wall clock | 1279.8 s |
| Warning lines logged (`Warning:`) | 11 (non-fatal; includes deprecated scalar `c_E` and singular-matrix ridge fit warnings) |
| Failures / incomplete names | none |

## Previous reduced run (local availability)

| Field | Value |
|---|---|
| Path | `results/revalidated/20260711_014438_mechanism_ablation_full_8026f16/` |
| Locally available | **yes** |
| Cell `.mat` count | 1080 |
| Top-level artifacts present | `manifest.json`, `manifest.mat`, `preregistered_config.mat`, `full_summary.mat`, `aggregate_paired.mat` |
| Modified during Phase 0 | **no** |

Manifest highlights confirming reduced / non-publication character:

- `extra.g7_complete = true` despite reduced lengths
- `pilot_not_for_publication = false` (incorrect for a reduced run)
- `base.n = 12` (not publication size 40)
- `lengths.mc_lags = 1:6`, short NARMA/MG/ESP lengths
- `length_note = reduced_lengths_for_compute_feasibility_not_publication_inference`
- secondary endpoints disabled; MG rollout off

**Explicit classification:** `reduced_structural_smoke_run_not_publication_evidence`

## Known blockers (must be fixed in later phases)

These defects are accepted as present; Phase 0 only records them.

### 2.1 Previous run was not a publication run

The 1,080-cell experiment used reduced lengths (`n=12`, short MC/NARMA/MG/ESP), yet `g7_complete=true` and `pilot_not_for_publication=false` remain possible.

### 2.2 Empirical convergence is invalid

Class-backed ESP path discards distinct ICs via `runReservoir` default `reset_before=true`. Aggregate receives `NaN` for `esp_median_slope` while cells can remain `ok`. Existing tests exercise `simulate_fn`, not real `SRNN_ESN`.

### 2.3 Aggregation uses the wrong contrasts

Global control confounds adaptation, STD, delay, and feature mode; no matched three- vs one-timescale SFA contrast.

### 2.4 Single-timescale SFA is not adequately matched

Default `logspace` timescales give one-timescale `[0.25]` vs three-timescale `[0.25, 2.5, 25]`; slow memory is unmatched.

### 2.5 `all` features confound mechanism and readout dimension

`all` exposes more readout variables when SFA/STD states exist; unsafe for unmatched primary mechanism comparisons.

### 2.6 Learning gate dominated by direct input

**Repaired in Phase 4B.** Legacy check reclassified as instantaneous readout
pipeline (`tests/scientific/test_instantaneous_readout_pipeline_check.m`).
Publication readiness now requires `temporal_learning_gate_v1`
(`y(t)=u(t-k)`, `include_input=false`). On the official smoke protocol the
MESN gate currently **fails** fixed thresholds (median NRMSE≈0.97 > 0.90;
median R²≈0.04 < 0.15; median Δ vs current≈0.02 < 0.10) without threshold
modification — see task log.

### 2.7 Baselines discarded by aggregation and figures

NARMA/MG baselines exist in cells but are not preserved in aggregate or Figure 4.

### 2.8 Calibration contradicts preregistration

Pilot sizes/tolerances, incomplete physical combinations, and calibration seeds overlapping the inferential set.

### 2.9 Input sparsity unsafe for small reservoirs

Bernoulli `input_sparsity=0.8` with small `n` can yield zero driven neurons; publication needs fixed-count connectivity.

### 2.10 Autonomous Mackey–Glass rollout likely skipped

Test segment too short for default init + 500-step rollout; protocol must allocate length explicitly.

### 2.11 Artifact and manuscript package incomplete

Raw revalidated run git-ignored; no compact tables/promoted figures; manuscript outline only; MESN must not be described as fractional.

## Phase 0 acceptance check

| Criterion | Status |
|---|---|
| No scientific code changed | yes |
| Baseline document exists | yes (`docs/validation/PUBLICATION_REPAIR_BASELINE.md`) |
| Current tests executed | yes (222/222 pass) |
| Previous run preserved | yes (read-only inspection) |
| Branch created | yes (`fix/mesn-publication-repair` from `fix/mesn-validation-foundation` @ `c83054c`) |
