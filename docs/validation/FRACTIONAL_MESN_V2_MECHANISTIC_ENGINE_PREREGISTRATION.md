# Fractional MESN v2 — Mechanistic Engine Foundation Preregistration (Phase 5D-E3-A)

**Phase:** 5D-E3-A (mechanistic foundation preregistration; documentation only)
**Schema:** `fractional_mesn_v2_mechanistic_engine_v1`
**Branch:** `design/fractional-mesn-v2`
**Starting SHA:** `146a7c53ef59955a4c571d45288e32bcced72073`
**Status:** mechanistic foundation contract **preregistered**; implementation **not yet authorised**
**Companion documents:**
- [`FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md`](FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md)
- [`FRACTIONAL_MESN_V2_ENGINE_PREREGISTRATION.md`](FRACTIONAL_MESN_V2_ENGINE_PREREGISTRATION.md)
- [`FRACTIONAL_MESN_V2_ENGINE_VALIDATION.md`](FRACTIONAL_MESN_V2_ENGINE_VALIDATION.md)
- [`FRACTIONAL_MESN_V2_NUMERICAL_CORE_PREREGISTRATION.md`](FRACTIONAL_MESN_V2_NUMERICAL_CORE_PREREGISTRATION.md)

---

## 0. Baseline verification record

| Field | Value |
|---|---|
| Required starting SHA | `146a7c53ef59955a4c571d45288e32bcced72073` |
| Local HEAD | `146a7c53ef59955a4c571d45288e32bcced72073` |
| Remote `origin/design/fractional-mesn-v2` | `146a7c53ef59955a4c571d45288e32bcced72073` |
| Tracked changes | none |
| Untracked tree | `results/development/` only; untouched |
| Phase 5D-E2 status | **complete** |
| Frozen E2 engine schema | `fractional_mesn_v2_engine_v1` |
| Frozen E2 engine content hash | `38414814b75f35c997e695347ec8f9979660108e053d8f676329758e4fc6971d` |
| Frozen Caputo core schema | `fractional_mesn_v2_caputo_l1_core_v1` |
| Frozen Caputo core content hash | `3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f` |
| Accepted full-suite baseline | 828/828, 0 failures, 0 incomplete |
| Phase 5D-E3-0 audit verdict | **READY FOR E3 PREREGISTRATION** |

### 0.1 Source audit findings (Phase 5D-E3-0; read-only)

The E3-0 audit established the following tracked-repository facts that bind this preregistration:

| Finding | Tracked evidence |
|---|---|
| Historical recurrence is `W*(b.*r)` | `SRNN_reservoir.m` line 45: `W * (b .* r)` |
| Adaptation is subtracted **before** activation | `compute_effective_q.m`: `q = x - a*c_a`; then `r = activation_function(q)` in `SRNN_reservoir.m` |
| `piecewiseSigmoid` range is `[0,1]` | `piecewiseSigmoid.m` header and clipping/saturation regions |
| Dale signs enforced on **presynaptic columns** | `create_paired_W_matrix.m`: `W(:, E_cols) = abs(...)`, `W(:, I_cols) = -abs(...)` |
| SFA and STD use **current** rates in historical v1 | `SRNN_reservoir.m`: `da = (r - a)`, `db` uses `r(E_indices)` / `r(I_indices)` at current `t` |
| Inhibitory recurrent contribution is **delayed** in historical DDE | Architecture decision §2.1 DDE mode; `SRNN_reservoir_DDE` |
| Fixed-step SFA, STD, and delay policies require **separate freezes** | Not present in E2 or this preregistration |
| Modifying E2 engine files would invalidate frozen schema/hash/tests | E2 validation §1–§2; four frozen files |
| Standalone modules plus separate mechanistic orchestrator is safest strategy | E2 exposes no reusable full-history step API; private configuration |

No binding decision in this document contradicts tracked repository evidence.

---

## 1. Scope boundary

### 1.1 Authorised in E3-A/B

1. Standalone rate-map module (`mesn_v2_rate_map`)
2. Standalone Dale-matrix validator (`validate_mesn_v2_dale_matrix`)
3. Separate no-delay mechanistic fractional engine (`FractionalMESN_v2_mechanistic`)
4. Exact E2 limiting-control comparisons
5. Deterministic module and engine schema/hash identities

### 1.2 Explicitly excluded from this preregistration

