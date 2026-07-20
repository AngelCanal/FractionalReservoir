# Temporal Memory Diagnostic — Scientific Review (Phase 5D-D)

**Phase:** 5D-D (scientific diagnosis correction; documentation only)  
**Status:** corrects overstatements in the Phase 5D-C interpretation  
**Role:** development-only architecture diagnosis — **not** publication evidence  
**No implementation** occurred in this phase.

---

## 1. Immutable run identity

| Field | Value |
|---|---|
| Run directory | `results/development/phase5dc_temporal_memory_diagnostic_20260720_101711` |
| Protocol | `temporal_memory_diagnostic_v1` |
| Protocol fingerprint | `bb3ac4fe71985a156c519f1065b99fb1ff3c1c22ae8bc139c46f43cce4a93310` |
| Bound code SHA | `579a935044e818a36a86cd0a9cc211142ec6d071` |
| Architecture version (diagnostic) | `nonfractional_mesn_v1` |
| Model seeds | `[1729, 2718, 31415]` |
| Manifest content hash | `879cacd1c6c2de31754fae26722c4fe702099d87f5f653f19b9365906ce5426f` |
| Registry content hash | `a7acd6cba8bfb183b574992d5b61cedfb6a4c286770111f00d6e61f93edf66db` |
| Checkpoint file SHA-256 | `aaf4ccbf5b73bbb3d5fdfcd7cd4d6e8d578ebcd8e1d71b463eec62cd749b6eaa` |
| Diagnostic config binary SHA-256 | `6c48f4f2987bfce726458603c7d2242bbf3b0dcd9d1b256ebbbd9e500516e386` |

**Historical validation note.** This package binds code SHA `579a935…`. Future revalidation must check out that bound SHA. Do not weaken the validator so that the historical run validates under a different `HEAD`.

**Phase 5D-D action.** Hashes above were recomputed on the immutable local package while checked out at `579a935…` and match the Phase 5D-C report. No result artifact was altered.

---

## 2. Validation summary

The completed 5D-C package is internally complete (checkpoint `complete`, 34 keys, registry 46 entries). Exact-history controls remain numerically valid (max NRMSE ≈ 2×10⁻¹³). Current-input-only and shuffled-target controls remain near NRMSE ≈ 1 / R² ≈ 0 at lag 10. Conventional leaky ESN (candidate 16; ρ=0.9, leak=1.0, input scaling=0.25) remains dramatically stronger than reference MESN on lag-10 and integrated memory.

This review **does not** recompute reservoir trajectories, refit readouts, or reopen sealed `temporal_learning_gate_v1`. Descriptive contrasts only; no p-values, CIs, or confirmatory inference.

---

## 3. Corrected interpretation of raw participation ratio

### What the code computes

`experiments/development/compute_temporal_feature_diagnostics.m` calculates covariance participation ratio from **centered raw features**:

\[
X_c = X - \mathrm{mean}(X),\qquad
C_{\mathrm{raw}} = X_c^\top X_c / N,\qquad
\mathrm{PR}_{\mathrm{raw}} = \frac{(\mathrm{tr}\,C_{\mathrm{raw}})^2}{\mathrm{tr}(C_{\mathrm{raw}}^2)}.
\]

It does **not** standardize each feature before computing \(\mathrm{PR}_{\mathrm{raw}}\).

`src/readout/fit_ridge_readout.m` fits on standardized features:

\[
Z = (X - \texttt{feature\_mean}) ./ \texttt{feature\_scale},
\]

with zero-variance scales replaced by 1.

### What \(\mathrm{PR}_{\mathrm{raw}}\approx 1.1\) does and does not show

Across reference and ablation cells, saved \(\mathrm{PR}_{\mathrm{raw}}\) lies near 1.06–1.37 with numerical rank typically 39–40. That demonstrates **concentration of raw feature covariance** (strong variance anisotropy and/or common-mode structure).

It does **not**, by itself, prove that the **standardized ridge design** has only ≈1 effective dimension. Full numerical rank alone also does **not** prove useful effective dimension. Low raw PR alone must **not** be called definitive “readout dimension collapse.”

