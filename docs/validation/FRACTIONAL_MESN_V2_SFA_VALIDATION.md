# Fractional MESN v2 — SFA Module and SFA-Engine Validation (Phase 5D-E3-C4)

**Status:** Phase 5D-E3-C4 **complete**
**Claim:** the SFA-enabled fractional mechanistic engine is **validated** (engineering / mechanism integration only)
**Authoritative preregistration:** [`FRACTIONAL_MESN_V2_SFA_PREREGISTRATION.md`](FRACTIONAL_MESN_V2_SFA_PREREGISTRATION.md)
**Architecture decision:** [`FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md`](FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md)

---

## 1. Implementation commits and validated SHA

| Phase | Commit SHA | Scope |
|---|---|---|
| E3-C2 SFA-step module | `a771f4298d85b1dee61f0c8a82d4a01ff0f75479` | `mesn_v2_sfa_step` + tests |
| Isolation-test repair | `964e455fd90f74db371a99be1b50986524b55218` | exact constructor-call matcher |
| E3-C3 SFA-enabled engine | `432d5b926587a6b7521df483724ab0beca16f509` | SFA engine + validator + spec + tests |
| **Validated implementation HEAD (before documentation)** | `432d5b926587a6b7521df483724ab0beca16f509` | C2 + repair + C3 |

**Branch:** `design/fractional-mesn-v2`
**MATLAB environment:** R2026a (26.1.0.3234472) Update 1, Windows 10 (PCWIN64)

**Binding preregistration path:** `docs/validation/FRACTIONAL_MESN_V2_SFA_PREREGISTRATION.md`

---

## 2. Isolation-test repair semantics

The frozen no-SFA suite test `testNoProductionCallerIntegration` previously used a broad substring search for `FractionalMESN_v2_mechanistic`, which falsely matched preregistered SFA identifiers (`FractionalMESN_v2_mechanistic_sfa`, validators, and specs).

**Repair:** replace substring matching with exact constructor-call detection:

```text
(?<![A-Za-z0-9_])FractionalMESN_v2_mechanistic\s*(
```

**Still detects** real production constructor calls such as `FractionalMESN_v2_mechanistic(cfg)` and `engine = FractionalMESN_v2_mechanistic(cfg);`.

**No longer false-positives** on SFA-prefixed or validator/spec identifiers that merely contain the substring.

Matcher self-checks are embedded in the same test. Preferred discovery count remains **24/24**. This is a harness false-positive repair only; frozen no-SFA engine behavior is unchanged.

---

## 3. Seven schema / content-hash identities

| Component | Schema | Content hash |
|---|---|---|
| E2 engine | `fractional_mesn_v2_engine_v1` | `38414814b75f35c997e695347ec8f9979660108e053d8f676329758e4fc6971d` |
| Caputo core | `fractional_mesn_v2_caputo_l1_core_v1` | `3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f` |
| Rate map | `mesn_v2_rate_map_v1` | `483b6192099426b1c22f29a35e04d9e22c508826a9d334f8da8b0134b94fe257` |
| Dale validator | `mesn_v2_dale_validator_v1` | `dba675ded7b3f3f8e91ceb93185171a6fbedc42bba5050a97cca8d830bc3f081` |
| No-SFA mechanistic engine | `fractional_mesn_v2_mechanistic_engine_v1` | `fe9691184cc22a4b4e9afe8d5740badf9442ed535e848f6fbbe94d6c2539fc69` |
| SFA-step module | `mesn_v2_sfa_step_v1` | `7bec90a56bc1df144848b5857eb9bd3565719a4905de4ca9ec7967124eee5fa0` |
| SFA-enabled engine | `fractional_mesn_v2_mechanistic_sfa_engine_v1` | `c51bc46648b17eb1b32b112665874dc565c49b9678480f58fbd8b4a95bf4ef13` |

All seven identities were recomputed at the validated implementation HEAD and matched exactly. The SFA-engine spec call is stable under repeated invocation.

---

## 4. Historical fingerprints (separated)

