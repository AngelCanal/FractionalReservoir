# MESN publication repair — task log

## Phase 1 checklist (before edits)

- [x] Confirm clean worktree at `bf78733`
- [x] Add `cfg.protocol_tier` (`smoke` | `pilot` | `publication`)
- [x] Add deterministic `cfg.protocol_fingerprint` (exclude timestamps/paths/host/runtime/fingerprint; canonicalize function handles)
- [x] Dedicated `run_mechanism_ablation_smoke.m`; reduced full-run path forces smoke + non-publication
- [x] Replace `g7_complete` with readiness fields; `publication_ready` is AND of all requirements
- [x] Add `validate_publication_run.m`
- [x] Regression tests: smoke≠publication-ready; fingerprint sensitivity/stability; missing seed/condition; duplicates; NaN primary; 30 smoke seeds fail readiness
- [x] Run Phase 1 tests; commit; do not start Phase 2

## Phase 1 after edits

| Field | Value |
|---|---|
| Status | complete |
| Starting SHA | `bf7873337d3e8df5a04f7bb32858910d380b1252` |
| Files changed | see git commit |
| Phase 1 tests | `tests/unit/test_protocol_fingerprint.m` — 14/14 pass |
| Full suite | 236/236 pass (elapsed ~1238 s) |
| Scientific behavior changed | no model equations or scientific parameters; protocol identity / gates only |
| Remaining blockers | Phase 2+ (ESP reset, matched contrasts, fair SFA, learning gate, etc.) |

## Phase 2 checklist (before edits)

- [x] Confirm clean worktree at `387f3eb`
- [x] `runReservoir`: explicit `initial_state` / `history_fn`, unambiguous precedence, no silent reset
- [x] Explicit IC must not mutate `obj.S` unless `update_internal_state=true`
- [x] Convergence uses packed `S_history`; slopes vs physical time (`slope_per_time`)
- [x] Exclude distance-floor samples from fits; record usable interval / floor fraction
- [x] STD resources perturbed in `[0,1]`; DDE uses explicit histories
- [x] Canonical fields; cell fails on nonfinite required convergence (unless documented inconclusive)
- [x] Actual-class regression + stable/unstable + DDE history tests
- [x] Run Phase 2 tests then `run_all_tests`; commit; stop

## Phase 2 after edits

| Field | Value |
|---|---|
| Status | complete |
| Starting SHA | `387f3ebbbaa3f80351a5a9abc3fb9011f7c84e19` |
| Targeted tests | 31/31 pass (`test_empirical_esp_controls` + `test_protocol_fingerprint`) |
| Full suite | 249/249 pass (~1261 s wall) |
| Scientific behavior changed | yes — empirical convergence path and `runReservoir` IC/history API |
| Remaining blockers | Phase 3+ (fair SFA profiles, aggregation, calibration, learning gate, etc.) |

## Phase 3 checklist (before edits)

- [x] Confirm clean worktree at `06551a6`
- [x] Replace implicit SFA levels with explicit adaptation profiles (label, n_a, tau_a, c_a, roles, description)
- [x] Document moment-matched τ_eff = 9.25 (DC + first temporal moment only)
- [x] Separate confirmatory (24 cells) vs SFA sensitivity (12 cells); do not overload `protocol_tier`
- [x] Primary feature policy: x/r confirmatory fixed-n; all exploratory unmatched
- [x] Publication-safe `adaptation_initialization_mode = 'paired_weighted_match'` (retain legacy)
- [x] Publication `input_mask_mode = 'fixed_count'` (retain Bernoulli legacy)
- [x] Propagate explicit scientific metadata into cells/params/summaries/fingerprints
- [x] Add Phase 3 tests covering profiles, couplings, init equivalence, cell counts, features, W/W_in, masks, fingerprints
- [x] Run targeted then full suite; commit `feat: add fair SFA profiles and fixed-dimension controls`; stop

## Phase 3 after edits

| Field | Value |
|---|---|
| Status | complete |
| Starting SHA | `06551a6f3cee6722b4100d0380d22fd60b18ac52` |
| Targeted tests | 34/34 pass (`test_fair_sfa_profiles` 20 + `test_protocol_fingerprint` 14; ~82 s) |
| Full suite | 269/269 pass (~1451 s wall) |
| Scientific behavior changed | yes — explicit fair SFA profiles, confirmatory/sensitivity split, fixed-count input masks, paired adaptation init; no new scientific run |
| Remaining blockers | Phase 4+ (learning gate, aggregation redesign, calibration, artifact export, figures) |

