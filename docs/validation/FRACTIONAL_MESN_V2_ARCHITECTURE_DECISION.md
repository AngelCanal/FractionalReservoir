# Fractional MESN v2 â€” Architecture Decision (Phase 5D-D)

**Phase:** 5D-D (architecture freeze) + **5D-E1 amendment** (Â§20)
**Branch:** `design/fractional-mesn-v2`
**Source SHA (5D-D freeze):** `579a935044e818a36a86cd0a9cc211142ec6d071`
**Status:** mathematical architecture **frozen** (5D-D); Caputo-L1 **standalone numerical core** implemented and verified (5D-E1); **not** integrated into `SRNN_ESN`
**Companion review:** [`TEMPORAL_MEMORY_DIAGNOSTIC_SCIENTIFIC_REVIEW.md`](TEMPORAL_MEMORY_DIAGNOSTIC_SCIENTIFIC_REVIEW.md)
**Numerical core preregistration:** [`FRACTIONAL_MESN_V2_NUMERICAL_CORE_PREREGISTRATION.md`](FRACTIONAL_MESN_V2_NUMERICAL_CORE_PREREGISTRATION.md)

This document freezes the recommended Fractional MESN v2 equations, numerical definition, claim boundary, and validation obligations. Phase 5D-D itself did not implement code. Phase 5D-E1 (Â§20) freezes and implements only the standalone Caputo-L1 reference core. It does **not** alter v1 artifacts or authorize future-seed execution.

---

## 1. Scientific objective

Correct the Phase 5D-C scientific diagnosis and freeze a v2 architecture that can:

1. host a **genuine Caputo fractional derivative** in the neuronal/reservoir state equation;
2. retain modular **STD**, **SFA**, **Dale law**, and **explicit delays** without conflating them with fractionality;
3. admit a matched **Î±=1** control inside the **same discrete v2 architecture**;
4. support identifiable development work on already-consumed seeds only;
5. define what may and may not be claimed as â€œfractional.â€

The motivating deficit from 5D-C (corrected in the companion review) is **insufficient effective recurrent memory** under the frozen non-fractional MESN, together with **common-mode / redundant feature geometry** â€” not â€œabsence of recurrence,â€ and not a raw-PR-only â€œreadout collapse.â€

---

## 2. Current v1 equation audit

**Confirmed:** the implemented system is **integer-order and non-fractional**. Multi-timescale exponential SFA is **not** fractional dynamics.

### 2.1 Continuous-time equations (as implemented)

Neurons \(i=1,\ldots,n\); excitatory set \(E\), inhibitory set \(I\).

**Effective input and rate**

\[
q_i = x_i - \sum_{m} c_{a,m}^{(E/I)}\, a_{i,m},
\qquad
r_i = \phi(q_i)
\]

(`compute_effective_q` + `piecewiseSigmoid`).

**Presynaptic STD resource** \(b_i\in[0,1]\) (implicit \(b_i\equiv 1\) if STD off):

\[
s_i = b_i\, r_i.
\]

**Membrane / reservoir ODE** (`SRNN_reservoir.m`):

\[
\tau_d\,\dot x_i
  = -x_i
    + \sum_j W_{ij}\, b_j\, r_j
    + u_i(t),
\qquad
u(t)=W_{\mathrm{in}}U(t).
\]

**DDE mode** (scalar inhibitory delay \(\delta\); E columns instant, I columns delayed):

\[
\tau_d\,\dot x_i
  = -x_i
    + \sum_j W^{\mathrm{inst}}_{ij}\, b_j(t)\, r_j(t)
    + \sum_j W^{\mathrm{del}}_{ij}\, b_j(t-\delta)\, r_j(t-\delta)
    + u_i(t).
\]

**SFA (integer-order)**

\[
\tau_{a,m}\,\dot a_{i,m} = r_i - a_{i,m}.
\]

**STD (integer-order, presynaptic)**

\[
\dot b_i
  = \frac{1-b_i}{\tau^{\mathrm{rec}}_{b}}
    - \frac{b_i\, r_i}{\tau^{\mathrm{rel}}_{b}}.
\]

