# Fractional MESN v2 â€” Caputo-L1 Numerical Core Preregistration (Phase 5D-E1)

**Phase:** 5D-E1
**Protocol / schema version:** `fractional_mesn_v2_caputo_l1_core_v1`
**Branch:** `design/fractional-mesn-v2`
**Status:** numerical core **frozen and implemented** as a standalone reference; **not** integrated into `SRNN_ESN`

This document freezes the exact Caputo-L1 operator, semi-implicit algebra, Î±=1 branch, initial-condition convention, causal forcing convention, and deterministic full-history behavior for the v2 numerical core.

Companion architecture decision: [`FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md`](FRACTIONAL_MESN_V2_ARCHITECTURE_DECISION.md).

---

## 1. Scope

**In scope**

- standalone full-history Caputo-L1 reference operators;
- analytic verification tests;
- documentation of exact indexing and algebra.

**Out of scope (this phase)**

- integration into `SRNN_ESN` or any reservoir class;
- STD, SFA, Dale law, or explicit delays;
- truncated history, fast convolution, or approximations;
- scientific Î± selection or default Î±;
- ESP claims;
- reservoir trajectories or learning tasks;
- development / future / calibration / publication seed execution.

---

## 2. Caputo derivative (standard, lower terminal \(t_0\))

For \(0 < \alpha < 1\),

\[
{}^{C}D_{t_0}^{\alpha} x(t)
  =
  \frac{1}{\Gamma(1-\alpha)}
  \int_{t_0}^{t}
  (t-s)^{-\alpha}\, x'(s)\, ds.
\]

**Frozen policy**

| Item | Policy |
|---|---|
| Lower terminal | \(t_0\) |
| Standard IVP for \(0<\alpha<1\) | \(x(t_0)=x_0\) |
| Pre-\(t_0\) fractional-history increments | **not consumed** |
| Explicit synaptic delays | require a **separate** delay-history function on \([t_0-\delta,t_0]\) (future module) |
| Initialized fractional operator with pre-\(t_0\) memory | **different model**; out of scope for core v1 |

---

## 3. Uniform grid and L1 weights

\[
t_n = t_0 + n h.
\]

Weights (for \(0<\alpha<1\)):

\[
w_k(\alpha) = (k+1)^{1-\alpha} - k^{1-\alpha},
\qquad k = 0,\ldots,n-1,
\]

with

\[
w_0 = 1.
\]

The L1 Caputo derivative at \(t_n\) is **normative only for** \(0<\alpha<1\):

\[
D_{\mathrm{L1}}^{\alpha} x_n
  =
  \frac{1}{\Gamma(2-\alpha)\, h^{\alpha}}
  \sum_{k=0}^{n-1}
  w_k \bigl(x_{n-k} - x_{n-k-1}\bigr).
\]

Full history is mandatory. History truncation is forbidden in this reference core.

---

## 4. Standalone reference problem and semi-implicit update

The standalone linear reference problem is

\[
\tau_x^{\alpha}\;{}^{C}D_{t_0}^{\alpha} x(t)
  = -x(t) + d(t),
\]

where \(d(t)\) is an externally supplied **causal** drive.

### 4.1 Forcing convention (frozen)

The numerical forcing used when computing \(x_n\) is

\[
d_{n-1}.
\]

The step may use only drive already available at \(t_{n-1}\). API parameters are named `drive_previous`, not `drive_current`.

### 4.2 Exact algebra

Define

\[
\kappa
  =
  \frac{\tau_x^{\alpha}}{\Gamma(2-\alpha)\, h^{\alpha}}
\]

and

\[
H_n
  =
  \sum_{k=1}^{n-1}
  w_k \bigl(x_{n-k} - x_{n-k-1}\bigr).
\]

Then

\[
\kappa \bigl[(x_n - x_{n-1}) + H_n\bigr]
  = -x_n + d_{n-1}.
\]

