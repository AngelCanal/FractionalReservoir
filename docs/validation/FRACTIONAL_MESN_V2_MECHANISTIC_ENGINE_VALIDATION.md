# Fractional MESN v2 — Mechanistic Engine Foundation Validation (Phase 5D-E3-B3)

**Status:** Phase 5D-E3-B3 **complete**
**Claim:** the no-delay mechanistic foundation is **validated**
**Authoritative preregistration:** [`FRACTIONAL_MESN_V2_MECHANISTIC_ENGINE_PREREGISTRATION.md`](FRACTIONAL_MESN_V2_MECHANISTIC_ENGINE_PREREGISTRATION.md)
**Architecture decision:** [`FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md`](FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md)

---

## 1. Implementation commits and validated SHA

| Phase | Commit SHA | Scope |
|---|---|---|
| E3-B1 standalone modules | `e0f8dcc51fd9acffe4f71401e4274fb473350de9` | rate map + Dale validator |
| E3-B2 mechanistic orchestrator | `5daa86202fb46e747f0c6ed83362d1ed27adc677` | mechanistic engine |
| **Validated implementation SHA** | `5daa86202fb46e747f0c6ed83362d1ed27adc677` | E3-B1 + E3-B2 |

**Branch:** `design/fractional-mesn-v2`
**MATLAB environment:** R2026a (26.1.0.3234472) Update 1, Windows 10 (PCWIN64)

---

## 2. Ten-file implementation and test scope

### E3-B1 (six files)

| Path | Role |
|---|---|
| `src/algorithms/fractional/mesn_v2_rate_map.m` | rate-map function |
| `src/algorithms/fractional/mesn_v2_rate_map_spec.m` | rate-map spec |
| `src/algorithms/fractional/validate_mesn_v2_dale_matrix.m` | Dale validator |
| `src/algorithms/fractional/mesn_v2_dale_validator_spec.m` | Dale validator spec |
| `tests/unit/test_mesn_v2_rate_map.m` | rate-map tests (20) |
| `tests/unit/test_mesn_v2_dale_validator.m` | Dale validator tests (14) |

### E3-B2 (four files)

| Path | Role |
|---|---|
| `src/algorithms/fractional/FractionalMESN_v2_mechanistic.m` | mechanistic engine |
| `src/algorithms/fractional/validate_fractional_mesn_v2_mechanistic_config.m` | config validator |
| `src/algorithms/fractional/fractional_mesn_v2_mechanistic_engine_spec.m` | engine spec |
| `tests/unit/test_fractional_mesn_v2_mechanistic_engine.m` | engine tests (24) |

No frozen E2 file, Caputo core file, v1 file, ODE/DDE file, experiment, configuration, result, or artifact changed in the E3-B1/B2 implementation commits relative to the E3-A preregistration commit `0fd2a46a6ea45e7dea3664e09bf9319e40012986`.

---

## 3. Public APIs

```matlab
[r, info] = mesn_v2_rate_map(q, activation_cfg)
dale_info = validate_mesn_v2_dale_matrix(W, presynaptic_signs)
cfg = validate_fractional_mesn_v2_mechanistic_config(cfg_in)
engine = FractionalMESN_v2_mechanistic(cfg)
[X, Q, R, info] = simulate(engine, U, x0)
```

Spec functions: `mesn_v2_rate_map_spec`, `mesn_v2_dale_validator_spec`, `fractional_mesn_v2_mechanistic_engine_spec`.

---

## 4. Value-class and stateless semantics

`FractionalMESN_v2_mechanistic` is a MATLAB **value class** (not a `handle` subclass). Validated configuration is stored in a `SetAccess = private` property. `simulate` does not mutate the object; no hidden trajectory state, continuation/checkpoint API, `persistent`, `global`, or RNG exists in E3 source. No production caller invokes the mechanistic engine. The mechanistic engine does **not** call `FractionalMESN_v2`.

---

## 5. Trajectory orientation and causal n−1 update

