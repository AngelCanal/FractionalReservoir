function [calibration, run_dir] = calibrate_operating_point(options)
%CALIBRATE_OPERATING_POINT  Publication-geometry operating-point calibration.
%
%   [calibration, run_dir] = calibrate_operating_point()
%   [calibration, run_dir] = calibrate_operating_point(options)
%
% Allowed options: save_results, verbose, run_id, revalidated_root_override,
% resume_run_dir.

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
    resume_run_dir = char(local_get(options, 'resume_run_dir', ''));
    if ~isempty(resume_run_dir) && ~save_results
        error('calibrate_operating_point:ResumeRequiresSave', ...
            'resume_run_dir requires save_results=true.');
    end

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
    plan = build_calibration_plan_struct(cfg, probe_keys, cal_fp, base_fp);
    commit_sha = try_git_head();

    run_dir = '';
    ctx = struct();
    if ~isempty(resume_run_dir)
        run_dir = resume_run_dir;
        ctx = struct('run_dir', run_dir);
        if isfile(fullfile(run_dir, 'calibration_manifest.mat'))
            calibration = load_completed_calibration_from_disk(run_dir);
            return;
        end
    elseif save_results
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

    input_by_seed = generate_calibration_inputs(cfg, op, seeds);
    input_hashes_by_seed = struct();
    for is = 1:numel(seeds)
        seed = seeds(is);
        input_hashes_by_seed.(seed_field(seed)) = ...
            input_by_seed.(seed_field(seed)).input_hash;
    end

    completed_table = [];
    completed_keys = {};
    checkpoint_created_utc = '';
    if ~isempty(resume_run_dir)
        cp = load_and_validate_calibration_checkpoint(run_dir, plan, commit_sha);
        checkpoint_created_utc = char(local_get(cp, 'created_utc', ''));
        if istable(cp.completed_trial_rows) && height(cp.completed_trial_rows) > 0
            completed_table = cp.completed_trial_rows;
            completed_keys = cp.completed_trial_keys(:)';
        end
    end

    rng_state_before = capture_global_rng_state();
    global_rng_mutated = false;
    global_rng_restored = false;

    try
        n_candidates = numel(op.candidate_order);
        n_conditions = numel(probe_keys);
        n_seeds = numel(seeds);

        for icand = 1:n_candidates
            cand = op.candidate_order{icand};
            iscale = cand.input_scaling;
            loc = cand.level_of_chaos;
            for icell = 1:n_conditions
                cell_spec = probe_cells{icell};
                for iseed = 1:n_seeds
                    seed = seeds(iseed);
                    trial_key = build_calibration_trial_key(icand, cell_spec.cell_key, seed);
                    if any(strcmp(completed_keys, trial_key))
                        continue;
                    end
                    in_info = input_by_seed.(seed_field(seed));
                    ov = struct('input_scaling', iscale, 'level_of_chaos', loc);
                    [params, meta] = build_ablation_params(cell_spec, seed, cfg, ov);
                    esn = SRNN_ESN(params);
                    diag = probe_operating_point_activity(esn, in_info.U, op);
                    dale_v = meta.sign_violations_E + meta.sign_violations_I;
                    passes = evaluate_activity_pass(diag, dale_v, op);
                    row = build_trial_row(op.protocol_version, cal_fp, icand, iscale, loc, ...
                        cell_spec, seed, in_info, cfg, op, diag, dale_v, passes);
                    if isempty(completed_table)
                        completed_table = struct2table(row, 'AsArray', true);
                    else
                        completed_table = [completed_table; struct2table(row, 'AsArray', true)]; %#ok<AGROW>
                    end
                    completed_keys{end+1} = trial_key; %#ok<AGROW>

                    if verbose
                        fprintf(['calib cand=%02d is=%.2f loc=%.2f %s seed=%d ', ...
                            'pass=%d rate=%.3f obs=%d\n'], ...
                            icand, iscale, loc, cell_spec.cell_key, seed, passes.row_pass, ...
                            diag.mean_rate, diag.n_rate_observations);
                    end

                    if save_results && ~isempty(run_dir)
                        cp = build_checkpoint_struct(plan, commit_sha, probe_keys, ...
                            input_hashes_by_seed, completed_table, completed_keys, ...
                            'in_progress');
                        if ~isempty(checkpoint_created_utc)
                            cp.created_utc = checkpoint_created_utc;
                        end
                        write_calibration_checkpoint(run_dir, cp);
                    end
                end
            end
        end

        global_rng_mutated = ~rng_states_equal(rng_state_before, capture_global_rng_state());
    catch ME
        global_rng_mutated = ~rng_states_equal(rng_state_before, capture_global_rng_state());
        restore_global_rng_state(rng_state_before);
        global_rng_restored = rng_states_equal(rng_state_before, capture_global_rng_state());
        rethrow(ME);
    end

    restore_global_rng_state(rng_state_before);
    global_rng_restored = rng_states_equal(rng_state_before, capture_global_rng_state());

    expected_rows = 512;
    if height(completed_table) ~= expected_rows
        error('calibrate_operating_point:IncompleteTrialMatrix', ...
            'Expected %d trial rows, got %d.', expected_rows, height(completed_table));
    end

    trial_table = completed_table;
    [status, selected, frozen_operating_point] = ...
        select_operating_point_from_trials(trial_table, op.candidate_order);
    candidate_table = build_candidate_summary_table(trial_table, op.candidate_order);

    calibration = finalize_calibration_artifacts(cfg, plan, probe_keys, cal_fp, base_fp, ...
        trial_table, candidate_table, status, selected, frozen_operating_point, ...
        input_hashes_by_seed, seeds, global_rng_mutated, global_rng_restored, commit_sha);

    if save_results && ~isempty(run_dir)
        write_operating_point_calibration_artifacts(run_dir, calibration.payload);
        cp = build_checkpoint_struct(plan, commit_sha, probe_keys, input_hashes_by_seed, ...
            trial_table, completed_keys, 'complete');
        write_calibration_checkpoint(run_dir, cp);
        save_run_manifest(ctx, cfg, struct( ...
            'stage', 'operating_point_calibration_complete', ...
            'status', status, ...
            'calibration_manifest_hash', calibration.manifest.artifact_content_hash, ...
            'selected_candidate_index', calibration.manifest.selected_candidate_index));
    end

    calibration = calibration.public;
    calibration.run_dir = run_dir;
