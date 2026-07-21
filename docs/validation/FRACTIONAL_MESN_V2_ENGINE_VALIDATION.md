# Fractional MESN v2 — Isolated Engine Validation (Phase 5D-E2)

**Status:** Phase 5D-E2 **complete**
**Validated implementation SHA:** `a927036e10506d11e99c930cc99f785e82f9756e`
**Branch:** `design/fractional-mesn-v2`
**MATLAB environment:** R2026a (26.1.0.3089807), Windows 10
**Preregistration:** [`FRACTIONAL_MESN_V2_ENGINE_PREREGISTRATION.md`](FRACTIONAL_MESN_V2_ENGINE_PREREGISTRATION.md)
**Architecture decision:** [`FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md`](FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md)

---

## 1. Implementation scope

Exactly four files were added at the validated implementation SHA:

| Path | Role |
|---|---|
| `src/algorithms/fractional/FractionalMESN_v2.m` | value-class engine |
| `src/algorithms/fractional/validate_fractional_mesn_v2_config.m` | configuration validator |
| `src/algorithms/fractional/fractional_mesn_v2_engine_spec.m` | fixed contract/spec function |
| `tests/unit/test_fractional_mesn_v2_engine.m` | implementation test suite (38 tests) |

No frozen core, v1, ODE/DDE, existing test, experiment, configuration, result, or artifact file changed at this SHA relative to the preceding documentation commit.

---

## 2. Public API

```matlab
cfg    = validate_fractional_mesn_v2_config(cfg_in);
engine = FractionalMESN_v2(cfg);
[X, info] = simulate(engine, U, x0);
```

Required configuration fields: `n`, `alpha`, `dt`, `tau_x`, `W_in`, `W`, `recurrence_mode`. There is **no default scientific `alpha`**.

---

## 3. Value-class and stateless simulation semantics

`FractionalMESN_v2` is a MATLAB **value class** (not a `handle` subclass). Validated configuration is stored in a `SetAccess = private` property. `simulate` does not mutate the object; no hidden trajectory state, continuation/checkpoint API, `persistent`, or `global` state exists in engine source. No `rand`/`randn`/`randi` calls occur in the four implementation files. No production or historical class invokes the engine.

**Continuation remains excluded:** fractional continuation requires the complete prior `x` history, not only the most recent state. A step-by-step continuation API is deferred to a separate future preregistration.

---

## 4. Trajectory orientation and causal indexing

| Variable | Shape | Interpretation |
|---|---|---|
| `U` | `N × n_input` | external input sequence |
| `U(k,:)` | row | `u_{k−1}` |
| `x0` | scalar or `1×n` (normalised) | initial state `x_0` |
| `X` | `(N+1) × n` | state trajectory |
| `X(1,:)` | row | `x_0` |
| `X(k+1,:)` | row | `x_k` |

Input drive uses `U(k,:)` only. Recurrence uses `X(k,:)` only. At step `k`, the complete history `X(1:k,:)` is passed to the frozen core. No future input or state access exists. `N = 0` returns `X = x0` with no core call.

---

## 5. Complete-history policy

Every nonempty trajectory step calls `caputo_l1_semiimplicit_step` with full state history `X(1:k,:)`. No history truncation, compression, approximation, or windowing exists in the engine. `info.full_history_used == true` and `info.truncated == false` for all runs.

---

## 6. Matched `alpha == 1` path

The engine has **exactly one** runtime call site to `caputo_l1_semiimplicit_step` (inside the step loop). There is **no** independent engine-level `alpha == 1` recurrence. The frozen core selects its exact backward-Euler-leak branch internally.

Input assembly, recurrence assembly, validation, trajectory layout, and metadata paths are **identical** for `alpha == 1` and `alpha < 1`.

Independent formula verified in tests (without re-calling the core for the expected trajectory):

\[
x_k = \frac{(\tau_x/dt)\, x_{k-1} + d_{k-1}}{(\tau_x/dt) + 1}
\]

This is the v2 matched integer-order control. It is **not** claimed to reproduce historical `ode23s` or `dde23` trajectories.

---

## 7. `alpha < 1` direct-core equivalence

For `alpha < 1`, engine trajectories match manually repeated calls to `caputo_l1_semiimplicit_step` with the same growing history and drive assembly (`testAlphaLessThanOneInputOnlyMatchesManualCore`, `testAlphaLessThanOneLinearMatchesManualCore`).

