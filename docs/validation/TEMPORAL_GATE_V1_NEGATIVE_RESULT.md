# temporal_learning_gate_v1 — sealed valid negative result

**Status:** permanently sealed. Do not reinterpret, replace, or reopen for
model selection.

**Phase:** 5D-A1 (documentation and provenance only).

This document records the Phase 5C-B2 publication gate run as a **valid
negative result**. Independent validators confirmed artifact integrity. The
scientific gate was **not** recomputed in Phase 5D-A1.

---

## 1. Code SHA

```
5a055d03a538ff2775e2e35603af6018fa94809d
```

Branch at seal: `fix/mesn-publication-repair` (local and
`origin/fix/mesn-publication-repair`).

Development branch created from this SHA:
`investigate/mesn-temporal-memory-v2`.

---

## 2. Run directory

```
results/revalidated/phase5cb2_publication_temporal_gate_20260718_100555
```

Calibration authority source (copied into the run directory):

```
results/revalidated/phase5cb1_publication_calibration_20260716_170100
```

Copied authority path inside the run:

```
results/revalidated/phase5cb2_publication_temporal_gate_20260718_100555/calibration_authority/
```

---

## 3. Artifact hashes (SHA-256)

Computed with `Get-FileHash -Algorithm SHA256` on the immutable local files.
These files must not be altered, copied over, renamed, or regenerated.

| File | SHA-256 |
|---|---|
| `validation/temporal_learning_gate.mat` | `000873448af0f37c05364eb8c8c6de15f478739b854cdd20e24e2fa211b4a561` |
| `preregistered_config.mat` | `fc4d54f3e139c85705ee06e688f6f15fa15f27faa0b7043a97aae50174b623cc` |
| `full_summary.mat` | `3f2d986bbaae920de576da483879ede45815f02073e9b3f8219a93fdcbdc2d2c` |
| `manifest.mat` | `521dc05d4417b0407ba05d18a260d4dae34aaa349932e6f8dd60702342f1a4f2` |
| `manifest.json` | `fac6529ced3cf59f8fe28ea0c419653c821d41199e56c0f4206d1bf06cc7ede4` |

---

## 4. Protocol and calibration fingerprints

| Item | Value |
|---|---|
| Protocol | `temporal_learning_gate_v1` |
| Protocol fingerprint | `e9e7f22037a7b5a2bbca4529bc172b0c287f7b9ab0d43dd993a8c3ee7211fdd7` |
| Calibration fingerprint | `7edeb15cc290e32719417fa7a20a5448cbeb33e7bd991d244636573bde2755fb` |
| Calibration manifest hash | `2842c2f0a18747c569e9a5a9d571384bc4e5bd5a3c70b028194fc514eae020ed` |

---

## 5. Frozen operating point

| Field | Value |
|---|---|
| `candidate_index` | `1` |
| `input_scaling` | `0.25` |
| `level_of_chaos` | `0.60` |

Candidates 5, 9, and 13 were feasible alternatives at calibration time
(selection ranks 2–4) but were **not** selected. After observing the gate
result, they **cannot** replace candidate 1.

---

## 6. Per-seed metrics

Model seeds: `[1729, 2718, 31415, 10007, 10009]`.

Task: lag-10 reconstruction (`target_lag_steps=10`, `target_lag_time=1.0`,
`dt=0.1`), `feature_mode=r`, `include_input=false`, washout 200 / train 4000 /
validation 1000 / test 2000.

| seed | mesn_nrmse | mesn_r2 | current_nrmse | no_rec_nrmse | shuffled_nrmse | exact_hist_nrmse | delta_vs_current | delta_vs_no_rec | selected_lambda | grid_boundary | effective_rank | fit_status |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1729 | 0.9137376738331582 | 0.1650834634179688 | 1.000577123586561 | 0.9793193294976381 | 1.002126501404534 | 2.513933627555283e-13 | 0.08683944975340285 | 0.06558165566447993 | 0.0001 | 0 | 40 | ok |
| 2718 | 0.9122318184143899 | 0.1678331094723753 | 1.000577123586561 | 0.9792121024221583 | 1.001836361572552 | 2.513933627555283e-13 | 0.0883453051721711 | 0.06698028400776834 | 1e-06 | 0 | 40 | ok |
| 31415 | 0.9059508536830070 | 0.1792530507110306 | 1.000577123586561 | 0.9811391020141585 | 1.002230402777106 | 2.513933627555283e-13 | 0.09462626990355405 | 0.07518824833115156 | 1e-05 | 0 | 40 | ok |
| 10007 | 0.9108513172494125 | 0.1703498778650099 | 1.000577123586561 | 0.9775327576756698 | 1.003039043118381 | 2.513933627555283e-13 | 0.08972580633714855 | 0.06668144042625734 | 0.0001 | 0 | 40 | ok |
| 10009 | 0.9087082159408841 | 0.1742493782815354 | 1.000577123586561 | 0.9789680532465521 | 1.002083518085971 | 2.513933627555283e-13 | 0.09186890764567690 | 0.07025983730566798 | 0.0001 | 0 | 40 | ok |

---

## 7. Aggregate metrics