The following must **not** be introduced during E3-A/B implementation without a new committed preregistration amendment:

- Modification of frozen E2 implementation/test files
- Modification of frozen Caputo core files
- Adaptive `ode23s`/`dde23` equivalence claims
- SFA states or coupling
- STD states or release dynamics
- Delay buffers or prehistory
- Interpolation of delayed samples
- Dale-matrix **construction** from random seeds
- Weight generation or spectral scaling
- E/I fraction selection
- Bias term
- Noise injection
- Readout layer or training
- Feature selection, PCA, or whitening
- Task benchmarks or temporal-memory evaluation
- Operating-point calibration or gain repair
- Scientific `alpha` selection
- Governed seed execution
- Acceleration or history truncation
- Stateful continuation or checkpoint APIs
- Performance benchmarks or ESP claims

---

## 2. Frozen E2 and core invariants

The following four E2 files remain **byte-stable** and regression-protected throughout E3-A/B:

| Path | Role |
|---|---|
| `src/algorithms/fractional/FractionalMESN_v2.m` | frozen E2 engine |
| `src/algorithms/fractional/validate_fractional_mesn_v2_config.m` | frozen E2 validator |
| `src/algorithms/fractional/fractional_mesn_v2_engine_spec.m` | frozen E2 spec |
| `tests/unit/test_fractional_mesn_v2_engine.m` | frozen E2 tests (38) |

| Identity | Schema | Content hash |
|---|---|---|
| Frozen E2 engine | `fractional_mesn_v2_engine_v1` | `38414814b75f35c997e695347ec8f9979660108e053d8f676329758e4fc6971d` |
| Frozen Caputo core | `fractional_mesn_v2_caputo_l1_core_v1` | `3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f` |

The new mechanistic engine is a **separate** class. It calls the frozen Caputo core directly. It does **not** subclass or compose the E2 engine, because E2 exposes no reusable full-history step API and has private configuration. Some drive-assembly logic will necessarily parallel E2, but E2 files remain unchanged.

---

## 3. Mechanistic engine identity

| Item | Value |
|---|---|
| Class | `FractionalMESN_v2_mechanistic` |
| Future source path | `src/algorithms/fractional/FractionalMESN_v2_mechanistic.m` |
| Configuration validator | `validate_fractional_mesn_v2_mechanistic_config` |
| Future validator path | `src/algorithms/fractional/validate_fractional_mesn_v2_mechanistic_config.m` |
| Contract/spec function | `fractional_mesn_v2_mechanistic_engine_spec` |
| Future spec path | `src/algorithms/fractional/fractional_mesn_v2_mechanistic_engine_spec.m` |
| Engine schema version | `fractional_mesn_v2_mechanistic_engine_v1` |
| Object semantics | MATLAB **value class** (not a `handle` subclass) |

`FractionalMESN_v2_mechanistic` stores **validated configuration only**. Its `simulate` method is **stateless with respect to the object**: no hidden trajectory state, continuation API, checkpoint API, `persistent` state, `global` state, or RNG is permitted. Repeated calls on the same object must produce bitwise-identical results for identical inputs.

---

## 4. Standalone rate-map module

### 4.1 Identity

| Item | Value |
|---|---|
| Function | `mesn_v2_rate_map` |
| Future path | `src/algorithms/fractional/mesn_v2_rate_map.m` |
| Spec function | `mesn_v2_rate_map_spec` |
| Future spec path | `src/algorithms/fractional/mesn_v2_rate_map_spec.m` |
| Schema version | `mesn_v2_rate_map_v1` |

### 4.2 Public API

```matlab
[r, info] = mesn_v2_rate_map(q, activation_cfg)
```

The module receives effective state `q`. It does **not** compute adaptation.

### 4.3 Canonical `activation_cfg` structure

Field order (deterministic, normalised by validator):

| Field | Type | Role |
|---|---|---|
| `mode` | string | `'piecewise_sigmoid'` or `'identity'` |
| `S_a` | scalar or `[]` | piecewise-sigmoid linear-fraction parameter |
| `S_c` | scalar or `[]` | piecewise-sigmoid centre shift |

For `identity` mode, the validator normalises `S_a = []` and `S_c = []` as the canonical empty representation.

### 4.4 Supported activation modes

**`piecewise_sigmoid`**