Therefore the **exact implementation equation** is

\[
x_n
  =
  \frac{\kappa\, x_{n-1} - \kappa\, H_n + d_{n-1}}{\kappa + 1}.
\]

Special case \(n=1\):

\[
H_1 = 0,
\qquad
x_1
  =
  \frac{\kappa\, x_0 + d_0}{\kappa + 1}.
\]

No future value may appear on the right-hand side.

---

## 5. Alpha = 1 branch (exact, separate)

Do **not** evaluate the fractional weight formula directly at \(\alpha=1\).

Use exact comparison `alpha == 1` and the explicit branch

\[
\tau_x \frac{x_n - x_{n-1}}{h}
  = -x_n + d_{n-1},
\]

hence

\[
x_n
  =
  \frac{(\tau_x/h)\, x_{n-1} + d_{n-1}}{(\tau_x/h) + 1}.
\]

This is:

- backward Euler for the linear leak;
- explicit previous-step forcing;
- the matched integer-order v2 core;
- **not** claimed equal to historical adaptive `ode23s`/`dde23`.

Do not silently map values close to 1 onto the integer branch.

For the weights helper, \(\alpha=1\) may return the limiting sequence \([1,0,0,\ldots]\) via a **dedicated branch**, not by evaluating \(k^{1-\alpha}\).

---

## 6. Stable weight evaluation near \(\alpha=1\)

Let \(p = 1-\alpha\). For \(k\ge 1\), prefer

\[
w_k
  =
  \exp(p\log k)\cdot\operatorname{expm1}\bigl(p\log(1+1/k)\bigr)
\]

rather than subtracting nearly equal powers. Set \(w_0=1\) explicitly. No persistent or global caches.

---

## 7. API shapes and indexing

| Function | Role |
|---|---|
| `fractional_l1_core_spec` | frozen method identity + content hash (no runtime Î±) |
| `caputo_l1_weights(alpha, n_terms)` | column vector \(w_0,\ldots,w_{n_{\mathrm{terms}}-1}\) |
| `caputo_l1_derivative(X, dt, alpha)` | L1 derivative at final sample; rows of `X` are \(x_0,\ldots,x_n\) |
| `caputo_l1_semiimplicit_step(X_history, drive_previous, dt, alpha, tau_x)` | compute \(x_n\) from history \(x_0,\ldots,x_{n-1}\) and \(d_{n-1}\) |
| `simulate_caputo_l1_reference(drive, x0, dt, alpha, tau_x)` | `drive` has \(N\) rows \(d_0,\ldots,d_{N-1}\); `X` has \(N+1\) rows \(x_0,\ldots,x_N\) |

---

## 8. Determinism

- double precision;
- no random numbers in the core;
- no global or persistent caches;
- bitwise-identical replay for identical inputs;
- caller global RNG state must be unchanged.

---

## 9. Analytic verification obligations

See `tests/scientific/test_caputo_l1_analytic.m`:

- constant function â†’ Caputo derivative â‰ˆ 0;
- power function vs exact Gamma formula (away from \(t=0\));
- time-step convergence (smooth power; observed order; no unrealistic \(2-\alpha\) demand under startup singularity);
- fractional relaxation vs `erfcx` Mittagâ€“Leffler identity at \(\alpha=1/2\);
- Î±=1 zero-drive exact discrete geometric decay;
- constant equilibrium \(x_0=c\), \(d\equiv c\) retains \(x_n=c\);
- causality and memory distinction;
- \(\kappa\) scaling \(\tau_x^{\alpha}/dt^{\alpha}\);
- no Symbolic Math Toolbox / third-party Mittagâ€“Leffler dependency.

---

## 10. Known limitations (core v1)

- standalone linear core only;
- \(O(N^2)\) full-history cost;
- not integrated with recurrence / STD / SFA / delays;
- no ESP claim;
- no scientific Î± selected.
