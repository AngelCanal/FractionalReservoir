function [result, run_dir] = run_mechanism_ablation_smoke(options)
% run_mechanism_ablation_smoke  Minimal smoke protocol (never publication evidence).
%
%   [result, run_dir] = run_mechanism_ablation_smoke()
%   [result, run_dir] = run_mechanism_ablation_smoke(options)
%
% Uses protocol_tier='smoke' with reduced lengths. publication_ready is always
% false for this entry point.

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end
    this_dir = fileparts(mfilename('fullpath'));
    addpath(this_dir);

    cfg = mechanism_ablation_config('smoke');
    assert(strcmp(cfg.protocol_tier, 'smoke'));
    assert(cfg.pilot_not_for_publication);

    verbose = local_get(options, 'verbose', true);
    max_cells = local_get(options, 'max_cells', inf);
    max_seeds = local_get(options, 'max_seeds', inf);
    cell_keys = local_get(options, 'cell_keys', {});
    save_results = local_get(options, 'save_results', true);
    param_overrides = local_get(options, 'param_overrides', struct());

    reject_baseline_overrides(options, 'run_mechanism_ablation_smoke');

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
    ctx = struct();
    if save_results
        ctx_opts = struct('master_seed', seeds(1));
        if isfield(options, 'run_id'); ctx_opts.run_id = options.run_id; end
        if isfield(options, 'revalidated_root_override')
            ctx_opts.revalidated_root_override = options.revalidated_root_override;
        end
        ctx = create_run_context('mechanism_ablation_smoke', ctx_opts);
        run_dir = ctx.run_dir;
        cells_dir = fullfile(run_dir, 'cells');
        mkdir(cells_dir);
        save_run_manifest(ctx, cfg, struct( ...
            'protocol_tier', cfg.protocol_tier, ...
            'protocol_fingerprint', cfg.protocol_fingerprint, ...
            'pilot_not_for_publication', true, ...
            'n_cells', n_cells, ...
            'seeds', seeds, ...
            'stage', 'smoke'));
        atomic_save_results(fullfile(run_dir, 'preregistered_config.mat'), ...
            struct('cfg', cfg));
    end

    cell_results = {};
    cell_index = {};
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
                fprintf('Smoke %d/%d seed=%d cell=%s\n', ...
                    (iseed-1)*n_cells + ic, numel(seeds)*n_cells, seed, cell_spec.cell_key);
            end
            cell_opts = struct( ...
                'verbose', verbose, 'run_secondary', false, ...
                'param_overrides', param_overrides);
            if ~isempty(bundle)
                cell_opts.shared_baseline_bundle = bundle;
            end
            cr = run_ablation_cell(cell_spec, seed, cfg, cell_opts);
            cell_results{end+1} = cr; %#ok<AGROW>
            if ~strcmp(cr.status, 'ok')
                n_fail = n_fail + 1;
            end
            fname = sprintf('seed_%d__%s.mat', seed, cell_spec.cell_key);
            if save_results
                atomic_save_results(fullfile(run_dir, 'cells', fname), ...
                    struct('cell_result', cr));
            end
            cell_index{end+1} = struct( ...
                'file', fname, 'seed', seed, 'cell_key', cell_spec.cell_key, ...
                'status', cr.status, 'wall_time_seconds', cr.wall_time_seconds, ...
                'matched_baseline_bundle_id', local_get(cr, 'matched_baseline_bundle_id', '')); %#ok<AGROW>
        end
    end

    % Final cfg is established (including any frozen operating point) — gate once.
    persist_opts = build_temporal_gate_persist_opts(options, 'run_mechanism_ablation_smoke');
    [temporal_gate, ~, gate_manifest] = ...
        evaluate_and_persist_temporal_learning_gate(cfg, run_dir, save_results, persist_opts);

    readiness = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', cell_results, ...
        'has_manifest', save_results, ...
        'has_commit_sha', save_results, ...
        'has_artifact_hashes', false, ...
        'run_dir', run_dir, ...
        'temporal_learning_gate', temporal_gate));

    if isfield(temporal_gate, 'evaluation_provenance') && ...
            strcmp(char(temporal_gate.evaluation_provenance.mode), 'injected_test_fixture')
        readiness.publication_ready = false;
        readiness.publication_protocol_complete = false;
    end

    result = struct();
    result.protocol_tier = cfg.protocol_tier;
    result.protocol_fingerprint = cfg.protocol_fingerprint;
    result.pilot_not_for_publication = true;
    result.cfg = cfg;
    result.seeds = seeds;
    result.n_cells = n_cells;
    result.n_completed = numel(cell_results);
    result.n_failed = n_fail;
    result.cell_index = cell_index;
    result.cell_results = cell_results;
    result.seed_baseline_index = seed_baseline_index;
    result.temporal_learning_gate = temporal_gate;
    result.run_dir = run_dir;
    result.status = ternary(n_fail == 0, 'ok', 'failed_cells');
    result = attach_readiness_fields(result, readiness);
    result.publication_protocol_complete = false;
    result.publication_ready = false;

    if save_results
        atomic_save_results(fullfile(run_dir, 'smoke_summary.mat'), ...
            struct('result', rmfield_if(result, 'cell_results')));
        man = struct( ...
            'protocol_tier', cfg.protocol_tier, ...
            'protocol_fingerprint', cfg.protocol_fingerprint, ...
            'status', result.status, ...
            'publication_ready', false, ...
            'publication_protocol_complete', false, ...
            'structurally_complete', result.structurally_complete, ...
            'n_failed', n_fail, ...
            'stage', 'smoke_complete');
        man = merge_structs(man, gate_manifest);
        save_run_manifest(ctx, cfg, man);
    end
end

function result = attach_readiness_fields(result, readiness)
    result.structurally_complete = readiness.structurally_complete;
    result.publication_protocol_complete = readiness.publication_protocol_complete;
    result.all_primary_endpoints_finite = readiness.all_primary_endpoints_finite;
    result.all_qa_checks_pass = readiness.all_qa_checks_pass;
    if isfield(readiness, 'all_required_secondary_endpoints_complete')
        result.all_required_secondary_endpoints_complete = ...
            readiness.all_required_secondary_endpoints_complete;
    else
        result.all_required_secondary_endpoints_complete = false;
    end
    result.artifact_package_complete = readiness.artifact_package_complete;
    result.publication_ready = readiness.publication_ready;
    result.readiness = readiness;
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