Phase 5D-C root-cause label **F | Feature collapse | strongly supported** overstated the inferential reach of raw PR. Corrected language appears in §8.

---

## 4. Standardized-feature post-hoc diagnostics

Read-only extraction from the 24 existing cell×seed artifacts (no reservoir rerun). Training design matrices were available for `reference_r` (`mesn_features.train.X`); other cells used saved `feature_diagnostics` and frozen lag-10 readout fields.

### 4.1 All 24 cell×seed artifacts (raw diagnostics + frozen lag-10 readout)

| cell | seed | PR_raw | rank | med\|ρ\| | max\|ρ\| | mean σ | med σ | near-const | zv | λ₁₀ | ‖β‖₁₀ |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| reference_r | 1729 | 1.137 | 40 | 0.675 | 0.999 | 0.00392 | 0.00199 | 0 | 0 | 1e-3 | 56.3 |
| reference_r | 2718 | 1.127 | 40 | 0.798 | 1.000 | 0.00575 | 0.00290 | 0 | 0 | 1e-4 | 147.4 |
| reference_r | 31415 | 1.079 | 40 | 0.779 | 0.999 | 0.00378 | 0.00174 | 0 | 0 | 1e-5 | 297.0 |
| reference_x | 1729 | 1.118 | 40 | 0.671 | 1.000 | 0.00507 | 0.00250 | 0 | 0 | 1e-5 | 638.8 |
| reference_x | 2718 | 1.110 | 40 | 0.800 | 1.000 | 0.00666 | 0.00332 | 0 | 0 | 0 | 16540 |
| reference_x | 31415 | 1.062 | 40 | 0.779 | 1.000 | 0.00432 | 0.00202 | 0 | 0 | 1e-11 | 25779 |
| delay_removed_r | 1729 | 1.128 | 40 | 0.698 | 0.999 | 0.00387 | 0.00197 | 0 | 0 | 1e-5 | 324.1 |
| delay_removed_r | 2718 | 1.115 | 40 | 0.797 | 1.000 | 0.00563 | 0.00276 | 0 | 0 | 1e-4 | 161.7 |
| delay_removed_r | 31415 | 1.072 | 40 | 0.780 | 0.999 | 0.00374 | 0.00169 | 0 | 0 | 1e-4 | 196.4 |
| std_removed_r | 1729 | 1.369 | 40 | 0.600 | 0.997 | 0.00518 | 0.00319 | 0 | 0 | 1e-3 | 40.3 |
| std_removed_r | 2718 | 1.352 | 39 | 0.841 | 0.999 | 0.01010 | 0.00814 | 0.025 | 1 | 1e-4 | 124.5 |
| std_removed_r | 31415 | 1.203 | 40 | 0.760 | 1.000 | 0.00517 | 0.00326 | 0 | 0 | 1e-5 | 312.0 |
| std_and_delay_removed_r | 1729 | 1.347 | 40 | 0.606 | 0.997 | 0.00507 | 0.00306 | 0 | 0 | 1e-3 | 46.8 |
| std_and_delay_removed_r | 2718 | 1.329 | 39 | 0.836 | 0.999 | 0.00955 | 0.00742 | 0.025 | 1 | 0 | 524.1 |
| std_and_delay_removed_r | 31415 | 1.187 | 40 | 0.764 | 1.000 | 0.00504 | 0.00318 | 0 | 0 | 1e-5 | 371.1 |
| single_moment_matched_r | 1729 | 1.137 | 40 | 0.675 | 0.999 | 0.00393 | 0.00199 | 0 | 0 | 1e-3 | 56.3 |
| single_moment_matched_r | 2718 | 1.127 | 40 | 0.799 | 1.000 | 0.00577 | 0.00291 | 0 | 0 | 1e-4 | 154.2 |
| single_moment_matched_r | 31415 | 1.079 | 40 | 0.779 | 0.999 | 0.00379 | 0.00175 | 0 | 0 | 1e-5 | 296.2 |
| adaptation_removed_r | 1729 | 1.144 | 40 | 0.675 | 0.999 | 0.00396 | 0.00206 | 0 | 0 | 1e-3 | 55.1 |
| adaptation_removed_r | 2718 | 1.129 | 40 | 0.785 | 0.999 | 0.00582 | 0.00297 | 0 | 0 | 0 | 343.8 |
| adaptation_removed_r | 31415 | 1.081 | 40 | 0.778 | 0.999 | 0.00383 | 0.00177 | 0 | 0 | 1e-5 | 356.6 |
| mechanisms_off_r | 1729 | 1.366 | 40 | 0.609 | 0.997 | 0.00510 | 0.00319 | 0 | 0 | 1e-4 | 110.4 |
| mechanisms_off_r | 2718 | 1.329 | 39 | 0.828 | 0.999 | 0.00950 | 0.00722 | 0.025 | 1 | 1e-5 | 459.4 |
| mechanisms_off_r | 31415 | 1.186 | 40 | 0.758 | 1.000 | 0.00508 | 0.00321 | 0 | 0 | 1e-5 | 460.7 |