---

## 8. Identity hashes (correctly separated)

| Identity | Schema / fingerprint | Hash |
|---|---|---|
| **Engine contract** | `fractional_mesn_v2_engine_v1` | `38414814b75f35c997e695347ec8f9979660108e053d8f676329758e4fc6971d` |
| **Frozen Caputo-L1 core** | `fractional_mesn_v2_caputo_l1_core_v1` | `3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f` |
| **Historical v1 model/protocol** | `compute_protocol_fingerprint(mechanism_ablation_config('publication'))` | `5a5c7a040768a97a5740a2b84e81b38d4c7d3147a4c8c8cdf6bac402b54f8823` |
| **Phase 5D-C sealed diagnostic protocol** | `temporal_memory_diagnostic_v1` (development-only) | `bb3ac4fe71985a156c519f1065b99fb1ff3c1c22ae8bc139c46f43cce4a93310` |

Repeated calls to `fractional_mesn_v2_engine_spec()` return the same engine hash. The engine spec references (does not duplicate) the frozen core schema and hash. The fixed hash payload excludes `content_hash` itself and excludes runtime `alpha`, configuration, weights, `dt`, `tau_x`, and trajectory data.

---

## 9. Executable engine tests (38)

1. `testValidInputOnlyConfig`
2. `testValidLinearConfig`
3. `testRecurrenceModeCanonicalization`
4. `testInputOnlyWNormalization`
5. `testInvalidOrMissingConfigFields`
6. `testInvalidN`
7. `testInvalidAlpha`
8. `testInvalidDt`
9. `testInvalidTauX`
10. `testInvalidWin`
11. `testInvalidWPerMode`
12. `testInvalidRecurrenceMode`
13. `testInvalidU`
14. `testInvalidX0`
15. `testScalarX0Broadcast`
16. `testRowAndColumnX0Normalization`
17. `testN0OutputAndMetadata`
18. `testAlphaOneSingleNeuronInputOnlyExactRecurrence`
19. `testAlphaOneMultiNeuronInputOnlyExactRecurrence`
20. `testAlphaOneSingleNeuronLinearExactRecurrence`
21. `testAlphaOneMultiNeuronLinearExactRecurrence`
22. `testAlphaLessThanOneInputOnlyMatchesManualCore`
23. `testAlphaLessThanOneLinearMatchesManualCore`
24. `testEarlyHistoryPerturbationChangesLaterFractionalState`
25. `testFutureInputPerturbationLeavesEarlierStatesUnchanged`
26. `testFullHistoryAndNoTruncationMetadata`
27. `testBitwiseDeterministicReplay`
28. `testCallerRngUnchanged`
29. `testValueClassObjectUnchangedAfterSimulate`
30. `testRepeatedSimulationsDoNotLeakState`
31. `testZeroInputAndZeroX0RemainZero`
32. `testConstantEquilibriumFixture`
33. `testZeroLinearRecurrenceMatchesInputOnly`
34. `testAlphaOneZeroDriveGeometricDecay`
35. `testEngineSchemaAndHash`
36. `testCoreSchemaAndHashPropagated`
37. `testMechanismDeclarationsPoliciesAndMetadata`
38. `testStableFractionalMesnErrorIdentifiers`

Helper functions (`base_cfg`, `manual_alpha_one`, `manual_fractional`, `normalize_x0_for_test`, `verify_common_info`) are **not** discovered as tests.

---

## 10. Preregistration-to-test traceability

