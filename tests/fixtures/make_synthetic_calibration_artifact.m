function run_dir = make_synthetic_calibration_artifact(opts)
%MAKE_SYNTHETIC_CALIBRATION_ARTIFACT  Synthetic calibration artifact fixture.
%
%   run_dir = make_synthetic_calibration_artifact()
%   run_dir = make_synthetic_calibration_artifact(opts)
%
% Does not execute reservoir simulations. Builds a valid 512-row artifact by
% default with the first candidate feasible.

    if nargin < 1 || isempty(opts)
        opts = struct();
    end

    cfg = mechanism_ablation_config('publication', 'confirmatory');
    [probe_keys, ~] = build_operating_point_calibration_probe_keys(cfg);
    op = cfg.operating_point;
    cal_fp = compute_calibration_protocol_fingerprint(cfg, probe_keys);
    base_fp = compute_protocol_fingerprint(cfg);

    root = tempname;
    mkdir(root);
    run_dir = fullfile(root, 'synth_calibration');
    mkdir(run_dir);

    seeds = op.calibration_seeds(:)';
    first_feasible = double(local_get(opts, 'first_feasible_candidate', 1));
    status = char(local_get(opts, 'status', 'frozen'));
    if first_feasible <= 0
        status = 'no_feasible_operating_point';
    end

    input_hashes = struct();
    for is = 1:numel(seeds)
        seed = seeds(is);
        input_seed = seed + op.input_seed_offset;
        stream = RandStream('mt19937ar', 'Seed', input_seed);
        U = op.input_min + (op.input_max - op.input_min) * ...
            rand(stream, op.total_steps, cfg.base.n_inputs);
        input_hashes.(sprintf('seed_%d', seed)) = canonical_sha256(U);
    end

    trial_rows = {};
    row_idx = 0;
    for ic = 1:16
        cand = op.candidate_order{ic};
        feasible = ic == first_feasible && first_feasible > 0;
        for ip = 1:numel(probe_keys)
            cell_key = probe_keys{ip};
            parts = strsplit(cell_key, '__');
            adapt = strrep(parts{1}, 'adapt-', '');
            std_l = strrep(parts{2}, 'std-', '');
            delay_l = strrep(parts{3}, 'delay-', '');
            for is = 1:numel(seeds)
                seed = seeds(is);
                row_idx = row_idx + 1;
                ih = input_hashes.(sprintf('seed_%d', seed));
                mean_rate = ternary(feasible, 0.4, 0.95);
                sat_frac = ternary(feasible, 0.1, 0.9);
                sil_frac = ternary(feasible, 0.1, 0.05);
                dale_v = 0;
                passes = evaluate_activity_pass_local(mean_rate, sat_frac, sil_frac, ...
                    dale_v, op);
                if isfield(opts, 'tamper_metric_row') && opts.tamper_metric_row == row_idx
                    mean_rate = 0.99;
                    passes = evaluate_activity_pass_local(mean_rate, sat_frac, sil_frac, ...
                        dale_v, op);
                    passes.row_pass = true;  % inconsistent pass flag for tamper test
                end
                if isfield(opts, 'tamper_pass_row') && opts.tamper_pass_row == row_idx
                    passes.row_pass = ~passes.row_pass;
                end
                packed_dim = synthetic_packed_dimension(cell_key, cfg.base.n);
                trial_rows{row_idx} = struct( ...
                    'protocol_version', op.protocol_version, ...
                    'calibration_protocol_fingerprint', cal_fp, ...
                    'candidate_index', ic, ...
                    'input_scaling', cand.input_scaling, ...
                    'level_of_chaos', cand.level_of_chaos, ...
                    'cell_key', cell_key, ...
                    'adaptation', adapt, ...
                    'std', std_l, ...
                    'delay', delay_l, ...
                    'feature', 'x', ...
                    'calibration_seed', seed, ...
                    'input_seed', seed + op.input_seed_offset, ...
                    'input_hash', ih, ...
                    'network_size', cfg.base.n, ...
                    'dt', cfg.base.dt, ...
                    'washout_steps', op.washout_steps, ...
                    'evaluation_steps', op.evaluation_steps, ...
                    'ode_reltol', op.ode_reltol, ...
                    'ode_abstol', op.ode_abstol, ...
                    'dde_reltol', op.dde_reltol, ...
                    'dde_abstol', op.dde_abstol, ...
                    'mean_rate', mean_rate, ...
                    'saturation_fraction', sat_frac, ...
                    'silent_fraction', sil_frac, ...
                    'dale_violations', dale_v, ...
                    'n_eval_time_points', op.evaluation_steps, ...
                    'n_neurons', cfg.base.n, ...
                    'n_rate_observations', op.evaluation_steps * cfg.base.n, ...
                    'packed_state_dimension', packed_dim, ...
                    'mean_rate_pass', passes.mean_rate_pass, ...
                    'saturation_pass', passes.saturation_pass, ...
                    'silent_pass', passes.silent_pass, ...
                    'dale_pass', passes.dale_pass, ...
                    'row_pass', passes.row_pass, ...
                    'status', ternary(passes.row_pass, 'pass', 'fail'));
            end
        end
    end

    if isfield(opts, 'omit_row') && ~isempty(opts.omit_row)
        trial_rows(opts.omit_row) = [];
    end
    if isfield(opts, 'duplicate_row') && ~isempty(opts.duplicate_row)
        trial_rows{end+1} = trial_rows{opts.duplicate_row}; %#ok<AGROW>
    end

    trial_table = struct2table(vertcat(trial_rows{:}), 'AsArray', true);
    candidate_table = build_candidate_summary_table_local(trial_table, op.candidate_order);

    if isfield(opts, 'tamper_selected_index') && opts.tamper_selected_index
        candidate_table.selected(:) = false;
        candidate_table.selected(2) = true;
    end

    frozen_operating_point = struct([]);
    selected_idx = [];
    if strcmp(status, 'frozen') && any(candidate_table.selected)
        sel = find(candidate_table.selected, 1);
        selected_idx = sel;
        frozen_operating_point = struct( ...
            'input_scaling', candidate_table.input_scaling(sel), ...
            'level_of_chaos', candidate_table.level_of_chaos(sel), ...
            'candidate_index', sel);
    end

    table_hashes = struct();
    table_hashes.calibration_trial_table = canonical_sha256(table2struct(trial_table));
    table_hashes.calibration_candidate_table = canonical_sha256(table2struct(candidate_table));

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
    manifest.expected_trial_row_count = 512;
    manifest.observed_trial_row_count = height(trial_table);
    manifest.input_hashes_by_seed = input_hashes;
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
    manifest.selected_candidate_index = selected_idx;
    manifest.frozen_operating_point = frozen_operating_point;
    manifest.status = status;
    manifest.table_content_hashes = table_hashes;
    manifest.provenance_mode = 'executed_publication_geometry_calibration';
    manifest.scientific_overrides_used = false;
    manifest.global_rng_mutated = false;
    manifest.global_rng_restored = true;
    manifest.creation_code_commit_sha = 'synthetic_fixture';
    manifest.created_utc = '2026-07-16T00:00:00Z';

    if isfield(opts, 'overlap_seeds') && opts.overlap_seeds
        manifest.calibration_seeds = [1729, cfg.publication_seeds(1)];
    end

    cfg.calibration_plan = build_synthetic_plan(cfg, probe_keys, cal_fp, base_fp);
    config_payload = cfg;
    result = struct();
    result.status = status;
    result.frozen_operating_point = frozen_operating_point;
    result.selected_candidate_index = selected_idx;
    result.calibration_protocol_fingerprint = cal_fp;
    result.global_rng_mutated = false;
    result.global_rng_restored = true;
    result.scientific_overrides_used = false;

    manifest.configuration_hash = canonical_sha256(manifest_for_config_hash(manifest));
    manifest.calibration_config_content_hash = canonical_sha256(calibration_config_for_hash(config_payload));
    manifest.calibration_result_content_hash = canonical_sha256(result_for_hash_local(result));
    manifest.artifact_content_hash = canonical_sha256(manifest_for_content_hash(manifest));
    result.calibration_manifest_hash = manifest.artifact_content_hash;

    if isfield(opts, 'tamper_hash') && opts.tamper_hash
        manifest.artifact_content_hash = 'deadbeef';
    end
    if isfield(opts, 'tamper_result') && opts.tamper_result
        result.status = 'tampered';
    end

    payload = struct( ...
        'cfg', config_payload, ...
        'plan', cfg.calibration_plan, ...
        'trial_table', trial_table, ...
        'candidate_table', candidate_table, ...
        'result', result, ...
        'manifest', manifest);
    write_operating_point_calibration_artifacts(run_dir, payload);