### Scientific notes (Phase 3)

Manipulated multiscale mechanism:
**multi-timescale excitatory SFA with a common single-timescale inhibitory SFA.**
Do not claim fully multiscale E/I adaptation (I remains one filter at τ=0.25 on all non-off profiles).

Moment-matched single timescale for equal-weight three-timescale bank
`tau_a_E = [0.25, 2.5, 25]`, `c_k = c_total_E/3`:

```text
tau_eff = sum(c_k * tau_k) / sum(c_k) = (0.25 + 2.5 + 25) / 3 = 9.25
```

Matches total coupling and first temporal moment only — not exact equivalence at every frequency.

Sensitivity cell count (documented choice): **12** per seed
(`6` SFA profiles × STD off × ODE × features `{x,r}`; no shared `off` reference in the sensitivity family).

Confirmatory cell count: **24** per seed
(`3` adapt × `2` STD × `2` delay × `2` features `{x,r}`).

Historical run `results/revalidated/20260711_014438_mechanism_ablation_full_8026f16/` remains immutable reduced structural-smoke evidence and was not modified.

## Phase 4A checklist (before edits)

- [x] Confirm branch `fix/mesn-publication-repair` at starting SHA `b534780`
- [x] Locate ridge fit/apply/selection, `SRNN_ESN.trainReadout`, time-warp protocol tests
- [x] Reproduce `MATLAB:nearlySingularMatrix` on `test_time_warp_protocol` with warnings-as-errors
- [x] Replace normal equations with economy-SVD ridge / min-norm (absolute lambda, unregularized intercept)
- [x] Training-only standardization + diagnostics schema; preserve `mu`/`sigma`/`constant_feature` aliases
- [x] Update `select_ridge_lambda` candidate records + deterministic larger-lambda ties (`tie_tolerance=1e-12`)
- [x] Harden `apply_ridge_readout`
- [x] Required ridge / selection / time-warp warning-as-error tests
- [x] Scientific compatibility check on well-conditioned fixtures
- [x] Targeted + `run_all_tests`; commit; stop (no Phase 4B)

## Phase 4A diagnosis (temporary warnings-as-errors)

Reproduced in `evaluate_time_warp_generalization` → `trainReadout` → `select_ridge_lambda` → `fit_ridge_readout`:

| Field | Value |
|---|---|
| Warning | `MATLAB:nearlySingularMatrix`, RCOND = `3.714967e-17` |
| Lambda candidate | `0` (first grid entry; solve attempted during selection) |
| `size(X)` | `[200, 8]` |
| `rank(X)` | `8` |
| `size(D)` (`[1,Z]`) | `[200, 9]` |
| Singular values of `D` (tail) | `…, 0.0279, 5.78e-10` |
| Zero-variance columns | `0` |
| `cond(D'D)` / `rcond` | `~1.4e16` / `3.71e-17` |
| Coefficient norm | unavailable (solve raised as error) |
| Root cause | Augmented normal equations `(D'D + λP)\(D'Y)` at `λ=0` square a near-null design direction; not a missing standardization bug |

Temporary diagnostic shadow code and global warning mutations were **not** committed.

## Phase 4A after edits

| Field | Value |
|---|---|
| Status | complete |
| Starting SHA | `b534780a5226fb34891fd7b7599133c66d4e126e` |
| Ending SHA | branch tip after Phase 4A commit (`fix: stabilize MESN ridge readout under collinearity`) |
| Numerical method | economy SVD; `gain = s/(s²+λ)`; `λ=0` uses `tol = max(size(Z))*eps(max(s))` min-norm |
| Lambda convention | absolute Frobenius ridge strength (unchanged; **not** divided by `n`) |
| Targeted tests | `test_ridge_readout` 18/18; `test_ridge_selection` 7/7; `test_time_warp_protocol` 6/6 (~329 s) |
| Full suite | 285/285 pass (~1402 s wall) |
| Scientific behavior changed | yes on ill-conditioned paths only — see notes |
| Files changed | `src/readout/fit_ridge_readout.m`, `apply_ridge_readout.m`, `select_ridge_lambda.m`; `tests/unit/test_ridge_readout.m`, `test_ridge_selection.m`; `tests/integration/test_time_warp_protocol.m`; `docs/validation/PUBLICATION_REPAIR_TASK_LOG.md` |

### Scientific compatibility

Well-conditioned synthetic fixtures (`λ > 0`): old normal-equation predictions vs new SVD agree within `~1e-14`.

