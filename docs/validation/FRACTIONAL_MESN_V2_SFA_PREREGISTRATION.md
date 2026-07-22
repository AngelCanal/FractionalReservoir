# Fractional MESN v2 — SFA Module and SFA-Engine Preregistration (Phase 5D-E3-C1)

**Phase:** 5D-E3-C1 (SFA module and SFA-engine preregistration; documentation only)
**Schema (SFA engine):** `fractional_mesn_v2_mechanistic_sfa_engine_v1`
**Schema (SFA step):** `mesn_v2_sfa_step_v1`
**Branch:** `design/fractional-mesn-v2`
**Starting SHA:** `52348ba06de301a6ae3968004fdef7f6b4da92b3`
**Status:** SFA module and SFA-enabled engine contract **preregistered**; implementation **not yet authorised**
**Companion documents:**
- [`FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md`](FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md)
- [`FRACTIONAL_MESN_V2_MECHANISTIC_ENGINE_PREREGISTRATION.md`](FRACTIONAL_MESN_V2_MECHANISTIC_ENGINE_PREREGISTRATION.md)
- [`FRACTIONAL_MESN_V2_MECHANISTIC_ENGINE_VALIDATION.md`](FRACTIONAL_MESN_V2_MECHANISTIC_ENGINE_VALIDATION.md)
- [`FRACTIONAL_MESN_V2_ENGINE_PREREGISTRATION.md`](FRACTIONAL_MESN_V2_ENGINE_PREREGISTRATION.md)
- [`FRACTIONAL_MESN_V2_ENGINE_VALIDATION.md`](FRACTIONAL_MESN_V2_ENGINE_VALIDATION.md)

---

## 0. Baseline verification record

| Field | Value |
|---|---|
| Required starting SHA | `52348ba06de301a6ae3968004fdef7f6b4da92b3` |
| Local HEAD | `52348ba06de301a6ae3968004fdef7f6b4da92b3` |
| Remote `origin/design/fractional-mesn-v2` | `52348ba06de301a6ae3968004fdef7f6b4da92b3` |
| Tracked changes | none |
| Untracked tree | `results/development/` only; untouched |
| Phase 5D-E3-B3 status | **complete** |
| Accepted full-suite baseline | **886/886**, 0 failures, 0 incomplete |

### 0.1 Frozen identity verification

| Component | Schema | Content hash |
|---|---|---|
| Frozen E2 engine | `fractional_mesn_v2_engine_v1` | `38414814b75f35c997e695347ec8f9979660108e053d8f676329758e4fc6971d` |
| Frozen Caputo core | `fractional_mesn_v2_caputo_l1_core_v1` | `3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f` |
| Frozen rate-map module | `mesn_v2_rate_map_v1` | `483b6192099426b1c22f29a35e04d9e22c508826a9d334f8da8b0134b94fe257` |
| Frozen Dale validator | `mesn_v2_dale_validator_v1` | `dba675ded7b3f3f8e91ceb93185171a6fbedc42bba5050a97cca8d830bc3f081` |
| Frozen no-SFA mechanistic engine | `fractional_mesn_v2_mechanistic_engine_v1` | `fe9691184cc22a4b4e9afe8d5740badf9442ed535e848f6fbbe94d6c2539fc69` |
| Historical v1 model/protocol fingerprint | `compute_protocol_fingerprint(...)` | `5a5c7a040768a97a5740a2b84e81b38d4c7d3147a4c8c8cdf6bac402b54f8823` |
| Phase 5D-C sealed diagnostic fingerprint | `temporal_memory_diagnostic_v1` | `bb3ac4fe71985a156c519f1065b99fb1ff3c1c22ae8bc139c46f43cce4a93310` |

Hashes verified by inspection of frozen spec functions and frozen unit tests at the starting SHA. No frozen identity differs from the accepted record.

### 0.2 Source audit findings (read-only)

| Finding | Tracked evidence |
|---|---|
| Adaptation is subtracted **before** the rate map | `compute_effective_q.m`: `q = x - a*c_a`; `SRNN_reservoir.m` computes `q` then `r = activation_function(q)` |
| Same neuronal rate `r_i` drives every adaptation channel `m` for neuron `i` | `SRNN_reservoir.m`: `da_E_dt = (r(E_indices) - state.a_E) ./ tau_a_E`; inhibitory analogue |
| Excitatory and inhibitory populations may differ in channel counts, time constants, and coupling vectors | `params.tau_a_E`, `params.tau_a_I`, `params.c_a_E`, `params.c_a_I`; `validate_MESN_params.m` |
| Historical ODE/DDE code evaluates simultaneous continuous-time RHS values through adaptive solvers | `SRNN_reservoir.m`, `SRNN_reservoir_DDE.m` with `ode23s`/`dde23` callers |
| Fixed-step v2 SFA engine is **not** claimed to reproduce exact `ode23s`/`dde23` trajectories | Architecture decision §6.5, §20.3; E3 validation §23 |
| v1 packed-state order is historical reference only | `state_layout.m`, `pack_state.m`, `unpack_state.m` |
| Legacy `c_E`/`c_I` aliases resolved in v1 only | `resolve_adaptation_coupling.m`; rejected in new v2 SFA API |

