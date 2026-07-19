# Temporal memory development diagnostics — preregistration

**Status:** superseded before scientific execution (Phase 5D-B1-R correction)  
**Protocol:** `temporal_memory_diagnostic_v1`  
**Config source of truth:** `experiments/development/temporal_memory_development_config.m`  
**Seed ledger:** `docs/validation/SEED_ROLE_LEDGER.md`  
**Architecture under diagnosis:** `nonfractional_mesn_v1` (current non-fractional MESN only)

### Protocol fingerprint history

| Fingerprint | Status |
|---|---|
| `fa7670433618a852f9c98732c2b5877cab3409198074aa6feb20833ed6a690ba` | superseded before scientific execution |
| `bb3ac4fe71985a156c519f1065b99fb1ff3c1c22ae8bc139c46f43cce4a93310` | current after B1-R conventional single-reservoir amendment |

**Supersession reason:** conventional baseline previously permitted per-lag reservoir switching. No diagnostic outcomes inspected; this is a pre-execution correction.

This document freezes protocol identity, diagnostic cells, endpoints, controls,
seed roles, and descriptive materiality rules **before** any development
diagnostic trajectories are executed.

This protocol is **development-only**. It never yields publication evidence and
**cannot** satisfy publication readiness.

---

## 1. Scientific question

Why did the sealed non-fractional MESN narrowly fail
`temporal_learning_gate_v1` (median NRMSE and Δ vs current-input), and which
mechanisms (adaptation / STD / delay) appear to carry the residual lag-10
memory under the same frozen operating point?

This is architecture diagnosis only. It is not a confirmatory paper analysis.

---

## 2. Protocol identity

| Field | Value |
|---|---|
| `protocol_version` | `temporal_memory_diagnostic_v1` |
| `protocol_role` | `development_only_architecture_diagnosis` |
| `protocol_tier` | `development` |
| `publication_evidence` | `false` |
| `can_satisfy_publication_readiness` | `false` |
| `publication_ready` | `false` (always) |
| `architecture_version` | `nonfractional_mesn_v1` |

Canonical protocol fingerprint: SHA-256 over scientifically frozen fields only
(via `compute_temporal_memory_development_fingerprint`). Timestamps, paths,
hostnames, and runtime metadata are excluded.

---

## 3. Non-negotiable isolation rules

1. Do **not** modify `temporal_learning_gate_v1`.
2. Do **not** modify `mechanism_ablation_config.m`, its thresholds, target,
   seeds, lengths, or reference cell.
3. Never use v1 test input seed **9003** for development.
4. Never use v1 test targets for model selection.
5. Do not execute current publication seeds in development.
6. Do not execute reserved future-v2 seeds during development.
7. This protocol must never satisfy publication readiness.
8. Diagnosis concerns the **current non-fractional MESN only**.

---

## 4. Operating point and geometry

Copied from sealed `temporal_learning_gate_v1` solely to diagnose the failure.
**Not recalibrated.**

| Field | Value |
|---|---|
| `n` | 40 |
| `dt` | 0.1 |
| `tau_d` | 0.55 |
| `input_scaling` | 0.25 |
| `level_of_chaos` | 0.60 |
| input distribution | IID uniform \([-1, 1]\) |
| washout | 200 |
| train / validation / test samples | 4000 / 1000 / 2000 |
| lags | `1:50` |
| primary diagnostic lag | 10 |
| `include_input` | `false` |
| `lambda_grid` | `[0, logspace(-12, 2, 15)]` |

---

## 5. Development seeds (executable)

| Role | Seeds |
|---|---|
| Model | `[1729, 2718, 31415]` |
| Task train / val / test | `12001` / `12002` / `12003` |
| Shuffle train / val / test | `12101` / `12102` / `12103` |

Model seeds `[1729, 2718, 31415]` were already observed under v1 and may be used
**only** for development. They must remain disjoint from development task and
shuffle seeds, from all reserved future-v2 seeds, and from current publication
execution roles.

---

## 6. Diagnostic cells (exactly eight)

Cell construction uses existing confirmatory semantics and
`build_ablation_params`. Do not invent alternate model-construction rules.