Time-warp protocol (same seeds/options as the warning regression):

- Old path: `λ=0` candidate emitted `nearlySingularMatrix` with RCOND `~3.7e-17` (numerically unreliable coefficients if the warning was ignored).
- New path: no singular-matrix warning; final selected `λ = 1e-5`; final refit `conditioning_status = well_conditioned`, rank `8/8`.
- Scientific thresholds were not altered to preserve old output.

### Remaining blockers

Phase 4B+ (temporal learning gate, conventional ESN baseline, NARMA/MG redesign, aggregation, calibration).

## Phase 4B checklist (before edits)

- [x] Confirm branch/SHA `80ee2a9` clean
- [x] Inspect legacy G5 `test_esn_can_learn.m` (include_input=true, input-dominated target)
- [x] Reclassify legacy check; add temporal_learning_gate_v1 config + evaluator + controls
- [x] Wire fingerprint + publication readiness fail-closed
- [x] Unit + scientific integration tests; docs; commit; stop (no 4C)

### Phase 4B inspection findings (legacy check)

| Item | Finding |
|---|---|
| Function | `tests/scientific/test_esn_can_learn.m` → reclassified as `test_instantaneous_readout_pipeline_check.m` |
| `include_input` | **true** |
| Target | `Y = 0.85*U + 0.15*U(t-1)` (input-dominated; not `u(t-k)` alone) |
| Split | `trainReadout` contiguous train/val/test ratios on one trajectory |
| Seeds | three fixed seeds `[1729, 2718, 31415]`; global `rng(seed)` |
| Result fields | none persisted; fprintf NRMSE only |
| Readiness consumer | none previously; baseline/docs called it a “learning gate” incorrectly |
| Tests declaring success | legacy G5 thresholds NRMSE<0.5 and gap≥0.4 |
| Test-target leakage | shuffled control refits separately; held-out mutation of unused variables does not change model (trainReadout never sees test) |

## Phase 4B after edits

| Field | Value |
|---|---|
| Status | complete (implementation + tests); temporal gate **failed** fixed thresholds |
| Starting SHA | `80ee2a9aab63809ae42cebbc70146456555bdd9c` |
| Ending SHA | branch tip after Phase 4B commit |
| Temporal task | `y(t)=u(t-k)`, i.i.d. uniform[-1,1], `k=10`, `include_input=false`, features=`r` |
| Publication lengths | washout 200 / train 4000 / val 1000 / test 2000; 5 model seeds |
| Smoke lengths | washout 40 / train 250 / val 80 / test 120; 3 model seeds |
| Controls | current-input-only; no-recurrent-coupling (W=0 rebuild); shuffled-target; exact-history |
| Ridge | Phase 4A SVD absolute-λ; diagnostics retained per fit |
| Targeted tests | `test_temporal_learning_gate` 14/14; integration 2/2; pipeline 2/2; fingerprint 14/14 |
| Full suite | 302/302 pass (~1389 s wall) |
| Actual smoke gate | **failed** (no threshold change): median MESN NRMSE≈0.9796 > 0.90; median R²≈0.04 < 0.15; median Δ vs current≈0.0236 < 0.10; fraction beat current=3/3; Δ vs no-recurrence OK; shuffled & exact-history OK. (Do not call a mean delta a median.) |
| Publication gate | not executed in-suite (lengths reserved); same thresholds apply |

### Remaining blockers

Phase 4C+ (matched benchmarks / MG rollout, aggregation redesign, calibration, artifact export, figures). Scientific review of the failed temporal gate (implementation verified; MESN memory on this IID lag task is weak under preregistered thresholds).

## Phase 4B-R checklist (before edits)

- [x] Confirm branch/SHA `5e2a5aa` clean
- [x] Integrate gate into smoke/pilot/full runners; persist artifact; manifest fields
- [x] Fix reduced-via-full temporal-gate rebuild before fingerprint
- [x] `validate_temporal_learning_gate_result` + immutable-run load (fail closed)
- [x] Compact lambda tables + `selected_at_grid_boundary`; real controls/diagnostics checks
- [x] Tests (runner readiness, revalidation, fail-closed mutations, smoke docs); commit; stop (no 4C)

## Phase 4C-A checklist

