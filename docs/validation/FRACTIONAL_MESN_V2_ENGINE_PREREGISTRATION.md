# Fractional MESN v2 — Isolated Engine Preregistration (Phase 5D-E2)

**Phase:** 5D-E2 (isolated engine preregistration; documentation only)
**Schema:** `fractional_mesn_v2_engine_v1`
**Branch:** `design/fractional-mesn-v2`
**Starting SHA:** `70d224d530cb665acc7dd4ce38eef4204ea3ebac`
**Status:** engine contract **preregistered**; implementation **not yet authorised**
**Companion documents:**
- [`FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md`](FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md)
- [`FRACTIONAL_MESN_V2_NUMERICAL_CORE_PREREGISTRATION.md`](FRACTIONAL_MESN_V2_NUMERICAL_CORE_PREREGISTRATION.md)
- [`TEMPORAL_MEMORY_DIAGNOSTIC_SCIENTIFIC_REVIEW.md`](TEMPORAL_MEMORY_DIAGNOSTIC_SCIENTIFIC_REVIEW.md)

---

## 0. Baseline verification record

| Field | Value |
|---|---|
| Required starting SHA | `70d224d530cb665acc7dd4ce38eef4204ea3ebac` |
| Phase 5D-E2 baseline verdict | READY FOR E2 PREREGISTRATION |
| Frozen core schema | `fractional_mesn_v2_caputo_l1_core_v1` |
| Frozen core content hash | `3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f` |
| Caputo unit tests | 25/25 |
| Analytic tests | 10/10 |
| Targeted regression | 110/110 |
| Full suite | 790/790 |
| Production path calls to core | none |
| Governed seeds consumed | none |
| Untracked tree | `results/development/` only; untouched |

---

## 1. Engine identity

| Item | Value |
|---|---|
| Class | `FractionalMESN_v2` |
| Future source path | `src/algorithms/fractional/FractionalMESN_v2.m` |
| Configuration validator | `validate_fractional_mesn_v2_config` |
| Future validator path | `src/algorithms/fractional/validate_fractional_mesn_v2_config.m` |
| Contract/spec function | `fractional_mesn_v2_engine_spec` |
| Future spec path | `src/algorithms/fractional/fractional_mesn_v2_engine_spec.m` |
| Engine schema version | `fractional_mesn_v2_engine_v1` |
| Object semantics | MATLAB **value class** (not a `handle` subclass) |

`FractionalMESN_v2` is preregistered as a MATLAB value class. The object
stores only validated configuration. Its `simulate` method is **stateless
with respect to the object**: it must not mutate any hidden trajectory
state. Repeated calls to `simulate` on the same object are independent
and must produce bitwise-identical results for identical inputs.

A step-by-step continuation API is **not** preregistered in E2. A valid
fractional continuation requires the complete prior `x` history, not only
the most recent state. Continuation and checkpoint semantics require a
separate future preregistration.

---

## 2. Minimum public API

### 2.1 Call sequence

```matlab
cfg    = validate_fractional_mesn_v2_config(cfg_in);
engine = FractionalMESN_v2(cfg);
[X, info] = simulate(engine, U, x0);
```

### 2.2 Configuration fields

| Field | Type / shape | Constraints |
|---|---|---|
| `n` | positive integer scalar | must be a finite positive integer |
| `alpha` | real scalar | finite, `0 < alpha <= 1`; **no default** |
| `dt` | real scalar | finite, `> 0` |
| `tau_x` | real scalar | finite, `> 0` |
| `W_in` | real 2-D matrix | finite, `n` rows; `n_input = size(W_in,2)` |
| `W` | real or empty matrix | see `recurrence_mode` constraints below |
| `recurrence_mode` | string | `'input_only'` or `'linear'` |

**There is no default scientific `alpha`.** Any call that does not supply
`alpha` is a validation error.

### 2.3 Recurrence mode constraints

**`input_only`:** `W` must be empty or a real `n×n` matrix. The validator
normalises `W` to `zeros(n,n)` internally. `recurrence_mode` remains the
authoritative switch; the zero matrix is the canonical normalised
representation. No recurrent contribution is computed regardless of any
residual values in the supplied `W`.

**`linear`:** `W` must be finite, real, and `n×n`. All elements must be
finite.

