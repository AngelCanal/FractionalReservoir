# Results and provenance

This directory holds generated data and figures for the MESN paper.

## Layout

| Subfolder | Produced by | Contents |
|---|---|---|
| `revalidated/<run_id>/` | experiment entry points via `create_run_context` | **New** immutable scientific runs + `manifest.mat` / `manifest.json` |
| `jacobian_checks/` | legacy | Historical Jacobian diagnostics (do not overwrite) |
| `esp_phase/` | legacy | Historical ESP phase grids (do not overwrite) |
| `parameter_grid/` | legacy | Historical parameter grids (do not overwrite) |
| `parameter_sweeps/` | legacy | Legacy 1D sweeps (do not overwrite) |
| `timescale_invariance/` | legacy | Historical timescale runs (do not overwrite) |
| `meanfield_bifurcation/` | legacy | Historical mean-field regime sweeps (do not overwrite) |
| `benchmarks/` | legacy | Historical benchmarks (do not overwrite) |
| `characterisation/<timestamp>/` | legacy | Historical characterisation bundles |
| `figures/paper/` | promoted publication figures | Versioned paper figures (tracked intentionally) |

Legacy committed artifacts listed in `docs/validation/BASELINE.md` are immutable
evidence of the pre-repair implementation. **Do not overwrite, delete, or mix
them with new revalidated outputs.**

## New runs (`results/revalidated/`)

- Every new experiment should call `create_run_context` then `save_run_manifest`
  after parameters are finalized.
- Generated contents under `results/revalidated/**` are **git-ignored**.
- The folder scaffold is retained via `results/revalidated/.gitkeep`.

### Reproducible command pattern

```matlab
setup_paths();
opts = struct( ...
    'seed', 1729, ...
    'dry_run', false, ...
    'save_results', true, ...
    'run_dependencies', false);   % default: do not chain expensive experiments
[result, run_dir] = run_benchmarks(opts);
% Manifest path (always written when save_results=true):
%   fullfile(run_dir, 'manifest.mat')
%   fullfile(run_dir, 'manifest.json')
```

Paper figures require **explicit** result paths (no “latest file” search):

```matlab
paths = struct( ...
    'esp_phase',              '<absolute>/esp_phase.mat', ...
    'parameter_grid',         '<absolute>/grid.mat', ...
    'timescale_invariance',   '<absolute>/timescale.mat', ...
    'meanfield',              '<absolute>/adaptation_....mat', ...
    'benchmarks',             '<absolute>/benchmarks.mat');
[fig_result, fig_run_dir] = make_paper_figures(struct( ...
    'result_paths', paths, ...
    'seed', 1729, ...
    'save_results', true));
```

Or pass `manifest_path` pointing to a `.mat` that contains `result_paths`.

## Promoting a paper artifact

Ignored run output is not a publication archive by itself. To promote a final
figure or table into the versioned tree:

1. Identify the immutable `results/revalidated/<run_id>/` directory and its
   `manifest.json` (record seed, git SHA, MATLAB version).
2. Copy only the reviewed artifact into `results/figures/paper/` (or a release
   archive outside this repo), using a **new** filename if a tracked file
   already exists — never overwrite legacy committed results.
3. Commit the promoted artifact in a dedicated docs/results commit with the
   source `run_id` and manifest path cited in the commit message.
4. Optionally tag a release / deposit a DOI that pins the commit SHA.

## License

There is **no declared license** in this repository. Reuse permissions are
undefined until the owner chooses and adds a license file. Do not assume
open-source reuse rights.