No binding decision in this document contradicts tracked repository evidence.

---

## 1. Scope boundary

### 1.1 Authorised in E3-C1/C2/C3/C4

1. Standalone deterministic SFA step module (`mesn_v2_sfa_step`)
2. Separately versioned SFA-enabled fractional mechanistic engine (`FractionalMESN_v2_mechanistic_sfa`)
3. Exact mechanism-off reductions to the frozen no-SFA mechanistic engine
4. Deterministic module and engine schema/hash identities
5. Causal state, initialization, and trajectory contracts

SFA remains **explicitly integer-order** and **separate** from the fractional Caputo state `x`.

### 1.2 Explicitly excluded from this preregistration

The following must **not** be introduced during E3-C2/C3/C4 implementation without a new committed preregistration amendment:

- Modification of frozen E2 implementation/test files
- Modification of frozen no-SFA mechanistic implementation/test files
- Modification of frozen Caputo core files
- Modification of frozen rate-map or Dale-validator files
- Adaptive `ode23s`/`dde23` equivalence claims
- STD states or release dynamics
- Synaptic-resource state `b`
- Recurrent drive `W*(b.*r)`
- Delay buffers, delay interpolation, or delay prehistory
- Random initial state construction
- Weight construction, scaling, or E/I fraction selection
- Legacy `c_E`/`c_I` aliases in the new v2 SFA API
- Clipping of adaptation state `A`
- Bias term
- Noise injection
- Readout layer or training
- Feature selection, PCA, or whitening
- Task benchmarks or temporal-memory evaluation
- Operating-point calibration or gain tuning
- Scientific `alpha` selection
- Governed seed execution
- Acceleration or history truncation
- Stateful continuation or checkpoint APIs
- Performance benchmarks or ESP claims

---

## 2. Frozen E2, E3-B1, and E3-B2 invariants

All existing E2, E3-B1, and E3-B2 files remain **byte-stable** and regression-protected throughout E3-C2/C3/C4.

### 2.1 Frozen E2 files

| Path | Role |
|---|---|
| `src/algorithms/fractional/FractionalMESN_v2.m` | frozen E2 engine |
| `src/algorithms/fractional/validate_fractional_mesn_v2_config.m` | frozen E2 validator |
| `src/algorithms/fractional/fractional_mesn_v2_engine_spec.m` | frozen E2 spec |
| `tests/unit/test_fractional_mesn_v2_engine.m` | frozen E2 tests (38) |

### 2.2 Frozen no-SFA mechanistic files

| Path | Role |
|---|---|
| `src/algorithms/fractional/FractionalMESN_v2_mechanistic.m` | frozen no-SFA mechanistic engine |
| `src/algorithms/fractional/validate_fractional_mesn_v2_mechanistic_config.m` | frozen no-SFA validator |
| `src/algorithms/fractional/fractional_mesn_v2_mechanistic_engine_spec.m` | frozen no-SFA spec |
| `tests/unit/test_fractional_mesn_v2_mechanistic_engine.m` | frozen no-SFA tests (24) |

### 2.3 Frozen foundation modules

| Path | Role |
|---|---|
| `src/algorithms/fractional/mesn_v2_rate_map.m` | frozen rate-map function |
| `src/algorithms/fractional/mesn_v2_rate_map_spec.m` | frozen rate-map spec |
| `src/algorithms/fractional/validate_mesn_v2_dale_matrix.m` | frozen Dale validator |
| `src/algorithms/fractional/mesn_v2_dale_validator_spec.m` | frozen Dale spec |
| Caputo core files | frozen per E1 |

The SFA-enabled engine is a **separate** class. It does **not** subclass, compose, or modify the frozen no-SFA engine. It calls the frozen Caputo core, rate-map module, Dale validator, and new SFA-step module **directly**.

---

## 3. Historical continuous-time SFA equation

### 3.1 Adaptation dynamics

For each neuron \(i\) and adaptation channel \(m\):

\[
\tau_{a,m}\,\frac{d a_{i,m}}{dt} = r_i - a_{i,m}.
\]

### 3.2 Effective state and rate map

\[
q_i = x_i - \sum_m c_{a,m}\, a_{i,m},
\qquad
r_i = \phi(q_i).
\]

### 3.3 Binding historical conventions

- Adaptation is **subtracted before** the rate map; SFA does **not** appear as a separate additive current on the \(x\)-RHS.
- The **same** neuronal rate \(r_i\) drives **every** adaptation channel \(m\) for that neuron.
- Excitatory and inhibitory populations may have different:
  - channel counts \(n_{a,E}\), \(n_{a,I}\);
  - time-constant vectors \(\tau_{a,E}\), \(\tau_{a,I}\);
  - coupling vectors \(c_{a,E}\), \(c_{a,I}\).
- Historical ODE/DDE code (`SRNN_reservoir.m`, `SRNN_reservoir_DDE.m`) evaluates simultaneous continuous-time RHS values through adaptive solvers (`ode23s`, `dde23`).
- The new fixed-step v2 SFA engine is **not** claimed to reproduce exact `ode23s` or `dde23` trajectories.

---

## 4. Standalone SFA-step module

### 4.1 Identity

