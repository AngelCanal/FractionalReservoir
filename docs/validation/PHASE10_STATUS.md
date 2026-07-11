# Phase 10–11 execution status

Recorded after implementing T100–T103 and T110–T111 on
`fix/mesn-validation-foundation`.

## Completed

| Task | Commit | Outcome |
|---|---|---|
| T100 | `e6138f0` `docs: preregister MESN mechanism ablation experiment` | Config + preregistration docs |
| T101 | `0c54db1` `experiment: run three-seed MESN ablation pilot` | 108/108 cells OK; G6 structural assertions pass; rerun pass |
| T102 | `7962126` `experiment: freeze shared operating-point calibration` | Frozen OP: `input_scaling=0.25`, `level_of_chaos=0.6` |
| T103 | `7904d11` `experiment: run full paired MESN ablation seeds` | Runner + aggregate infrastructure; 30-seed reduced-length run started |
| T110 | `770aff7` `figures: rebuild MESN evidence from validated paired experiments` | Explicit-path figure rebuild; incomplete without G7 |
| T111 | `8026f16` `docs: align MESN manuscript claims with validated evidence` | Claim–evidence table; manuscript/README rewritten |

## Immutable result paths (do not overwrite legacy)

- Pilot: `results/revalidated/20260711_011425_mechanism_ablation_pilot_e6138f0/`
  - `pilot_not_for_publication=true`
  - seeds `1729, 2718, 31415`; 36 cells × 3 seeds
- Calibration: `results/revalidated/20260711_014150_operating_point_calibration_e6138f0/`
- Figures (incomplete): `results/revalidated/20260711_014502_paper_figures_validated_8026f16/`

## Stop / open conditions

1. **G5** (`test_esn_can_learn.m`) may still be uncommitted/in progress — Phase 10 code/docs proceeded per instruction; learning claims remain pending in `CLAIM_EVIDENCE.md`.
2. **G7 incomplete** until the full ≥30-seed run finishes with all 36 cells and aggregate CIs. T103 supports 30 seeds via `run_mechanism_ablation_full` with `use_reduced_lengths=true` for compute feasibility; publication inference still requires declared full lengths or an explicit human decision that reduced lengths are only structural.
3. Figure 1 needs a packaged `validation_controls.mat` path.
4. Mechanism-superiority claims remain **unsupported** until G7.

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
