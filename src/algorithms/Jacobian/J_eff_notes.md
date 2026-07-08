# Effective Jacobian and a sufficient condition for the Echo State Property

This note derives the effective Jacobian `J_eff` computed in
[`compute_J_eff.m`](compute_J_eff.m) and uses it to state a sufficient
condition on the adaptation (SFA) and short-term depression (STD) parameters
under which the Membrane Echo State Network (MESN) reservoir contracts, and
therefore satisfies the Echo State Property (ESP). This is the analytical
contribution referenced by Result 1 of the paper workplan.

Notation follows [`SRNN_reservoir.m`](../../SRNN_reservoir.m).

## 1. Reservoir dynamics

State `S = [a_E; a_I; b_E; b_I; x]` with `x` the dendritic potential
(dimension `n`), `a` the (multi-timescale) adaptation variables, and `b` the
presynaptic depression variables (`0 < b <= 1`). Writing `c_i` for the
adaptation scale of neuron `i` (`c_E` for excitatory, `c_I` for inhibitory):

```
x_eff_i = x_i - c_i * sum_k a_{i,k}                     (effective drive)
r_i     = phi(x_eff_i)                                  (firing rate)
s_j     = b_j * r_j                                     (depressed output)
tau_d dx_i/dt = -x_i + sum_j W_ij s_j + u_i
      da_{i,k}/dt = (r_i - a_{i,k}) / tau_{a,k}
      db_i/dt = (1 - b_i)/tau_rec - b_i r_i / tau_rel
```

`phi` is the piecewise sigmoid ([`piecewiseSigmoid.m`](../../nonlinearities/piecewiseSigmoid.m))
with range `[0,1]` and, crucially, a bounded derivative

```
0 <= phi'(z) <= 1,      with phi'(z) = 1 only on the central linear band
                        and phi'(z) -> 0 as |z - c| grows (saturation).
```

## 2. Effective Jacobian of the fast (x) subsystem

The adaptation and depression variables evolve on slow timescales
(`tau_{a,k}`, `tau_rec`, `tau_rel` are large relative to `tau_d`). Freezing
`a` and `b` at their current values (a quasi-static / singular-perturbation
reduction) leaves the fast `x`-subsystem

```
tau_d dx/dt = -x + W (b .* phi(x_eff)) + u,     x_eff = x - C a_sum
```

Differentiating with respect to `x` (with `a`, `b` frozen, and noting
`d x_eff_i / d x_j = delta_ij`):

```
d/dx_j [ (W (b .* phi(x_eff)))_i ] = W_ij b_j phi'(x_eff_j)
```

so, with `g_j = b_j phi'(x_eff_j)` and `G = diag(g)`,

```
J_eff(x,a,b) = (1/tau_d) * ( -I + W G ).            (Eq. J_eff)
```

This is exactly the matrix assembled in `compute_J_eff.m`, line 136, and it is
the `dx/dt`-by-`x` diagonal block of the full state Jacobian assembled in
[`compute_Jacobian.m`](compute_Jacobian.m) (Block 9). The
[`verifyJacobianConsistency.m`](../../../scripts/verifyJacobianConsistency.m)
script checks this identity numerically.

### Why the reduction is legitimate for ESP

The full Jacobian is block-triangular-dominant: the `a` and `b` rows have
diagonal entries `-1/tau_{a,k}`, `-(1/tau_rec + r/tau_rel)`, which are
strictly negative and bounded away from zero, while their coupling back into
`x` is `O(c)` and `O(1/tau_rel)`. When `tau_{a,k}, tau_rec >> tau_d` the slow
variables cannot destabilise the fast subsystem on their own; the contraction
of the coupled system is governed, to leading order, by `J_eff`. A rigorous
version uses the coupled logarithmic-norm bound in Section 5.

## 3. Contraction implies the Echo State Property

Two trajectories `x(t)`, `x'(t)` of the same driven reservoir obey, for their
difference `e = x - x'`,

```
tau_d de/dt = -e + W ( g .* e ) + higher-order,
```

whose instantaneous linear part is `J_eff`. If there is a constant `nu > 0`
and a vector norm `||.||` with matrix measure (logarithmic norm) `mu` such that

```
mu( J_eff(x,a,b) ) <= -nu   for all reachable (x,a,b),           (C)
```

then `d/dt ||e|| <= -nu ||e||`, so `||e(t)|| <= e^{-nu t} ||e(0)|| -> 0`.
Input-driven trajectories from different initial conditions converge: this is
the (uniform, state-contracting) Echo State Property. Condition (C) is what we
now translate into parameter constraints. It is verified empirically by
[`verify_echo_state_property.m`](../../stability/verify_echo_state_property.m).

## 4. Sufficient conditions on adaptation and depression

Use the logarithmic norm induced by the 2-norm,
`mu_2(A) = lambda_max( (A + A^T)/2 )`. From (Eq. J_eff),

```
mu_2(J_eff) = (1/tau_d) * ( -1 + lambda_max( (WG + (WG)^T)/2 ) )
           <= (1/tau_d) * ( -1 + || W G ||_2 )
           <= (1/tau_d) * ( -1 + ||W||_2 * max_j g_j ).
```