### 2.4 Validation requirements

The validator must check and enforce:

- `n` is a positive integer scalar (finite, real, scalar, integer-valued,
  `>= 1`).
- `alpha` is a finite real scalar satisfying `0 < alpha <= 1`. No default
  value is permitted. Complex, `NaN`, `Inf`, `alpha <= 0`, and
  `alpha > 1` must all be rejected.
- `dt` is a finite positive real scalar.
- `tau_x` is a finite positive real scalar.
- `W_in` is finite, real, and two-dimensional with `n` rows.
- `U` (checked at simulate-call time) has size `N × n_input`, where
  `n_input = size(W_in,2)`.
- For `input_only`: `W` is normalised to `zeros(n,n)`.
- For `linear`: `W` is finite, real, and `n×n`.
- `x0` (checked at simulate-call time) is a finite real scalar or a
  finite real vector with `n` elements. `x0` is normalised internally to
  a `1×n` row vector before use.
- Reject complex, nonfinite, or dimensionally inconsistent inputs at
  validation time.

### 2.5 Error identifiers

All validation errors must use stable MATLAB error identifiers with the
prefix `FractionalMESN_v2:`. Examples (non-exhaustive):

- `FractionalMESN_v2:invalidAlpha`
- `FractionalMESN_v2:invalidDt`
- `FractionalMESN_v2:invalidTauX`
- `FractionalMESN_v2:invalidN`
- `FractionalMESN_v2:invalidWin`
- `FractionalMESN_v2:invalidW`
- `FractionalMESN_v2:invalidU`
- `FractionalMESN_v2:invalidX0`
- `FractionalMESN_v2:invalidRecurrenceMode`

---

## 3. Units and dimensional interpretation

| Quantity | Unit convention |
|---|---|
| `dt` | time; same unit as `tau_x` (normally seconds) |
| `tau_x` | time; same unit as `dt` (normally seconds) |
| `alpha` | dimensionless |
| `x` | state unit (arbitrary but consistent) |
| assembled `drive_previous` | same state unit as `x` |
| `W` | dimensionless (multiplies `x` to produce a state-unit quantity) |
| `W_in` | maps input units into state/drive units |

The numerical coefficient uses `tau_x^alpha` exactly as implemented by
the frozen core. E2 does not claim a calibrated physical neuronal unit
system.

---

## 4. Exact trajectory orientation and causal indexing

### 4.1 Input / output shapes

| Variable | Shape | Interpretation |
|---|---|---|
| `U` | `N × n_input` | external input sequence |
| `U(k,:)` | row | represents `u_{k−1}` |
| `x0` | `1×n` (normalised) | initial state `x_0` |
| `X` | `(N+1) × n` | state trajectory |
| `X(1,:)` | row | `x_0` |
| `X(k+1,:)` | row | `x_k` |

`N = 0` is a valid call and returns `X = x0` (a `1×n` row) without
executing any core step.

### 4.2 Step-loop pseudocode (normative)

For `k = 1, …, N`:

```
x_previous = X(k,:)            % x_{k-1}
u_previous = U(k,:)            % u_{k-1}

if recurrence_mode == 'input_only'
    recurrent_previous = zeros(1, n)
else  % 'linear'
    recurrent_previous = (W * x_previous.').'
end

input_previous    = (W_in * u_previous.').'
drive_previous    = input_previous + recurrent_previous

[x_next, step_info] = caputo_l1_semiimplicit_step( ...
    X(1:k,:), ...          % complete history x_0,...,x_{k-1}
    drive_previous, ...    % d_{k-1}
    dt, alpha, tau_x)

X(k+1,:) = x_next
```

### 4.3 Explicit causal constraints (frozen)

- No `u_k` or future input is used to produce `x_k`.
- Linear recurrence uses only `x_{k−1}`, not `x_k`.
- No nonlinear rate map is present in E2.
- No bias term is present in E2.
- No future sample may affect any earlier state.
- Every step passes the **complete** state history `X(1:k,:)` to the core.
- No history truncation, windowing, compression, or approximation is
  permitted in this reference engine.
- `caputo_l1_semiimplicit_step` receives `X_history = X(1:k,:)`
  (rows `x_0,…,x_{k−1}`) and `drive_previous = d_{k−1}`.