end

function dim = synthetic_packed_dimension(cell_key, n)
    if contains(cell_key, 'adapt-off') && contains(cell_key, 'std-off')
        dim = n;
    elseif contains(cell_key, 'dde_on')
        dim = n + round(n * 0.5) * 3 + round(n * 0.5);
    else
        dim = n + round(n * 0.5) * 3 + round(n * 0.5) * 2;
    end
end

function plan = build_synthetic_plan(cfg, probe_keys, cal_fp, base_fp)
    op = cfg.operating_point;
    plan = struct();
    plan.protocol_version = op.protocol_version;
    plan.calibration_protocol_fingerprint = cal_fp;
    plan.base_publication_config_fingerprint = base_fp;
    plan.calibration_seeds = op.calibration_seeds(:)';
    plan.probe_cell_keys = probe_keys;
    plan.candidate_order = op.candidate_order;
    plan.input_min = op.input_min;
    plan.input_max = op.input_max;
    plan.input_seed_offset = op.input_seed_offset;
    plan.total_steps = op.total_steps;
    plan.n_inputs = cfg.base.n_inputs;
end

function r = result_for_hash_local(result)
    r = result;
    if isfield(r, 'calibration_manifest_hash')
        r = rmfield(r, 'calibration_manifest_hash');
    end
end

function passes = evaluate_activity_pass_local(mean_rate, sat_frac, sil_frac, dale_v, op)
    passes = struct();
    passes.mean_rate_pass = mean_rate >= op.mean_rate_band(1) && ...
        mean_rate <= op.mean_rate_band(2);
    passes.saturation_pass = sat_frac <= op.saturation_fraction_max;
    passes.silent_pass = sil_frac <= op.silent_fraction_max;
    passes.dale_pass = dale_v == 0;
    passes.row_pass = passes.mean_rate_pass && passes.saturation_pass && ...
        passes.silent_pass && passes.dale_pass;
end

function candidate_table = build_candidate_summary_table_local(trial_table, candidate_order)
    n_candidates = numel(candidate_order);
    rows = cell(n_candidates, 1);
    selection_rank = 0;
    for ic = 1:n_candidates
        mask = trial_table.candidate_index == ic;
        sub = trial_table(mask, :);
        n_expected = 32;
        all_finite = all(isfinite(sub.mean_rate));
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

function m = manifest_for_config_hash(manifest)
    m = manifest;
    drop = {'created_utc', 'artifact_content_hash', 'creation_code_commit_sha', ...
        'configuration_hash', 'calibration_config_content_hash', ...
        'calibration_result_content_hash'};
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
