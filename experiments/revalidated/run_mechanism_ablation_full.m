function [result, run_dir] = run_mechanism_ablation_full(options)
% run_mechanism_ablation_full  T103 paired mechanism ablation (>=30 seeds).
%
% Requires a frozen operating point from T102. Supports running a seed subset
% when full 30-seed compute is prohibitive; documents completion status.

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end
    this_dir = fileparts(mfilename('fullpath'));
    addpath(this_dir);

    cfg = mechanism_ablation_config('full');
    assert(~cfg.pilot_not_for_publication);

    % Optional: use reduced pilot lengths while keeping the full seed list / G7 structure.
    if local_get(options, 'use_reduced_lengths', false)
        pilot_cfg = mechanism_ablation_config('pilot');
        cfg.lengths = pilot_cfg.lengths;
        cfg.base.n = pilot_cfg.base.n;
        cfg.secondary_enabled = false;
        cfg.length_note = 'reduced_lengths_for_compute_feasibility_not_publication_inference';
    end

    if ~isfield(options, 'frozen_operating_point') || isempty(options.frozen_operating_point)
        error('run_mechanism_ablation_full:MissingOperatingPoint', ...
            'Pass options.frozen_operating_point from T102 before full runs.');
    end
    cfg.frozen_operating_point = options.frozen_operating_point;

    verbose = local_get(options, 'verbose', true);
    save_results = local_get(options, 'save_results', true);
    max_seeds = local_get(options, 'max_seeds', numel(cfg.seeds));
    max_cells = local_get(options, 'max_cells', numel(cfg.cells));
    run_secondary = local_get(options, 'run_secondary', false); % default off for feasibility
    seeds = cfg.seeds(1:min(numel(cfg.seeds), max_seeds));
    cells = cfg.cells(1:min(numel(cfg.cells), max_cells));

    run_dir = '';
    if save_results
        ctx_opts = struct('master_seed', seeds(1));
        if isfield(options, 'run_id'); ctx_opts.run_id = options.run_id; end
        if isfield(options, 'revalidated_root_override')
            ctx_opts.revalidated_root_override = options.revalidated_root_override;
        end
        ctx = create_run_context('mechanism_ablation_full', ctx_opts);
        run_dir = ctx.run_dir;
        mkdir(fullfile(run_dir, 'cells'));
        save_run_manifest(ctx, cfg, struct( ...
            'stage', 'T103_full', ...
            'frozen_operating_point', cfg.frozen_operating_point, ...
            'n_seeds_requested', numel(cfg.full_seeds), ...
            'n_seeds_this_run', numel(seeds), ...
            'n_cells', numel(cells)));
        atomic_save_results(fullfile(run_dir, 'preregistered_config.mat'), struct('cfg', cfg));
    end

    cell_index = {};
    n_fail = 0;
    for iseed = 1:numel(seeds)
        seed = seeds(iseed);
        for ic = 1:numel(cells)
            cell_spec = cells{ic};
            if verbose
                fprintf('Full %d/%d seed=%d cell=%s\n', ...
                    (iseed-1)*numel(cells)+ic, numel(seeds)*numel(cells), ...
                    seed, cell_spec.cell_key);
            end
            cr = run_ablation_cell(cell_spec, seed, cfg, struct( ...
                'verbose', verbose, ...
                'run_secondary', run_secondary));
            if ~strcmp(cr.status, 'ok')
                n_fail = n_fail + 1;
            end
            fname = sprintf('seed_%d__%s.mat', seed, cell_spec.cell_key);
            if save_results
                atomic_save_results(fullfile(run_dir, 'cells', fname), ...
                    struct('cell_result', cr));
            end
            cell_index{end+1} = struct( ...
                'file', fname, ...
                'seed', seed, ...
                'cell_key', cell_spec.cell_key, ...
                'status', cr.status, ...
                'wall_time_seconds', cr.wall_time_seconds); %#ok<AGROW>
        end
    end

    aggregate = struct('status', 'not_computed');
    if save_results && n_fail == 0
        aggregate = aggregate_ablation_results(run_dir, struct( ...
            'control_cell_key', 'adapt-off__std-off__delay-ode_off__feat-x', ...
            'save', true));
    end

    result = struct();
    result.cfg = cfg;
    result.seeds = seeds;
    result.n_seeds_requested = numel(cfg.full_seeds);
    result.n_seeds_completed = numel(seeds);
    result.n_cells = numel(cells);
    result.n_failed = n_fail;
    result.cell_index = cell_index;
    result.aggregate = aggregate;
    result.frozen_operating_point = cfg.frozen_operating_point;
    result.run_dir = run_dir;
    result.g7_complete = (numel(seeds) >= 30) && (n_fail == 0) && ...
        (numel(cells) == cfg.n_cells);
    result.status = ternary(n_fail == 0, 'ok', 'failed_cells');
    result.completion_note = sprintf( ...
        'Completed %d/%d preregistered seeds and %d/%d cells. G7=%d.', ...
        numel(seeds), numel(cfg.full_seeds), numel(cells), cfg.n_cells, ...
        result.g7_complete);

    if save_results
        atomic_save_results(fullfile(run_dir, 'full_summary.mat'), struct('result', result));
        save_run_manifest(ctx, cfg, struct( ...
            'stage', 'T103_full_complete', ...
            'status', result.status, ...
            'g7_complete', result.g7_complete, ...
            'completion_note', result.completion_note, ...
            'n_failed', n_fail));
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end

function out = ternary(cond, a, b)
    if cond
        out = a;
    else
        out = b;
    end
end