| Diagnostic name | Meaning |
|---|---|
| `reference_r` | three_timescales / STD on / DDE on / feature `r` |
| `reference_x` | three_timescales / STD on / DDE on / feature `x` |
| `delay_removed_r` | three_timescales / STD on / ODE / feature `r` |
| `std_removed_r` | three_timescales / STD off / DDE on / feature `r` |
| `std_and_delay_removed_r` | three_timescales / STD off / ODE / feature `r` |
| `single_moment_matched_r` | single_moment_matched / STD on / DDE on / feature `r` |
| `adaptation_removed_r` | adaptation off / STD on / DDE on / feature `r` |
| `mechanisms_off_r` | adaptation off / STD off / ODE / feature `r` |

---

## 7. Diagnostic endpoints

### Per cell × model seed × lag `1:50`

- held-out NRMSE
- held-out R²
- held-out Pearson correlation
- squared correlation memory coefficient
- selected lambda
- grid-boundary flag
- effective numerical rank
- coefficient norm

### Per cell × model seed

- memory-capacity sum over lags `1:10`, `1:25`, and `1:50`
- lag of maximum memory coefficient
- lag-10 NRMSE and R²
- feature covariance effective rank
- feature participation ratio
- fraction of numerically near-constant features
- mean / median feature standard deviation
- mean firing rate
- saturation fraction
- silence fraction

---

## 8. Controls

Required controls (existing implementations only):

- current-input-only
- no-recurrent-coupling
- exact-history
- shuffled-target for the reference cell
- existing matched conventional leaky ESN baseline

Do **not** create a differently tuned conventional ESN for this protocol.

### Conventional memory-curve policy (`matched_conventional_memory_curve_v1`)

Pre-execution correction (Phase 5D-B1-R). No real diagnostic trajectory had been
run; scientific outcomes did not influence this amendment.

| Field | Value |
|---|---|
| `protocol_version` | `matched_conventional_memory_curve_v1` |
| `engine` | `run_conventional_leaky_esn` |
| `candidate_grid_source` | `build_matched_task_baselines_config` |
| `candidate_count` | 27 |
| `reservoir_selection_unit` | one candidate per model seed for entire lag curve |
| `reservoir_selection_metric` | mean validation NRMSE over lags `1:50` |
| `tie_tolerance` | `1e-12` |
| `tie_break` | earliest candidate in frozen order |
| `readout_policy` | per-lag lambda on train/val, then refit train+val |
| `test_targets_used_for_reservoir_selection` | false |
| `execution_scope` | once per model seed, shared across all diagnostic cells |

### Control allocation (Phase 5D-B2 runner)

- Shared task controls (once per task realization): current-input-only, exact-history
- Shared model-seed controls (once per model seed): conventional ESN
- Reference-cell only (`reference_r`): shuffled-target, no-recurrent coupling

---

## 9. Descriptive materiality rules

Frozen before observing diagnostic outcomes:

| Rule | Threshold / policy |
|---|---|
| NRMSE materiality | absolute paired median difference ≥ 0.02 |
| R² materiality | absolute paired median difference ≥ 0.03 |
| Directional consistency | all three development seeds share the same sign |
| Formal p-values | forbidden |
| Confirmatory inference with n=3 | forbidden |
| Comparison role | development hypotheses only |

---

## 10. Validator

`validate_temporal_memory_development_config` fail-closes on:

- unknown protocol versions
- publication protocol tiers
- `publication_ready=true`
- any use of v1 test seed 9003
- any reserved-v2 seed in executed roles
- overlap between development task and model seeds
- missing or duplicate diagnostic cells
- changed lengths or lag set
- `include_input=true`
- raw operating-point changes
- absent protocol fingerprint
- nondeterministic fingerprint fields (timestamps/paths affecting identity)

---

## 11. Explicit non-goals for this phase

- No scientific diagnostic trajectories are executed in Phase 5D-A2.
- No model selection on v1 test targets.
- No claim that development outcomes are publication evidence.
- No fractional-architecture reinterpretation of the sealed v1 negative result.
