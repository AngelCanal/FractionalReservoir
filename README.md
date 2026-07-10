# Membrane Echo State Network (MESN)

A biologically-inspired Echo State Network (ESN) built on a rate-coded spiking reservoir with:

- **Spike-frequency adaptation (SFA)** — multi-timescale adaptation currents for E and I populations
- **Short-term synaptic depression (STD)** — presynaptic depletion dynamics
- **Dale's law** — strict excitatory/inhibitory separation
- **Synaptic delay (DDE mode)** — one scalar inhibitory delay (vector delays unsupported)

See [Current mathematical support and validation status](docs/validation/SUPPORT_MATRIX.md) for supported modes and validation gates.

This branch is a minimal, publication-ready codebase for hyperparameter tuning and analysis.

---

## Quick Start

Open MATLAB, navigate to this repository, then:

```matlab
% 1. Add all source files to the path
run('scripts/setup_paths.m');

% 2. Run the main dynamics exploration script
run('test_reservoir_dynamics.m');
```

---

## Repository Structure

```
.
├── test_reservoir_dynamics.m      # Main entry point — dynamics & Jacobian analysis
├── scripts/
│   └── setup_paths.m              # Adds src/ to MATLAB path
└── src/
    ├── SRNN_ESN.m                 # ESN wrapper class (training, prediction, feature extraction)
    ├── SRNN_reservoir.m           # ODE reservoir dynamics (ode23s solver)
    ├── SRNN_reservoir_DDE.m       # DDE reservoir dynamics (dde23 solver)
    ├── compute_metrics.m          # MSE / NRMSE metrics
    ├── clear_SRNN_persistent.m    # Clears persistent interpolant between runs
    ├── algorithms/
    │   └── Jacobian/
    │       ├── compute_Jacobian_at_indices.m   # Jacobian at trajectory timepoints
    │       └── compute_Jacobian_fast.m         # Sparse/vectorised Jacobian assembly
    ├── generate_stimulus/
    │   └── generate_mackey_glass.m             # Mackey-Glass chaotic input generator
    ├── nonlinearities/
    │   ├── piecewiseSigmoid.m                  # Piecewise-linear sigmoid φ(x)
    │   └── piecewiseSigmoidDerivative.m        # φ'(x) — required for Jacobian
    └── plotting/
        └── bluewhitered_colormap.m             # Diverging colormap for Jacobian plots
```

---

## Key Hyperparameters (tunable in `test_reservoir_dynamics.m`)

| Parameter | Variable | Description |
|---|---|---|
| Network size | `n`, `fraction_E` | Total neurons and E/I ratio |
| Chaos level | `level_of_chaos` | Scales spectral abscissa of W |
| Dendritic timescale | `tau_d` | Membrane time constant |
| Adaptation | `n_a_E`, `n_a_I`, `tau_a_E`, `tau_a_I`, `c_E`, `c_I` | SFA scales and strength |
| STD | `n_b_E`, `n_b_I`, `tau_b_*_rec`, `tau_b_*_rel` | Depression recovery/release |
| Synaptic delay | `lags` | Inhibitory synaptic delay (s) |
| Input | `input_scaling`, `input_type` | Driving signal configuration |

---

## State Vector Layout

```
S = [ a_E(:)  |  a_I(:)  |  b_E(:)  |  b_I(:)  |  x(:) ]
      SFA (E)    SFA (I)    STD (E)    STD (I)   dendritic
```

---

## Model Equations

```
dx/dt  = ( -x + W*(b⊙r) + u ) / τ_d
r      = φ( x - c_E·Σa_E )   [E neurons]
r      = φ( x - c_I·Σa_I )   [I neurons]
da/dt  = ( r - a ) / τ_a
db/dt  = ( 1-b ) / τ_rec  -  (b·r) / τ_rel
```

where `φ` is the piecewise sigmoid activation function.

---

## Branch Purpose

This branch is intended for:
- 🔬 Hyperparameter search (chaos level, adaptation strengths, timescales)
- 📊 Dynamical regime characterisation (Jacobian/eigenvalue analysis)
- 📄 Publication-ready, minimal, well-commented codebase