end

function calibration = load_completed_calibration_from_disk(run_dir)
    report = validate_operating_point_calibration(run_dir);
    if ~report.valid
        error('calibrate_operating_point:InvalidCompletedArtifact', ...
            'Existing calibration artifact failed validation.');
    end
    Sm = load(fullfile(run_dir, 'calibration_manifest.mat'), 'calibration_manifest');
    St = load(fullfile(run_dir, 'calibration_trial_table.mat'), 'calibration_trial_table');
    Sc = load(fullfile(run_dir, 'calibration_candidate_table.mat'), ...
        'calibration_candidate_table');
    calibration = struct();
    calibration.schema_version = Sm.calibration_manifest.schema_version;
    calibration.calibration_protocol_version = Sm.calibration_manifest.calibration_protocol_version;
    calibration.calibration_protocol_fingerprint = report.calibration_protocol_fingerprint;
    calibration.calibration_manifest_hash = report.calibration_manifest_hash;
    calibration.calibration_seeds = Sm.calibration_manifest.calibration_seeds;
    calibration.probe_cell_keys = Sm.calibration_manifest.probe_cell_keys;
    calibration.trial_table = St.calibration_trial_table;
    calibration.candidate_table = Sc.calibration_candidate_table;
    calibration.frozen_operating_point = report.frozen_operating_point;
    calibration.status = report.status;
    calibration.manifest = Sm.calibration_manifest;
    calibration.global_rng_mutated = Sm.calibration_manifest.global_rng_mutated;
    calibration.global_rng_restored = Sm.calibration_manifest.global_rng_restored;
    calibration.scientific_overrides_used = false;
    calibration.no_outcome_fishing = true;
    calibration.run_dir = run_dir;
end

function input_by_seed = generate_calibration_inputs(cfg, op, seeds)
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
            'U', U);
    end
