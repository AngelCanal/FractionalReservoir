function [calibration, run_dir] = calibrate_operating_point(options)
%CALIBRATE_OPERATING_POINT  Publication-geometry operating-point calibration.
%
%   [calibration, run_dir] = calibrate_operating_point()
%   [calibration, run_dir] = calibrate_operating_point(options)
%
% Uses publication n=40 geometry and frozen calibration protocol only.
% Allowed options: save_results, verbose, run_id, revalidated_root_override.

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end
    this_dir = fileparts(mfilename('fullpath'));
    addpath(this_dir);

    reject_calibration_scientific_overrides(options);

    save_results = local_get(options, 'save_results', true);
    verbose = local_get(options, 'verbose', true);

    cfg = mechanism_ablation_config('publication', 'confirmatory');
    assert(cfg.base.n == 40, 'calibrate_operating_point:NetworkSize', ...
        'Publication calibration requires n=40.');
    assert(strcmp(cfg.protocol_tier, 'publication'), ...
        'calibrate_operating_point:ProtocolTier', ...
        'Publication calibration requires protocol_tier=publication.');
    op = cfg.operating_point;
    seeds = op.calibration_seeds(:)';
    assert(isequal(seeds, [1729, 2718]), ...
        'calibrate_operating_point:CalibrationSeeds', ...
        'Calibration seeds must be exactly [1729, 2718].');
    assert(isempty(intersect(seeds, cfg.publication_seeds)), ...
        'calibrate_operating_point:SeedOverlap', ...
        'Calibration seeds must not overlap publication seeds.');

    [probe_keys, probe_cells] = build_operating_point_calibration_probe_keys(cfg);
    cal_fp = compute_calibration_protocol_fingerprint(cfg, probe_keys);
    base_fp = compute_protocol_fingerprint(cfg);

    rng_state = capture_global_rng_state();
    global_rng_mutated = false;

    run_dir = '';
    ctx = struct();
    if save_results
        ctx_opts = struct('master_seed', seeds(1));
        if isfield(options, 'run_id'); ctx_opts.run_id = options.run_id; end
        if isfield(options, 'revalidated_root_override')
            ctx_opts.revalidated_root_override = options.revalidated_root_override;
        end
        ctx = create_run_context('operating_point_calibration', ctx_opts);
        run_dir = ctx.run_dir;
        save_run_manifest(ctx, cfg, struct( ...
            'stage', 'operating_point_calibration', ...
            'calibration_protocol_version', op.protocol_version, ...
            'calibration_protocol_fingerprint', cal_fp, ...
            'probe_cell_keys', {probe_keys}));
    end

    input_by_seed = struct();
    for iseed = 1:numel(seeds)
        seed = seeds(iseed);
        input_seed = seed + op.input_seed_offset;
        stream = RandStream('mt19937ar', 'Seed', input_seed);
        U = op.input_min + (op.input_max - op.input_min) * ...
            rand(stream, op.total_steps, cfg.base.n_inputs);
        input_by_seed.(seed_field(seed)) = struct( ...
            'calibration_seed', seed, ...
            'input_seed', input_seed, ...
            'input_hash', canonical_sha256(U), ...
            'input_length', size(U, 1), ...
            'input_distribution', op.input_distribution, ...
            'input_min', op.input_min, ...
            'input_max', op.input_max, ...
            'U', U);
    end
    global_rng_mutated = ~rng_states_equal(rng_state, capture_global_rng_state());

    n_candidates = numel(op.candidate_order);
    n_conditions = numel(probe_keys);
    n_seeds = numel(seeds);
    expected_rows = n_candidates * n_conditions * n_seeds;

    trial_rows = cell(expected_rows, 1);
    row_idx = 0;
    selected = struct('input_scaling', [], 'level_of_chaos', [], 'candidate_index', []);
    status = 'no_feasible_operating_point';

    for icand = 1:n_candidates
        cand = op.candidate_order{icand};
        iscale = cand.input_scaling;
        loc = cand.level_of_chaos;
        cand_pass_all = true;

        for icell = 1:n_conditions
            cell_spec = probe_cells{icell};
            for iseed = 1:n_seeds
                seed = seeds(iseed);
                row_idx = row_idx + 1;
                in_info = input_by_seed.(seed_field(seed));
                ov = struct('input_scaling', iscale, 'level_of_chaos', loc);
                [params, meta] = build_ablation_params(cell_spec, seed, cfg, ov);
                esn = SRNN_ESN(params);
                diag = probe_operating_point_activity(esn, in_info.U, op);
                dale_v = meta.sign_violations_E + meta.sign_violations_I;
                passes = evaluate_activity_pass(diag, dale_v, op);
                if ~passes.row_pass
                    cand_pass_all = false;
                end

                trial_rows{row_idx} = build_trial_row( ...
                    op.protocol_version, cal_fp, icand, iscale, loc, cell_spec, ...
                    seed, in_info, cfg, op, diag, dale_v, passes);

                if verbose
                    fprintf(['calib cand=%02d is=%.2f loc=%.2f %s seed=%d ', ...
                        'pass=%d rate=%.3f sat=%.3f sil=%.3f dale=%d\n'], ...
                        icand, iscale, loc, cell_spec.cell_key, seed, passes.row_pass, ...
                        diag.mean_rate, diag.saturation_fraction, ...
                        diag.silent_fraction, dale_v);
                end
            end
        end

        if cand_pass_all && isempty(selected.input_scaling)
            selected = struct( ...
                'input_scaling', iscale, ...
                'level_of_chaos', loc, ...
                'candidate_index', icand);
            status = 'frozen';
        end
    end

    trial_table = struct2table(vertcat(trial_rows{:}), 'AsArray', true);
    candidate_table = build_candidate_summary_table(trial_table, op.candidate_order);

    frozen_operating_point = struct([]);
    if strcmp(status, 'frozen')
        frozen_operating_point = struct( ...
            'input_scaling', selected.input_scaling, ...
            'level_of_chaos', selected.level_of_chaos, ...
            'candidate_index', selected.candidate_index);
    end

    input_hashes_by_seed = struct();
    for iseed = 1:n_seeds
        seed = seeds(iseed);
        input_hashes_by_seed.(seed_field(seed)) = ...
            input_by_seed.(seed_field(seed)).input_hash;
    end

    table_hashes = struct();
    table_hashes.calibration_trial_table = canonical_sha256(table_for_hash(trial_table));
    table_hashes.calibration_candidate_table = canonical_sha256(table_for_hash(candidate_table));

    manifest = struct();
    manifest.schema_version = 'publication_operating_point_calibration_artifact_v1';
    manifest.calibration_protocol_version = op.protocol_version;
    manifest.calibration_protocol_fingerprint = cal_fp;
    manifest.base_publication_config_fingerprint = base_fp;
    manifest.network_size = op.network_size;
    manifest.dt = op.dt;
    manifest.calibration_seeds = seeds;
    manifest.publication_seeds_hash = canonical_sha256(cfg.publication_seeds(:)');
    manifest.probe_cell_keys = probe_keys;
    manifest.candidate_order = op.candidate_order;
    manifest.expected_trial_row_count = expected_rows;
    manifest.observed_trial_row_count = height(trial_table);
    manifest.input_hashes_by_seed = input_hashes_by_seed;
    manifest.bands = struct( ...
        'mean_rate_band', op.mean_rate_band, ...
        'saturation_fraction_max', op.saturation_fraction_max, ...
        'silent_fraction_max', op.silent_fraction_max, ...
        'dale_violations_max', 0);
    manifest.washout_steps = op.washout_steps;
    manifest.evaluation_steps = op.evaluation_steps;
    manifest.solver_tolerances = struct( ...
        'ode_reltol', op.ode_reltol, ...
        'ode_abstol', op.ode_abstol, ...
        'dde_reltol', op.dde_reltol, ...
        'dde_abstol', op.dde_abstol);
    manifest.selection_rule = op.selection_rule;
    manifest.selected_candidate_index = local_selected_index(status, selected);
    manifest.frozen_operating_point = frozen_operating_point;
    manifest.status = status;
    manifest.table_content_hashes = table_hashes;
    manifest.configuration_hash = canonical_sha256(manifest_for_config_hash(manifest));
    manifest.provenance_mode = 'executed_publication_geometry_calibration';
    manifest.scientific_overrides_used = false;
    manifest.global_rng_mutated = global_rng_mutated;
    manifest.creation_code_commit_sha = try_git_head();
    manifest.created_utc = char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
    manifest.artifact_content_hash = canonical_sha256(manifest_for_content_hash(manifest));

    result = struct();
    result.status = status;
    result.frozen_operating_point = frozen_operating_point;
    result.selected_candidate_index = manifest.selected_candidate_index;
    result.calibration_protocol_fingerprint = cal_fp;
    result.calibration_manifest_hash = manifest.artifact_content_hash;
    result.global_rng_mutated = global_rng_mutated;
    result.scientific_overrides_used = false;

    calibration = struct();
    calibration.schema_version = manifest.schema_version;
    calibration.calibration_protocol_version = op.protocol_version;
    calibration.calibration_protocol_fingerprint = cal_fp;
    calibration.calibration_manifest_hash = manifest.artifact_content_hash;
    calibration.calibration_seeds = seeds;
    calibration.probe_cell_keys = probe_keys;
    calibration.trial_table = trial_table;
    calibration.candidate_table = candidate_table;
    calibration.frozen_operating_point = frozen_operating_point;
    calibration.status = status;
    calibration.run_dir = run_dir;
    calibration.manifest = manifest;
    calibration.global_rng_mutated = global_rng_mutated;
    calibration.scientific_overrides_used = false;
    calibration.no_outcome_fishing = true;

    if save_results
        payload = struct( ...
            'cfg', sanitize_calibration_cfg(cfg, probe_keys, cal_fp), ...
            'plan', build_calibration_plan_struct(cfg, probe_keys, cal_fp), ...
            'trial_table', trial_table, ...
            'candidate_table', candidate_table, ...
            'result', result, ...
            'manifest', manifest);
        write_operating_point_calibration_artifacts(run_dir, payload);
        save_run_manifest(ctx, cfg, struct( ...
            'stage', 'operating_point_calibration_complete', ...
            'status', status, ...
            'calibration_manifest_hash', manifest.artifact_content_hash, ...
            'selected_candidate_index', manifest.selected_candidate_index));
    end
end

function reject_calibration_scientific_overrides(options)
    forbidden = { ...
        'cfg', ...
        'probe_cell_keys', ...
        'calibration_seeds', ...
        'candidate_input_scaling', ...
        'candidate_level_of_chaos', ...
        'mean_rate_band', ...
        'saturation_fraction_max', ...
        'silent_fraction_max', ...
        'washout_steps', ...
        'evaluation_steps', ...
        'input_distribution', ...
        'solver_tolerances', ...
        'selection_rule', ...
        'frozen_operating_point' ...
        };
    for i = 1:numel(forbidden)
        if isfield(options, forbidden{i}) && ~isempty(options.(forbidden{i}))
            error('calibrate_operating_point:ScientificOverrideForbidden', ...
                'Option %s is forbidden for publication calibration.', forbidden{i});
        end
    end
end

function diag = probe_operating_point_activity(esn, U, op)
    run_opts = struct( ...
        'reset_before', true, ...
        'update_internal_state', false, ...
        'ode_reltol', op.ode_reltol, ...
        'ode_abstol', op.ode_abstol, ...
        'dde_reltol', op.dde_reltol, ...
        'dde_abstol', op.dde_abstol);
    [~, S_hist] = esn.runReservoir(U, run_opts);
    eval_idx = (op.washout_steps + 1):op.total_steps;
    n_eval = numel(eval_idx);
    n_neurons = size(S_hist, 2);
    rates = zeros(n_neurons, n_eval);
    for k = 1:n_eval
        rates(:, k) = esn.computeRates(S_hist(eval_idx(k), :)');
    end
    diag = struct();
    diag.mean_rate = mean(rates(:));
    diag.saturation_fraction = mean(rates(:) >= 0.99);
    diag.silent_fraction = mean(rates(:) <= 0.01);
    diag.n_eval_time_points = n_eval;
    diag.n_neurons = n_neurons;
    diag.n_rate_observations = numel(rates);
end

function passes = evaluate_activity_pass(diag, dale_v, op)
    passes = struct();
    passes.mean_rate_pass = diag.mean_rate >= op.mean_rate_band(1) && ...
        diag.mean_rate <= op.mean_rate_band(2);
    passes.saturation_pass = diag.saturation_fraction <= op.saturation_fraction_max;
    passes.silent_pass = diag.silent_fraction <= op.silent_fraction_max;
    passes.dale_pass = isfinite(dale_v) && dale_v == 0;
    passes.row_pass = passes.mean_rate_pass && passes.saturation_pass && ...
        passes.silent_pass && passes.dale_pass;
end

function row = build_trial_row(protocol_version, cal_fp, candidate_index, ...
        input_scaling, level_of_chaos, cell_spec, seed, in_info, cfg, op, ...
        diag, dale_v, passes)
    row = struct();
    row.protocol_version = protocol_version;
    row.calibration_protocol_fingerprint = cal_fp;
    row.candidate_index = candidate_index;
    row.input_scaling = input_scaling;
    row.level_of_chaos = level_of_chaos;
    row.cell_key = cell_spec.cell_key;
    row.adaptation = cell_spec.adaptation;
    row.std = cell_spec.std;
    row.delay = cell_spec.delay;
    row.feature = cell_spec.readout_features;
    row.calibration_seed = seed;
    row.input_seed = in_info.input_seed;
    row.input_hash = in_info.input_hash;
    row.network_size = cfg.base.n;
    row.dt = cfg.base.dt;
    row.washout_steps = op.washout_steps;
    row.evaluation_steps = op.evaluation_steps;
    row.ode_reltol = op.ode_reltol;
    row.ode_abstol = op.ode_abstol;
    row.dde_reltol = op.dde_reltol;
    row.dde_abstol = op.dde_abstol;
    row.mean_rate = diag.mean_rate;
    row.saturation_fraction = diag.saturation_fraction;
    row.silent_fraction = diag.silent_fraction;
    row.dale_violations = dale_v;
    row.mean_rate_pass = passes.mean_rate_pass;
    row.saturation_pass = passes.saturation_pass;
    row.silent_pass = passes.silent_pass;
    row.dale_pass = passes.dale_pass;
    row.row_pass = passes.row_pass;
    if passes.row_pass
        row.status = 'pass';
    else
        row.status = 'fail';
    end
end

function candidate_table = build_candidate_summary_table(trial_table, candidate_order)
    n_candidates = numel(candidate_order);
    rows = cell(n_candidates, 1);
    selection_rank = 0;
    for ic = 1:n_candidates
        mask = trial_table.candidate_index == ic;
        sub = trial_table(mask, :);
        n_expected = 32;
        all_finite = all(isfinite(sub.mean_rate)) && ...
            all(isfinite(sub.saturation_fraction)) && ...
            all(isfinite(sub.silent_fraction)) && ...
            all(isfinite(sub.dale_violations));
        all_pass = all(sub.row_pass);
        feasible = height(sub) == n_expected && all_finite && all_pass;
        selected = false;
        if feasible
            selection_rank = selection_rank + 1;
            if selection_rank == 1
                selected = true;
            end
        end
        cand = candidate_order{ic};
        rows{ic} = struct( ...
            'candidate_index', ic, ...
            'input_scaling', cand.input_scaling, ...
            'level_of_chaos', cand.level_of_chaos, ...
            'n_expected_rows', n_expected, ...
            'n_observed_rows', height(sub), ...
            'all_rows_finite', all_finite, ...
            'all_rows_pass', all_pass, ...
            'feasible', feasible, ...
            'selection_rank', ternary(feasible, selection_rank, 0), ...
            'selected', selected);
    end
    candidate_table = struct2table(vertcat(rows{:}), 'AsArray', true);
end

function plan = build_calibration_plan_struct(cfg, probe_keys, cal_fp)
    op = cfg.operating_point;
    plan = struct();
    plan.protocol_version = op.protocol_version;
    plan.calibration_protocol_fingerprint = cal_fp;
    plan.network_size = op.network_size;
    plan.dt = op.dt;
    plan.calibration_seeds = op.calibration_seeds(:)';
    plan.probe_cell_keys = probe_keys;
    plan.candidate_order = op.candidate_order;
    plan.input_distribution = op.input_distribution;
    plan.input_min = op.input_min;
    plan.input_max = op.input_max;
    plan.input_seed_offset = op.input_seed_offset;
    plan.washout_steps = op.washout_steps;
    plan.evaluation_steps = op.evaluation_steps;
    plan.total_steps = op.total_steps;
    plan.bands = struct( ...
        'mean_rate_band', op.mean_rate_band, ...
        'saturation_fraction_max', op.saturation_fraction_max, ...
        'silent_fraction_max', op.silent_fraction_max, ...
        'dale_violations_max', 0);
    plan.solver_tolerances = struct( ...
        'ode_reltol', op.ode_reltol, ...
        'ode_abstol', op.ode_abstol, ...
        'dde_reltol', op.dde_reltol, ...
        'dde_abstol', op.dde_abstol);
    plan.selection_rule = op.selection_rule;
end

function cfg_out = sanitize_calibration_cfg(cfg, probe_keys, cal_fp)
    cfg_out = cfg;
    cfg_out.calibration_plan = build_calibration_plan_struct(cfg, probe_keys, cal_fp);
end

function idx = local_selected_index(status, selected)
    if strcmp(status, 'frozen')
        idx = selected.candidate_index;
    else
        idx = [];
    end
end

function name = seed_field(seed)
    name = sprintf('seed_%d', seed);
end

function state = capture_global_rng_state()
    state = struct();
    state.type = rng;
    state.stream = RandStream.getGlobalStream;
end

function tf = rng_states_equal(a, b)
    tf = isequal(a.type, b.type);
end

function T = table_for_hash(T)
    if istable(T)
        T = table2struct(T);
    end
end

function m = manifest_for_config_hash(manifest)
    m = manifest;
    drop = {'created_utc', 'artifact_content_hash', 'creation_code_commit_sha', ...
        'configuration_hash'};
    for i = 1:numel(drop)
        if isfield(m, drop{i})
            m = rmfield(m, drop{i});
        end
    end
end

function m = manifest_for_content_hash(manifest)
    m = manifest_for_config_hash(manifest);
    if isfield(m, 'configuration_hash')
        m = rmfield(m, 'configuration_hash');
    end
end

function sha = try_git_head()
    sha = '';
    try
        [status, out] = system('git rev-parse HEAD');
        if status == 0
            sha = strtrim(out);
        end
    catch
        sha = '';
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