| Variable | Shape | Interpretation |
|---|---|---|
| `U` | `N × n_input` | external input sequence |
| `U(k,:)` | row | `u_{k-1}` |
| `X` | `(N+1) × n` | membrane/reservoir state |
| `X(1,:)` | row | `x_0` |
| `X(j+1,:)` | row | `x_j` |
| `Q` | `(N+1) × n` | effective drive before activation |
| `Q(j+1,:)` | row | `q_j` |
| `R` | `(N+1) × n` | firing-rate map output |
| `R(j+1,:)` | row | `r_j` |

**Step producing `x_k` uses only `r_{k-1}` and `u_{k-1}`:**

\[
d_{k-1} = W\, r_{k-1} + W_{\mathrm{in}}\, u_{k-1}
\]

Recurrence is `W * r_{k-1}`, not `W * x_{k-1}` unless identity mode makes `R = X`. Complete `X(1:k,:)` history is passed at every nonempty step. `Q(k+1,:) = X(k+1,:)` (no SFA in E3). `R(k+1,:)` is computed after storing `X(k+1,:)`. `N = 0` computes initial `Q`/`R` rows but makes no Caputo step.

---

## 6. Complete-history / no-truncation policy

Every nonempty step calls `caputo_l1_semiimplicit_step` with full state history `X(1:k,:)`. No history truncation, compression, approximation, or acceleration exists. `info.full_history_used == true` and `info.truncated == false`.

---

## 7. Rate-map contract

- Supported modes only: `piecewise_sigmoid`, `identity`
- **No scientific defaults** for activation parameters
- **Identity** returns `r = q` exactly; `S_a = []` and `S_c = []` are the canonical empty representation; identity is an **engineering limiting control only**, not a biological firing-rate model
- **Piecewise** delegates to tracked `piecewiseSigmoid`; the piecewise formula is **not** copied into the module
- Input shape is preserved; `q` and `activation_cfg` validation match the preregistration; metadata is bounded

---

## 8. Dale contract

- Presynaptic-column signs: `+1` column → `W(:,j) >= 0`; `-1` column → `W(:,j) <= 0`
- Signs are caller-supplied, normalized to `1×n`, exactly `±1`
- Zero entries and zero columns are accepted
- `W` is validated but never modified; no construction, scaling, spectral calculation, neuron-type selection, or RNG

---

## 9. W*r recurrence and distinction from W*x

Under piecewise-sigmoid activation, `testRecurrenceUsesRNotXAndRateRecomputed` verifies the engine trajectory matches an independent `W*r` reference and **differs** from an independent `W*x` reference when `R ≠ X`. Under identity mode, `R = Q = X` and recurrence reduces to `W*x_{k-1}`.

---

## 10. E2 limiting controls

| Control | Evidence |
|---|---|
| `W = 0` input-only `X` equality to frozen E2 | `testE2InputOnlyLimitingControls` (identity + piecewise) |
| Identity linear `X` equality to frozen E2 | `testE2LinearLimitingControlsAndIdentityQR` (`alpha==1` and `alpha<1`) |
| `Q = R = X` under identity | `testE2LinearLimitingControlsAndIdentityQR` |

---

## 11. Matched alpha==1 path and independent formula

The mechanistic engine has **exactly one** runtime call site to `caputo_l1_semiimplicit_step`. There is **no** independent engine-level `alpha==1` state formula; the frozen core alone selects its backward-Euler-leak branch.

Independent reference (no core, no engine calls):

\[
x_k = \frac{(\tau_x/dt)\, x_{k-1} + d_{k-1}}{(\tau_x/dt) + 1},
\qquad
d_{k-1} = W\, r_{k-1} + W_{\mathrm{in}}\, u_{k-1}
\]

Verified in `testAlphaOneIndependentIdentitySingleAndMulti` and `testAlphaOneIndependentPiecewiseSingleAndMulti`.

---

## 12. alpha<1 manual-core evidence

`testAlphaLessThanOneManualCoreIdentityAndPiecewise` compares engine `X`, `Q`, `R` against a manual growing-history reference that calls `caputo_l1_semiimplicit_step` and `mesn_v2_rate_map` directly but **does not** call `FractionalMESN_v2_mechanistic`.

---

## 13. Identity hashes (correctly separated)