- Calls the existing tracked `piecewiseSigmoid(x, a, c)` implementation (`src/nonlinearities/piecewiseSigmoid.m`).
- Requires explicit finite real scalar `S_a` and `S_c`.
- Requires `0 <= S_a <= 1`.
- Preserves the existing `piecewiseSigmoid` formula exactly (including the `a == 0.5` hard-sigmoid branch and general five-region case).
- Returns `r` in `[0,1]`, subject only to ordinary floating-point tolerance.
- Does **not** add extra clipping beyond existing `piecewiseSigmoid` behaviour.
- Preserves input shape and orientation.

**`identity`**

- Returns `r = q` exactly.
- Included **only** as an engineering/limiting control allowing exact reduction to the E2 linear recurrence (`W*x`).
- Is **not** a biological firing-rate model.
- Must **not** be promoted into scientific cells without a later frozen protocol.
- `S_a` and `S_c` must be absent, empty, or normalised to `[]`.

### 4.5 Validation rules

Reject:

- unsupported `mode` values;
- missing required fields;
- non-scalar `activation_cfg` structures;
- invalid `S_a` (nonfinite, complex, outside `[0,1]`, or present in identity mode);
- nonfinite or complex `S_c` (or present in identity mode);
- nonnumeric, nonfinite, or complex `q`.

**No default activation parameters are permitted.**

### 4.6 Rate-map spec and hash

`mesn_v2_rate_map_spec` must expose the exact schema, include a deterministic fixed-contract payload, compute `content_hash` using repository canonical hashing (`canonical_sha256`), exclude `content_hash` from its own hash payload, exclude runtime `q` and configuration values, and use deterministic field ordering.

---

## 5. Standalone Dale-matrix validator module

### 5.1 Identity

| Item | Value |
|---|---|
| Function | `validate_mesn_v2_dale_matrix` |
| Future path | `src/algorithms/fractional/validate_mesn_v2_dale_matrix.m` |
| Spec function | `mesn_v2_dale_validator_spec` |
| Future spec path | `src/algorithms/fractional/mesn_v2_dale_validator_spec.m` |
| Schema version | `mesn_v2_dale_validator_v1` |

### 5.2 Public API

```matlab
dale_info = validate_mesn_v2_dale_matrix(W, presynaptic_signs)
```

### 5.3 Validation contract

| Rule | Detail |
|---|---|
| `W` | finite, real, numeric `n×n` matrix |
| `presynaptic_signs` | exactly `n` elements |
| Sign normalisation | normalise to `1×n` row vector |
| Allowed sign values | exactly `+1` (excitatory) or `-1` (inhibitory) |
| Excitatory column `j` (`+1`) | `W(:,j) >= 0` |
| Inhibitory column `j` (`-1`) | `W(:,j) <= 0` |
| Zero entries | satisfy either sign |
| All-zero columns | satisfy either sign |
| Sign convention | **presynaptic-column** constraints, **not** row constraints |
| W mutation | validator does **not** modify, construct, or scale `W` |
| Neuron typing | validator does **not** select neuron types |
| Spectral constraints | validator does **not** enforce spectral radius or abscissa |
| Diagonal policy | validator does **not** enforce diagonal/self-connection policy |
| RNG | validator does **not** consume RNG |
| Historical ordering | E-first/I-second reproduced when caller supplies `[+1…+1,-1…-1]`; arbitrary explicit ordering is valid |

### 5.4 Returned `dale_info` (bounded)

Must include at least:

| Field | Value |
|---|---|
| `schema_version` | `'mesn_v2_dale_validator_v1'` |
| `content_hash` | deterministic spec hash |
| `n` | matrix dimension |
| `n_excitatory` | count of `+1` signs |
| `n_inhibitory` | count of `-1` signs |
| `signs_by` | `'presynaptic_columns'` |
| `signs_valid` | `true` |

No full copy of `W` in `info`.

---

## 6. Mechanistic configuration

### 6.1 Required fields

| Field | Type / shape | Constraints |
|---|---|---|
| `n` | positive integer scalar | finite, real, positive integer |
| `alpha` | real scalar | finite, `0 < alpha <= 1`; **no default** |
| `dt` | real scalar | finite, `> 0` |
| `tau_x` | real scalar | finite, `> 0` |
| `W_in` | real 2-D matrix | finite, `n` rows |
| `W` | real `n×n` matrix | finite; must pass Dale validator |
| `presynaptic_signs` | vector length `n` | explicit `±1`; normalised to `1×n` |
| `activation` | struct | canonical validated `activation_cfg` |