| Fingerprint | Role | Value |
|---|---|---|
| Historical v1 model/protocol fingerprint | `compute_protocol_fingerprint(...)` | `5a5c7a040768a97a5740a2b84e81b38d4c7d3147a4c8c8cdf6bac402b54f8823` |
| Phase 5D-C sealed diagnostic fingerprint | `temporal_memory_diagnostic_v1` | `bb3ac4fe71985a156c519f1065b99fb1ff3c1c22ae8bc139c46f43cce4a93310` |

These fingerprints are **not** interchangeable. The v1 fingerprint was recomputed via the frozen protocol suite (**17/17**). The 5D-C diagnostic fingerprint remains separately documented and was not recomputed as a live diagnostic run.

---

## 5. Continuous SFA equation and discrete update

**Continuous (integer-order) SFA:**

\[
\tau_{a,m}\,\frac{d a_{i,m}}{dt} = r_i - a_{i,m}.
\]

**Effective drive before rate map:**

\[
q_i = x_i - \sum_m c_{a,m}\, a_{i,m},
\qquad
r_i = \phi(q_i).
\]

**Exact exponential \(n-1\) (zero-order hold) update:**

\[
\mathrm{decay}_m = \exp(-\Delta t / \tau_{a,m}),
\]

\[
a_{i,m,k} = \mathrm{decay}_m \cdot a_{i,m,k-1} + (1 - \mathrm{decay}_m) \cdot r_{i,k-1}.
\]

**Binding properties recorded:**

- SFA is **integer-order**.
- Caputo applies **only** to membrane/reservoir state \(x\).
- SFA does **not** consume fractional \(x\) history.
- Update uses \(r_{k-1}\), never \(r_k\); no algebraic loop; no clipping.

---

## 6. Public API, value class, and configuration contracts

```matlab
cfg = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_in)
engine = FractionalMESN_v2_mechanistic_sfa(cfg)
[X, Q, R, A_E, A_I, info] = simulate(engine, U, x0, a0)
```

- `FractionalMESN_v2_mechanistic_sfa` is a MATLAB **value class** (not a handle).
- `Config` has `SetAccess = private` (not publicly writable).
- `simulate` is **stateless** with respect to the object.
- Top-level config fields exactly: `n`, `alpha`, `dt`, `tau_x`, `W_in`, `W`, `presynaptic_signs`, `activation`, `sfa`.
- `sfa` fields exactly: `tau_a_E`, `c_a_E`, `tau_a_I`, `c_a_I`.
- **No defaults**; legacy `c_E`/`c_I` aliases rejected.
- Arbitrary explicit E/I ordering via caller-supplied `presynaptic_signs`.
- Exact `a0` shapes: `a_E` is `n_E × n_a_E`; `a_I` is `n_I × n_a_I`; deterministic zero-channel / zero-population normalization without `squeeze`.

---

## 7. Trajectory layouts and causal update order

| Variable | Layout |
|---|---|
| `X`, `Q`, `R` | `(N+1) × n` |
| `A_E` | `(N+1) × n_E × n_a_E` |
| `A_I` | `(N+1) × n_I × n_a_I` |

**Causal order for step \(k\):**

1. \(x_k\) uses \(r_{k-1}\) and \(u_{k-1}\) (complete history `X(1:k,:)` into Caputo).
2. \(a_k\) uses \(r_{k-1}\) via exactly **two** runtime `mesn_v2_sfa_step` call sites (E and I).
3. \(q_k\) uses \(x_k\) and \(a_k\).
4. \(r_k\) is computed after \(q_k\) via `mesn_v2_rate_map`.

Exactly **one** runtime Caputo call site. Rate mapping delegates to `mesn_v2_rate_map`. No construction/call of existing E2 or no-SFA engines. No STD, delays, RNG, clipping, or separate engine-level `alpha==1` \(x\) formula.

---

## 8. Mechanism-off and reference controls

| Control | Evidence |
|---|---|
| Zero-channel equals no-SFA engine | `testZeroChannelEqualsNoSfaEngine` |
| Zero-coupling equals no-SFA with `Q=X` while `A` may evolve | `testZeroCouplingEqualsNoSfaAndAEvolves` |
| `W=0` equals E2 input-only | `testWZeroEqualsE2InputOnly` |
| Identity + zero coupling equals E2 linear | `testIdentityZeroCouplingEqualsE2Linear` |
| `alpha==1` independent reference | `testAlphaOneIndependentMixedAndOrdering`, `testAlphaOneIdentityAndPiecewise` |
| `alpha<1` manual growing-history reference | `testAlphaLessThanOneManualReference` |
| Piecewise / SFA limiting fixtures | `testPiecewiseInvariantAndSfaLimitingFixtures` |