- [x] Confirm branch/SHA `9e2c18b` clean
- [x] Add `cfg.benchmark_baselines` (`matched_task_baselines_v1`) to fingerprint
- [x] Dedicated conventional leaky tanh ESN (not SRNN_ESN / not Dale-only)
- [x] NARMA/MG one-step baselines with Phase 4A ridge; Dale reference pending aggregation
- [x] Preserve baselines through `compact_bench`; cell fails if required baseline fails
- [x] Unit/integration tests + docs; commit; stop before 4C-B (autonomous rollout)

## Phase 4C-A-R checklist (share matched baselines per seed)

- [x] Confirm branch/SHA `df49839` clean
- [x] Shared seed baseline bundle (`executed_shared_seed_bundle`) with identity hashes
- [x] Identical NARMA/MG task+split helpers for benchmarks and shared baselines
- [x] Compute/persist once per seed before cell loop; reject W_in / fingerprint mismatches
- [x] Compact cell payloads; recompute cell-specific comparisons; Dale remains feature-specific
- [x] Central fail-closed `validate_matched_task_baselines`; publication rejects overrides
- [x] Focused shared-bundle / fail-closed tests + docs; stop before 4C-B

## Phase 4C-B1 checklist (MG autonomous alignment + allocation)

- [x] Confirm branch/SHA `e9704b1` clean
- [x] Regression tests for off-by-one first step and publication skip allocation
- [x] Fingerprinted `cfg.mg_autonomous_rollout` (`mackey_glass_autonomous_rollout_v1`)
- [x] Deterministic origin schedule helper (fail closed; no silent shorten)
- [x] Corrected `generateAutonomous` / `generateAutonomousFromState` (step 1 = origin readout)
- [x] Single teacher-forced trajectory; state-seeded per origin; obj.S unchanged
- [x] Score `Y(i:i+H-1)`; train/val `sigma_ref`; valid-horizon + censoring; fixed horizons
- [x] ODE `computed` / DDE `unsupported_not_computed` schemas; fail closed (no skip)
- [x] One-step λ/readout/metrics invariance with rollout enabled
- [x] Compaction + publication-readiness `mg_autonomous_protocol_complete`
- [x] Unit/scientific/smoke tests + docs; stop before 4C-B2 (matched autonomous controls)

### Phase 4C-B1 defects reproduced (before repair)

| Defect | Evidence |
|---|---|
| Allocation skip | Publication `T=3000` → `U` length 2999 → test ≈601; old `init_len=200` + `rollout_steps=500` required 700 → `status=skipped` |
| First-step discard | `generateAutonomous` computed origin readout then fed it as input before recording step 1 |
| Truncatable washout context | `washout_steps = min(washout, N)` could ignore trailing context rows |

### Corrected contract

- Step 1 = frozen one-step prediction at origin; feedback starts at step 2
- Targets: prediction `k` scores `Y(origin+k-1)`
- Publication origins: 5 × horizon 100; smoke/pilot: 2 × horizon 20
- DDE: explicit `unsupported_not_computed`; never call `generateAutonomous` for DDE cells in the benchmark path

### Remaining blockers

Aggregation; calibration; figures.

## Phase 5A checklist (before edits)

- [x] Confirm branch/SHA `6431644` clean
- [x] Document defects in current `aggregate_ablation_results` (below)
- [x] Repair B2 defensive failure path (`first_step_alignment` missing-field crash)
- [x] Freeze `cfg.aggregation_plan` (`matched_seed_contrasts_v1`) + contrast registries
- [x] Rewrite aggregation: expected matrix from cfg; seed-level matched contrasts; no inference
- [x] Dale resolution; unique seed baselines; autonomous/ODE restrictions
- [x] Runner + readiness gates (`matched_seed_contrast_structure_complete`; inference deferred)
- [x] Focused + full tests; commit; stop before Phase 5B

### Phase 5A defects in current `aggregate_ablation_results` (documented before rewrite)

| Defect | Evidence |
|---|---|
| One global feat-x ODE/off/off control | Hardcoded `control_cell_key = adapt-off__std-off__delay-ode_off__feat-x`; every non-control cell contrasted against it |
| Factors changed simultaneously | Contrasts confound adaptation, STD, delay, and feature vs the single global control |
| Feature-r cells vs feat-x control | `feat-r` cells share the same feat-x control; no feature-matched pairing |
| No matched three-timescale vs moment-matched SFA contrast | No factorial A/S/D/F registry; no within-seed stratum averaging |
| Expected seeds/keys inferred from observed files | `unique([T.seed])` and `unique({T.cell_key})` from loaded cells only |
| Missing seed or condition can escape Cartesian check | Completeness is `numel(T) == n_obs_seeds * n_obs_keys` (self-consistent partial runs pass) |
| Repeated `rng` reset inside each bootstrap call | `bootstrap_ci` calls `rng(1729)` every invocation |
| Mislabeled Cliff’s delta | `cliff_delta` on paired diffs vs zeros, not two independent groups |
| No autonomous-control aggregation | Raw rows omit MG autonomous metrics and shared autonomous controls |
| No Dale-reference resolution | Dale remains `pending_paired_aggregation` with no paired-cell resolution |
| No analysis-set separation | Single aggregation path; no confirmatory vs SFA-sensitivity registries |
| Inference performed in Phase 5A scope | Bootstrap CIs, Cliff’s delta, effect summaries computed before matched contrasts exist |

