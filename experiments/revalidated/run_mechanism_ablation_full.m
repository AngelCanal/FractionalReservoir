function [result, run_dir] = run_mechanism_ablation_full(options)
% run_mechanism_ablation_full  Publication-intent paired mechanism ablation.
%
% Requires a frozen operating point. Reduced lengths force protocol_tier='smoke'
% and can never set publication_ready / publication_protocol_complete.

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end
    this_dir = fileparts(mfilename('fullpath'));
    addpath(this_dir);

    analysis_set = resolve_runner_analysis_set(options);
    cfg = mechanism_ablation_config('publication', analysis_set);
    assert(strcmp(cfg.protocol_tier, 'publication'));
    assert(~cfg.pilot_not_for_publication);

    used_reduced_lengths = local_get(options, 'use_reduced_lengths', false);
    if used_reduced_lengths
        smoke_cfg = mechanism_ablation_config('smoke', analysis_set);
        cfg.lengths = smoke_cfg.lengths;
        cfg.base.n = smoke_cfg.base.n;
        cfg.secondary_enabled = false;
        % Rebuild temporal-gate config for smoke n/lengths/seeds/tier before
        % fingerprinting (publication gate was constructed earlier).
        cfg.temporal_learning_gate = smoke_cfg.temporal_learning_gate;
        cfg = force_smoke_protocol(cfg, ...
            'reduced_lengths_for_compute_feasibility_not_publication_inference');
    end

    if isfield(options, 'frozen_operating_point') && ~isempty(options.frozen_operating_point)
        error('run_mechanism_ablation_full:RawOperatingPointForbidden', ...
            'options.frozen_operating_point is forbidden; use calibration_run_dir.');
    end

    calibration_authority = struct();
    if strcmp(cfg.protocol_tier, 'publication')
        if ~isfield(options, 'calibration_run_dir') || isempty(options.calibration_run_dir)
            error('run_mechanism_ablation_full:MissingCalibrationArtifact', ...
                'Publication runs require options.calibration_run_dir.');
        end
        calibration_authority = validate_operating_point_calibration( ...
            options.calibration_run_dir);
        if ~calibration_authority.valid
            error('run_mechanism_ablation_full:InvalidCalibrationArtifact', ...
                'Calibration artifact failed validation: %s', ...
                strjoin(calibration_authority.reasons, ','));
        end
        if ~calibration_authority.authorizes_publication_run
            error('run_mechanism_ablation_full:CalibrationNotAuthorizing', ...
                'Calibration artifact does not authorize publication runs.');
        end
        cfg.frozen_operating_point = calibration_authority.frozen_operating_point;
        cfg.frozen_operating_point_provenance = struct( ...
            'schema_version', 'publication_operating_point_calibration_artifact_v1', ...
            'calibration_protocol_version', ...
                'publication_operating_point_calibration_v1', ...
            'calibration_protocol_fingerprint', ...
                calibration_authority.calibration_protocol_fingerprint, ...
            'calibration_manifest_hash', calibration_authority.calibration_manifest_hash, ...
            'validation_status', 'valid', ...
            'scientific_overrides_used', false);
        cfg.protocol_fingerprint = compute_protocol_fingerprint(cfg);
    end

    reject_temporal_gate_override(options, 'run_mechanism_ablation_full');
    reject_baseline_overrides(options, 'run_mechanism_ablation_full');

    verbose = local_get(options, 'verbose', true);
    save_results = local_get(options, 'save_results', true);
    max_seeds = local_get(options, 'max_seeds', numel(cfg.seeds));
    max_cells = local_get(options, 'max_cells', numel(cfg.cells));
    run_secondary = local_get(options, 'run_secondary', false); % default off for feasibility
    if used_reduced_lengths
        run_secondary = false;
    end
    seeds = cfg.seeds(1:min(numel(cfg.seeds), max_seeds));
    cells = cfg.cells(1:min(numel(cfg.cells), max_cells));

    run_dir = '';
    ctx = struct();
    if save_results
        ctx_opts = struct('master_seed', seeds(1));
        if isfield(options, 'run_id'); ctx_opts.run_id = options.run_id; end
        if isfield(options, 'revalidated_root_override')
            ctx_opts.revalidated_root_override = options.revalidated_root_override;
        end
        exp_name = 'mechanism_ablation_full';
        if strcmp(cfg.protocol_tier, 'smoke')
            exp_name = 'mechanism_ablation_smoke_via_full';
        end
        ctx = create_run_context(exp_name, ctx_opts);
        run_dir = ctx.run_dir;
        mkdir(fullfile(run_dir, 'cells'));
        save_run_manifest(ctx, cfg, struct( ...
            'stage', 'T103_full', ...
            'protocol_tier', cfg.protocol_tier, ...
            'active_analysis_set', cfg.active_analysis_set, ...
            'protocol_fingerprint', cfg.protocol_fingerprint, ...
            'frozen_operating_point', cfg.frozen_operating_point, ...
            'n_seeds_requested', numel(cfg.full_seeds), ...
            'n_seeds_this_run', numel(seeds), ...
            'n_cells', numel(cells), ...
            'use_reduced_lengths', used_reduced_lengths));
        atomic_save_results(fullfile(run_dir, 'preregistered_config.mat'), struct('cfg', cfg));
        if strcmp(cfg.protocol_tier, 'publication') && ...
                isfield(options, 'calibration_run_dir') && ...
                ~isempty(options.calibration_run_dir)
            copy_calibration_authority(options.calibration_run_dir, run_dir);
        end
    end

    cell_index = {};
    cell_results = {};
    n_fail = 0;
    seed_baseline_index = {};
    for iseed = 1:numel(seeds)
        seed = seeds(iseed);
        bundle = [];
        if numel(cells) > 0
            [bundle, bundle_path] = prepare_seed_matched_baselines( ...
                cfg, seed, cells, run_dir, save_results, struct());
            seed_baseline_index{end+1} = struct( ...
                'seed', seed, ...
                'bundle_id', bundle.bundle_id, ...
                'file', bundle_path, ...
                'status', bundle.baseline_result_status); %#ok<AGROW>
        end
        for ic = 1:numel(cells)
            cell_spec = cells{ic};
            if verbose
                fprintf('Full %d/%d seed=%d cell=%s\n', ...
                    (iseed-1)*numel(cells)+ic, numel(seeds)*numel(cells), ...
                    seed, cell_spec.cell_key);
            end
            cell_opts = struct( ...
                'verbose', verbose, ...
                'run_secondary', run_secondary);
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
                'file', fname, ...
                'seed', seed, ...
                'cell_key', cell_spec.cell_key, ...
                'status', cr.status, ...
                'wall_time_seconds', cr.wall_time_seconds, ...
                'matched_baseline_bundle_id', local_get(cr, 'matched_baseline_bundle_id', '')); %#ok<AGROW>
        end
    end

    aggregate = struct('status', 'not_computed');
    inference = struct('status', 'skipped', 'aggregation_inference_complete', false);
    if save_results && n_fail == 0 && ~isempty(cell_results)
        allow_incomplete = used_reduced_lengths || ...
            ~strcmp(cfg.protocol_tier, 'publication') || ...
            numel(seeds) < numel(cfg.seeds) || ...
            numel(cells) < numel(cfg.cells);
        agg_opts = struct('save', true);
        if allow_incomplete
            agg_opts.allow_incomplete_diagnostic = true;
        end
        aggregate = aggregate_ablation_results(run_dir, agg_opts);
        if strcmp(char(local_get(aggregate, 'status', '')), 'ok') && ...
                logical(local_get(aggregate, 'matched_seed_contrast_structure_complete', false)) && ...
                strcmp(cfg.protocol_tier, 'publication') && ~used_reduced_lengths && ...
                numel(seeds) == numel(cfg.seeds) && numel(cells) == numel(cfg.cells)
            inference = run_seed_level_inference(run_dir, struct('save', true));
            aggregate.inference_status = inference.inference_status;
            aggregate.aggregation_inference_complete = inference.aggregation_inference_complete;
        elseif strcmp(char(local_get(aggregate, 'status', '')), 'ok') && ...
                logical(local_get(aggregate, 'matched_seed_contrast_structure_complete', false))
            try
                inference = run_seed_level_inference(run_dir, struct('save', true));
                aggregate.inference_status = inference.inference_status;
                aggregate.aggregation_inference_complete = false;
            catch ME
                inference = struct('status', 'failed', 'error_id', ME.identifier, ...
                    'aggregation_inference_complete', false);
            end
        end
    end

    % Final cfg is established (including frozen OP / smoke rebuild) — gate once.
    [temporal_gate, ~, gate_manifest] = ...
        evaluate_and_persist_temporal_learning_gate(cfg, run_dir, save_results);

    readiness = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', cell_results, ...
        'has_manifest', save_results, ...
        'has_commit_sha', save_results, ...
        'has_artifact_hashes', false, ...
        'run_dir', run_dir, ...
        'temporal_learning_gate', temporal_gate, ...
        'aggregation', aggregate));

    % Hard overrides for reduced/smoke masquerading as full.
    if used_reduced_lengths || ~strcmp(cfg.protocol_tier, 'publication')
        readiness.publication_protocol_complete = false;
        readiness.publication_ready = false;
    end

    result = struct();
    result.cfg = cfg;
    result.analysis_set = cfg.active_analysis_set;
    result.protocol_tier = cfg.protocol_tier;
    result.protocol_fingerprint = cfg.protocol_fingerprint;
    result.seeds = seeds;
    result.n_seeds_requested = numel(cfg.full_seeds);
    result.n_seeds_completed = numel(seeds);
    result.n_cells = numel(cells);
    result.n_failed = n_fail;
    result.cell_index = cell_index;
    result.aggregate = aggregate;
    result.seed_baseline_index = seed_baseline_index;
    result.temporal_learning_gate = temporal_gate;
    result.frozen_operating_point = local_get(cfg, 'frozen_operating_point', struct([]));
    result.run_dir = run_dir;
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
    result.matched_seed_contrast_structure_complete = ...
        local_get(readiness, 'matched_seed_contrast_structure_complete', false);
    result.inference = inference;
    result.inference_status = char(local_get(inference, 'inference_status', ...
        local_get(inference, 'status', 'skipped')));
    result.aggregation_inference_complete = readiness.aggregation_inference_complete;
    if isfield(inference, 'inference_manifest_hash')
        result.inference_manifest_hash = inference.inference_manifest_hash;
    else
        result.inference_manifest_hash = '';
    end
    result.artifact_package_complete = readiness.artifact_package_complete;
    result.publication_ready = readiness.publication_ready;
    result.readiness = readiness;
    result.status = ternary(n_fail == 0, 'ok', 'failed_cells');
    result.completion_note = sprintf( ...
        ['Completed %d/%d preregistered seeds and %d/%d cells. ', ...
         'protocol_tier=%s publication_ready=%d structurally_complete=%d.'], ...
        numel(seeds), numel(cfg.full_seeds), numel(cells), cfg.n_cells, ...
        cfg.protocol_tier, result.publication_ready, result.structurally_complete);

    if save_results
        atomic_save_results(fullfile(run_dir, 'full_summary.mat'), struct('result', result));
        man = struct( ...
            'stage', 'T103_full_complete', ...
            'status', result.status, ...
            'protocol_tier', cfg.protocol_tier, ...
            'active_analysis_set', cfg.active_analysis_set, ...
            'protocol_fingerprint', cfg.protocol_fingerprint, ...
            'structurally_complete', result.structurally_complete, ...
            'publication_protocol_complete', result.publication_protocol_complete, ...
            'all_primary_endpoints_finite', result.all_primary_endpoints_finite, ...
            'all_qa_checks_pass', result.all_qa_checks_pass, ...
            'all_required_secondary_endpoints_complete', ...
                local_get(result, 'all_required_secondary_endpoints_complete', false), ...
            'artifact_package_complete', result.artifact_package_complete, ...
            'publication_ready', result.publication_ready, ...
            'completion_note', result.completion_note, ...
            'n_failed', n_fail);
        man = merge_structs(man, gate_manifest);
        save_run_manifest(ctx, cfg, man);
    end
end

function out = merge_structs(a, b)
    out = a;
    fn = fieldnames(b);
    for i = 1:numel(fn)
        out.(fn{i}) = b.(fn{i});
    end
end

function reject_temporal_gate_override(options, runner_id)
    if isfield(options, 'temporal_learning_gate_override') && ...
            ~isempty(options.temporal_learning_gate_override)
        error(sprintf('%s:TemporalGateOverrideForbidden', runner_id), ...
            'temporal_learning_gate_override is forbidden for publication runners.');
    end
    if logical(local_get(options, 'allow_injected_test_fixture', false))
        error(sprintf('%s:InjectedFixtureForbidden', runner_id), ...
            'allow_injected_test_fixture is forbidden for publication runners.');
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