---

## 5. Exact E2 scope

### 5.1 Included

- External input plumbing via `W_in`.
- Optional linear recurrence `W * x_{k−1}` (`recurrence_mode = 'linear'`).
- Full-history Caputo `x` stepping using the frozen core
  `caputo_l1_semiimplicit_step`.
- Exact matched `alpha == 1` path: through the same engine call and the
  same core call; the core selects its exact `alpha == 1` backward-Euler
  branch internally.
- Deterministic numerical fixtures for tests.
- Regression protection for existing baselines.
- Engine contract/spec identity (`fractional_mesn_v2_engine_spec`).

### 5.2 Explicitly excluded from E2

The following are **not** in scope and must not be introduced during E2
implementation without a new committed preregistration amendment:

- `φ(q)` or any nonlinear rate map.
- Dale-law matrix generation or enforcement.
- Spike-frequency adaptation (SFA).
- Short-term synaptic depression/facilitation (STD).
- Synaptic or axonal delays.
- Delay interpolation or pre-`t0` delay prehistory.
- Bias term.
- Noise injection.
- Readout training.
- Feature selection between `x` and `r`.
- PCA, whitening, or feature normalisation.
- Task benchmarks.
- Memory-capacity measurements.
- Operating-point calibration.
- Scientific `alpha` selection.
- Gain tuning.
- Development, gate, calibration, or publication seed execution.
- Modifications to `SRNN_ESN`, `SRNN_reservoir`, or `SRNN_reservoir_DDE`.
- Fast convolution or short-memory approximations.
- Stateful continuation or checkpoint APIs.

---

## 6. `alpha == 1` matched-control requirement

`FractionalMESN_v2` always calls `caputo_l1_semiimplicit_step`. The
engine must **not** implement a second independent `alpha = 1` recurrence
formula. The frozen core detects `alpha == 1` exactly and selects its
dedicated backward-Euler-leak branch.

Input assembly, recurrence assembly, validation, trajectory layout,
result metadata, and all other engine behaviour are **identical** across
all `alpha` values.

For `alpha == 1`, tests must independently verify (without re-calling the
engine or core) that:

```
x_k = [ (tau_x/dt) * x_{k-1} + d_{k-1} ] / [ (tau_x/dt) + 1 ]
```

This is the v2 matched integer-order control. It is **not** claimed to
reproduce historical `ode23s` or `dde23` trajectories.

---

## 7. Engine spec and metadata

### 7.1 `fractional_mesn_v2_engine_spec` — fixed fields

The spec function returns a deterministic struct whose content is fixed
by the engine contract, **not** by runtime configuration and **not** by
the selected `alpha`. It references (not duplicates or modifies) the
frozen core identity.

Required fixed fields (minimum):

| Field | Value / description |
|---|---|
| `schema_version` | `'fractional_mesn_v2_engine_v1'` |
| `core_schema_version` | `'fractional_mesn_v2_caputo_l1_core_v1'` |
| `core_content_hash` | `'3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f'` |
| `state_operator` | `'caputo_l1_full_history'` |
| `integration_scheme` | `'semiimplicit_linear_leak_explicit_drive'` |
| `drive_index` | `'n_minus_1'` |
| `input_index` | `'n_minus_1'` |
| `recurrence_index` | `'n_minus_1'` |
| `history_policy` | `'full_history_no_truncation'` |
| `alpha_one_policy` | `'core_exact_backward_euler_branch'` |
| `object_semantics` | `'value_class_stateless_simulate'` |
| `continuation_policy` | `'not_supported_in_e2_requires_separate_preregistration'` |
| `included_mechanisms` | `{'input_plumbing','linear_recurrence','caputo_l1_stepping'}` |
| `excluded_mechanisms` | `{'nonlinear_rate_map','sfa','std','dale_law','delays','bias','noise','readout','fast_convolution','continuation'}` |

### 7.2 Engine content hash computation

The engine content hash represents the fixed engine contract and is
**not** a runtime configuration hash. It must be computed consistently
with the existing repository canonical hashing conventions (as used for
`fractional_l1_core_spec` in the E1 core). The implementation phase will
compute and freeze the actual hash value by applying the same canonical
serialisation method to the fixed `fractional_mesn_v2_engine_spec` struct.
This documentation prompt does not invent or pre-calculate the hash.