| Item | Value |
|---|---|
| Function | `mesn_v2_sfa_step` |
| Future path | `src/algorithms/fractional/mesn_v2_sfa_step.m` |
| Spec function | `mesn_v2_sfa_step_spec` |
| Future spec path | `src/algorithms/fractional/mesn_v2_sfa_step_spec.m` |
| Schema version | `mesn_v2_sfa_step_v1` |

### 4.2 Public API

```matlab
[a_next, info] = mesn_v2_sfa_step( ...
    a_previous, ...
    r_previous, ...
    dt, ...
    tau_a)
```

### 4.3 Input contract

**`a_previous`**

- finite, real, numeric, two-dimensional matrix;
- shape: `n_population × n_channels`;
- rows correspond to neurons within one population;
- columns correspond to adaptation timescales;
- may have zero columns;
- must not be modified.

**`r_previous`**

- finite, real, numeric vector;
- exactly `n_population` elements;
- row or column accepted;
- normalize internally to `n_population × 1`;
- unrestricted finite real values at module level because identity activation is an engineering control;
- must not be modified.

**`dt`**

- finite, real, positive numeric scalar.

**`tau_a`**

- finite, real, positive numeric vector;
- exactly `n_channels` elements;
- row or column accepted;
- normalize internally to `1 × n_channels`;
- when `n_channels = 0`, canonical `tau_a` is empty.

### 4.4 Zero-channel behavior

When `n_channels = 0`:

- `a_previous` has shape `n_population × 0`;
- `tau_a` is empty;
- `a_next` has the identical `n_population × 0` shape;
- no numerical update is performed;
- `info` reports `n_channels = 0`.

### 4.5 Exact discrete SFA update (zero-order hold)

Driven by \(r_{k-1}\):

\[
\text{decay}_m = \exp(-\Delta t / \tau_{a,m}),
\]

\[
a_{i,m,k} = \text{decay}_m \cdot a_{i,m,k-1} + (1 - \text{decay}_m) \cdot r_{i,k-1}.
\]

Equivalent matrix form:

```matlab
decay = exp(-dt ./ tau_a);
a_next = a_previous .* decay + r_previous(:) * (1 - decay);
```

**Binding properties:**

- the update is **exact** for the continuous first-order adaptation equation when \(r\) is held constant during the step;
- the update uses \(r_{k-1}\), **never** \(r_k\);
- it is **causal**;
- no implicit algebraic loop exists;
- no explicit-Euler approximation is used;
- no backward-Euler approximation is used;
- no clipping is performed;
- this update is **integer-order**;
- this update is **not** part of the Caputo memory;
- it does **not** consume fractional \(x\) history;
- it does **not** consume delay prehistory.

### 4.6 Invariant and limiting behavior (preregistered tests)

1. If \(0 \le a_{\text{previous}} \le 1\) and \(0 \le r_{\text{previous}} \le 1\), then \(0 \le a_{\text{next}} \le 1\) **without clipping**.
2. For \(r_{\text{previous}} = 0\): \(a_{\text{next}} = a_{\text{previous}} \odot \exp(-\Delta t / \tau_a)\).
3. For \(a_{\text{previous}} = r_{\text{previous}}\) replicated across channels: \(a_{\text{next}} = a_{\text{previous}}\) exactly.
4. For constant \(r\) and two consecutive steps: the two-step update equals the closed-form update over total duration \(2\Delta t\), within tight floating-point tolerance.
5. As \(\Delta t \to 0\), \(a_{\text{next}} \to a_{\text{previous}}\).
6. The module accepts finite values outside \([0,1]\) and applies the formula without clipping; the \([0,1]\) guarantee applies only under its stated premises.

### 4.7 Bounded `info` (SFA step)

Must include at least:

| Field | Value |
|---|---|
| `schema_version` | `'mesn_v2_sfa_step_v1'` |
| `content_hash` | deterministic spec hash |
| `update_scheme` | `'exact_exponential_zero_order_hold'` |
| `rate_index` | `'n_minus_1'` |
| `n_population` | integer |
| `n_channels` | integer |
| `clipped` | `false` |
| `integer_order` | `true` |
| `fractional_history_used` | `false` |
| `delay_history_used` | `false` |

Do **not** store: `a_previous`, `a_next`, `r_previous`, `tau_a`, or trajectories.

### 4.8 SFA-step spec

`mesn_v2_sfa_step_spec` must:

- use schema: `mesn_v2_sfa_step_v1`;
- use `canonical_sha256`;
- hash a deterministic fixed-contract payload;
- exclude `content_hash` from its own payload;
- exclude runtime: `a`, `r`, `dt`, `tau` values, population sizes, channel counts;
- record the exact equation;
- record the \(n-1\) rate index;
- record the zero-channel policy;
- record no-clipping policy;
- record integer-order status;
- record separation from Caputo and delay history;
- use deterministic field order.

The actual hash will be computed and frozen during implementation, not invented in this documentation prompt.

---

## 5. SFA-enabled engine identity

