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