| Identity | Schema | Content hash |
|---|---|---|
| Frozen E2 engine | `fractional_mesn_v2_engine_v1` | `38414814b75f35c997e695347ec8f9979660108e053d8f676329758e4fc6971d` |
| Frozen Caputo core | `fractional_mesn_v2_caputo_l1_core_v1` | `3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f` |
| Rate-map module | `mesn_v2_rate_map_v1` | `483b6192099426b1c22f29a35e04d9e22c508826a9d334f8da8b0134b94fe257` |
| Dale validator | `mesn_v2_dale_validator_v1` | `dba675ded7b3f3f8e91ceb93185171a6fbedc42bba5050a97cca8d830bc3f081` |
| Mechanistic engine | `fractional_mesn_v2_mechanistic_engine_v1` | `fe9691184cc22a4b4e9afe8d5740badf9442ed535e848f6fbbe94d6c2539fc69` |
| **Historical v1 model/protocol** | `compute_protocol_fingerprint(...)` | `5a5c7a040768a97a5740a2b84e81b38d4c7d3147a4c8c8cdf6bac402b54f8823` |
| **Phase 5D-C sealed diagnostic protocol** | `temporal_memory_diagnostic_v1` (development-only) | `bb3ac4fe71985a156c519f1065b99fb1ff3c1c22ae8bc139c46f43cce4a93310` |

Repeated calls to each spec function return stable identical output. The mechanistic-engine spec references exact core, rate-map, and Dale schemas/hashes. Fixed hash payloads exclude `content_hash` and exclude runtime configuration, weights, signs, activation parameters, and trajectories.

---

## 14. Executable test inventory

### Rate-map tests (20/20)

1. `testIdentityScalarExactness`
2. `testIdentityVectorAndMatrixExactness`
3. `testIdentityEmptyInput`
4. `testIdentityCanonicalEmptyParameters`
5. `testIdentityRejectsNonemptyParameters`
6. `testPiecewiseMatchesPiecewiseSigmoid`
7. `testPiecewiseInteriorAndBoundaryValues`
8. `testPiecewiseSaBoundaryValues`
9. `testPiecewiseOutputRange`
10. `testInvalidActivationCfgTypeAndShape`
11. `testMissingActivationFields`
12. `testUnsupportedMode`
13. `testInvalidSaValues`
14. `testInvalidScValues`
15. `testInvalidQValues`
16. `testDeterministicReplayAndRngUnchanged`
17. `testActivationCfgUnchanged`
18. `testSchemaAndContentHash`
19. `testBoundedInfoWithoutDataCopies`
20. `testStableErrorIdentifiers`

### Dale-validator tests (14/14)

1. `testValidMixedEIColumns`
2. `testArbitraryExplicitOrdering`
3. `testSignVectorNormalization`
4. `testZeroEntriesAndZeroColumns`
5. `testExcitatoryNegativeEntryRejection`
6. `testInhibitoryPositiveEntryRejection`
7. `testColumnNotRowSignValidation`
8. `testInvalidWValues`
9. `testInvalidSignValues`
10. `testInputsUnchanged`
11. `testBoundedInfoCounts`
12. `testDeterministicReplayAndRngUnchanged`
13. `testSchemaAndContentHash`
14. `testStableErrorIdentifiers`

### Mechanistic-engine tests (24/24)

1. `testValidPiecewiseAndIdentityConfig`
2. `testNormalizedFieldOrderAndNoDefaults`
3. `testSignAndActivationNormalization`
4. `testMissingAndInvalidConfigFields`
5. `testInvalidAlphaDtTauAndMatrices`
6. `testDaleSignViolationUnderMechanisticPrefix`
7. `testInvalidActivationAndStableErrorIds`
8. `testCfgInUnchanged`
9. `testInvalidUAndX0`
10. `testX0BroadcastAndNormalization`
11. `testN0ShapesValuesAndMetadata`
12. `testPhysicalTimeRowAlignment`
13. `testAlphaOneIndependentIdentitySingleAndMulti`
14. `testAlphaOneIndependentPiecewiseSingleAndMulti`
15. `testAlphaLessThanOneManualCoreIdentityAndPiecewise`
16. `testRecurrenceUsesRNotXAndRateRecomputed`
17. `testCausalityFutureInputAndEarlyHistory`
18. `testCompleteHistoryMetadataAndSingleCorePath`
19. `testDeterminismRngValueObjectAndNoMutation`
20. `testE2InputOnlyLimitingControls`
21. `testE2LinearLimitingControlsAndIdentityQR`
22. `testZeroStateConstantAndAlphaOneDecay`
23. `testEngineSchemaHashDependenciesAndBoundedInfo`
24. `testNoProductionCallerIntegration`