### 7.3 Required `info` output fields

The `info` struct returned by `simulate` must include at least:

| Field | Type / value |
|---|---|
| `engine_schema_version` | `'fractional_mesn_v2_engine_v1'` |
| `engine_content_hash` | string; content hash of fixed spec |
| `core_schema_version` | `'fractional_mesn_v2_caputo_l1_core_v1'` |
| `core_content_hash` | `'3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f'` |
| `alpha` | scalar; the `alpha` used for this run |
| `alpha_one_branch_used` | logical; true iff `alpha == 1` |
| `n_steps` | integer; number of steps `N` executed |
| `recurrence_mode` | string; `'input_only'` or `'linear'` |
| `full_history_used` | `true` |
| `truncated` | `false` |
| `input_index` | `'n_minus_1'` |
| `recurrence_index` | `'n_minus_1'` |

Per-step core `step_info` structures must **not** be accumulated in
`info` unless required for a specific invariant. Prefer bounded summary
metadata.

---

## 8. Required future implementation tests

### A. Configuration and API

1. Valid `input_only` configuration round-trips through the validator.
2. Valid `linear` recurrence configuration round-trips through the validator.
3. Invalid `alpha` rejected: `0`, negative, `> 1`, `NaN`, `Inf`, complex.
4. Invalid `dt`: zero, negative, `NaN`, `Inf`, complex.
5. Invalid `tau_x`: zero, negative, `NaN`, `Inf`, complex.
6. Invalid `n`: zero, negative, non-integer, non-scalar.
7. Invalid `W_in` dimensions (wrong number of rows; 3-D; empty).
8. Invalid `W` for `linear` mode: wrong size, nonfinite, complex.
9. Invalid `U`: wrong number of columns, `NaN`/`Inf` entries.
10. Invalid `x0`: wrong length, `NaN`/`Inf`, complex.
11. Scalar `x0 = c` broadcasts correctly to `[c c … c]`.
12. Column-vector `x0` normalised to row vector.
13. `N = 0` returns `X = x0` (shape `1×n`) with no core step.
14. Each rejection uses a stable `FractionalMESN_v2:` error identifier.
15. No default `alpha` is accepted; missing `alpha` is an error.

### B. Exact `alpha == 1` behaviour

16. Single-neuron, `input_only`: each `X(k+1)` equals the independently
    computed formula `((tau_x/dt)*X(k) + U(k)) / ((tau_x/dt)+1)`.
17. Multi-neuron, `input_only`: element-wise match of independently
    computed formula.
18. Single-neuron, `linear` recurrence: independently computed recurrent
    formula matches.
19. Multi-neuron, `linear` recurrence: independently computed recurrent
    formula matches.
20. Comparison is against an independently calculated expression, not
    merely another call to the core or the engine.
21. `alpha == 1` and `alpha < 1` traverse the same engine code path
    (same spec, same data path, same `info` fields).

### C. `alpha < 1` wrapper correctness

22. `input_only` trajectory over `N` steps equals manually repeated
    calls to `caputo_l1_semiimplicit_step` with the same growing history.
23. `linear` trajectory equals manually repeated calls to the core with
    recurrent drive included.
24. Perturbation test: changing `x0` or an early step's drive changes a
    later fractional state (memory is present).
25. Future-input isolation test: perturbing `U(k+1,:)` does not change
    `X(k,:)` or any earlier row.
26. At every step `k`, `caputo_l1_semiimplicit_step` receives the full
    `X(1:k,:)` history; verified by fixture with known history-dependence.
27. No truncation: `info.truncated == false` and `info.full_history_used == true`
    for every run.

### D. Determinism and side effects

28. Bitwise deterministic replay: two identical calls return identical `X` and `info`.
29. Caller RNG state (`rng('state')`) is unchanged before and after `simulate`.
30. No `rand`/`randn`/`randi` call occurs inside the engine.
31. The `FractionalMESN_v2` value-class object is structurally unchanged
    after `simulate` (MATLAB `isequaln` before/after).
32. Two successive `simulate` calls on the same object yield identical results.

### E. Limiting and equilibrium cases