Per-feature `feature_scale` vectors are stored in each artifact’s lag-10 `fit_identity.feature_scale` (length 40). Across cells they track the training feature standard deviations (near-zero variance columns, when present, appear as scale `1` after `fit_ridge_readout` zero-variance handling). Full vectors are not reprinted here; min/median/max of lag-10 scales were extracted for every cell×seed.

Selected λ across all 50 lags: many cells place a nontrivial fraction of lags at λ=0 (grid boundary). Conventional ESN λ medians are larger (≈0.01–1) with **no** λ=0 selections in the stored per-lag tables.

### 4.2 `reference_r` standardized design (saved \(X_{\mathrm{train}}\) only)

Constructed exactly as ridge:

\[
Z = \bigl(X_{\mathrm{train}} - \mathrm{mean}(X_{\mathrm{train}},1)\bigr) ./ \mathrm{std}(X_{\mathrm{train}},0,1)
\]

with zero-variance scales set to 1 (none observed for `reference_r`).

| seed | PR_raw | PR_std | rank_raw | rank_std | med\|ρ\|_raw | med\|ρ\|_Z | max\|ρ\|_Z | cond(Z) |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1729 | 1.137 | 2.106 | 40 | 40 | 0.675 | 0.675 | 0.999 | 2.62×10⁴ |
| 2718 | 1.127 | 1.770 | 40 | 40 | 0.798 | 0.798 | 1.000 | 3.64×10⁴ |
| 31415 | 1.079 | 1.788 | 40 | 40 | 0.779 | 0.779 | 0.999 | 7.45×10⁴ |

Off-diagonal correlations are unchanged by column scaling (as expected). Standardized covariance PR rises only modestly above raw PR and remains ≈2, not near the ambient dimension 40. Singular-value spectra of \(Z\) are extremely anisotropic (retained SV ratio ∼10⁻⁵).

### 4.3 Interpretation under the declared policy

| Pattern | Verdict for `reference_r` |
|---|---|
| Low raw PR + healthy standardized PR | **Not observed.** Standardization does not restore a healthy PR. |
| Low raw PR + low standardized PR / high correlations | **Observed.** Genuine redundant / common-mode feature geometry. |
| Full numerical rank | Present (40/40) but does **not** imply useful effective dimension. |

**Corrected claim.** Raw \(\mathrm{PR}\approx 1.1\) shows raw covariance concentration. Post-hoc standardized analysis shows that ridge’s built-in standardization does **not** remove the redundancy: the standardized design still has PR ≈ 1.8–2.1 with median absolute pairwise correlation ≈ 0.67–0.80. That supports a **common-mode / redundant feature-geometry** hypothesis. It does **not** license the shorthand “definitive readout dimension collapse” from raw PR alone.

### 4.4 Conventional ESN design singular values

Stored conventional bundles expose per-lag `selected_lambda`, `numerical_rank`, and `coefficient_norm`, but **do not** persist training-design singular-value vectors. No conventional SV spectrum can be reported without rerunning. Descriptively: ranks are 40/40 at every lag; median ‖β‖ ≈ 1.6–2.9 (orders of magnitude smaller than many MESN `reference_x` fits); λ selections avoid the zero boundary.