Local helper functions in the three test files are **not** discovered as tests.

---

## 15. Preregistration-to-test traceability (groups A–F)

### A. Rate-map module

| Req. | Topic | Test(s) |
|---|---|---|
| A1 | Identity exactness `r=q` | `testIdentityScalarExactness`, `testIdentityVectorAndMatrixExactness`, `testIdentityEmptyInput` |
| A2 | Identity empty `S_a`/`S_c` | `testIdentityCanonicalEmptyParameters` |
| A3 | Identity rejects nonempty params | `testIdentityRejectsNonemptyParameters` |
| A4 | Piecewise equals `piecewiseSigmoid` | `testPiecewiseMatchesPiecewiseSigmoid`, `testPiecewiseInteriorAndBoundaryValues` |
| A5 | Output range `[0,1]` | `testPiecewiseOutputRange`, `testPiecewiseSaBoundaryValues` |
| A6 | Shape preservation | `testIdentityVectorAndMatrixExactness` |
| A7 | Invalid modes/config/q | `testInvalidActivationCfgTypeAndShape`, `testMissingActivationFields`, `testUnsupportedMode`, `testInvalidSaValues`, `testInvalidScValues`, `testInvalidQValues` |
| A8 | Determinism / caller RNG | `testDeterministicReplayAndRngUnchanged` |
| A9 | Schema/hash | `testSchemaAndContentHash` |
| A10 | Bounded info | `testBoundedInfoWithoutDataCopies` |
| A11 | Stable error IDs | `testStableErrorIdentifiers` |
| A12 | No defaults | `testMissingActivationFields`; source audit |
| A13 | `activation_cfg` unchanged | `testActivationCfgUnchanged` |

### B. Dale validator

| Req. | Topic | Test(s) |
|---|---|---|
| B1 | Valid mixed E/I columns | `testValidMixedEIColumns` |
| B2 | Arbitrary explicit ordering | `testArbitraryExplicitOrdering` |
| B3 | Sign normalization `1×n` | `testSignVectorNormalization` |
| B4 | Zero entries/columns | `testZeroEntriesAndZeroColumns` |
| B5 | Excitatory negative rejection | `testExcitatoryNegativeEntryRejection` |
| B6 | Inhibitory positive rejection | `testInhibitoryPositiveEntryRejection` |
| B7 | Column not row enforcement | `testColumnNotRowSignValidation` |
| B8 | Invalid `W` | `testInvalidWValues` |
| B9 | Invalid signs | `testInvalidSignValues` |
| B10 | Inputs unchanged | `testInputsUnchanged` |
| B11 | Bounded info | `testBoundedInfoCounts` |
| B12 | Determinism / caller RNG | `testDeterministicReplayAndRngUnchanged` |
| B13 | Schema/hash | `testSchemaAndContentHash` |
| B14 | Stable error IDs | `testStableErrorIdentifiers` |

### C. Mechanistic config/API

| Req. | Topic | Test(s) |
|---|---|---|
| C1 | Valid piecewise/identity config | `testValidPiecewiseAndIdentityConfig` |
| C2 | Eight required fields, no defaults | `testNormalizedFieldOrderAndNoDefaults`, `testMissingAndInvalidConfigFields` |
| C3 | Sign normalization | `testSignAndActivationNormalization` |
| C4 | Activation normalization | `testSignAndActivationNormalization`, `testValidPiecewiseAndIdentityConfig` |
| C5 | Dale delegation | `testDaleSignViolationUnderMechanisticPrefix` |
| C6 | Invalid `alpha`/`dt`/`tau_x`/`W_in`/`W` | `testInvalidAlphaDtTauAndMatrices` |
| C7 | `U`/`x0` validation | `testInvalidUAndX0` |
| C8 | Stable mechanistic error IDs | `testInvalidActivationAndStableErrorIds`, `testMissingAndInvalidConfigFields` |
| C9 | `cfg_in` unchanged | `testCfgInUnchanged` |
| C10 | `N=0` | `testN0ShapesValuesAndMetadata` |