## Phase 5A after edits

| Field | Value |
|---|---|
| Status | complete |
| Starting SHA | `6431644ef550f4825f83d4ae8711d1bc964d269e` |
| Aggregation protocol | `matched_seed_contrasts_v1` |
| Independent unit | `base_seed` |
| Inference | deferred (`aggregation_inference_complete=false`; `publication_ready` remains false) |
| Targeted tests | 154/154 (registry, seed aggregation, estimands, artifacts, fingerprint, B2/baselines/rollout/shared) |
| Full suite | 483/483 pass |
| Scientific behavior changed | no model equations; aggregation estimands/contrasts frozen; B2 defensive fail-closed only |
| Remaining blockers | Phase 5B (seed-level inference, multiplicity, aggregation validation) |

## Phase 4C-B2 checklist (matched MG autonomous controls)

- [x] Confirm branch/SHA `cddf46d` clean
- [x] Harden B1 origin/scoring validation (exact schedule; targets in test block)
- [x] Fingerprint `matched_mg_autonomous_controls_v1` (separate from one-step v1)
- [x] Retain frozen one-step fitted models + hashes in seed bundle v2
- [x] Recursive persistence / linear-AR / conventional ESN autonomous rollouts
- [x] Central compute + attach + validate helpers; shared per base seed
- [x] ODE cell comparisons; DDE non-applicability; Dale pending per feature
- [x] Publication gate `mg_autonomous_matched_controls_complete`
- [x] Unit/scientific/smoke tests + docs; stop before Phase 5 aggregation

## Phase 5B-A checklist (before edits)

- [x] Confirm branch `fix/mesn-publication-repair` at starting SHA `6251c68`
- [x] Separate publication / development / calibration seeds (30 untouched publication seeds)
- [x] Remove Cliff's delta; freeze paired effect quantities
- [x] Create `build_seed_inference_plan.m` (`seed_level_inference_v1`)
- [x] Freeze hypothesis registry (12 + 4 + 27 + 25 families)
- [x] Implement inference primitives under `experiments/revalidated/inference/`
- [x] Fingerprint includes `aggregation_inference_plan`
- [x] Unit tests + Phase 5A regression; commit; stop before Phase 5B-B

### Phase 5B-A starting SHA

`6251c68d78d4510ec8cbb1133438944125d4cdee`

## Phase 5B-B checklist (execute validated inference)

- [x] Confirm branch `fix/mesn-publication-repair` at starting SHA `228ffc5`
- [x] Harden inference helpers (bootstrap, sign-flip, RNG seed, effect summary, dimension control, plan validation)
- [x] Implement `run_seed_level_inference.m` from immutable Phase 5A tables
- [x] Allowlist `test_and_holm` vs `estimate_only` classification
- [x] Holm families frozen (12 + 4 + 27 + 25); smoke/pilot diagnostic-only
- [x] Write inference artifacts + `validate_aggregation_inference_artifact.m`
- [x] Repair `evaluate_publication_readiness` (forbid caller Boolean; independent artifact validation)
- [x] Integrate smoke/pilot/full runners + `validate_publication_run.m`
- [x] Unit/integration/scientific tests; full suite pass
- [x] Docs updated; commit; push

### Phase 5B-B starting SHA

`228ffc51c12893a7e3e52ff63b6a84621d111fb3`

| Field | Value |
|---|---|
| Status | complete |
| Inference protocol | `seed_level_inference_v1` |
| Artifact schema | `seed_level_inference_artifact_v1` |
| Provenance mode | `executed_from_immutable_phase5a_tables` |
| Publication inference executed | no (synthetic/diagnostic fixtures only) |
| `publication_ready` | false (temporal learning gate + calibration remain) |
| Phase 6 unblocked | no — repair temporal-learning/calibration blockers first |