| Prereg. req. | Topic | Test(s) |
|---|---|---|
| A1 | Valid `input_only` config | `testValidInputOnlyConfig`, `testInputOnlyWNormalization` |
| A2 | Valid `linear` config | `testValidLinearConfig` |
| A3 | Invalid `alpha` | `testInvalidAlpha` |
| A4 | Invalid `dt` | `testInvalidDt` |
| A5 | Invalid `tau_x` | `testInvalidTauX` |
| A6 | Invalid `n` | `testInvalidN` |
| A7 | Invalid `W_in` | `testInvalidWin` |
| A8 | Invalid `W` (linear) | `testInvalidWPerMode` |
| A9 | Invalid `U` | `testInvalidU` |
| A10 | Invalid `x0` | `testInvalidX0` |
| A11 | Scalar `x0` broadcast | `testScalarX0Broadcast` |
| A12 | Column `x0` normalisation | `testRowAndColumnX0Normalization` |
| A13 | `N = 0` | `testN0OutputAndMetadata` |
| A14 | Stable error identifiers | `testStableFractionalMesnErrorIdentifiers`, all `verifyError` tests |
| A15 | No default `alpha` | `testInvalidOrMissingConfigFields` |
| B16–B19 | `alpha==1` independent formula | `testAlphaOneSingleNeuronInputOnlyExactRecurrence`, `testAlphaOneMultiNeuronInputOnlyExactRecurrence`, `testAlphaOneSingleNeuronLinearExactRecurrence`, `testAlphaOneMultiNeuronLinearExactRecurrence` |
| B20 | Independent expression, not core replay | `manual_alpha_one` in B16–B19 tests |
| B21 | Same path for `alpha==1` and `alpha<1` | `verify_common_info` in alpha-one tests; shared engine loop in source audit |
| C22–C23 | Manual core equivalence | `testAlphaLessThanOneInputOnlyMatchesManualCore`, `testAlphaLessThanOneLinearMatchesManualCore` |
| C24 | Early perturbation sensitivity | `testEarlyHistoryPerturbationChangesLaterFractionalState` |
| C25 | Future-input isolation | `testFutureInputPerturbationLeavesEarlierStatesUnchanged` |
| C26 | Full history at every step | `manual_fractional` in C22–C23; source audit |
| C27 | No truncation metadata | `testFullHistoryAndNoTruncationMetadata` |
| D28 | Bitwise replay | `testBitwiseDeterministicReplay` |
| D29 | Caller RNG unchanged | `testCallerRngUnchanged` |
| D30 | No RNG in engine | source audit (no `rand`/`randn`/`randi`) |
| D31 | Value object unchanged | `testValueClassObjectUnchangedAfterSimulate` |
| D32 | Repeated simulate identical | `testRepeatedSimulationsDoNotLeakState` |
| E33 | Zero input/state | `testZeroInputAndZeroX0RemainZero` |
| E34 | Constant equilibrium | `testConstantEquilibriumFixture` |
| E35 | Empty trajectory | `testN0OutputAndMetadata` |
| E36 | Zero `W` ≡ `input_only` | `testZeroLinearRecurrenceMatchesInputOnly` |
| E37 | `alpha==1` geometric decay | `testAlphaOneZeroDriveGeometricDecay` |
| F38–F39 | Core schema/hash unchanged | `testCoreSchemaAndHashPropagated`, `testEngineSchemaAndHash` |
| F40–F47 | Existing suites green | E2-C full suite 828/828 (includes 25 Caputo, 10 analytic, 17 fingerprint, 4 ODE/DDE, 110 targeted E1, 790 baseline) |
| — | Engine schema/hash | `testEngineSchemaAndHash` |
| — | Mechanism/policy metadata | `testMechanismDeclarationsPoliciesAndMetadata` |
| — | `recurrence_mode` canonicalisation | `testRecurrenceModeCanonicalization` |
| — | Nonzero `W` rejected in `input_only` | `testInvalidWPerMode` |

---

## 11. E2-B targeted evidence (at implementation SHA)

| Suite | Count |
|---|---|
| New engine tests | 38/38 |
| Frozen core unit tests | 25/25 |
| Analytic tests | 10/10 |
| Historical v1 fingerprint tests | 17/17 |
| ODE/DDE tests | 4/4 |
| Targeted E1 regression | 110/110 |

---

## 12. E2-C full-suite validation

**Command:** `run_all_tests` (from repository root with paths initialised)

| Metric | Result |
|---|---|
| Prior baseline | 790 |
| New engine tests | +38 |
| **Total discovered** | **828** |
| Passed | **828** |
| Failed | **0** |
| Incomplete | **0** |

Discovery count equals 828 exactly.

---

## 13. Warning inventory