### D. Mechanistic dynamics

| Req. | Topic | Test(s) |
|---|---|---|
| D1 | `alpha==1` independent formula | `testAlphaOneIndependentIdentitySingleAndMulti`, `testAlphaOneIndependentPiecewiseSingleAndMulti` |
| D2 | `alpha<1` manual core | `testAlphaLessThanOneManualCoreIdentityAndPiecewise` |
| D3 | Future-input isolation | `testCausalityFutureInputAndEarlyHistory` |
| D4 | Early-history sensitivity | `testCausalityFutureInputAndEarlyHistory` |
| D5 | Complete history / no truncation | `testCompleteHistoryMetadataAndSingleCorePath`; source audit |
| D6 | Recurrence uses `r` not `x` | `testRecurrenceUsesRNotXAndRateRecomputed` |
| D7 | `Q`/`R` physical-time alignment | `testPhysicalTimeRowAlignment`, `testN0ShapesValuesAndMetadata` |
| D8 | Rate recomputed after each `x` step | `testRecurrenceUsesRNotXAndRateRecomputed` |
| D9 | Deterministic replay | `testDeterminismRngValueObjectAndNoMutation` |
| D10 | Caller RNG unchanged | `testDeterminismRngValueObjectAndNoMutation` |
| D11 | Value object unchanged | `testDeterminismRngValueObjectAndNoMutation` |
| D12 | No hidden state across repeats | `testDeterminismRngValueObjectAndNoMutation` |

### E. Limiting controls

| Req. | Topic | Test(s) |
|---|---|---|
| E1 | `W=0` exact E2 input-only | `testE2InputOnlyLimitingControls` |
| E2 | Identity exact E2 linear | `testE2LinearLimitingControlsAndIdentityQR` |
| E3 | `Q=R=X` identity | `testE2LinearLimitingControlsAndIdentityQR` |
| E4 | Zero input/state | `testZeroStateConstantAndAlphaOneDecay` |
| E5 | Constant equilibrium | `testZeroStateConstantAndAlphaOneDecay` |
| E6 | `alpha==1` zero-drive decay | `testZeroStateConstantAndAlphaOneDecay` |

### F. Regression and isolation

| Req. | Topic | Test(s) |
|---|---|---|
| F1 | Frozen E2 unchanged | full suite 38/38 `test_fractional_mesn_v2_engine`; identity checks |
| F2 | Frozen core unchanged | full suite 25/25 `test_caputo_l1_core`; identity checks |
| F3 | v1 fingerprint unchanged | full suite 17/17 `test_protocol_fingerprint` |
| F4 | No production caller | `testNoProductionCallerIntegration` |
| F5 | No E3 engine calls E2 | source audit |
| F6 | Full-suite additive discovery | 886/886 (828 + 34 + 24) |

---

## 16. Targeted E3-B1 and E3-B2 results

| Suite | Result |
|---|---|
| Rate-map module | **20/20** |
| Dale validator | **14/14** |
| Mechanistic engine | **24/24** |
| Frozen E2 engine | 38/38 |
| Frozen Caputo core | 25/25 |
| Caputo analytic | 10/10 |
| Historical Dale/scaling | 17/17 |
| Protocol fingerprint | 17/17 |
| ODE/DDE RHS | 4/4 |

---

## 17. E3-B3 full-suite validation

**Command:** `run_all_tests` (from repository root with `src`, `scripts`, and `tests` on path)

| Metric | Result |
|---|---|
| Prior E2 baseline | 828 |
| E3-B1 additions | +34 |
| E3-B2 additions | +24 |
| **Total discovered** | **886** |
| Passed | **886** |
| Failed | **0** |
| Incomplete | **0** |

Discovery count equals **886** exactly.

---

## 18. Warning inventory