| Aggregate | Value |
|---|---|
| median MESN NRMSE | 0.9108513172494125 |
| median MESN R² | 0.1703498778650099 |
| median Δ vs current-input | 0.08972580633714855 |
| mean Δ vs current-input | 0.09028114776239068 |
| fraction beating current-input | 1.0 |
| median Δ vs no-recurrence | 0.06698028400776834 |
| fraction beating no-recurrence | 1.0 |
| median shuffled NRMSE | 1.002126501404534 |
| median exact-history NRMSE | 2.513933627555283e-13 |

---

## 8. Gate thresholds

| Rule | Threshold |
|---|---|
| `mesn_median_nrmse_max` | ≤ 0.90 |
| `mesn_median_r2_min` | ≥ 0.15 |
| `median_delta_vs_current_min` | ≥ 0.10 |
| `fraction_beating_current_min` | ≥ 0.80 |
| `median_delta_vs_no_recurrence_min` | ≥ 0.02 |
| `fraction_beating_no_recurrence_min` | ≥ 0.60 |
| `shuffled_median_nrmse_min` | ≥ 0.95 |
| `exact_history_median_nrmse_max` | ≤ 1e-6 |

---

## 9. Passed and failed conditions

`gate.passed = false`.

| Condition | Passed |
|---|---|
| `all_fits_and_metrics_finite` | yes |
| `include_input_false` | yes |
| `target_lag_positive` | yes |
| `target_lag_time_consistent` | yes |
| `splits_independent` | yes |
| `mesn_median_nrmse_ok` | **no** |
| `mesn_median_r2_ok` | yes |
| `median_delta_vs_current_ok` | **no** |
| `fraction_beating_current_ok` | yes |
| `median_delta_vs_no_recurrence_ok` | yes |
| `fraction_beating_no_recurrence_ok` | yes |
| `shuffled_median_nrmse_ok` | yes |
| `exact_history_median_nrmse_ok` | yes |
| `seed_rows_complete` | yes |
| `controls_present` | yes |
| `diagnostics_present` | yes |

Failed conditions (exact):

1. `mesn_median_nrmse_ok`
2. `median_delta_vs_current_ok`

Provenance:

| Field | Value |
|---|---|
| `evaluation_provenance.mode` | `executed` |
| `test_override_used` | `false` |
| `test_target_mutated` | `false` |

---

## 10. Independent-validation outcome (Phase 5D-A1)

Fresh MATLAB process. Scientific gate **not** recomputed. Actions:

1. Loaded `preregistered_config.mat`.
2. Loaded `validation/temporal_learning_gate.mat`.
3. Ran `validate_temporal_learning_gate_result` → **ok** (`gate_validation_ok=1`).
4. Ran `validate_publication_run` on the gate-only run → temporal-gate and
   calibration-authority independent checks **pass**;
   `publication_ready=false` (expected for gate-only incomplete publication
   matrix).
5. Independently validated copied `calibration_authority/` and the source
   calibration directory → both **valid** and authorize publication runs.

Confirmed:

- protocol `temporal_learning_gate_v1`
- protocol fingerprint `e9e7f22037a7b5a2bbca4529bc172b0c287f7b9ab0d43dd993a8c3ee7211fdd7`
- calibration fingerprint `7edeb15cc290e32719417fa7a20a5448cbeb33e7bd991d244636573bde2755fb`
- calibration manifest hash `2842c2f0a18747c569e9a5a9d571384bc4e5bd5a3c70b028194fc514eae020ed`
- `candidate_index=1`, `input_scaling=0.25`, `level_of_chaos=0.60`
- provenance mode `executed`; overrides/mutations false
- `gate.passed=false` with exactly the two failed conditions above

Artifact SHA-256 values were unchanged after this load-only revalidation.

---

## 11. Scientific conclusion

> The frozen MESN demonstrates measurable and seed-consistent lag-10
> information, but it does not satisfy the preregistered
> temporal_learning_gate_v1 validity requirement.

---

## 12. Forbidden interpretations

Do **not** claim or imply any of the following from this sealed result:

- “the MESN cannot learn”
- “the MESN contains no temporal information”
- “the architecture passed”
- “the result is evidence of fractional dynamics”

The per-seed and aggregate numbers show positive lag-10 signal versus controls,
but the preregistered validity thresholds were not all met.

---

## 13. Reference model (architecture under test)

The reference confirmatory cell was
`adapt-three_timescales__std-on__delay-dde_on__feat-r`:

- three-timescale excitatory SFA
- common single-timescale inhibitory SFA
- STD enabled
- inhibitory DDE delay enabled
- firing-rate features `r`
- raw input excluded (`include_input=false`)

---

## 14. Non-fractional architecture

This architecture is still **non-fractional**. No fractional derivative is
implemented by this gate. Multi-timescale exponential SFA is not a fractional
operator. See `MESN_ARCHITECTURE_CLAIM_BOUNDARY.md`.

---

## 15. Candidate replacement ban

After observing the result, candidates **5**, **9**, and **13** cannot replace
candidate **1**. The frozen operating point remains candidate 1
(`input_scaling=0.25`, `level_of_chaos=0.60`).

---

## 16. Protocol closure

`temporal_learning_gate_v1` and its test target are **permanently closed** for
model selection.

Further diagnosis of the MESN memory shortfall belongs on
`investigate/mesn-temporal-memory-v2` under a new protocol / architecture
version, not by mutating this sealed negative result.
