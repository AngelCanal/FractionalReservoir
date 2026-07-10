# MESN validation baseline

Immutable record of the repository state at the start of the validation repair program.

## Source

| Field | Value |
|---|---|
| Source branch | `Membrane-Echo-State-Network` |
| Source SHA | `c11e2ac7b2fc273bbf685baa267c7ec677c93602` |
| Repair branch | `fix/mesn-validation-foundation` |
| MATLAB version | 26.1.0.3234472 (R2026a) Update 1 |
| Operating system | Windows 10 (win64) |
| Hostname | DELL-D9SJ034 |
| Date (UTC) | 2026-07-10 |

## Pre-existing `git status --short`

```
?? results/benchmarks/benchmarks_20260710_154634.mat
?? results/figures/paper/fig2_esp_phase.png
?? results/figures/paper/fig3_lle_nonnormality.png
?? results/figures/paper/fig4_memory_nonnormality.png
?? results/figures/paper/fig5_timescale_invariance.png
?? results/figures/paper/fig6_meanfield_bifurcation.png
?? results/figures/paper/fig7_benchmarks.png
```

## Known invalid committed artifacts

The following legacy result paths are historical evidence of the pre-repair implementation. **They must never be overwritten, deleted, or mixed with new revalidated outputs.**

### Jacobian checks

- `results/jacobian_checks/jacobian_consistency_20260709_095529.mat`

### Parameter grid

- `results/parameter_grid/grid_20260710_044956.mat`

### ESP phase diagram

- `results/esp_phase/esp_phase_20260709_123103.mat`

### Timescale invariance

- `results/timescale_invariance/timescale_20260710_082627.mat`

### Mean-field bifurcation

- `results/meanfield_bifurcation/adaptation_20260710_154457.mat`

### Characterisation reference runs

- `results/characterisation/20260415_170740/reference_run.mat`
- `results/characterisation/20260415_172119/reference_run.mat`
- `results/characterisation/20260415_175349/reference_run.mat`
- `scripts/results/characterisation/20260415_132342/reference_run.mat`

### Legacy paper figures (committed)

- `results/figures/Figure_1.png` through `Figure_4.png`
- `results/figures/paper/fig2_esp_phase.png` through `fig7_benchmarks.png` (untracked at baseline)

New scientific results must be written only under `results/revalidated/<run_id>/` with provenance manifests.