| Warning | Origin | Status |
|---|---|---|
| `Scalar c_E is deprecated; use c_a_E instead` | `resolve_adaptation_coupling` in existing `test_adaptation_coupling` | Pre-existing; unchanged |
| `Expected joint-cell occupancy ... below min_expected_occupancy` | `mutual_info_SISO` in `test_mutual_information` | Pre-existing; unchanged |
| Informational convergence / smoke output | Existing scientific/integration tests (`test_caputo_l1_analytic`, `test_meanfield_parameter_sweep`, etc.) | Pre-existing; unchanged |

**No warnings** originated from `FractionalMESN_v2`, `validate_fractional_mesn_v2_config`, `fractional_mesn_v2_engine_spec`, or `test_fractional_mesn_v2_engine`. No `nearlySingularMatrix`, nonfinite-state, dimensional, history, or causality warnings appeared. `lastwarn` after the suite was empty.

---

## 14. Determinism, causality, and isolation evidence

- **Determinism:** `testBitwiseDeterministicReplay`, `testRepeatedSimulationsDoNotLeakState`
- **Caller RNG:** `testCallerRngUnchanged`
- **Value object:** `testValueClassObjectUnchangedAfterSimulate` (`isequaln` before/after)
- **Causality:** `testFutureInputPerturbationLeavesEarlierStatesUnchanged`
- **Early-history sensitivity:** `testEarlyHistoryPerturbationChangesLaterFractionalState`
- **No truncation:** `testFullHistoryAndNoTruncationMetadata`; source audit
- **`N = 0`:** `testN0OutputAndMetadata`
- **Limiting cases:** `testZeroInputAndZeroX0RemainZero`, `testConstantEquilibriumFixture`, `testAlphaOneZeroDriveGeometricDecay`

---

## 15. Regression and production isolation

| Component | Status |
|---|---|
| `SRNN_ESN` | Unchanged |
| `SRNN_reservoir` | Unchanged |
| `SRNN_reservoir_DDE` | Unchanged |
| Frozen Caputo-L1 core | Unchanged (hash verified) |
| Production callers of `FractionalMESN_v2` | **None** |

---

## 16. Limitations and exclusions (E2 scope boundary)

E2 implements **linear recurrence only** with external input plumbing and full-history Caputo-L1 stepping. Explicitly **not** included:

- nonlinear rate map (`φ(q)`)
- Dale law
- SFA, STD
- synaptic/axonal delays
- readout layer or task benchmark
- scientific `alpha` selection
- gain/operating-point tuning
- fast convolution or acceleration claims
- stateful continuation/checkpoint API
- bias, noise, history truncation

---

## 17. Seed governance

No governed seed was executed during E2 validation. Numerical `alpha` values in engine tests are deterministic engineering fixtures, not scientific candidates. Historical v1 model/protocol fingerprint and Phase 5D-C diagnostic fingerprint remain correctly separated.

---

## 18. E2 exit criteria

| Criterion | Result | Evidence |
|---|---|---|
| Branch and SHA match | **PASS** | `design/fractional-mesn-v2` @ `a927036e...` |
| Four-file scope only | **PASS** | `git diff --stat daa29a0..a927036` |
| Read-only audit vs preregistration | **PASS** | Sections 3–8 above |
| Engine schema/hash | **PASS** | Identity checks; `testEngineSchemaAndHash` |
| Core schema/hash | **PASS** | Identity checks; `testCoreSchemaAndHashPropagated` |
| v1 fingerprint unchanged | **PASS** | Recomputed `5a5c7a04...` |
| 5D-C diagnostic fingerprint documented separately | **PASS** | `bb3ac4fe...` (provenance only) |
| 38/38 engine tests | **PASS** | Discovery count |
| 828/828 full suite | **PASS** | E2-C run |
| No new engine warnings | **PASS** | Warning inventory |
| Post-test worktree clean | **PASS** | Only untracked `results/development/` |
| Production isolation | **PASS** | No production caller |
| No governed seed/scientific alpha | **PASS** | Test fixtures only |

---

## 19. Claim boundary

**E2 validates numerical/engineering integration only.** It provides **no** evidence that fractionality improves temporal memory or reservoir performance. E2 does **not** prove ESP, task benefit, or biological mechanism necessity.

---

## 20. Next phase boundary

**Phase 5D-E3 is not authorised.** Adding any biological mechanism, nonlinear recurrence, readout, task benchmark, scientific `alpha`, gain tuning, or stateful continuation requires a **new preregistration prompt** before implementation.
