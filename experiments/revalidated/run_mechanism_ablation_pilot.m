function [result, run_dir] = run_mechanism_ablation_pilot(options)
% run_mechanism_ablation_pilot  T101 three-seed smoke pilot (not for publication).
%
%   [result, run_dir] = run_mechanism_ablation_pilot()
%   [result, run_dir] = run_mechanism_ablation_pilot(options)
%
% Seeds: exactly 1729, 2718, 31415. Reduced sequence lengths.
% Tag: pilot_not_for_publication=true.
% Results under results/revalidated/<run_id>/ only.

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end
    this_dir = fileparts(mfilename('fullpath'));
    addpath(this_dir);

    cfg = mechanism_ablation_config('pilot');
    assert(isequal(cfg.seeds(:)', [1729, 2718, 31415]), ...
        'Pilot must use exactly seeds 1729, 2718, 31415.');
    assert(cfg.pilot_not_for_publication, 'Pilot must be tagged not for publication.');

    verbose = local_get(options, 'verbose', true);
    max_cells = local_get(options, 'max_cells', inf);
    max_seeds = local_get(options, 'max_seeds', inf);
    cell_keys = local_get(options, 'cell_keys', {});
    save_results = local_get(options, 'save_results', true);
    do_rerun_check = local_get(options, 'do_rerun_check', true);
    param_overrides = local_get(options, 'param_overrides', struct());

    % Optional frozen operating point from T102
    if isfield(options, 'frozen_operating_point')
        cfg.frozen_operating_point = options.frozen_operating_point;
    end

    cells = cfg.cells;
    if ~isempty(cell_keys)
        keep = false(size(cells));
        for i = 1:numel(cells)
            keep(i) = any(strcmp(cells{i}.cell_key, cell_keys));
        end
        cells = cells(keep);
    end
    n_cells = min(numel(cells), max_cells);
    cells = cells(1:n_cells);
    seeds = cfg.seeds(1:min(numel(cfg.seeds), max_seeds));

    run_dir = '';
    if save_results
        ctx_opts = struct('master_seed', seeds(1));
        if isfield(options, 'run_id'); ctx_opts.run_id = options.run_id; end
        if isfield(options, 'revalidated_root_override')
            ctx_opts.revalidated_root_override = options.revalidated_root_override;
        end
        ctx = create_run_context('mechanism_ablation_pilot', ctx_opts);
        run_dir = ctx.run_dir;
        cells_dir = fullfile(run_dir, 'cells');
        mkdir(cells_dir);
        save_run_manifest(ctx, cfg, struct( ...
            'pilot_not_for_publication', true, ...
            'n_cells', n_cells, ...
            'seeds', seeds, ...
            'stage', 'T101_pilot'));
        atomic_save_results(fullfile(run_dir, 'preregistered_config.mat'), ...
            struct('cfg', cfg));
    end

    qa_rows = {};
    cell_results = {};
    n_fail = 0;

    for iseed = 1:numel(seeds)
        seed = seeds(iseed);
        for ic = 1:n_cells
            cell_spec = cells{ic};
            if verbose
                fprintf('Pilot %d/%d seed=%d cell=%s\n', ...
                    (iseed-1)*n_cells + ic, numel(seeds)*n_cells, seed, cell_spec.cell_key);
            end
            cell_opts = struct('verbose', verbose, 'run_secondary', false, ...
                'param_overrides', param_overrides);
            cr = run_ablation_cell(cell_spec, seed, cfg, cell_opts);
            cell_results{end+1} = cr; %#ok<AGROW>

            if save_results
                fname = sprintf('seed_%d__%s.mat', seed, cell_spec.cell_key);
                atomic_save_results(fullfile(cells_dir, fname), struct('cell_result', cr));
            end

            qa_rows{end+1} = make_qa_row(cr); %#ok<AGROW>
            if ~strcmp(cr.status, 'ok')
                n_fail = n_fail + 1;
            end
        end
    end

    qa_table = [qa_rows{:}];
    assertions = assert_pilot_structural_qa(qa_table, cell_results, cfg);

    rerun = struct('performed', false);
    if do_rerun_check && ~isempty(cell_results)
        rerun = rerun_reproducibility_check(cells{1}, seeds(1), cfg, ...
            cell_results{1}, param_overrides, verbose);
        assertions.rerun = rerun;
    end

    result = struct();
    result.pilot_not_for_publication = true;
    result.cfg = cfg;
    result.seeds = seeds;
    result.n_cells = n_cells;
    result.n_completed = numel(cell_results);
    result.n_failed = n_fail;
    result.qa_table = qa_table;
    result.assertions = assertions;
    result.rerun = rerun;
    result.cell_results = cell_results;
    result.run_dir = run_dir;
    result.status = ternary(n_fail == 0 && assertions.all_pass, 'ok', 'failed_assertions');

    if save_results
        atomic_save_results(fullfile(run_dir, 'pilot_summary.mat'), ...
            struct('result', rmfield_if(result, 'cell_results')));
        % Keep full payload separately (large)
        atomic_save_results(fullfile(run_dir, 'pilot_full.mat'), struct('result', result));
        write_qa_csv(fullfile(run_dir, 'pilot_qa_table.csv'), qa_table);
        save_run_manifest(ctx, cfg, struct( ...
            'pilot_not_for_publication', true, ...
            'status', result.status, ...
            'assertions', assertions, ...
            'n_failed', n_fail, ...
            'stage', 'T101_pilot_complete'));
    end
end

function row = make_qa_row(cr)
    row = struct();
    row.cell_key = cr.cell_key;
    row.base_seed = cr.base_seed;
    row.mode = cr.mode;
    row.status = cr.status;
    row.failure_status = cr.failure_status;
    row.wall_time_seconds = cr.wall_time_seconds;
    row.dale_violations = local_get(cr, 'dale_violations', NaN);
    if isfield(cr, 'qa')
        row.state_min = cr.qa.state_min;
        row.state_max = cr.qa.state_max;
        row.saturation_fraction = cr.qa.saturation_fraction;
        row.silent_fraction = cr.qa.silent_fraction;
        row.mean_rate = cr.qa.mean_rate;
        row.feature_effective_rank = cr.qa.feature_effective_rank;
        row.feature_condition_number = cr.qa.feature_condition_number;
        row.resource_in_unit_interval = cr.qa.resource_in_unit_interval;
    else
        row.state_min = NaN;
        row.state_max = NaN;
        row.saturation_fraction = NaN;
        row.silent_fraction = NaN;
        row.mean_rate = NaN;
        row.feature_effective_rank = NaN;
        row.feature_condition_number = NaN;
        row.resource_in_unit_interval = false;
    end
    row.selected_lambda_narma = local_get(cr, 'selected_lambda_narma', NaN);
end

function assertions = assert_pilot_structural_qa(qa_table, cell_results, cfg)
    assertions = struct();
    assertions.dale_zero = all([qa_table.dale_violations] == 0 | isnan([qa_table.dale_violations]));
    assertions.resources_ok = all([qa_table.resource_in_unit_interval] | ...
        strcmp({qa_table.status}, 'failed'));
    assertions.no_unexpected_nonfinite = true;
    for i = 1:numel(cell_results)
        cr = cell_results{i};
        if ~strcmp(cr.status, 'ok')
            continue;
        end
        if ~isfinite(cr.memory_capacity.MC_total) || ...
                ~isfinite(cr.narma.test_nrmse) || ...
                ~isfinite(cr.mackey_glass.test_nrmse)
            assertions.no_unexpected_nonfinite = false;
        end
        % Unsupported metrics may be NaN with status strings
        if strcmp(cr.mode, 'DDE')
            if ~isfield(cr.unsupported, 'dde_lle')
                assertions.no_unexpected_nonfinite = false;
            end
        end
    end
    assertions.all_cells_completed = all(strcmp({qa_table.status}, 'ok'));
    assertions.pilot_tag = cfg.pilot_not_for_publication;
    assertions.all_pass = assertions.dale_zero && assertions.resources_ok && ...
        assertions.no_unexpected_nonfinite && assertions.all_cells_completed && ...
        assertions.pilot_tag;
end

function rerun = rerun_reproducibility_check(cell_spec, seed, cfg, first, param_overrides, verbose)
    rerun = struct();
    rerun.performed = true;
    rerun.cell_key = cell_spec.cell_key;
    rerun.seed = seed;
    second = run_ablation_cell(cell_spec, seed, cfg, struct( ...
        'verbose', verbose, 'run_secondary', false, 'param_overrides', param_overrides));
    if ~strcmp(first.status, 'ok') || ~strcmp(second.status, 'ok')
        rerun.pass = false;
        rerun.reason = 'original_or_rerun_failed';
        return;
    end
    if strcmp(cell_spec.mode, 'ODE')
        tol = 1e-6;  % pilot uses reduced solver tolerances / ode45
    else
        tol = 1e-5;  % documented DDE solver tolerance band for pilot QA
    end
    d_mc = abs(first.memory_capacity.MC_total - second.memory_capacity.MC_total);
    d_narma = abs(first.narma.test_nrmse - second.narma.test_nrmse);
    d_mg = abs(first.mackey_glass.test_nrmse - second.mackey_glass.test_nrmse);
    rerun.deltas = struct('mc', d_mc, 'narma', d_narma, 'mg', d_mg, 'tol', tol);
    rerun.pass = (d_mc <= tol) && (d_narma <= tol) && (d_mg <= tol);
end

function write_qa_csv(path_csv, qa_table)
    fid = fopen(path_csv, 'w');
    if fid < 0
        warning('run_mechanism_ablation_pilot:QAWriteFailed', 'Could not write %s', path_csv);
        return;
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fields = fieldnames(qa_table);
    fprintf(fid, '%s\n', strjoin(fields, ','));
    for i = 1:numel(qa_table)
        vals = cell(1, numel(fields));
        for j = 1:numel(fields)
            v = qa_table(i).(fields{j});
            if isnumeric(v) || islogical(v)
                vals{j} = num2str(v);
            else
                vals{j} = char(string(v));
            end
        end
        fprintf(fid, '%s\n', strjoin(vals, ','));
    end
end

function s = rmfield_if(s, name)
    if isfield(s, name)
        s = rmfield(s, name);
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