**No field receives a scientific default.**

### 6.2 Validation requirements

- `n`: finite real positive integer scalar.
- `alpha`: finite real scalar, `0 < alpha <= 1`; reject complex, `NaN`, `Inf`, `alpha <= 0`, `alpha > 1`.
- `dt`, `tau_x`: finite positive real scalars.
- `W_in`: finite, real, two-dimensional with `n` rows.
- `W`: finite, real, `n×n`; must pass `validate_mesn_v2_dale_matrix(W, presynaptic_signs)`.
- `presynaptic_signs`: exactly `n` elements, each exactly `+1` or `-1`.
- `activation`: validated and normalised to canonical field order.
- Return deterministic normalised field order from validator.
- Stable error identifiers prefixed `FractionalMESN_v2_mechanistic:`.

### 6.3 Explicitly absent fields

Do **not** include: `recurrence_mode`, random weight construction, weight seeds, spectral scaling, bias, noise, SFA parameters, STD parameters, delay parameters, readout parameters.

Input-only behaviour is represented by `W = zeros(n,n)`, which is valid for any `presynaptic_signs` vector.

---

## 7. Public API and trajectory contract

### 7.1 Call sequence

```matlab
cfg    = validate_fractional_mesn_v2_mechanistic_config(cfg_in);
engine = FractionalMESN_v2_mechanistic(cfg);
[X, Q, R, info] = simulate(engine, U, x0);
```

### 7.2 Shapes and physical-time row semantics

| Variable | Shape | Interpretation |
|---|---|---|
| `U` | `N × n_input` | external input sequence |
| `U(k,:)` | row | `u_{k-1}` |
| `x0` | scalar or vector (normalised) | initial state `x_0` |
| `X` | `(N+1) × n` | membrane/reservoir state |
| `X(1,:)` | row | `x_0` |
| `X(j+1,:)` | row | `x_j` |
| `Q` | `(N+1) × n` | effective drive before activation |
| `Q(j+1,:)` | row | `q_j` |
| `R` | `(N+1) × n` | firing-rate map output |
| `R(j+1,:)` | row | `r_j` |

`N = 0` returns the three initial rows (`X`, `Q`, `R` each `1×n`) and makes **no** core call.

### 7.3 Initial row

```
X(1,:) = normalised x0
Q(1,:) = X(1,:)          % no SFA in E3-A/B
R(1,:) = mesn_v2_rate_map(Q(1,:), activation)
```

### 7.4 Step-loop pseudocode (normative)

For `k = 1, …, N`:

```
x_previous = X(k,:)            % x_{k-1}
q_previous = Q(k,:)            % q_{k-1}
r_previous = R(k,:)            % r_{k-1}
u_previous = U(k,:)            % u_{k-1}

input_previous    = (W_in * u_previous.').'
recurrent_previous = (W * r_previous.').'
drive_previous    = input_previous + recurrent_previous

[x_next, step_info] = caputo_l1_semiimplicit_step( ...
    X(1:k,:), ...          % complete history x_0,...,x_{k-1}
    drive_previous, ...    % d_{k-1}
    dt, alpha, tau_x)

X(k+1,:) = x_next
Q(k+1,:) = X(k+1,:)        % no SFA in this scope
R(k+1,:) = mesn_v2_rate_map(Q(k+1,:), activation)
```

### 7.5 Mandatory causal constraints

- Drive for `x_k` uses `r_{k-1}` and `u_{k-1}` only.
- No `r_k` or `u_k` may enter the step producing `x_k`.
- Complete `X(1:k,:)` history is passed every step.
- The engine has **exactly one** runtime Caputo-step call site.
- **No** engine-level `alpha == 1` step formula is implemented; the frozen core alone selects `alpha == 1`.
- No rate history before `t0` exists in the no-delay engine.
- `Q` is explicit even though `Q = X` in this subphase, to establish future SFA-compatible output semantics.

### 7.6 Recurrent formula (no-SFA/no-STD/no-delay foundation)

\[
q_{k-1} = x_{k-1}, \qquad r_{k-1} = \phi(q_{k-1})
\]

\[
d_{k-1} = W\, r_{k-1} + W_{\mathrm{in}}\, u_{k-1}
\]