33. Zero input and zero initial state: `X` remains all-zero.
34. Constant-equilibrium fixture: `x0 = c`, `d ≡ c` (constant drive) retains `x_k = c`
    for all `k` (where analytically applicable for the linear reference).
35. Empty trajectory: `N = 0` returns `X = x0`.
36. `W = zeros(n,n)` in `linear` mode produces results identical to
    `input_only` mode with the same inputs.
37. `alpha == 1`, zero drive: `X(k+1) = (tau_x/dt)/(tau_x/dt+1) * X(k)`,
    geometric decay verified numerically.

### F. Regression protection

38. Frozen core schema (`fractional_mesn_v2_caputo_l1_core_v1`) is
    unchanged; `fractional_l1_core_spec` returns the same struct.
39. Frozen core content hash
    `3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f`
    is verified.
40. All 25 existing Caputo unit tests remain green.
41. All 10 existing analytic tests remain green.
42. v1 protocol fingerprint
    (`bb3ac4fe71985a156c519f1065b99fb1ff3c1c22ae8bc139c46f43cce4a93310`)
    is unchanged.
43. `SRNN_ESN`, `SRNN_reservoir`, and `SRNN_reservoir_DDE` are unmodified
    (content hash or direct file comparison).
44. ODE/DDE tests remain green.
45. Targeted regression suite (110/110) remains green.
46. Full test suite (790/790) remains green.

---

## 9. Anticipated implementation file scope

The files listed below will be created or modified in the **later
implementation phase**. This prompt does **not** create any of them.

### Files to create

| Path | Role |
|---|---|
| `src/algorithms/fractional/FractionalMESN_v2.m` | value-class engine |
| `src/algorithms/fractional/validate_fractional_mesn_v2_config.m` | configuration validator |
| `src/algorithms/fractional/fractional_mesn_v2_engine_spec.m` | fixed contract/spec function |
| `tests/unit/test_fractional_mesn_v2_engine.m` | implementation test suite |
| `docs/validation/FRACTIONAL_MESN_V2_ENGINE_VALIDATION.md` | post-implementation validation record |

### Files that may be modified (only if explicitly authorised in the later prompt)

| Path | Condition |
|---|---|
| `docs/validation/FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md` | only if a justified design revision is separately authorised |

Any scope expansion beyond the above requires a **new committed
preregistration amendment** before implementation begins.

---

## 10. Governance and stop conditions

### 10.1 What E2 verifies

E2 verifies **engineering, causality, identity, and numerical plumbing
only**. No scientific inference, performance benchmarking, or reservoir
characterisation is permitted.

### 10.2 Explicit prohibitions

- No scientific `alpha` is selected in E2. Deterministic test constants
  are fixtures, not scientific candidates.
- No governed seed may be executed.
- No reservoir-performance claim is permitted.
- No temporal-memory or task benchmark is permitted.
- Historical v1 behavior must remain unchanged.

### 10.3 STOP conditions

Any of the following constitutes a hard STOP requiring a new assessment
before proceeding:

- Frozen core content hash changes or cannot be verified.
- Baseline protocol fingerprint (`bb3ac4fe…`) changes.
- Causal indexing invariant is violated (future input affects past state).
- History policy is violated (truncation, windowing, or approximation
  detected).
- Any production code path calls `caputo_l1_semiimplicit_step` outside
  the authorised engine.
- Full test suite falls below 790/790.

### 10.4 Deferral policy

Any need for the following is **deferred to a later preregistered phase**:

- Nonlinear recurrence or `φ(q)` rate map.
- SFA, STD, Dale law, or explicit delays.
- Readout layer or task training.
- Gain tuning or calibration.
- Fast convolution or short-memory acceleration.
- Stateful continuation or checkpoint APIs.

---

## 11. Document traceability

| Field | Value |
|---|---|
| Preregistration schema | `fractional_mesn_v2_engine_v1` |
| Authored at commit | `70d224d530cb665acc7dd4ce38eef4204ea3ebac` |
| Core schema frozen in | 5D-E1 |
| Architecture frozen in | 5D-D |
| This document authorises | documentation commit only |
| Implementation authorised by | separate future prompt only |
| Amendment policy | any scope change requires a new committed amendment before implementation |