| Item | Value |
|---|---|
| Class | `FractionalMESN_v2_mechanistic_sfa` |
| Future source path | `src/algorithms/fractional/FractionalMESN_v2_mechanistic_sfa.m` |
| Configuration validator | `validate_fractional_mesn_v2_mechanistic_sfa_config` |
| Future validator path | `src/algorithms/fractional/validate_fractional_mesn_v2_mechanistic_sfa_config.m` |
| Engine spec | `fractional_mesn_v2_mechanistic_sfa_engine_spec` |
| Future spec path | `src/algorithms/fractional/fractional_mesn_v2_mechanistic_sfa_engine_spec.m` |
| Engine schema version | `fractional_mesn_v2_mechanistic_sfa_engine_v1` |
| Object semantics | MATLAB **value class** (not a `handle` subclass) |

`FractionalMESN_v2_mechanistic_sfa` stores **validated configuration only**. Its `simulate` method is **stateless with respect to the object**: no hidden trajectory state, continuation API, checkpoint API, `persistent` state, `global` state, or RNG is permitted. Repeated calls on the same object must produce bitwise-identical results for identical inputs.

The SFA-enabled engine does **not** subclass, compose, or modify the frozen no-SFA engine. It calls the frozen Caputo core, rate-map module, Dale validator, and new SFA-step module directly.

---

## 6. SFA configuration

### 6.1 Required fields

The SFA-enabled engine configuration contains the eight frozen mechanistic fields:

| Field | Role |
|---|---|
| `n` | network size |
| `alpha` | Caputo order |
| `dt` | time step |
| `tau_x` | membrane time constant |
| `W_in` | input weights |
| `W` | recurrent weights |
| `presynaptic_signs` | Dale signs |
| `activation` | rate-map configuration |

plus:

| Field | Role |
|---|---|
| `sfa` | adaptation configuration struct |

### 6.2 Canonical `sfa` struct fields (deterministic order)

1. `tau_a_E`
2. `c_a_E`
3. `tau_a_I`
4. `c_a_I`

**No defaults.**

Channel counts are inferred:

```
n_a_E = numel(tau_a_E)
n_a_I = numel(tau_a_I)
```

### 6.3 Validation rules

**`tau_a_E` and `tau_a_I`**

- numeric;
- finite;
- real;
- positive;
- vectors;
- normalized to row vectors;
- may be empty.

**`c_a_E` and `c_a_I`**

- numeric;
- finite;
- real;
- **nonnegative**;
- vectors;
- normalized to row vectors;
- may be empty;
- length must exactly match the corresponding `tau` vector.

**Binding coupling contract:**

- nonnegative coupling is a **stricter v2 SFA contract** representing subtractive adaptation;
- negative coupling is **outside** this SFA contract and would represent facilitation or a different mechanism;
- no coupling magnitude is selected scientifically here;
- zero coupling is allowed as an exact engineering control;
- zero channels are represented by matched empty `tau` and coupling vectors.

**Population indexing:**

```matlab
E_idx = find(presynaptic_signs == +1)
I_idx = find(presynaptic_signs == -1)
```

Historical E-first/I-second ordering is **not** required. Arbitrary explicit Dale-valid ordering remains supported.

### 6.4 Explicitly absent fields

Do **not** include: `recurrence_mode`, random weight construction, weight seeds, spectral scaling, bias, noise, STD parameters, delay parameters, readout parameters, legacy `c_E`/`c_I` aliases.

---

## 7. Public API and initial SFA state

### 7.1 Call sequence

```matlab
cfg    = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_in);
engine = FractionalMESN_v2_mechanistic_sfa(cfg);
[X, Q, R, A_E, A_I, info] = simulate(engine, U, x0, a0);
```

### 7.2 `a0` contract

`a0` must be an explicit scalar struct with fields:

- `a_E`
- `a_I`

**No random or deterministic default initialization is allowed.**

**`a0.a_E`**

- finite real numeric matrix;
- exact shape: `n_E × n_a_E`.

**`a0.a_I`**

- finite real numeric matrix;
- exact shape: `n_I × n_a_I`.

For zero channels, accept an empty input only if it can be normalized unambiguously to `zeros(n_E, 0)` or `zeros(n_I, 0)`. For a zero-sized population, preserve the correct zero-row shape.

Do **not**:

- broadcast scalar `a0`;
- generate random `a0`;
- clip `a0`;
- silently reshape an incorrectly sized nonempty matrix.

---

## 8. Trajectory layout

### 8.1 Input and output shapes

| Variable | Shape | Interpretation |
|---|---|---|
| `U` | `N × n_input` | external input sequence |
| `U(k,:)` | row | `u_{k-1}` |
| `x0` | scalar or vector (normalised) | initial state `x_0` |
| `X` | `(N+1) × n` | membrane/reservoir state |
| `X(j+1,:)` | row | `x_j` |
| `Q` | `(N+1) × n` | effective drive before activation |
| `Q(j+1,:)` | row | `q_j` |
| `R` | `(N+1) × n` | firing-rate map output |
| `R(j+1,:)` | row | `r_j` |
| `A_E` | `(N+1) × n_E × n_a_E` | excitatory adaptation |
| `A_E(j+1,i,m)` | scalar | adaptation at \(t_j\) for the \(i\)th excitatory neuron in `E_idx` and channel \(m\) |
| `A_I` | `(N+1) × n_I × n_a_I` | inhibitory adaptation |
| `A_I(j+1,i,m)` | scalar | adaptation at \(t_j\) for the \(i\)th inhibitory neuron in `I_idx` and channel \(m\) |