---

## 9. Determinism, RNG, and dimension evidence

| Check | Evidence |
|---|---|
| Deterministic replay | `testDeterminismRngValueObjectAndNoMutation` |
| Caller RNG unchanged | same |
| Value-object immutability / stateless simulate | same |
| `N=0` and zero-size populations/channels | `testN0ShapesValuesAndMetadata`, `testDimensionEdgeCasesSingletonZeroChannelZeroPop`, `testA0ValidationShapesAndZeroSizeNormalization` |
| Causality / no algebraic loop / `W*r` | `testCausalityRkm1Ukm1QkAndNoAlgebraicLoop` |
| Future-input / early-history sensitivity | `testHistorySensitivityAndCompleteHistoryMetadata` |
| Production isolation | `testNoProductionCallerIntegration` |
| Dependency identities / bounded metadata | `testEngineSchemaHashDependenciesBoundedInfo` |

---

## 10. Targeted regression results

| Suite | Result |
|---|---|
| SFA-enabled engine | **22/22** |
| SFA-step module | **24/24** |
| Rate map + Dale validator | **34/34** |
| Repaired no-SFA mechanistic engine | **24/24** |
| Frozen E2 engine | **38/38** |
| Caputo core | **25/25** |
| Caputo analytic | **10/10** |
| Historical adaptation | **26/26** |
| ODE/DDE RHS | **4/4** |
| Protocol fingerprint | **17/17** |

---

## 11. Full-suite validation (E3-C4 hard gate)

**Command:** `run_all_tests` (repository root with `src`, `scripts`, and `tests` on path)

| Metric | Result |
|---|---|
| Accepted E3-B3 baseline | 886 |
| E3-C2 SFA-step additions | +24 |
| E3-C3 SFA-engine additions | +22 |
| **Total discovered** | **932** |
| Passed | **932** |
| Failed | **0** |
| Incomplete | **0** |

Discovery count equals **932** exactly (`886 + 24 + 22`). Suite discovery via `TestSuite.fromFolder` independently confirmed **932**.

---

## 12. Warning inventory

| Warning | Origin | Status |
|---|---|---|
| `Scalar c_E is deprecated; use c_a_E instead` | `resolve_adaptation_coupling` in `test_adaptation_coupling` | Pre-existing; unchanged |
| `Expected joint-cell occupancy ... below min_expected_occupancy` | `mutual_info_SISO` in `test_mutual_information` | Pre-existing; unchanged |
| Informational convergence / smoke / sweep output | Existing scientific/integration tests | Pre-existing; unchanged |

**No warnings** originated from new SFA source or SFA tests. No `nearlySingularMatrix`, nonfinite-state, dimension, causality, or dependency-identity warnings. Final `lastwarn` was empty.

---

## 13. Frozen-file and production-isolation record

- Frozen E2, Caputo core, rate-map, Dale, no-SFA mechanistic **implementations** were **not** modified for SFA behavior.
- The **only** authorized frozen-suite change was the exact-call isolation-test repair in `tests/unit/test_fractional_mesn_v2_mechanistic_engine.m`.
- No production caller constructs `FractionalMESN_v2_mechanistic` or `FractionalMESN_v2_mechanistic_sfa`.
- No STD, delays, delay prehistory, scientific `alpha` selection, operating-point tuning, governed seeds, or performance benchmarks were executed in this phase.

---

## 14. Claim boundary

E3-C validates **engineering and mechanism integration only**: exact exponential SFA stepping, causal \(n-1\) indexing, subtractive adaptation before the rate map, full-history Caputo stepping on \(x\), and exact mechanism-off limiting controls.

E3-C does **not** establish biological fidelity, ESP, stability advantage, temporal-memory improvement, or superiority of `alpha<1`. No equality to historical `ode23s`/`dde23` is claimed.

---

## 15. Next boundary

**STD and delays remain unimplemented.** Adding STD, delays, readout, task benchmarks, scientific `alpha`, gain tuning, or stateful continuation requires a **separate binding preregistration** before any code edit.
