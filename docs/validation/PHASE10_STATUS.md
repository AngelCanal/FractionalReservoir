# Phase 10–11 execution status

Recorded after implementing T100–T103 and T110–T111 on
`fix/mesn-validation-foundation`.

## Completed

| Task | Commit | Outcome |
|---|---|---|
| T100 | `e6138f0` `docs: preregister MESN mechanism ablation experiment` | Config + preregistration docs |
| T101 | `0c54db1` `experiment: run three-seed MESN ablation pilot` | 108/108 cells OK; G6 structural assertions pass; rerun pass |
| T102 | `7962126` `experiment: freeze shared operating-point calibration` | Frozen OP: `input_scaling=0.25`, `level_of_chaos=0.6` |
| T103 | `7904d11` `experiment: run full paired MESN ablation seeds` | **G7 complete:** 30/30 seeds × 36/36 cells (1080/1080 OK); `aggregate_paired.mat` written |
| T110 | `770aff7` `figures: rebuild MESN evidence from validated paired experiments` | Explicit-path figure rebuild |
| T111 | `8026f16` `docs: align MESN manuscript claims with validated evidence` | Claim–evidence table; manuscript/README rewritten |

## Immutable result paths (do not overwrite legacy)

- Pilot: `results/revalidated/20260711_011425_mechanism_ablation_pilot_e6138f0/`
  - `pilot_not_for_publication=true`
  - seeds `1729, 2718, 31415`; 36 cells × 3 seeds
- Calibration: `results/revalidated/20260711_014150_operating_point_calibration_e6138f0/`
- Full (G7): `results/revalidated/20260711_014438_mechanism_ablation_full_8026f16/`
  - 1080 cell `.mat` files; `aggregate_paired.mat`; `full_summary.mat`
  - reduced lengths (structural / compute-feasible; not publication-length inference)
- Figures: `results/revalidated/20260711_014502_paper_figures_validated_8026f16/`

## Status notes

1. **G5** — `tests/scientific/test_esn_can_learn.m` committed (`d2e3824`); Gate G5 **passed**.
2. **G7** — full 30-seed reduced-length run **completed** (`g7=1`, exit 0, ~2.8 h wall time).
3. Mechanism-superiority claims may cite paired CIs from `aggregate_paired.mat`, but must note **reduced sequence lengths** unless a full-length rerun is approved.
4. Figure 1 still needs a packaged `validation_controls.mat` path for the validation-controls panel.

## Commands

```matlab
setup_paths();
cfg = mechanism_ablation_config('pilot');
[result, run_dir] = run_mechanism_ablation_pilot();
[cal, cal_dir] = calibrate_operating_point();
[full, full_dir] = run_mechanism_ablation_full(struct( ...
    'frozen_operating_point', cal.frozen_operating_point, ...
    'use_reduced_lengths', true, ...
    'max_seeds', 30));
make_paper_figures(struct('result_paths', struct('ablation_run_dir', full_dir)));
```