SFA/STD always use **current** \(r(t)\), even in DDE mode.

### 2.2 Variable ledger (summary)

| Symbol | MATLAB | Dim | Role | Readout? |
|---|---|---|---|---|
| \(x\) | `state.x` | \(n\) | membrane / reservoir state | if `which_states='x'` |
| \(a_E,a_I\) | `state.a_*` | pop Ã— filters | SFA adaptation | only if `'all'` |
| \(b_E,b_I\) | `state.b_*` | pop | STD resource (presynaptic) | only if `'all'` |
| \(q\) | computed | \(n\) | SFA-adjusted drive | no |
| \(r\) | computed | \(n\) | firing rate \(\phi(q)\) | if `which_states='r'` |
| \(W\) | `params.W` | \(n\times n\) | Dale-constrained recurrent | no |
| \(W_{\mathrm{in}}\) | `params.W_in` | \(n\times n_{\mathrm{in}}\) | input weights | no |
| \(\tau_d\) | `params.tau_d` | scalar (s) | membrane time constant | no |
| \(\delta\) | `params.lags` | scalar (s) | I-column delay | no |

Packed state: \(S=[a_E(:);a_I(:);b_E(:);b_I(:);x(:)]\).

Dale: presynaptic columns \(W_{:,E}\ge 0\), \(W_{:,I}\le 0\). Recurrent scaling: spectral **abscissa** to `level_of_chaos` (frozen diagnostic OP: 0.60). Integrators: `ode23s` / `dde23`.

**Critical STD convention:** recurrent term is \(W(b\odot r)\) â€” **presynaptic** resource on source rates â€” not postsynaptic gain on the summed input.

**Adaptation placement:** SFA enters **through** \(q=x-\sum c_a a\), not as a separate additive current on the \(x\)-RHS. The v2 freeze must preserve that convention unless a separately justified change is introduced later (listed under unresolved decisions).

---

## 3. Architecture option matrix

| Criterion | A. Readout/feature-only | B. Integer recurrent-gain repair | C. Fractional readout/post only | D. Fractional neuronal state (selected) |
|---|---|---|---|---|
| Scientific validity for â€œfractional ESNâ€ | low | N/A (non-fractional) | **insufficient** | **high** |
| Reservoir genuinely fractional? | no | no | **no** | **yes** |
| Recover Î±=1? | N/A | baseline | N/A | **yes (matched discrete)** |
| Compatible with STD | yes | yes | yes | **yes (keep integer-order)** |
| Compatible with SFA | yes | yes | yes | **yes (keep integer-order)** |
| Compatible with delays | yes | yes | yes | **yes (keep explicit)** |
| Computational cost | low | lowâ€“med | low | **high (history)** |
| Stability / ESP burden | low | medium | low | **high (Volterra memory)** |
| Confounding risk | medium (geometry only) | medium | **high (mislabeling)** | manageable if Î±=1 matched |
| Paper contribution suitability | weak alone | strong as **control** | **reject as fractional claim** | **primary estimand** |

### Option assessments

- **A.** `x` vs `r` was directionally consistent but **below materiality**. Ridge already standardizes; rawâ†’standardized PR remains â‰ˆ2 with high correlations, so whitening/PCA might help geometry but cannot by themselves supply the missing memory depth versus the conventional ESN. Insufficient as the sole v2 answer to a fractional-architecture program.
- **B.** Still needed as a **matched integer-order control / repair track** (recurrent gain, Dale-consistent Jacobian calibration, E/I balance, anti-synchrony). Does not create fractionality. Should proceed in parallel conceptually, but the fractional estimandâ€™s primary control is Î±=1 of **v2**, not historical v1 ODE.
- **C.** Fractional filtering of outputs or fractional readout operators does **not** make the reservoir fractional. **Rejected** as sufficient for a fractional-ESN claim.
- **D.** Place a Caputo derivative on \(x\) with common Î±. Keep STD/SFA/delays modular and integer-order. Selected.

---

## 4. Selected architecture