### 8.2 MATLAB singleton and zero-size dimensions

Tests must use `size(A_E, dim)` and `size(A_I, dim)` rather than relying on displayed dimensionality or `squeeze`. Singleton-channel dimensions (`n_a_E = 1` or `n_a_I = 1`) and zero-channel dimensions (`n_a_E = 0` or `n_a_I = 0`) must be represented deterministically.

### 8.3 Population ordering

- the second dimension of `A_E` follows ascending `E_idx`;
- the second dimension of `A_I` follows ascending `I_idx`;
- `Q` and `R` retain original global neuronal ordering.

No v1 packed-state vector is used.

---

## 9. Initial row

Normalize `x0` to `1 × n`.

```
X(1,:) = x0
A_E(1,:,:) = a0.a_E
A_I(1,:,:) = a0.a_I
```

Compute adaptation contribution in global neuron order:

```
adaptation_0(E_idx) = a0.a_E * c_a_E(:)
adaptation_0(I_idx) = a0.a_I * c_a_I(:)
```

with zero contribution for a population with zero channels.

Then:

```
Q(1,:) = X(1,:) - adaptation_0
R(1,:) = mesn_v2_rate_map(Q(1,:), activation)
```

---

## 10. Causal update order

For `k = 1, …, N`:

1. Read:
   - `x_previous = X(k,:)` — \(x_{k-1}\)
   - `q_previous = Q(k,:)` — \(q_{k-1}\)
   - `r_previous = R(k,:)` — \(r_{k-1}\)
   - `u_previous = U(k,:)` — \(u_{k-1}\)

2. Assemble input drive:
   ```
   input_previous = (W_in * u_previous.').'
   ```

3. Assemble no-STD/no-delay recurrent drive:
   ```
   recurrent_previous = (W * r_previous.').'
   ```

4. Assemble:
   ```
   drive_previous = input_previous + recurrent_previous
   ```

5. Advance \(x\) using the frozen full-history Caputo core:
   ```
   x_next = caputo_l1_semiimplicit_step( ...
       X(1:k,:), ...
       drive_previous, ...
       dt, alpha, tau_x)
   ```

6. Advance excitatory adaptation using only `r_previous(E_idx)`:
   ```
   a_E_next = mesn_v2_sfa_step( ...
       a_E_previous, ...
       r_previous(E_idx), ...
       dt, tau_a_E)
   ```

7. Advance inhibitory adaptation using only `r_previous(I_idx)`:
   ```
   a_I_next = mesn_v2_sfa_step( ...
       a_I_previous, ...
       r_previous(I_idx), ...
       dt, tau_a_I)
   ```

8. Store `X(k+1,:)` and `A` states at \(t_k\).

9. Compute current adaptation contribution from the newly stored `A` states:
   ```
   adaptation_k(E_idx) = a_E_next * c_a_E(:)
   adaptation_k(I_idx) = a_I_next * c_a_I(:)
   ```

10. Compute:
    ```
    Q(k+1,:) = X(k+1,:) - adaptation_k
    ```

11. Compute:
    ```
    R(k+1,:) = mesn_v2_rate_map(Q(k+1,:), activation)
    ```

### 10.1 Mandatory causal statements

- the drive producing \(x_k\) uses \(r_{k-1}\) and \(u_{k-1}\);
- the SFA update producing \(a_k\) uses \(r_{k-1}\);
- \(q_k\) uses \(x_k\) and \(a_k\);
- \(r_k\) is computed **only after** \(x_k\) and \(a_k\) exist;
- \(r_k\) **never** affects \(x_k\) or \(a_k\);
- there is **no** algebraic loop;
- complete `X(1:k,:)` history is used for every \(x\) step;
- adaptation history beyond \(a_{k-1}\) is **not** required because SFA remains first-order Markovian;
- no delay history exists in this phase.

---

## 11. N = 0 contract

For `N = 0`:

- no Caputo step occurs;
- no SFA step occurs;
- `X`, `Q`, and `R` contain only their \(t_0\) row;
- `A_E` and `A_I` contain only their \(t_0\) slices;
- metadata reports `n_steps = 0`;
- the explicit initial conditions are returned unchanged.

---

## 12. Mechanism-off and control limits

Preregistered **engineering controls**, not performance comparisons.

### 12.1 Zero-channel SFA-off limit

When:

```
tau_a_E = []
c_a_E = []
tau_a_I = []
c_a_I = []
```

and `a0` uses canonical zero-channel shapes, the complete `X`, `Q`, and `R` trajectories must match the frozen no-SFA `FractionalMESN_v2_mechanistic` engine for identical:

- `n`, `alpha`, `dt`, `tau_x`, `W_in`, `W`, `presynaptic_signs`, `activation`, `U`, `x0`

This comparison must be exact where operation order permits.

### 12.2 Zero-coupling limit

When adaptation channels exist but:

```
c_a_E = zeros(...)
c_a_I = zeros(...)
```

then:

- `Q = X` exactly;
- `X`, `Q`, and `R` must match the frozen no-SFA mechanistic engine;
- `A_E` and `A_I` still evolve but do not feed back into `Q`.