---

## 5. Corrected recurrence interpretation

Lag-10 metrics from the completed package:

| seed | reference_r NRMSE / R² / MC² | W=0 NRMSE / R² / MC² | ΔNRMSE (W0−ref) | ΔR² (ref−W0) | conventional NRMSE / R² |
|---:|---|---|---:|---:|---|
| 1729 | 0.926 / 0.143 / 0.144 | 0.978 / 0.044 / 0.045 | +0.052 | +0.098 | 0.230 / 0.947 |
| 2718 | 0.918 / 0.157 / 0.157 | 0.979 / 0.042 / 0.042 | +0.061 | +0.115 | 0.167 / 0.972 |
| 31415 | 0.923 / 0.148 / 0.148 | 0.978 / 0.044 / 0.045 | +0.055 | +0.104 | 0.245 / 0.940 |

### Separated questions

1. **Does recurrent coupling contribute information?**  
   Yes. `reference_r` consistently beats W=0 on all three seeds (median ΔNRMSE ≈ 0.055, ΔR² ≈ 0.104). “Absence of recurrent contribution” is **contradicted**.

2. **Is that contribution sufficient for the desired memory task?**  
   Not established. `reference_r` remains dramatically below the matched conventional ESN (median lag-10 NRMSE gap ≈ 0.70; R² gap ≈ 0.80; MC₁₋₅₀ ≈ 5.8 vs ≈ 16–17). “Insufficient effective recurrent memory” is **not** contradicted and remains a supported candidate explanation.

**Do not** infer recurrent sufficiency merely because W≠0 improves over W=0. Phase 5D-C’s labeling of “Insufficient recurrent coupling | contradicted” conflated contribution with sufficiency and must be retired.

---

## 6. Endpoint-specific delay interpretation

Contrast `reference_r` − `delay_removed_r` (positive improvement ⇒ delays help):

| endpoint | seed 1729 | 2718 | 31415 | median | seed-sign consistency |
|---|---:|---:|---:|---:|---|
| lag-10 ΔNRMSE | −0.00013 | −0.00100 | −0.00150 | −0.00100 | all negative (delays slightly worse) |
| lag-10 ΔR² | −0.00024 | −0.00183 | −0.00276 | −0.00183 | all negative |
| ΔMC₁₋₁₀ | +0.290 | +0.256 | +0.411 | +0.290 | all positive |
| ΔMC₁₋₂₅ | +0.337 | +0.301 | +0.417 | +0.337 | all positive |
| ΔMC₁₋₅₀ | +0.270 | +0.340 | +0.409 | +0.340 | all positive |

**Required language.**

- Delays show a **small unfavorable lag-10 point effect**.
- Delays may still **improve integrated memory across lags**.
- The evidence is **endpoint-dependent**.
- Do **not** globally classify delays as helpful or harmful.
- Explicit delays and fractional memory are **distinct** mechanisms and may interact in v2.

### STD and SFA (same endpoint care)

- **STD** (`reference_r` vs `std_removed_r`): lag-10 NRMSE/R² mixed/inconclusive; MC contrasts mixed across seeds and horizons.
- **SFA distribution** (`single_moment_matched_r`): lag-10 mixed; MC contrasts small.
- **SFA presence** (`adaptation_removed_r`): lag-10 mixed (seed 2718 large positive; seed 31415 negative); not a global verdict.
- **Full mechanisms** vs `mechanisms_off_r`: small favorable lag-10 direction below materiality; larger favorable MC₁₋₁₀/₂₅/₅₀.

---

## 7. Conventional ESN comparison

Selected conventional model (all seeds): spectral radius 0.9, leak 1.0, input scaling 0.25, candidate index 16, one reservoir per seed across all lags.