**Selected: Option D â€” Fractional neuronal/reservoir state equation (Caputo), common order Î±, modular integer-order STD/SFA/delays, Dale law retained.**

Initial policy: **one shared** \(\alpha\) with \(0<\alpha\le 1\). Neuron-specific Î± values are **out of scope** for the first freeze (identifiability / multiplicity).

---

## 5. Exact continuous-time equations (frozen candidate)

Reconciled with the audited v1 signs and STD/SFA placement.

### 5.1 Fractional membrane equation

For each neuron \(i\),

\[
\tau_x^{\alpha}\;{}^{C}D_{t}^{\alpha} x_i(t)
  = -x_i(t)
    + I_{\mathrm{rec},i}(t)
    + I_{\mathrm{in},i}(t).
\]

Here \({}^{C}D_{t}^{\alpha}\) is the **Caputo** derivative of order \(\alpha\).
\(\tau_x>0\) has time units; \(\tau_x^{\alpha}\) supplies dimensional consistency so the RHS remains in the same units as \(x\).

**Note on adaptation.** There is **no** separate \(-I_{\mathrm{adapt}}\) on the \(x\)-RHS in v1. Adaptation remains inside the rate map (Â§5.2). Do not silently move SFA onto the linear \(x\)-current without a new justified design revision.

### 5.2 Rate map, SFA, STD (integer-order auxiliaries)

\[
q_i(t)=x_i(t)-\sum_{m=1}^{n_a(i)} c_{a,m}\,a_{i,m}(t),
\qquad
r_i(t)=\phi\bigl(q_i(t)\bigr),
\]

\[
\tau_{a,m}\,\frac{d a_{i,m}}{dt}=r_i(t)-a_{i,m}(t),
\]

\[
\frac{d b_j}{dt}
  =\frac{1-b_j}{\tau^{\mathrm{rec}}_{b}}
   -\frac{b_j\, r_j}{\tau^{\mathrm{rel}}_{b}},
\qquad b_j\in[0,1].
\]

### 5.3 Recurrent and input terms (presynaptic STD; Dale \(W\))

**ODE (no delay) candidate**

\[
I_{\mathrm{rec},i}(t)=\sum_{j=1}^{n} W_{ij}\, b_j(t)\, r_j(t),
\qquad
I_{\mathrm{in},i}(t)=\bigl[W_{\mathrm{in}}U(t)\bigr]_i.
\]

**DDE candidate** (match v1: E instant, I delayed by scalar \(\delta\))

\[
I_{\mathrm{rec},i}(t)
  =\sum_{j\in E} W_{ij}\, b_j(t)\, r_j(t)
   +\sum_{j\in I} W_{ij}\, b_j(t-\delta)\, r_j(t-\delta).
\]

### 5.4 Symbol freeze

| Symbol | Meaning | MATLAB / config field (v1 analog) | Notes |
|---|---|---|---|
| \(x_i\) | neuronal / reservoir state | `state.x` | fractional state |
| \(r_i\) | firing-rate / nonlinear output | computed | readout candidate |
| \(W_{ij}\) | Dale-constrained recurrent weight | `params.W` | fixed per seed |
| \(b_j\) / \(q_j^{\mathrm{std}}\) | STD resource | `state.b_*` | **presynaptic** factor; not postsynaptic |
| \(a_{i,m}\) | SFA component \(m\) | `state.a_*` | integer-order |
| \(\delta\) | inhibitory recurrent delay | `params.lags` | scalar seconds |
| \(W_{\mathrm{in}}\) | input weights | `params.W_in` | masked |
| \(\alpha\) | Caputo order | **new** | common; \(0<\alpha\le 1\) |
| \(\tau_x\) | membrane time constant | `params.tau_d` (v1 name) | enter as \(\tau_x^{\alpha}\) |
| history | initial function on \([t_0-\Delta,t_0]\) | **new** | Caputo IC convention |

### 5.5 Why this separation is preferred