### 12.3 W = 0 input-only limit

When `W = zeros(n, n)`:

- SFA can change `Q`, `R`, and `A`;
- `X` must match the frozen E2 input-only engine exactly because rate does not enter the \(x\) drive.

### 12.4 Identity and zero-coupling linear limit

When `activation.mode = 'identity'` and all SFA couplings are zero:

- `Q = X`;
- `R = X`;
- `X` must match the frozen E2 linear engine exactly.

### 12.5 Piecewise invariant fixture

For piecewise activation, if initial `A` values lie in \([0,1]\):

- `R` remains in \([0,1]\);
- exact SFA updates preserve `A` in \([0,1]\);
- no clipping is used.

---

## 13. Matched `alpha == 1` control

- The SFA-enabled engine **always** uses the same Caputo core call site.
- The engine implements **no** separate `alpha == 1` \(x\) update.
- The frozen core alone selects its exact backward-Euler-leak branch.
- SFA uses the **same** exact exponential integer-order update at `alpha == 1` and `alpha < 1`.
- `alpha` affects \(x\) dynamics only.

Tests must independently calculate the `alpha == 1` \(x\) recurrence:

\[
x_k = \frac{(\tau_x/\Delta t)\, x_{k-1} + d_{k-1}}{(\tau_x/\Delta t) + 1}.
\]

The independent `alpha == 1` reference must also calculate the SFA exponential update directly. The reference must **not** call:

- the Caputo step;
- the no-SFA engine;
- the SFA-enabled engine.

No equality to historical `ode23s`/`dde23` trajectories is claimed.

---

## 14. SFA-engine spec and hashing

`fractional_mesn_v2_mechanistic_sfa_engine_spec` must:

- expose schema: `fractional_mesn_v2_mechanistic_sfa_engine_v1`;
- use `canonical_sha256`;
- hash a deterministic fixed-contract payload;
- exclude `content_hash` from its own payload;
- exclude runtime: `alpha`, `dt`, `tau_x`, `W`, `W_in`, signs, activation parameters, `tau_a` values, `c_a` values, `x0`, `a0`, `U`, trajectories;
- reference and verify:

| Dependency | Schema | Content hash |
|---|---|---|
| Frozen Caputo core | `fractional_mesn_v2_caputo_l1_core_v1` | `3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f` |
| Frozen rate-map module | `mesn_v2_rate_map_v1` | `483b6192099426b1c22f29a35e04d9e22c508826a9d334f8da8b0134b94fe257` |
| Frozen Dale validator | `mesn_v2_dale_validator_v1` | `dba675ded7b3f3f8e91ceb93185171a6fbedc42bba5050a97cca8d830bc3f081` |
| Frozen no-SFA mechanistic engine | `fractional_mesn_v2_mechanistic_engine_v1` | `fe9691184cc22a4b4e9afe8d5740badf9442ed535e848f6fbbe94d6c2539fc69` |
| New SFA-step module | `mesn_v2_sfa_step_v1` | computed at E3-C2 |

- record exact `X`/`Q`/`R`/`A_E`/`A_I` layouts;
- record causal \(n-1\) policies;
- record exact mechanism-off limits;
- record value-class/stateless semantics;
- record SFA as integer-order;
- record no STD and no delay;
- use deterministic field order.

The actual SFA-engine hash will be computed during implementation and frozen in tests.

---

## 15. Required `info` output (SFA engine)

Bounded `info` from `simulate` must include at least:

| Field | Type / value |
|---|---|
| `engine_schema_version` | `'fractional_mesn_v2_mechanistic_sfa_engine_v1'` |
| `engine_content_hash` | string |
| `foundation_engine_schema_version` | `'fractional_mesn_v2_mechanistic_engine_v1'` |
| `foundation_engine_content_hash` | `'fe9691184cc22a4b4e9afe8d5740badf9442ed535e848f6fbbe94d6c2539fc69'` |
| `core_schema_version` | `'fractional_mesn_v2_caputo_l1_core_v1'` |
| `core_content_hash` | `'3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f'` |
| `rate_map_schema_version` | `'mesn_v2_rate_map_v1'` |
| `rate_map_content_hash` | `'483b6192099426b1c22f29a35e04d9e22c508826a9d334f8da8b0134b94fe257'` |
| `dale_validator_schema_version` | `'mesn_v2_dale_validator_v1'` |
| `dale_validator_content_hash` | `'dba675ded7b3f3f8e91ceb93185171a6fbedc42bba5050a97cca8d830bc3f081'` |
| `sfa_step_schema_version` | `'mesn_v2_sfa_step_v1'` |
| `sfa_step_content_hash` | string |
| `alpha` | scalar used for this run |
| `alpha_one_branch_used` | logical; true iff `alpha == 1` |
| `n_steps` | integer `N` |
| `n_E` | integer |
| `n_I` | integer |
| `n_a_E` | integer |
| `n_a_I` | integer |
| `drive_index` | `'n_minus_1'` |
| `sfa_rate_index` | `'n_minus_1'` |
| `input_index` | `'n_minus_1'` |
| `full_fractional_history_used` | `true` |
| `fractional_history_truncated` | `false` |
| `sfa_integer_order` | `true` |
| `sfa_clipped` | `false` |
| `activation_mode` | string |
| `dale_signs_valid` | `true` |
| `included_mechanisms` | cell array |
| `excluded_mechanisms` | cell array |

