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

    analysis_set = resolve_runner_analysis_set(options);
    cfg = mechanism_ablation_config('pilot', analysis_set);
    assert(strcmp(cfg.protocol_tier, 'pilot'), 'Pilot must use protocol_tier=pilot.');
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

    reject_baseline_overrides(options, 'run_mechanism_ablation_pilot');

    % Optional frozen operating point from T102
    if isfield(options, 'frozen_operating_point')
        cfg.frozen_operating_point = options.frozen_operating_point;
        cfg.protocol_fingerprint = compute_protocol_fingerprint(cfg);
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
            'protocol_tier', cfg.protocol_tier, ...
            'active_analysis_set', cfg.active_analysis_set, ...
            'protocol_fingerprint', cfg.protocol_fingerprint, ...
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
    seed_baseline_index = {};

    for iseed = 1:numel(seeds)
        seed = seeds(iseed);
        bundle = [];
        if n_cells > 0
            prep_opts = struct('param_overrides', param_overrides);
            [bundle, bundle_path] = prepare_seed_matched_baselines( ...
                cfg, seed, cells, run_dir, save_results, prep_opts);
            seed_baseline_index{end+1} = struct( ...
                'seed', seed, ...
                'bundle_id', bundle.bundle_id, ...
                'file', bundle_path, ...
                'status', bundle.baseline_result_status); %#ok<AGROW>
        end
        for ic = 1:n_cells
            cell_spec = cells{ic};
            if verbose
                fprintf('Pilot %d/%d seed=%d cell=%s\n', ...
                    (iseed-1)*n_cells + ic, numel(seeds)*n_cells, seed, cell_spec.cell_key);
            end
            cell_opts = struct('verbose', verbose, 'run_secondary', false, ...
                'param_overrides', param_overrides);
            if ~isempty(bundle)
                cell_opts.shared_baseline_bundle = bundle;
            end
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
    if do_rerun_check && ~isempty(cell_results) && n_cells > 0
        [bundle_rerun, ~] = prepare_seed_matched_baselines( ...
            cfg, seeds(1), cells, '', false, struct('param_overrides', param_overrides));
        rerun = rerun_reproducibility_check(cells{1}, seeds(1), cfg, ...
            cell_results{1}, param_overrides, verbose, bundle_rerun);
        assertions.rerun = rerun;
    end

    aggregate = struct('status', 'not_computed', ...
        'inference_status', 'deferred_to_phase_5b', ...
        'matched_seed_contrast_structure_complete', false, ...
        'aggregation_inference_complete', false);
    if save_results && n_fail == 0 && ~isempty(cell_results)
        allow_incomplete = numel(seeds) < numel(cfg.seeds) || ...
            n_cells < numel(cfg.cells);
        agg_opts = struct('save', true, 'allow_incomplete_diagnostic', true);
        if ~allow_incomplete
            agg_opts.allow_incomplete_diagnostic = false;
        end
        try
            aggregate = aggregate_ablation_results(run_dir, agg_opts);
        catch ME
            aggregate = struct( ...
                'status', 'diagnostic_incomplete_not_for_inference', ...
                'inference_status', 'deferred_to_phase_5b', ...
                'matched_seed_contrast_structure_complete', false, ...
                'aggregation_inference_complete', false, ...
                'error_id', ME.identifier, ...
                'error_message', ME.message);
        end
        if strcmp(char(local_get(aggregate, 'status', '')), 'ok') && ...
                logical(local_get(aggregate, 'matched_seed_contrast_structure_complete', false))
            try
                inference = run_seed_level_inference(run_dir, struct('save', true));
                aggregate.inference_status = inference.inference_status;
                aggregate.aggregation_inference_complete = false;
            catch ME
                inference = struct('status', 'failed', 'error_id', ME.identifier, ...
                    'aggregation_inference_complete', false);
            end
        else
            inference = struct('status', 'skipped', 'aggregation_inference_complete', false);
        end
    else
        inference = struct('status', 'skipped', 'aggregation_inference_complete', false);
    end

    % Final cfg is established (including any frozen operating point) — gate once.
    persist_opts = build_temporal_gate_persist_opts(options, 'run_mechanism_ablation_pilot');
    [temporal_gate, ~, gate_manifest] = ...
        evaluate_and_persist_temporal_learning_gate(cfg, run_dir, save_results, persist_opts);

    readiness = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', cell_results, ...
        'has_manifest', save_results, ...
        'has_commit_sha', save_results, ...
        'has_artifact_hashes', false, ...
        'run_dir', run_dir, ...
        'temporal_learning_gate', temporal_gate, ...
        'aggregation', aggregate));

    if isfield(temporal_gate, 'evaluation_provenance') && ...
            strcmp(char(temporal_gate.evaluation_provenance.mode), 'injected_test_fixture')
        readiness.publication_ready = false;
        readiness.publication_protocol_complete = false;
    end

    result = struct();
    result.analysis_set = cfg.active_analysis_set;
    result.protocol_tier = cfg.protocol_tier;
    result.protocol_fingerprint = cfg.protocol_fingerprint;
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
    result.seed_baseline_index = seed_baseline_index;
    result.aggregate = aggregate;
    result.inference = inference;
    result.inference_status = char(local_get(inference, 'inference_status', ...
        local_get(inference, 'status', 'skipped')));
    result.aggregation_inference_complete = readiness.aggregation_inference_complete;
    if isfield(inference, 'inference_manifest_hash')
        result.inference_manifest_hash = inference.inference_manifest_hash;
    else
        result.inference_manifest_hash = '';
    end
    result.temporal_learning_gate = temporal_gate;
    result.run_dir = run_dir;
    result.status = ternary(n_fail == 0 && assertions.all_pass, 'ok', 'failed_assertions');
    result.structurally_complete = readiness.structurally_complete;
    result.publication_protocol_complete = false;
    result.all_primary_endpoints_finite = readiness.all_primary_endpoints_finite;
    result.all_qa_checks_pass = readiness.all_qa_checks_pass;
    if isfield(readiness, 'all_required_secondary_endpoints_complete')
        result.all_required_secondary_endpoints_complete = ...
            readiness.all_required_secondary_endpoints_complete;
    else
        result.all_required_secondary_endpoints_complete = false;
    end
    result.artifact_package_complete = readiness.artifact_package_complete;
    result.publication_ready = false;
    result.readiness = readiness;

    if save_results
        atomic_save_results(fullfile(run_dir, 'pilot_summary.mat'), ...
            struct('result', rmfield_if(result, 'cell_results')));
        % Keep full payload separately (large)
        atomic_save_results(fullfile(run_dir, 'pilot_full.mat'), struct('result', result));
        write_qa_csv(fullfile(run_dir, 'pilot_qa_table.csv'), qa_table);
        man = struct( ...
            'protocol_tier', cfg.protocol_tier, ...
            'protocol_fingerprint', cfg.protocol_fingerprint, ...
            'pilot_not_for_publication', true, ...
            'status', result.status, ...
            'assertions', assertions, ...
            'publication_ready', false, ...
            'publication_protocol_complete', false, ...
            'n_failed', n_fail, ...
            'stage', 'T101_pilot_complete');
        man = merge_structs(man, gate_manifest);
        save_run_manifest(ctx, cfg, man);
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
    if isempty(qa_table)
        assertions.dale_zero = true;
        assertions.resources_ok = true;
        assertions.no_unexpected_nonfinite = true;
        assertions.all_cells_completed = true;
        assertions.pilot_tag = cfg.pilot_not_for_publication;
        assertions.all_pass = assertions.pilot_tag;
        return;
    end
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