- The reservoir is genuinely fractional **through \(x\)**.
- SFA remains a sum of exponential adaptation processes.
- STD remains a synaptic resource mechanism.
- Delays remain explicit propagation delays.
- Fractional power-law memory is **not** conflated with SFA/STD/DDE.

---

## 6. Numerical Caputo definition (frozen)

### 6.1 Primary candidate: causal uniform-step L1

On grid \(t_n=t_0+n\Delta t\),

\[
{}^{C}D_{t}^{\alpha}x(t_n)
  \approx
  \frac{1}{\Gamma(2-\alpha)\,(\Delta t)^{\alpha}}
  \sum_{k=0}^{n-1}
  a_k\bigl(x_{n-k}-x_{n-k-1}\bigr),
\]

\[
a_k=(k+1)^{1-\alpha}-k^{1-\alpha}.
\]

### 6.2 Recommended stability-oriented update

Let \(L_n\) denote the L1 memory sum using **already computed** increments through \(x_n-x_{n-1}\) arranged so that \(x_n\) appears only through the \(k=0\) term (standard L1 rearrangement).

**Policy (frozen intent):**

1. Treat the **linear leak** \(-x\) **semi-implicitly** at time \(t_n\).
2. Treat nonlinear recurrent / input / adaptation drives **causally** from states available at \(t_n\) or earlier (never future).
3. Recurrent rates: use \(r_j\) consistent with the same causal index as v1 discrete intent (instant E; delayed I via indexed history).
4. STD/SFA: advance with integer-order causal discretizations using \(r\) at the declared index (prefer values already available before or at \(t_n\) under the semi-implicit split).
5. Explicit delays: index by nearest grid samples; **linear interpolation** for non-integer \(\delta/\Delta t\); interpolation policy must be fingerprinted.
6. **Never silently truncate** fractional history in the reference implementation.
7. Deterministic replay required; no global RNG mutation during stepping.

Schematic semi-implicit leak form (exact algebraic rearrangement to be locked in implementation phase):

\[
\bigl(\tau_x^{\alpha} c_{\alpha,\Delta t} + 1\bigr) x_n
  =
  \tau_x^{\alpha} c_{\alpha,\Delta t}\,(\text{memory terms without }x_n)
  + I_{\mathrm{rec},n}^{\mathrm{causal}}
  + I_{\mathrm{in},n}
\]

with \(c_{\alpha,\Delta t}=1/(\Gamma(2-\alpha)(\Delta t)^{\alpha})\).

### 6.3 History policy

- Caputo initial condition: prescribe \(x(t_0)\) and, for the discrete convolution, a history of increments from an initial function \(\psi\) on a declared prehistory interval when delays and/or startup require it.
- Constant-state Caputo derivative is zero; constant history must reproduce that.
- Full-history L1 is the **reference**.
- Any short-memory / accelerated approximation, if added later, must be labeled an approximation, fingerprint truncation length, and demonstrate agreement vs full history.

### 6.4 Complexity and precision

| Item | Full-history L1 |
|---|---|
| Time cost | \(O(N_t)\) steps Ã— \(O(n)\) neurons Ã— \(O(N_t)\) history â‡’ \(O(n N_t^2)\) dominant term |
| Memory | store \(x\)-history length \(N_t\) (and delay buffers for \(r,b\)) |
| Precision | floating-point double; deterministic |
| Delays | \(O(1)\) indexed/interpolated reads per edge class |

### 6.5 Î±=1 limit (matched control)

At \(\alpha=1\), Caputo reduces to the ordinary derivative and L1 weights beyond the immediate increment vanish in the classical sense, recovering a declared **matched integer-order discrete scheme** on the same grid, same \(W\), \(W_{\mathrm{in}}\), STD/SFA/delay modules, and readout rules.

**Primary matched control for the fractional estimand:**
same v2 discrete architecture at \(\alpha=1\).

**Do not** claim exact equivalence to the historical v1 adaptive `ode23s`/`dde23` path unless separately demonstrated. Historical v1 remains a secondary reference, not the principal Î±=1 control.

---

## 7. Alpha=1 matched control