Do **not** include: weights, sign vectors, activation parameters, `tau` vectors, coupling vectors, `x0` or `a0`, trajectories, or per-step info arrays.

Suggested fixed `included_mechanisms`:

```matlab
{'input_plumbing', 'nonlinear_rate_map', 'dale_validation', ...
 'linear_w_recurrence_on_r', 'caputo_l1_stepping', 'sfa_integer_order'}
```

Suggested fixed `excluded_mechanisms`:

```matlab
{'std', 'delays', 'delay_prehistory', 'bias', 'noise', 'readout', ...
 'weight_construction', 'spectral_scaling', 'fast_convolution', ...
 'continuation', 'sfa_clipping'}
```

---

## 16. Implementation decomposition (frozen execution sequence)

### E3-C2 — Standalone SFA module

Create:

- `src/algorithms/fractional/mesn_v2_sfa_step.m`
- `src/algorithms/fractional/mesn_v2_sfa_step_spec.m`
- `tests/unit/test_mesn_v2_sfa_step.m`

Run targeted module and frozen-foundation regressions.

Commit/push and **STOP**.

### E3-C3 — SFA-enabled engine

Create:

- `src/algorithms/fractional/FractionalMESN_v2_mechanistic_sfa.m`
- `src/algorithms/fractional/validate_fractional_mesn_v2_mechanistic_sfa_config.m`
- `src/algorithms/fractional/fractional_mesn_v2_mechanistic_sfa_engine_spec.m`
- `tests/unit/test_fractional_mesn_v2_mechanistic_sfa_engine.m`

Run targeted SFA-engine and frozen-foundation regressions.

Commit/push and **STOP**.

### E3-C4 — Integrated SFA validation

- perform read-only implementation and traceability audit;
- verify all identities;
- calculate the exact additive discovery count from accepted 886 baseline plus new SFA-module and SFA-engine tests;
- run the full suite;
- require exact discovery and all-pass results;
- create an SFA validation document;
- minimally update the architecture decision;
- commit/push documentation only;
- **STOP**.

**STD preregistration may begin only after E3-C4 completion.**

---

## 17. Preregistered test matrix

### A. Standalone SFA-step module

- scalar population / single channel formula;
- multiple neurons / single channel;
- single neuron / multiple channels;
- multiple neurons / multiple channels;
- row/column `r` normalization;
- row/column `tau` normalization;
- zero-channel behavior;
- invalid `a_previous` type, shape, complexity, and finiteness;
- invalid `r` type, shape, length, complexity, and finiteness;
- invalid `dt`;
- invalid `tau` type, length, sign, complexity, and finiteness;
- exact zero-rate decay;
- exact fixed-point behavior;
- constant-rate two-step semigroup;
- \([0,1]\) invariant under stated premises;
- no clipping outside the invariant premise;
- deterministic replay;
- caller RNG unchanged;
- inputs unchanged;
- bounded info;
- exact schema and computed hash;
- stable error identifiers.

### B. SFA configuration and initial state

- valid mixed E/I multi-channel configuration;
- E-only population;
- I-only population;
- arbitrary Dale ordering;
- zero channels in either population;
- zero channels in both populations;
- zero couplings with nonzero channels;
- `tau`/`c` row/column normalization;
- `tau`/`c` length mismatch;
- invalid `tau`;
- invalid coupling;
- negative-coupling rejection;
- absence of defaults;
- legacy `c_E`/`c_I` rejection;
- exact normalized field order;
- exact `a0` shapes;
- zero-population and zero-channel `a0` shapes;
- invalid `a0` type, shape, complexity, or finiteness;
- config and `a0` unchanged;
- stable mechanistic-SFA error identifiers.

### C. SFA-engine initialization and layout

- exact `X`/`Q`/`R` initial row;
- exact `A_E`/`A_I` initial slices;
- correct arbitrary E/I scatter into global `Q`;
- multiple channels summed with `c` vectors;
- exact trajectory sizes using `size(..., dim)`;
- singleton-channel dimensions;
- zero-channel dimensions;
- zero-population dimensions;
- `N = 0` behavior and metadata;
- physical-time row alignment.

### D. SFA-engine dynamics

- `alpha == 1` independent reference: single neuron, multiple neurons, mixed E/I, multiple channels, identity activation, piecewise activation;
- `alpha < 1` manual growing-history core reference;
- exact SFA-step module use;
- SFA uses \(r_{k-1}\), not \(r_k\);
- \(x\) drive uses \(r_{k-1}\) and \(u_{k-1}\);
- \(q_k\) uses \(x_k\) and \(a_k\);
- \(r_k\) is computed after \(q_k\);
- future-input isolation;
- early \(x\)-history sensitivity;
- early adaptation-state sensitivity;
- complete fractional history;
- no adaptation-history convolution;
- no algebraic loop;
- `W*r` rather than `W*x` in nonlinear mode;
- determinism;
- caller RNG unchanged;
- value object unchanged;
- repeated simulation leaks no state;
- `U`, `x0`, and `a0` unchanged.