\[
x_k = \text{frozen full-history Caputo-L1 step using } d_{k-1}
\]

Dale law constrains `W` by presynaptic column. Dale law alone does **not** guarantee the sign of recurrent current under identity activation, because identity `q` may be negative. Piecewise-sigmoid mode provides the historical nonnegative-rate semantics.

---

## 8. E2 limiting-control contracts

Both controls are **engineering limiting controls**, not scientific performance comparisons.

### 8.1 Input-only equivalence

When `W = zeros(n,n)`, `X` from the mechanistic engine must match the frozen E2 `FractionalMESN_v2` **input-only** trajectory exactly for identical:

- `alpha`, `dt`, `tau_x`, `W_in`, `U`, `x0`

This must hold **regardless of activation**, because recurrence is zero.

E2 reference: `recurrence_mode = 'input_only'` with the same fields (E2 normalises `W` to `zeros(n,n)` internally).

### 8.2 Linear-engine equivalence

When `activation.mode = 'identity'`, the mechanistic recurrence uses `W * r_{k-1}` with `r = q = x`, i.e. `W * x_{k-1}`.

For identical inputs/configuration, `X` must match the frozen E2 **linear** engine exactly.

Additionally:

```
Q = X
R = X
```

E2 reference: `recurrence_mode = 'linear'` with the same `W`, inputs, and scalar fields.

---

## 9. Matched `alpha == 1` control

- `alpha == 1` uses the same mechanistic engine, input assembly, rate-map path, Dale validation, metadata, and core call site as `alpha < 1`.
- The frozen core supplies its exact backward-Euler-leak branch.
- Tests must independently calculate `alpha == 1` trajectories using:

\[
x_k = \frac{(\tau_x/dt)\, x_{k-1} + d_{k-1}}{(\tau_x/dt) + 1},
\qquad
d_{k-1} = W\, r_{k-1} + W_{\mathrm{in}}\, u_{k-1}.
\]

- The reference calculation must **not** call the frozen core.
- No claim of equality to historical `ode23s`/`dde23` is permitted.

---

## 10. Module and engine specs and hashing

Each spec (`mesn_v2_rate_map_spec`, `mesn_v2_dale_validator_spec`, `fractional_mesn_v2_mechanistic_engine_spec`) must:

- expose its exact schema version;
- include a deterministic fixed-contract payload;
- compute `content_hash` using repository canonical hashing (`canonical_sha256`);
- exclude `content_hash` from its own hash payload;
- exclude runtime `q`, `W`, signs, `alpha`, `dt`, `tau_x`, inputs, states, and configuration values;
- reference dependent schema/hash identities where applicable;
- use deterministic field ordering.

The mechanistic-engine spec must reference:

| Dependency | Schema | Content hash |
|---|---|---|
| Frozen Caputo core | `fractional_mesn_v2_caputo_l1_core_v1` | `3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f` |
| Rate map | `mesn_v2_rate_map_v1` | computed at E3-B1 |
| Dale validator | `mesn_v2_dale_validator_v1` | computed at E3-B1 |

It must **not** claim that SFA, STD, delay, matrix construction, readout, or scientific tuning is included.

Actual hash values for new modules/engine are computed and frozen during implementation; this document does not invent them.

---

## 11. Required `info` output (mechanistic engine)

Bounded `info` from `simulate` must include at least:

| Field | Type / value |
|---|---|
| `engine_schema_version` | `'fractional_mesn_v2_mechanistic_engine_v1'` |
| `engine_content_hash` | string |
| `core_schema_version` | `'fractional_mesn_v2_caputo_l1_core_v1'` |
| `core_content_hash` | `'3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f'` |
| `rate_map_schema_version` | `'mesn_v2_rate_map_v1'` |
| `rate_map_content_hash` | string |
| `dale_validator_schema_version` | `'mesn_v2_dale_validator_v1'` |
| `dale_validator_content_hash` | string |
| `alpha` | scalar used for this run |
| `alpha_one_branch_used` | logical; true iff `alpha == 1` |
| `n_steps` | integer `N` |
| `drive_index` | `'n_minus_1'` |
| `rate_index` | `'n_minus_1'` |
| `input_index` | `'n_minus_1'` |
| `full_history_used` | `true` |
| `truncated` | `false` |
| `activation_mode` | string |
| `dale_signs_valid` | `true` |
| `included_mechanisms` | cell array |
| `excluded_mechanisms` | cell array |

