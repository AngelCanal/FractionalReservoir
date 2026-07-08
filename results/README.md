# Results and provenance

This directory holds all generated data and figures for the MESN paper. Heavy
artifacts (`*.mat`, most `*.png`/`*.pdf`) are git-ignored; the folder scaffold
and the final publication figures under `results/figures/paper/` are tracked so
the paper can be rebuilt and shared.

## Layout

| Subfolder | Produced by | Contents |
|---|---|---|
| `jacobian_checks/` | `scripts/verifyJacobianConsistency.m` | Jacobian consistency diagnostics |
| `esp_phase/` | `scripts/run_esp_phase_diagram.m` | ESP phase diagram grid (Result 1) |
| `parameter_grid/` | `scripts/run_parameter_grid.m` | Multi-parameter Lyapunov/ESP/non-normality grid (Result 2) |
| `parameter_sweeps/` | `scripts/run_parameter_sweep.m` | Legacy 1D sweeps |
| `timescale_invariance/` | `scripts/run_timescale_invariance.m` | Memory spectrum, invariance, phase advance (Result 3) |
| `meanfield_bifurcation/` | `scripts/run_meanfield_adaptation_bifurcation.m`, `scripts/run_bifurcation_meanfield.m` | Reduced-model bifurcation (Result 4) |
| `benchmarks/` | `scripts/run_benchmarks.m` | Task performance, adaptation ON/OFF (Result 5) |
| `characterisation/<timestamp>/` | `scripts/run_full_characterisation.m` | Full characterisation bundles |
| `figures/paper/` | `scripts/make_paper_figures.m` | Final publication figures (tracked) |

## Provenance convention

- Every analysis script saves a timestamped `*.mat` named `<analysis>_<yyyymmdd_HHMMSS>.mat`
  containing both the results and the configuration used to produce them
  (grids, inputs, options), so a result file is self-describing.
- `make_paper_figures.m` consumes the most recent `*.mat` in each subfolder and
  writes canonical figures to `figures/paper/`. It never re-runs a simulation
  unless invoked with `regenerate = true`.

## One-command rebuild

```matlab
setup_paths();
make_paper_figures();                                  % figures from latest saved results
make_paper_figures(struct('regenerate', true));        % re-run all analyses first (slow)
```