| property | current MESN (`reference_r`) | matched conventional ESN |
|---|---|---|
| recurrent construction | Dale-constrained Gaussian → abscissa-scaled | signed dense/sparse ESN weights → radius-scaled |
| Dale constraints | yes (E≥0, I≤0 columns) | no |
| states / rates | continuous \(x\); nonnegative rates \(r=\phi(q)\) | typically signed tanh (leaky update) |
| recurrent scaling | spectral **abscissa** target `level_of_chaos=0.60` | spectral **radius** 0.9 |
| leak / update | continuous \(\tau_d\dot x=-x+\cdots\), \(\tau_d=0.55\) | discrete leaky integrator, leak=1.0 |
| activation | piecewise sigmoid on SFA-adjusted \(q\) | tanh (conventional engine) |
| input scaling / support | frozen 0.25; fixed-count mask | 0.25; conventional Win construction |
| feature normalization | ridge standardization | ridge standardization |
| features | rates \(r\) (reference) | reservoir states |
| dimension | n=40 | n=40 |
| λ distribution | often small; frequent λ=0 boundary | larger medians; no λ=0 in stored tables |
| lag-10 / MC | NRMSE≈0.92; MC₁₋₅₀≈5.5–6.1 | NRMSE≈0.17–0.25; MC₁₋₅₀≈16–17 |

Plausible structural contributors to the conventional advantage include: signed unbounded activations, radius-based recurrent gain near the ESP edge, discrete full-leak update, absence of Dale/SFA/STD/DDE operating-point constraints, and healthier effective readout geometry (much smaller coefficient norms). **None of these imply that fractionality is required** merely because the conventional ESN performs better.

---

## 8. Revised root-cause ranking

Descriptive ranking only (n=3 development seeds; no confirmatory inference).

| Rank | Hypothesis | Status | Notes |
|---:|---|---|---|
| 1 | Insufficient **effective** recurrent memory relative to the task / conventional baseline | **supported candidate** | W≠0 helps, but far from conventional capacity |
| 2 | Common-mode / redundant feature geometry (high pairwise correlation; low standardized PR) | **supported** | corrected vs raw-PR-only “collapse” claim |
| 3 | Short memory horizon (peak lag=1; weak lag-10) | **supported descriptively** | consistent with (1) |
| 4 | Ridge / λ-boundary pathology | **weakly supported** | nontrivial λ=0 rate; not primary |
| 5 | Mechanism combination effects (delays/STD/SFA jointly) | **endpoint-dependent / unresolved** | see §6 |
| 6 | Representation `x` vs `r` | **weak; below materiality** | small consistent lag-10 gain for `x` |
| — | Absence of recurrent contribution | **contradicted** | |
| — | Global “delays harmful” or “delays helpful” | **not warranted** | endpoint-dependent |
| — | Fractionality required because conventional wins | **not warranted** | |

---

## 9. Exact claim boundary

**Permitted from this diagnostic package**

- The non-fractional MESN under the frozen v1 operating point has measurable but weak lag-10 memory versus current-input and shuffled controls.
- Recurrent coupling contributes genuine information versus W=0.
- Effective recurrent memory remains far below a matched conventional leaky ESN.
- Raw feature covariance is highly concentrated; standardized features remain strongly correlated with low participation ratio.
- Delay/STD/SFA effects are small and endpoint-dependent at n=3.

**Forbidden**

- Calling raw PR≈1.1 definitive “readout dimension collapse.”
- Claiming “no recurrent contribution.”
- Claiming recurrent memory is sufficient.
- Globally labeling delays (or STD/SFA) helpful or harmful.
- Treating multi-timescale SFA, STD, or DDE delays as fractional dynamics.
- Using this package as publication evidence or as authorization to touch future v2 seeds.
- Inferring that a fractional architecture is empirically necessary solely from the conventional gap.

---

## 10. Limitations

- Development seeds only (`1729`, `2718`, `31415`); n=3; descriptive contrasts only.
- Frozen v1 operating point by design; no recalibration.
- Adaptive ODE/DDE solvers (v1) are not a matched discrete α=1 control for a future fractional method.
- Standardized diagnostics for non-`reference_r` cells could not rebuild \(Z\) from saved \(X_{\mathrm{train}}\) (features not persisted); raw diagnostics and frozen scales were used instead.
- Conventional design singular values were not stored in the fitted bundles.
- No p-values, confidence intervals, or confirmatory hypothesis tests were computed.

**Companion architecture decision:** [`FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md`](FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md).