Because `g_j = b_j phi'(x_eff_j)`, `0 <= b_j <= 1`, and `0 <= phi'(<=) 1`,

```
max_j g_j <= (max_j b_j) * (max_z phi'(z)) <= 1.
```

Hence a **sufficient condition for the ESP** is

```
||W||_2 * g_max < 1,     with   g_max = max_j b_j phi'(x_eff_j).     (ESP*)
```

Equivalently, the contraction rate is `nu = (1 - ||W||_2 g_max)/tau_d`.

### How SFA and STD each tighten (ESP*)

Both biological mechanisms reduce `g_max`, i.e. they shrink the effective gain
that `||W||` acts on:

1. **STD (`b`)**: depression pulls `b_j` below 1 whenever the neuron is active
   (`db/dt < 0` once `b r / tau_rel > (1-b)/tau_rec`). Its quasi-static value
   under sustained rate `r` is

   ```
   b_inf(r) = (1/tau_rec) / (1/tau_rec + r/tau_rel) = tau_rel / (tau_rel + r tau_rec).
   ```

   So a larger `tau_rec/tau_rel` ratio (stronger, slower-recovering depression)
   directly lowers `b_inf` and therefore `g_max`. This is the mechanism behind
   the meeting note "STD helps it come back to normal": depression is a
   negative feedback on the effective gain that restores contraction after a
   perturbation drives rates up.

2. **SFA (`a`, `c`)**: adaptation lowers `x_eff = x - c sum_k a_k`. For the
   piecewise sigmoid, `phi'` is maximal on the central band and decays into
   saturation, so pushing `x_eff` away from the high-slope region reduces
   `phi'(x_eff)` and hence `g_max`. The quasi-static adaptation is
   `a_k^inf = r`, giving an effective self-inhibition `c * n_a * r` that scales
   with the adaptation strength `c` and the number of timescales `n_a`.

Combining, a conservative closed form that guarantees (ESP*) for all reachable
states is

```
||W||_2 * max_i [ b_i^inf(r_i) * phi'( x_i - c_i n_{a,i} r_i ) ] < 1.
```

Because `||W|| = level_of_chaos * ||gamma W0||` in
[`default_MESN_config.m`](../../../src/configs/default_MESN_config.m), this
predicts an ESP boundary in the `(level_of_chaos, adaptation-strength)` plane:
for a given spectral scaling of `W`, there is a minimum SFA/STD strength above
which `g_max` is small enough for (ESP*) to hold. This is the "wouldn't it be
nice if the ESP always appears after a certain adaptation" statement, made
precise and testable.

### Remarks and sharper variants

- (ESP*) uses `||W||_2` (the largest singular value), which for a **non-normal**
  Dale-structured `W` can substantially exceed the spectral radius. The gap
  between `||W||_2` and `rho(W)` is exactly the non-normality quantified by the
  Kreiss-constant / departure-from-normality metrics of Result 2, and it makes
  (ESP*) a conservative (sufficient, not necessary) bound. A tighter,
  non-conservative test replaces `||W||_2 g_max < 1` with the direct spectral
  abscissa `alpha(J_eff) < 0`, i.e. `max Re eig(-I + WG) < 0`.
- The bound is uniform over the input only through the reachable set of
  `x_eff`; a bounded input `|u| <= u_max` bounds `x` (since `dx/dt` is
  dissipative for `-x`), which bounds `x_eff` and hence closes the argument.

## 5. Coupled (non-quasi-static) statement

Without freezing `a`, `b`, contraction of the full system holds if the
measure of the full Jacobian `J` (assembled in `compute_Jacobian.m`) is
negative. A block bound in a weighted 2-norm `||.||_P`, `P = diag(p_x I, p_a I,
p_b I)`, gives contraction when, in addition to (ESP*),

```
1/tau_{a,k} > 0,   1/tau_rec + r/tau_rel > 0   (always true),
```

and the slow->fast couplings (`O(c/tau_d)` from `a`, `O(1/tau_d)` from `b`) are
dominated by the fast contraction margin `nu`. Choosing the timescale
separation `tau_{a,k}, tau_rec >> tau_d` makes the off-diagonal Gershgorin
contributions arbitrarily small relative to the negative diagonal, recovering
(C) for the full system. The empirical Lyapunov sweep (Result 2) measures the
resulting largest exponent directly and is expected to approach zero from below
as adaptation is increased, consistent with the contraction margin `nu`
shrinking to the edge of chaos.

## 6. What to report in the paper

- Figure: ESP phase diagram in `(level_of_chaos, c_E)` (and STD) with the
  analytical boundary `||W||_2 g_max = 1` overlaid on the empirical
  `esp_holds` region produced by
  [`run_esp_phase_diagram.m`](../../../scripts/run_esp_phase_diagram.m).
- Statement of Proposition (ESP*) with the two-line contraction proof of
  Section 3 and the gain-reduction argument of Section 4.
- Discussion that the bound is conservative precisely by the non-normality of
  `W`, linking Result 1 to the Kreiss analysis of Result 2.