### E. Exact limiting controls

- zero-channel `X`/`Q`/`R` equality to no-SFA mechanistic engine;
- zero-coupling `X`/`Q`/`R` equality to no-SFA mechanistic engine;
- zero-coupling `Q = X`;
- `W = 0` `X` equality to E2 input-only despite active SFA;
- identity plus zero coupling equality to E2 linear;
- piecewise `A` and `R` invariant fixture;
- zero-rate adaptation decay;
- adaptation fixed point;
- `alpha == 1` zero-drive limit.

### F. Regression and isolation

- accepted 886 tests remain green before additive SFA tests;
- all five frozen schemas/hashes unchanged;
- new SFA module schema/hash exact;
- new SFA engine schema/hash exact;
- historical v1 fingerprint unchanged;
- Phase 5D-C fingerprint remains separately documented;
- `SRNN_ESN`, ODE, and DDE files unchanged;
- no production caller uses the SFA engine;
- no existing engine calls the SFA engine;
- no SFA source uses RNG;
- full-suite discovery is strictly additive.

---

## 18. Governance and claim boundary

### 18.1 What E3-C verifies

E3-C verifies **engineering and SFA mechanism plumbing only**: exact exponential SFA stepping, causal \(n-1\) indexing, subtractive adaptation before the rate map, full-history Caputo stepping, and exact mechanism-off limiting controls.

### 18.2 Explicit prohibitions

- All numeric constants in tests are **deterministic fixtures**.
- No scientific `tau` or coupling value is chosen.
- No scientific `alpha` is chosen.
- No governed seed is consumed.
- No performance or temporal-memory result is generated.
- No stability or marginal-stability claim is tested.
- SFA remains a **separate integer-order mechanism**.
- Adding multiple SFA channels does **not** make \(x\) fractional.
- Caputo \(x\) dynamics and multi-timescale SFA must remain **separately ablatable**.
- Successful unit tests do **not** establish biological fidelity.
- Successful unit tests do **not** establish ESP.
- Successful unit tests do **not** establish a memory advantage.
- `alpha < 1` is **not** presumed superior to `alpha == 1`.
- No adaptive-solver (`ode23s`/`dde23`) equality claim is permitted.

### 18.3 STOP conditions

Before implementation, **STOP** for:

- any required edit to a frozen E2, no-SFA mechanistic, core, rate-map, or Dale file;
- unresolved causal index (\(r_k\) vs \(r_{k-1}\), \(a_k\) vs \(a_{k-1}\), \(q_k\) construction);
- inability to support arbitrary Dale ordering;
- inability to represent zero-channel or zero-population dimensions deterministically;
- inability to specify exact mechanism-off comparison;
- SFA requiring a scientific default;
- implementation using \(r_k\) to produce \(a_k\);
- implementation moving adaptation onto the \(x\) RHS;
- implementation combining SFA history with Caputo history;
- implementation adding clipping without a new amendment;
- implementation requiring RNG;
- scope expansion to STD, delay, readout, tuning, or benchmarking;
- inability to assign deterministic module or engine identities.

---

## 19. Anticipated implementation file scope

This prompt creates **documentation only**. The files below will be created in later implementation phases.

### E3-C2 files to create

| Path | Role |
|---|---|
| `src/algorithms/fractional/mesn_v2_sfa_step.m` | SFA step function |
| `src/algorithms/fractional/mesn_v2_sfa_step_spec.m` | SFA step spec |
| `tests/unit/test_mesn_v2_sfa_step.m` | SFA step tests |

### E3-C3 files to create

| Path | Role |
|---|---|
| `src/algorithms/fractional/FractionalMESN_v2_mechanistic_sfa.m` | SFA-enabled engine |
| `src/algorithms/fractional/validate_fractional_mesn_v2_mechanistic_sfa_config.m` | SFA config validator |
| `src/algorithms/fractional/fractional_mesn_v2_mechanistic_sfa_engine_spec.m` | SFA engine spec |
| `tests/unit/test_fractional_mesn_v2_mechanistic_sfa_engine.m` | SFA engine tests |

### E3-C4 files to create or minimally update

| Path | Role |
|---|---|
| `docs/validation/FRACTIONAL_MESN_V2_SFA_VALIDATION.md` | post-implementation validation record |
| `docs/validation/FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md` | minimal status amendment only |

Any scope expansion beyond the above requires a **new committed preregistration amendment** before implementation begins.

---

## 20. Document traceability

| Field | Value |
|---|---|
| Preregistration schema (engine) | `fractional_mesn_v2_mechanistic_sfa_engine_v1` |
| Preregistration schema (SFA step) | `mesn_v2_sfa_step_v1` |
| Authored at commit | `52348ba06de301a6ae3968004fdef7f6b4da92b3` |
| No-SFA mechanistic engine frozen in | 5D-E3-B2 |
| E2 engine frozen in | 5D-E2 |
| Caputo core frozen in | 5D-E1 |
| Architecture frozen in | 5D-D |
| This document authorises | documentation commit only |
| Implementation authorised by | separate E3-C2/C3/C4 prompts only |
| Amendment policy | any scope change requires a new committed amendment before implementation |
