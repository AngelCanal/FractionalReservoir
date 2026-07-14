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