Do **not** store `W`, trajectories, or per-step core `info` in `info`.

Suggested fixed `included_mechanisms`:

```matlab
{'input_plumbing', 'nonlinear_rate_map', 'dale_validation', 'linear_w_recurrence_on_r', 'caputo_l1_stepping'}
```

Suggested fixed `excluded_mechanisms`:

```matlab
{'sfa', 'std', 'delays', 'delay_prehistory', 'bias', 'noise', 'readout', 'weight_construction', 'spectral_scaling', 'fast_convolution', 'continuation'}
```

---

## 12. State-ledger boundary

| Topic | Policy |
|---|---|
| Historical v1 packed-state order | unchanged; available only as historical reference (`[a_E(:); a_I(:); b_E(:); b_I(:); x(:)]`) |
| New engine packed state | does **not** reuse or modify v1 packed state |
| E3-A/B trajectory outputs | `X`, `Q`, `R` row-oriented trajectories only |
| Subphase A/B trajectory layouts | **not** frozen here |
| SFA layout/update | requires later SFA preregistration |
| STD layout/update | requires later STD preregistration |
| Delay history | requires later delay preregistration |
| Future mechanism insertion | no future mechanism may be inserted silently into this engine schema |

---

## 13. Implementation decomposition (frozen execution sequence)

### E3-B1 — Standalone modules

Create and verify:

- `mesn_v2_rate_map`
- `mesn_v2_rate_map_spec`
- `validate_mesn_v2_dale_matrix`
- `mesn_v2_dale_validator_spec`
- isolated unit tests

Commit/push and **STOP**.

### E3-B2 — No-delay mechanistic orchestrator

Create and verify:

- `FractionalMESN_v2_mechanistic`
- `validate_fractional_mesn_v2_mechanistic_config`
- `fractional_mesn_v2_mechanistic_engine_spec`
- mechanistic-engine unit tests

Run targeted regressions, commit/push, and **STOP**.

### E3-B3 — Integrated validation

- audit preregistration traceability;
- verify module/engine hashes;
- run the then-current full suite;
- create a validation record;
- minimally update architecture status;
- commit/push and **STOP**.

**Only after E3-B3** may an SFA preregistration begin.

---

## 14. Required future implementation tests

### A. Rate-map module

1. Identity exactness and shape preservation.
2. Identity empty-parameter normalisation (`S_a = []`, `S_c = []`).
3. Piecewise mode equality to existing `piecewiseSigmoid`.
4. Boundary and representative interior values.
5. Output range `[0,1]`.
6. Row, column, matrix, and empty inputs as supported.
7. Invalid modes, configs, parameters, and `q`.
8. Determinism.
9. Caller RNG unchanged.
10. Exact schema/hash.

### B. Dale validator

1. Valid mixed E/I columns.
2. Arbitrary explicit E/I ordering.
3. Zero entries and all-zero columns.
4. Excitatory negative-entry rejection.
5. Inhibitory positive-entry rejection.
6. Row-sign enforcement is **not** substituted for column signs.
7. Invalid `W` dimensions/type/finiteness/complexity.
8. Invalid sign length/values/type/finiteness/complexity.
9. Input `W` and signs unchanged after call.
10. Deterministic bounded `info`.
11. Caller RNG unchanged.
12. Exact schema/hash.

### C. Mechanistic config/API

1. All required-field validation.
2. No defaults.
3. Normalised field order.
4. Activation normalisation.
5. Presynaptic-sign normalisation.
6. `W` Dale validation delegation.
7. `U` and `x0` validation.
8. Stable `FractionalMESN_v2_mechanistic:` error identifiers.
9. `N = 0`.

### D. Mechanistic dynamics

1. `alpha == 1` independent formula, single and multi-neuron.
2. `alpha < 1` equality to manual growing-history core calls.
3. Future-input isolation.
4. Early-history sensitivity.
5. Complete-history/no-truncation behaviour.
6. Piecewise recurrence uses `r` rather than `x`.
7. `Q`/`R` physical-time alignment.
8. Rate recomputed after each `x` step for output.
9. Deterministic replay.
10. Caller RNG unchanged.
11. Value object unchanged after `simulate`.
12. No hidden state across repeated simulations.

### E. Limiting controls