function rerun = rerun_reproducibility_check(cell_spec, seed, cfg, first, param_overrides, verbose, shared_bundle)
    rerun = struct();
    rerun.performed = true;
    rerun.cell_key = cell_spec.cell_key;
    rerun.seed = seed;
    second = run_ablation_cell(cell_spec, seed, cfg, struct( ...
        'verbose', verbose, 'run_secondary', false, ...
        'param_overrides', param_overrides, ...
        'shared_baseline_bundle', shared_bundle));
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
    if isempty(qa_table)
        fid = fopen(path_csv, 'w');
        if fid >= 0
            fclose(fid);
        end
        return;
    end
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

function out = merge_structs(a, b)
    out = a;
    fn = fieldnames(b);
    for i = 1:numel(fn)
        out.(fn{i}) = b.(fn{i});
    end
end

function persist_opts = build_temporal_gate_persist_opts(options, runner_id)
    persist_opts = struct();
    gate_override = local_get(options, 'temporal_learning_gate_override', []);
    allow_injected = logical(local_get(options, 'allow_injected_test_fixture', false));
    if ~isempty(gate_override)
        if ~allow_injected
            error(sprintf('%s:TemporalGateOverrideForbidden', runner_id), ...
                ['temporal_learning_gate_override requires ', ...
                 'allow_injected_test_fixture=true.']);
        end
        persist_opts.gate_override = gate_override;
        persist_opts.allow_injected_test_fixture = true;
    elseif allow_injected
        error(sprintf('%s:InjectedFixtureWithoutOverride', runner_id), ...
            'allow_injected_test_fixture=true without temporal_learning_gate_override.');
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

function reject_baseline_overrides(options, runner_id)
    forbidden = { ...
        'baseline_bundle_override', ...
        'matched_baseline_bundles', ...
        'precomputed_baseline_bundles', ...
        'shared_baseline_bundle_override'};
    for i = 1:numel(forbidden)
        if isfield(options, forbidden{i}) && ~isempty(options.(forbidden{i}))
            error(sprintf('%s:BaselineOverrideForbidden', runner_id), ...
                '%s is forbidden; shared baselines must be computed internally.', ...
                forbidden{i});
        end
    end
end