| Warning | Origin | Status |
|---|---|---|
| `Scalar c_E is deprecated; use c_a_E instead` | `resolve_adaptation_coupling` in `test_adaptation_coupling` | Pre-existing; unchanged |
| `Expected joint-cell occupancy ... below min_expected_occupancy` | `mutual_info_SISO` in `test_mutual_information` | Pre-existing; unchanged |
| Informational convergence / smoke / sweep output | Existing scientific/integration tests (`test_caputo_l1_analytic`, `test_meanfield_parameter_sweep`, `test_temporal_learning_gate_integration`, etc.) | Pre-existing; unchanged |

**No warnings** originated from any E3-B1/B2 source or test file. No `nearlySingularMatrix`, nonfinite-state, dimensional, causality, Dale, rate-map, history, or dependency-identity warnings appeared.

---

## 19. Determinism, causality, and isolation evidence

- **Determinism / RNG / value object / no mutation:** `testDeterminismRngValueObjectAndNoMutation`
- **Causality / future-input isolation:** `testCausalityFutureInputAndEarlyHistory` (rows `1:5` unchanged when `U(5)` perturbed)
- **Early-history sensitivity:** `testCausalityFutureInputAndEarlyHistory`
- **Complete history:** `testCompleteHistoryMetadataAndSingleCorePath`
- **Physical-time alignment:** `testPhysicalTimeRowAlignment`
- **`N=0`:** `testN0ShapesValuesAndMetadata`
- **Limiting cases:** `testZeroStateConstantAndAlphaOneDecay`
- **Production isolation:** `testNoProductionCallerIntegration`
- **E2/core/v1 unchanged:** full-suite regressions + identity checks

---

## 20. Exclusions (E3 scope boundary)

Explicitly **not** included in E3:

- SFA, STD, delays, delay prehistory
- readout layer or task benchmark
- matrix construction, spectral scaling, bias, noise
- scientific `alpha` selection
- gain/operating-point tuning
- acceleration or history truncation
- stateful continuation/checkpoint API
- governed seed execution

---

## 21. Seed governance

No governed seed was executed during E3 validation. Numerical `alpha` values in tests are deterministic engineering fixtures, not scientific candidates. Historical v1 model/protocol fingerprint and Phase 5D-C diagnostic fingerprint remain correctly separated.

---

## 22. E3 exit criteria

| Criterion | Result | Evidence |
|---|---|---|
| Branch and SHA match | **PASS** | `design/fractional-mesn-v2` @ `5daa862...` |
| Ten-file E3 scope only since E3-A | **PASS** | `git diff --name-only 0fd2a46..5daa862` |
| Read-only audit vs preregistration | **PASS** | Sections 4–12; E3-B3 source audit |
| All five schema/hash identities | **PASS** | Identity checks; mechanistic test §23 |
| v1 fingerprint unchanged | **PASS** | `5a5c7a04...`; 17/17 fingerprint tests |
| 5D-C diagnostic fingerprint documented separately | **PASS** | `bb3ac4fe...` |
| 20/20 + 14/14 + 24/24 targeted tests | **PASS** | Discovery counts |
| 886/886 full suite | **PASS** | Section 17 |
| No E3 warnings | **PASS** | Section 18 |
| Post-test worktree clean | **PASS** | Only untracked `results/development/` |
| Production isolation | **PASS** | `testNoProductionCallerIntegration` |
| No governed seed / scientific alpha / benchmark | **PASS** | Test fixtures only |

---

## 23. Claim boundary

**E3 validates engineering and mechanism plumbing only:** rate-map correctness, Dale validation, causal no-delay nonlinear recurrence on `r`, full-history Caputo stepping, and exact E2 limiting controls.

E3 does **not** establish biological fidelity, ESP, stability advantage, temporal-memory improvement, or superiority of `alpha<1`. Dale-valid nonlinear recurrence is **not** evidence of biological fidelity. Identity activation is an engineering control, not a biological firing-rate model. No equality to historical `ode23s`/`dde23` is claimed.

---

## 24. Next boundary

**SFA remains unauthorized.** Adding SFA, STD, delays, readout, task benchmarks, scientific `alpha`, gain tuning, or stateful continuation requires a **separate binding preregistration** before any code edit.