Matched fields between Fractional MESN (\(\alpha<1\)) and v2-\(\alpha=1\):

- \(W\), \(W_{\mathrm{in}}\), Dale signs
- network size \(n\)
- input sequence \(U(t)\)
- STD on/off and parameters
- SFA on/off and parameters
- delays on/off and \(\delta\)
- feature representation (`r` or `x`)
- readout dimension and Î» protocol
- train/validation/test splits
- activity-range / operating-point policy (explicitly declared)

Avoid â€œall changes at onceâ€ contrasts between historical v1 ODE MESN and a new fractional implementation.

---

## 8. STD / SFA / delay integration

| Mechanism | Order in v2 | Role |
|---|---|---|
| Caputo on \(x\) | fractional | long-memory reservoir state |
| SFA \(a\) | integer-order ODEs | exponential adaptation bank |
| STD \(b\) | integer-order ODEs | presynaptic resource in \([0,1]\) |
| Delays | explicit DDE indexing | I-column propagation delay |

Default: **do not fractionalize** SFA or STD unless a future document separately justifies it.

---

## 9. Initialization / history

1. Declare initial time \(t_0\) and Caputo initial state \(x(t_0)=x_0\).
2. Declare initial SFA/STD: follow v1 paired/weighted policy unless changed under a fingerprinted revision.
3. For delays: provide history of \((r,b)\) on \([t_0-\delta,t_0]\).
4. For L1: provide the discrete increment history implied by the initial function; constant extension of \(x_0\) is the default startup unless otherwise fingerprinted.
5. Washout policy must be restated for fractional startup (history effects persist).

---

## 10. Units and dimensions

| Quantity | Implied units |
|---|---|
| \(t\), \(\tau_x\), \(\tau_a\), \(\tau_b\), \(\delta\) | seconds |
| \(x\), \(q\), \(u\) | consistent drive units |
| \(r\), \(b\), \(c_a\) | dimensionless (rates in \([0,1]\); resources in \([0,1]\)) |
| \(W\), \(W_{\mathrm{in}}\) | map driveâ†’drive |
| \(\alpha\) | dimensionless |
| \(\tau_x^{\alpha}\,{}^{C}D_t^{\alpha}x\) | same units as \(x\) |

Dimensional check: LHS and RHS of the membrane equation share units.

---

## 11. Computational complexity

See Â§6.4. Development work may use short trajectories; any production claim comparing Î± must either use full history or a disclosed, validated truncation.

---

## 12. Stability / ESP requirements

Classical integer-order ESP (spectral radius / contraction of a Markovian map) is **not** sufficient for fractional Volterra memory.

Required:

- distinguish Markovian ESP from fractional fading-memory / contraction in history space;
- state a sufficient stability/contraction condition or clearly label empirical-only status;
- empirical convergence from distinct initial state/**history** functions;
- perturb complete fractional histories, not only instantaneous \(x\);
- report convergence versus physical time;
- **do not** claim ESP from spectral radius alone.

---

## 13. Analytic verification suite (frozen; not implemented here)

1. Constant function: \({}^{C}D_t^{\alpha} c=0\).
2. Power function: \({}^{C}D_t^{\alpha} t^{\beta}=\Gamma(\beta+1)/\Gamma(\beta+1-\alpha)\, t^{\beta-\alpha}\).
3. Fractional relaxation \({}^{C}D_t^{\alpha}x=-\lambda x\) vs Mittagâ€“Leffler solution.
4. Î±=1 limit vs declared matched integer-order scheme.
5. Time-step convergence under \(\Delta t\) refinement.
6. Full-history vs truncated/accelerated agreement (when approx exists).
7. Zero-input equilibrium.
8. Deterministic replay.
9. No global RNG mutation.
10. State packing/unpacking round trip.
11. Delay indexing and interpolation.
12. STD resource remains in \([0,1]\).
13. SFA states remain finite.
14. Dale-law signs remain exact.
15. Readout fit/test isolation.

---

## 14. What counts as â€œproperly fractionalâ€

The architecture may be called fractional only if **all** hold:

1. A reservoir state equation contains a fractional derivative with \(0<\alpha<1\).
2. The numerical update contains the corresponding causal power-law history convolution.
3. Constant-state Caputo derivatives are zero.
4. The implementation retains the declared initial-condition convention.
5. The Î±=1 limit is verified against the matched discrete scheme.
6. Reducing history changes the approximation and is disclosed.
7. Fractional order affects **internal dynamics**, not merely readout filtering.
8. Stability and empirical state convergence are tested for the fractional implementation.
9. Fractional vs Î±=1 comparisons use matched weights, inputs, dimensions, mechanisms, and readout rules.

**Rejected as sufficient fractionality:** multiple SFA timescales alone; synaptic delays alone; STD alone; power-law fit to outputs; fractional filtering after readout; merely naming the architecture fractional.

---

## 15. Scientific comparisons for v2

**Principal estimand**

\[
\text{matched Fractional MESN }(\alpha<1)
\quad\text{vs}\quad
\text{same v2 architecture at }\alpha=1.
\]

**Additional controls**

- conventional leaky ESN
- current-input-only
- no-recurrent coupling
- shuffled target
- exact history
- mechanisms-off
- fractional without STD
- fractional without SFA
- fractional without delays

---

## 16. Development-versus-future seed policy

Architecture development may continue using **only** already-consumed development roles:

| Role | Seeds |
|---|---|
| Model | `[1729, 2718, 31415]` |
| Task | `12001 / 12002 / 12003` |
| Shuffle | `12101 / 12102 / 12103` |

**Do not use**

| Role | Seeds |
|---|---|
| Future v2 gate model | `[11003, 11027, 11047, 11057, 11069]` |
| Future v2 gate task | `13001 / 13003 / 13007` |
| Future v2 shuffle | `13101 / 13103 / 13107` |
| Future v2 calibration | `[14009, 14011]` |
| Future v2 full publication | `[10037, 10039, 10061, 10067, 10069, 10079, 10091, 10093, 10099, 10103, 10111, 10133, 10139, 10141, 10151, 10159, 10163, 10169, 10177, 10181, 10193, 10211, 10223, 10243, 10247, 10253, 10259, 10267, 10271, 10273]` |

Future seeds remain untouched until: equations frozen (this document); implementation tests pass; development tuning complete; v2 gate preregistered; v2 operating-point calibration frozen.

Authority: [`SEED_ROLE_LEDGER.md`](SEED_ROLE_LEDGER.md).

---

## 17. Permitted and forbidden claims

**Permitted (after implementation + verification)**

- â€œCaputo fractional MESN of common order Î± with integer-order SFA/STD and explicit delays.â€
- Matched Î±<1 vs Î±=1 comparisons under the frozen protocol.
- Claims that the reservoir is fractional **only** when Â§14 is satisfied.

**Forbidden**

- Calling v1 / multi-SFA / STD / DDE â€œfractional.â€
- Claiming fractionality from readout-only filters (Option C).
- Claiming empirical necessity of Î±â‰ 1 solely from the conventional ESN gap in 5D-C.
- Using development diagnostics as publication evidence.
- Executing reserved future seeds during architecture bring-up.

---

## 18. Unresolved architectural decisions

Deferred to later design/implementation phases (not blockers for this freeze of the **form** of the equations):

1. Whether default readout remains `r` or switches to `x` under a fingerprinted policy.
2. Nonlinear recurrent integration into the verified Caputo-L1 core (drive construction from \(W\), \(r\), Dale \(W\)).
3. Auxiliary SFA/STD integration with the fractional \(x\)-step (integer-order auxiliaries; causal index for \(r\)).
4. Whether a parallel integer-order recurrent-gain repair (Option B) is calibrated before or alongside first Î± sweeps.
5. Operating-point recalibration policy for v2 (must not silently reuse sealed v1 gate authority).
6. Discrete delay interpolation order (linear frozen as default intent; higher-order needs justification) and delay-history module on \([t_0-\delta,t_0]\).
7. Optional fast convolution / hierarchical memory **as disclosed approximation only**.
8. Whether \(\tau_x^{\alpha}\) is written with a fixed \(\tau_x=\tau_d\) or a reparameterized Ï„(Î±).

**Resolved by Phase 5D-E1** (see Â§20): exact L1 causal algebra / semi-implicit coefficients; core forcing index \(d_{n-1}\); Î±=1 branch; Caputo lower-terminal / no pre-\(t_0\) fractional history; full-history mandate.

---

## 19. Explicit statement: Phase 5D-D produced documentation only

Phase 5D-D produced **documentation only** at its freeze:

- no MATLAB source or test code for fractional dynamics at that time;
- no new reservoir trajectories;
- no readout refits;
- no future-v2 seed execution;
- no modification of the completed 5D-C run;
- no modification of `temporal_learning_gate_v1` or sealed v1 artifacts.

Phase 5D-E1 subsequently implements the **standalone** Caputo-L1 numerical reference core and analytic tests only (see Â§20). It does **not** integrate the core into `SRNN_ESN`.

---

## 20. Phase 5D-E1 amendment â€” Caputo-L1 numerical core freeze

**Phase:** 5D-E1
**Protocol / schema:** `fractional_mesn_v2_caputo_l1_core_v1`
**Preregistration:** [`FRACTIONAL_MESN_V2_NUMERICAL_CORE_PREREGISTRATION.md`](FRACTIONAL_MESN_V2_NUMERICAL_CORE_PREREGISTRATION.md)

This amendment **does not delete** Phase 5D-D history. It resolves previously deferred numerical items for the **standalone linear reference core**.

### 20.1 Exact semi-implicit algebra (resolved)

Standalone problem:

\[
\tau_x^{\alpha}\;{}^{C}D_{t_0}^{\alpha} x(t) = -x(t) + d(t).
\]

With

\[
\kappa = \frac{\tau_x^{\alpha}}{\Gamma(2-\alpha)\, h^{\alpha}},
\qquad
H_n = \sum_{k=1}^{n-1} w_k\bigl(x_{n-k}-x_{n-k-1}\bigr),
\]

\[
x_n = \frac{\kappa\, x_{n-1} - \kappa\, H_n + d_{n-1}}{\kappa + 1},
\qquad
H_1 = 0.
\]

### 20.2 Core forcing index (resolved)

Core forcing uses \(d_{n-1}\) only (API: `drive_previous`). No future drive on the RHS.

### 20.3 Alpha = 1 branch (resolved)

Exact `alpha == 1` branch (backward Euler leak, explicit previous drive):

\[
x_n = \frac{(\tau_x/h)\, x_{n-1} + d_{n-1}}{(\tau_x/h) + 1}.
\]

Not claimed equal to historical `ode23s`/`dde23`.

### 20.4 Caputo memory / initial condition (resolved)

- Lower terminal is \(t_0\).
- Standard IVP uses \(x(t_0)=x_0\).
- **No** pre-\(t_0\) fractional history in core v1.
- Delay prehistory on \([t_0-\delta,t_0]\) remains a **separate future module**.
- Full history is mandatory; truncation forbidden in the reference core.

### 20.5 Time-step convergence (resolved policy)

Convergence claims must account for startup regularity. Do not impose unrealistic \(2-\alpha\) rates on solutions with startup singularities; require monotonic error decrease under refinement for smooth tests and document observed order.

### 20.6 Still unresolved (carry forward)

- \(r\) versus \(x\) readout;
- nonlinear recurrent integration;
- auxiliary SFA/STD integration;
- delay interpolation / delay-history module;
- operating-point recalibration;
- gain-repair strategy;
- accelerated memory approximations.

### 20.7 Integration boundary

Phase 5D-E1 implements only:

`src/algorithms/fractional/*` + unit/analytic tests + this amendment + the preregistration document.

`SRNN_ESN.m` and existing ODE/DDE scientific behavior remain unchanged.

**Next phase:** Phase 5D-E2 â€” integrate the verified core into an isolated Fractional MESN v2 class with matched Î±=1 dynamics, without scientific tuning.