end

function cp = build_checkpoint_struct(plan, commit_sha, probe_keys, input_hashes, ...
        completed_table, completed_keys, status)
    cp = struct();
    cp.schema_version = 'publication_operating_point_calibration_checkpoint_v1';
    cp.calibration_protocol_version = plan.protocol_version;
    cp.calibration_protocol_fingerprint = plan.calibration_protocol_fingerprint;
    cp.base_publication_config_fingerprint = plan.base_publication_config_fingerprint;
    cp.creation_code_commit_sha = commit_sha;
    cp.candidate_order = plan.candidate_order;
    cp.probe_cell_keys = probe_keys;
    cp.calibration_seeds = plan.calibration_seeds;
    cp.input_hashes_by_seed = input_hashes;
    cp.expected_row_count = 512;
    cp.completed_row_count = height(completed_table);
    cp.completed_trial_rows = completed_table;
    cp.completed_trial_keys = completed_keys(:)';
    cp.status = status;
    if ~isfield(cp, 'created_utc') || isempty(cp.created_utc)
        cp.created_utc = char(datetime('now', 'TimeZone', 'UTC', ...
            'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
    end
end

function out = finalize_calibration_artifacts(cfg, plan, probe_keys, cal_fp, base_fp, ...
        trial_table, candidate_table, status, selected, frozen_operating_point, ...
        input_hashes_by_seed, seeds, global_rng_mutated, global_rng_restored, commit_sha)

    table_hashes = struct();
    table_hashes.calibration_trial_table = canonical_sha256(table_for_hash(trial_table));
    table_hashes.calibration_candidate_table = canonical_sha256(table_for_hash(candidate_table));

    config_payload = sanitize_calibration_cfg(cfg, probe_keys, cal_fp, base_fp);
    result = struct();
    result.status = status;
    result.frozen_operating_point = frozen_operating_point;
    result.selected_candidate_index = local_selected_index(status, selected);
    result.calibration_protocol_fingerprint = cal_fp;
    result.global_rng_mutated = global_rng_mutated;
    result.global_rng_restored = global_rng_restored;
    result.scientific_overrides_used = false;

    manifest = struct();
    manifest.schema_version = 'publication_operating_point_calibration_artifact_v1';
    manifest.calibration_protocol_version = plan.protocol_version;
    manifest.calibration_protocol_fingerprint = cal_fp;
    manifest.base_publication_config_fingerprint = base_fp;
    manifest.network_size = cfg.operating_point.network_size;
    manifest.dt = cfg.base.dt;
    manifest.calibration_seeds = seeds;
    manifest.publication_seeds_hash = canonical_sha256(cfg.publication_seeds(:)');
    manifest.probe_cell_keys = probe_keys;
    manifest.candidate_order = plan.candidate_order;
    manifest.expected_trial_row_count = 512;
    manifest.observed_trial_row_count = height(trial_table);
    manifest.input_hashes_by_seed = input_hashes_by_seed;
    manifest.bands = plan.bands;
    manifest.washout_steps = plan.washout_steps;
    manifest.evaluation_steps = plan.evaluation_steps;
    manifest.solver_tolerances = plan.solver_tolerances;
    manifest.selection_rule = plan.selection_rule;
    manifest.selected_candidate_index = result.selected_candidate_index;
    manifest.frozen_operating_point = frozen_operating_point;
    manifest.status = status;
    manifest.table_content_hashes = table_hashes;
    manifest.provenance_mode = 'executed_publication_geometry_calibration';
    manifest.scientific_overrides_used = false;
    manifest.global_rng_mutated = global_rng_mutated;
    manifest.global_rng_restored = global_rng_restored;
    manifest.creation_code_commit_sha = commit_sha;
    manifest.created_utc = char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
    manifest.configuration_hash = canonical_sha256(manifest_for_config_hash(manifest));
    manifest.calibration_config_content_hash = canonical_sha256(calibration_config_for_hash(config_payload));
    manifest.calibration_result_content_hash = canonical_sha256(result_for_hash(result));
    manifest.artifact_content_hash = canonical_sha256(manifest_for_content_hash(manifest));
    result.calibration_manifest_hash = manifest.artifact_content_hash;

    public = struct();
    public.schema_version = manifest.schema_version;
    public.calibration_protocol_version = plan.protocol_version;
    public.calibration_protocol_fingerprint = cal_fp;
    public.calibration_manifest_hash = manifest.artifact_content_hash;
    public.calibration_seeds = seeds;
    public.probe_cell_keys = probe_keys;
    public.trial_table = trial_table;
    public.candidate_table = candidate_table;
    public.frozen_operating_point = frozen_operating_point;
    public.status = status;
    public.manifest = manifest;
    public.global_rng_mutated = global_rng_mutated;
    public.global_rng_restored = global_rng_restored;
    public.scientific_overrides_used = false;
    public.no_outcome_fishing = true;

    payload = struct( ...
        'cfg', config_payload, ...
        'plan', plan, ...
        'trial_table', trial_table, ...
        'candidate_table', candidate_table, ...
        'result', result, ...
        'manifest', manifest);

    out = struct('public', public, 'payload', payload, 'manifest', manifest);
end

function [status, selected, frozen_operating_point] = ...
        select_operating_point_from_trials(trial_table, candidate_order)
    selected = struct('input_scaling', [], 'level_of_chaos', [], 'candidate_index', []);
    status = 'no_feasible_operating_point';
    frozen_operating_point = struct([]);
    for ic = 1:numel(candidate_order)
        mask = trial_table.candidate_index == ic;
        sub = trial_table(mask, :);
        if height(sub) == 32 && all(sub.row_pass)
            selected = struct( ...
                'input_scaling', candidate_order{ic}.input_scaling, ...
                'level_of_chaos', candidate_order{ic}.level_of_chaos, ...
                'candidate_index', ic);
            status = 'frozen';
            frozen_operating_point = struct( ...
                'input_scaling', selected.input_scaling, ...
                'level_of_chaos', selected.level_of_chaos, ...
                'candidate_index', selected.candidate_index);
            return;
        end
    end
end

function reject_calibration_scientific_overrides(options)
    forbidden = { ...
        'cfg', 'probe_cell_keys', 'calibration_seeds', 'candidate_input_scaling', ...
        'candidate_level_of_chaos', 'mean_rate_band', 'saturation_fraction_max', ...
        'silent_fraction_max', 'washout_steps', 'evaluation_steps', ...
        'input_distribution', 'solver_tolerances', 'selection_rule', ...
        'frozen_operating_point' ...
        };
    for i = 1:numel(forbidden)
        if isfield(options, forbidden{i}) && ~isempty(options.(forbidden{i}))
            error('calibrate_operating_point:ScientificOverrideForbidden', ...
                'Option %s is forbidden for publication calibration.', forbidden{i});
        end
    end
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
    row.n_eval_time_points = diag.n_eval_time_points;
    row.n_neurons = diag.n_neurons;
    row.n_rate_observations = diag.n_rate_observations;
    row.packed_state_dimension = diag.packed_state_dimension;
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

function plan = build_calibration_plan_struct(cfg, probe_keys, cal_fp, base_fp)
    op = cfg.operating_point;
    plan = struct();
    plan.protocol_version = op.protocol_version;
    plan.calibration_protocol_fingerprint = cal_fp;
    plan.base_publication_config_fingerprint = base_fp;
    plan.network_size = op.network_size;
    plan.n_inputs = cfg.base.n_inputs;
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

function cfg_out = sanitize_calibration_cfg(cfg, probe_keys, cal_fp, base_fp)
    cfg_out = cfg;
    cfg_out.calibration_plan = build_calibration_plan_struct(cfg, probe_keys, cal_fp, base_fp);
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
end

function restore_global_rng_state(state)
    rng(state.type);
end

function tf = rng_states_equal(a, b)
    tf = isequal(a.type, b.type);
end

function T = table_for_hash(T)
    if istable(T)
        T = table2struct(T);
    end
end

function r = result_for_hash(result)
    r = result;
    if isfield(r, 'calibration_manifest_hash')
        r = rmfield(r, 'calibration_manifest_hash');
    end
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