1. `W = 0` exact `X` equality to E2 input-only.
2. Identity exact `X` equality to E2 linear engine.
3. `Q = X` and `R = X` in identity mode.
4. Zero-input/zero-state cases.
5. Constant or fixed-point fixture where valid.
6. `alpha == 1` zero-drive decay.

### F. Regression and isolation

1. Frozen E2 schema/hash unchanged.
2. All 38 E2 tests remain green.
3. Frozen core schema/hash unchanged.
4. Core unit and analytic tests remain green.
5. Historical v1 fingerprint unchanged.
6. `SRNN_ESN` / ODE / DDE files unchanged.
7. No production caller invokes the mechanistic engine.
8. Full suite additive discovery with no lost tests.

---

## 15. Governance and claim boundary

### 15.1 What E3-A/B verifies

E3-A/B verifies **engineering and mechanistic plumbing only**: rate-map correctness, Dale validation, causal no-delay nonlinear recurrence on `r`, full-history Caputo stepping, and exact E2 limiting controls.

### 15.2 Explicit prohibitions

- Deterministic constants in tests are **fixtures only**.
- No governed seed may be used.
- No scientific `alpha` may be selected.
- No performance or temporal-memory outcome may be generated.
- No operating-point choice may be made.
- Dale-valid nonlinear recurrence is **not** evidence of biological fidelity.
- `alpha < 1` is **not** presumed superior to `alpha == 1`.
- No ESP claim follows from Dale signs, spectral measures, or these unit tests.
- Identity activation is an engineering control, **not** a biological firing-rate model.
- No adaptive-solver (`ode23s`/`dde23`) equality claim is permitted.

### 15.3 STOP conditions

Before implementation, **STOP** for:

- any required edit to a frozen E2/core file;
- unresolved causal index (`t_n` vs `t_{n-1}`, `r_k` vs `r_{k-1}`);
- inability to reproduce exact E2 limiting controls;
- module contract requiring a scientific default;
- rate-map mismatch with tracked `piecewiseSigmoid`;
- Dale validator using rows instead of presynaptic columns;
- hidden RNG or governed seed need;
- scope expansion to SFA, STD, delay, readout, or benchmark;
- inability to assign deterministic schema/hash identities.

---

## 16. Anticipated implementation file scope

This prompt creates **documentation only**. The files below will be created in later implementation phases.

### E3-B1 files to create

| Path | Role |
|---|---|
| `src/algorithms/fractional/mesn_v2_rate_map.m` | rate-map function |
| `src/algorithms/fractional/mesn_v2_rate_map_spec.m` | rate-map spec |
| `src/algorithms/fractional/validate_mesn_v2_dale_matrix.m` | Dale validator |
| `src/algorithms/fractional/mesn_v2_dale_validator_spec.m` | Dale validator spec |
| `tests/unit/test_mesn_v2_rate_map.m` | rate-map tests |
| `tests/unit/test_mesn_v2_dale_validator.m` | Dale validator tests |

### E3-B2 files to create

| Path | Role |
|---|---|
| `src/algorithms/fractional/FractionalMESN_v2_mechanistic.m` | mechanistic engine |
| `src/algorithms/fractional/validate_fractional_mesn_v2_mechanistic_config.m` | config validator |
| `src/algorithms/fractional/fractional_mesn_v2_mechanistic_engine_spec.m` | engine spec |
| `tests/unit/test_fractional_mesn_v2_mechanistic_engine.m` | engine tests |

### E3-B3 files to create or minimally update

| Path | Role |
|---|---|
| `docs/validation/FRACTIONAL_MESN_V2_MECHANISTIC_ENGINE_VALIDATION.md` | post-implementation validation record |
| `docs/validation/FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md` | minimal status amendment only |

Any scope expansion beyond the above requires a **new committed preregistration amendment** before implementation begins.

---

## 17. Document traceability

| Field | Value |
|---|---|
| Preregistration schema | `fractional_mesn_v2_mechanistic_engine_v1` |
| Authored at commit | `146a7c53ef59955a4c571d45288e32bcced72073` |
| E2 engine frozen in | 5D-E2 |
| Caputo core frozen in | 5D-E1 |
| Architecture frozen in | 5D-D |
| Source audit completed in | 5D-E3-0 |
| This document authorises | documentation commit only |
| Implementation authorised by | separate E3-B1/B2/B3 prompts only |
| Amendment policy | any scope change requires a new committed amendment before implementation |
