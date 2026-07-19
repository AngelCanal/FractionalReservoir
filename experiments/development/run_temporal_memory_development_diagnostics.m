function [result, run_dir] = run_temporal_memory_development_diagnostics(options)
%RUN_TEMPORAL_MEMORY_DEVELOPMENT_DIAGNOSTICS  Resumable development diagnostics.
%
%   [result, run_dir] = run_temporal_memory_development_diagnostics()
%   [result, run_dir] = run_temporal_memory_development_diagnostics(options)
%
% Production: 8 cells x 3 seeds x lags 1:50 with B1-R shared controls.
% Never authorizes publication. Never executes reserved future seeds or 9003.
% Never modifies temporal_learning_gate_v1 artifacts.

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end
    this_dir = fileparts(mfilename('fullpath'));
    addpath(this_dir);

    allow_fixture = isfield(options, 'allow_test_fixture') && ...
        logical(options.allow_test_fixture);
    reject_scientific_overrides(options, allow_fixture);

    frozen_cfg = temporal_memory_development_config();
    cfg_report = validate_temporal_memory_development_config(frozen_cfg);
    if ~logical(cfg_report.ok)
        error('run_temporal_memory_development_diagnostics:InvalidConfig', ...
            'temporal_memory_development_config failed validation.');
    end

    [cfg, fixture, use_synthetic] = apply_fixture_geometry(frozen_cfg, options, ...
        allow_fixture);
    assert_seeds_executable(cfg);

    commit_sha = try_git_head();
    gs = RandStream.getGlobalStream();
    rng_before = gs.State;
    global_rng_restored = false;
    run_dir = '';

    try
        [run_dir, resuming] = prepare_run_dir(options, cfg, commit_sha, allow_fixture);

        if resuming && isfile(fullfile(run_dir, 'diagnostic_manifest.mat')) && ...
                isfile(fullfile(run_dir, 'diagnostic_checkpoint.mat'))
            Scp = load(fullfile(run_dir, 'diagnostic_checkpoint.mat'), ...
                'diagnostic_checkpoint');
            if strcmp(char(Scp.diagnostic_checkpoint.status), 'complete')
                load_and_validate_temporal_memory_development_checkpoint( ...
                    run_dir, cfg, commit_sha);
                Sr = load(fullfile(run_dir, 'diagnostic_result.mat'), ...
                    'diagnostic_result');
                result = Sr.diagnostic_result;
                gs = RandStream.getGlobalStream();
                gs.State = rng_before;
                result.global_rng_restored = true;
                return;
            end
        end

        splits = ensure_shared_splits(run_dir, cfg, fixture, allow_fixture);
        input_hashes = struct( ...
            'split_train', canonical_sha256(splits.train.U), ...
            'split_validation', canonical_sha256(splits.validation.U), ...
            'split_test', canonical_sha256(splits.test.U));
        atomic_save_if_absent(fullfile(run_dir, 'shared', 'splits.mat'), ...
            struct('splits', splits, 'input_hashes', input_hashes));

        checkpoint = init_or_load_checkpoint(run_dir, cfg, commit_sha, ...
            input_hashes, resuming);

        [Y_train, ~] = build_temporal_memory_targets(splits.train, cfg.lags);
        [Y_val, ~] = build_temporal_memory_targets(splits.validation, cfg.lags);
        [Y_test, ~] = build_temporal_memory_targets(splits.test, cfg.lags);

        % --- shared task controls once ---
        checkpoint = ensure_shared_task_controls(run_dir, checkpoint, cfg, ...
            splits, Y_train, Y_val, Y_test, use_synthetic);

        cell_names = cfg.diagnostic_cell_names(:);
        seeds = cfg.model_seeds(:);
        seed_results = cell(numel(cell_names) * numel(seeds), 1);
        sr_idx = 0;
        Win_hashes_by_seed = local_get(checkpoint, 'Win_hashes_by_seed', struct());

        for is = 1:numel(seeds)
            seed = seeds(is);
            sf = sprintf('seed_%d', seed);
            if ~isfield(Win_hashes_by_seed, sf)
                Win_hashes_by_seed.(sf) = struct();
            end

            for ic = 1:numel(cell_names)
                cell_name = char(cell_names{ic});
                cell_spec = cfg.diagnostic_cells.(cell_name);
                key = temporal_memory_checkpoint_key('cell', cell_name, seed);
                art_path = cell_artifact_path(run_dir, seed, cell_name);

                if key_completed(checkpoint, key)
                    S = load(art_path, 'seed_cell_result');
                    scored = S.seed_cell_result;
                else
                    if use_synthetic
                        scored = synthesize_seed_cell_result(cfg, cell_spec, seed);
                    else
                        scored = evaluate_mesn_cell(cfg, cell_spec, seed, ...
                            allow_fixture, fixture);
                    end
                    persist_cell_result(art_path, scored);
                    rh = canonical_sha256(seed_result_hash_payload(scored));
                    checkpoint = mark_key_complete(checkpoint, key, rh, 'cell');
                    checkpoint = write_temporal_memory_development_checkpoint( ...
                        run_dir, checkpoint);
                end

                sr_idx = sr_idx + 1;
                seed_results{sr_idx} = scored;
                if isfield(scored, 'W_in_hash') && ~isempty(scored.W_in_hash)
                    Win_hashes_by_seed.(sf).(cell_name) = char(scored.W_in_hash);
                elseif isfield(scored, 'W_in')
                    Win_hashes_by_seed.(sf).(cell_name) = canonical_sha256(scored.W_in);
                end
            end

            checkpoint.Win_hashes_by_seed = Win_hashes_by_seed;
            verify_win_hashes_for_seed(Win_hashes_by_seed.(sf), cell_names, seed);

            % Conventional once per model seed
            checkpoint = ensure_conventional_for_seed(run_dir, checkpoint, cfg, ...
                seed, splits, Y_train, Y_val, Y_test, Win_hashes_by_seed.(sf), ...
                cell_names, use_synthetic, allow_fixture, fixture);

            % Reference-only controls once per model seed
            checkpoint = ensure_reference_controls_for_seed(run_dir, checkpoint, ...
                cfg, seed, splits, Y_train, Y_val, Y_test, use_synthetic, ...
                allow_fixture, fixture);
        end

        seed_results = seed_results(1:sr_idx);
        controls = assemble_controls_for_tables(run_dir, seeds);
        controls.mesn_cell_seed_fits = numel(cell_names) * numel(seeds);

        tables = build_temporal_memory_development_tables(cfg, seed_results, controls);

        gs = RandStream.getGlobalStream();
        gs.State = rng_before;
        global_rng_restored = true;

        result = struct();
        result.schema_version = 'temporal_memory_development_result_v1';
        result.protocol_version = char(cfg.protocol_version);
        result.protocol_fingerprint = char(cfg.protocol_fingerprint);
        result.code_commit_sha = commit_sha;
        result.model_seeds = seeds(:)';
        result.diagnostic_cell_names = cell_names;
        result.lags = cfg.lags(:)';
        result.n_long_rows = height(tables.long_table);
        result.n_summary_rows = height(tables.summary_table);
        result.n_control_long_rows = height(tables.control_long_table);
        result.control_allocation = tables.control_summary.allocation;
        result.publication_evidence = false;
        result.publication_ready = false;
        result.can_authorize_publication = false;
        result.is_test_fixture = allow_fixture;
        result.synthetic_provenance = use_synthetic || allow_fixture;
        result.global_rng_restored = true;
        result.status = 'complete';

        write_temporal_memory_development_artifacts(run_dir, struct( ...
            'cfg', cfg, ...
            'tables', tables, ...
            'control_summary', tables.control_summary, ...
            'result', result, ...
            'commit_sha', commit_sha, ...
            'is_test_fixture', allow_fixture));

        checkpoint.status = 'complete';
        checkpoint.completed_shared_task_controls = true;
        checkpoint = write_temporal_memory_development_checkpoint(run_dir, checkpoint);

    catch ME
        gs = RandStream.getGlobalStream();
        gs.State = rng_before;
        global_rng_restored = true; %#ok<NASGU>
        rethrow(ME);
    end
end

%% -------------------------------------------------------------------------
function reject_scientific_overrides(options, allow_fixture)
    forbidden = { ...
        'cfg', 'washout_steps', 'train_samples', 'validation_samples', ...
        'test_samples', 'lags', 'lambda_grid', 'model_seeds', 'task_seeds', ...
        'cells', 'frozen_operating_point', 'conventional_config', ...
        'selection_lags', 'tie_tolerance', 'inject_candidates'};
    for i = 1:numel(forbidden)
        if isfield(options, forbidden{i}) && ~isempty(options.(forbidden{i}))
            error('run_temporal_memory_development_diagnostics:ScientificOverrideForbidden', ...
                'Option %s is a forbidden scientific override.', forbidden{i});
        end
    end
    if ~allow_fixture
        if isfield(options, 'fixture') && ~isempty(options.fixture)
            error('run_temporal_memory_development_diagnostics:ScientificOverrideForbidden', ...
                'options.fixture requires allow_test_fixture=true.');
        end
    end
end

function [cfg, fixture, use_synthetic] = apply_fixture_geometry(frozen_cfg, options, ...
        allow_fixture)
    cfg = frozen_cfg;
    fixture = struct();
    use_synthetic = false;
    if ~allow_fixture
        return;
    end
    if isfield(options, 'fixture') && ~isempty(options.fixture)
        fixture = options.fixture;
    end
    use_synthetic = isfield(fixture, 'use_synthetic_metrics') && ...
        logical(fixture.use_synthetic_metrics);

    if isfield(fixture, 'washout_steps')
        cfg.lengths.washout_steps = fixture.washout_steps;
    end
    if isfield(fixture, 'train_samples')
        cfg.lengths.train_samples = fixture.train_samples;
    end
    if isfield(fixture, 'validation_samples')
        cfg.lengths.validation_samples = fixture.validation_samples;
    end
    if isfield(fixture, 'test_samples')
        cfg.lengths.test_samples = fixture.test_samples;
    end
    if isfield(fixture, 'lags')
        cfg.lags = fixture.lags(:)';
    end
    if isfield(fixture, 'lambda_grid')
        cfg.lambda_grid = fixture.lambda_grid(:);
    end
    if isfield(fixture, 'model_seeds')
        cfg.model_seeds = fixture.model_seeds(:)';
        cfg.seeds = cfg.model_seeds;
        cfg.n_seeds = numel(cfg.model_seeds);
    end
    if isfield(fixture, 'n_cells') || isfield(fixture, 'cell_names')
        if isfield(fixture, 'cell_names')
            names = fixture.cell_names(:)';
        else
            names = frozen_cfg.diagnostic_cell_names(1:fixture.n_cells);
            names = names(:);
        end
        cfg.diagnostic_cell_names = names;
        cfg.n_cells = numel(names);
        cells = cell(1, numel(names));
        named = struct();
        for i = 1:numel(names)
            named.(names{i}) = frozen_cfg.diagnostic_cells.(names{i});
            cells{i} = named.(names{i});
        end
        cfg.diagnostic_cells = named;
        cfg.cells = cells;
        cfg.n_paired_runs = cfg.n_cells * cfg.n_seeds;
    end
    % Align conventional baseline selection lags with fixture lags for identity checks
    cfg.conventional_memory_baseline.selection_lags = cfg.lags(:)';
    if use_synthetic && isfield(fixture, 'n_candidates')
        cfg.conventional_memory_baseline.candidate_count = fixture.n_candidates;
    elseif use_synthetic
        cfg.conventional_memory_baseline.candidate_count = 3;
    end
end

function assert_seeds_executable(cfg)
    seeds = cfg.model_seeds(:);
    if any(seeds == 9003)
        error('run_temporal_memory_development_diagnostics:ReservedSeed', ...
            'Seed 9003 is forbidden.');
    end
    reserved = flatten_numeric(local_get(cfg, 'reserved_future_v2', struct()));
    if any(ismember(seeds, reserved(:)))
        error('run_temporal_memory_development_diagnostics:ReservedSeed', ...
            'Reserved future-v2 seeds cannot be executed.');
    end
    forbidden = local_get(cfg, 'forbidden_executed_seeds', []);
    bad = intersect(seeds(:)', setdiff(forbidden(:)', cfg.model_seeds(:)'));
    if ~isempty(bad)
        error('run_temporal_memory_development_diagnostics:ReservedSeed', ...
            'Forbidden seeds requested: %s', mat2str(bad));
    end
end

function [run_dir, resuming] = prepare_run_dir(options, cfg, commit_sha, allow_fixture)
    resume_dir = char(local_get(options, 'resume_run_dir', ''));
    if ~isempty(resume_dir)
        run_dir = resume_dir;
        resuming = true;
        return;
    end
    resuming = false;
    repo_root = find_repo_root_local();
    if isfield(options, 'development_root_override') && ...
            ~isempty(options.development_root_override)
        root = char(options.development_root_override);
    elseif isfield(options, 'run_root_override') && ~isempty(options.run_root_override)
        root = char(options.run_root_override);
    else
        root = fullfile(repo_root, 'results', 'development');
    end
    ctx_opts = struct('revalidated_root_override', root, ...
        'master_seed', cfg.model_seeds(1));
    if isfield(options, 'run_id') && ~isempty(options.run_id)
        ctx_opts.run_id = char(options.run_id);
    end
    ctx = create_run_context(char(cfg.experiment_name), ctx_opts);
    run_dir = ctx.run_dir;

    mkdir_p(fullfile(run_dir, 'shared', 'conventional'));
    mkdir_p(fullfile(run_dir, 'shared', 'reference_controls'));
    mkdir_p(fullfile(run_dir, 'seed_cell_results'));

    cfg_save = cfg;
    cfg_save.is_test_fixture = allow_fixture;
    atomic_save_results(fullfile(run_dir, 'diagnostic_config.mat'), ...
        struct('diagnostic_config', cfg_save, 'code_commit_sha', commit_sha));
end

function splits = ensure_shared_splits(run_dir, cfg, fixture, allow_fixture)
    path = fullfile(run_dir, 'shared', 'splits.mat');
    if isfile(path)
        S = load(path, 'splits');
        splits = S.splits;
        return;
    end
    split_opts = struct();
    if allow_fixture
        for f = {'washout_steps', 'train_samples', 'validation_samples', ...
                'test_samples'}
            if isfield(fixture, f{1})
                split_opts.(f{1}) = fixture.(f{1});
            end
        end
        if isfield(fixture, 'lags')
            split_opts.max_lag = max(fixture.lags(:));
        else
            split_opts.max_lag = max(cfg.lags(:));
        end
        if isfield(fixture, 'task_seeds')
            split_opts.task_seeds = fixture.task_seeds;
        end
    end
    splits = build_temporal_memory_development_splits(cfg, split_opts);
end

function checkpoint = init_or_load_checkpoint(run_dir, cfg, commit_sha, ...
        input_hashes, resuming)
    path = fullfile(run_dir, 'diagnostic_checkpoint.mat');
    if resuming || isfile(path)
        checkpoint = load_and_validate_temporal_memory_development_checkpoint( ...
            run_dir, cfg, commit_sha);
        return;
    end
    checkpoint = struct();
    checkpoint.schema_version = 'temporal_memory_development_checkpoint_v1';
    checkpoint.protocol_version = char(cfg.protocol_version);
    checkpoint.protocol_fingerprint = char(cfg.protocol_fingerprint);
    checkpoint.code_commit_sha = commit_sha;
    checkpoint.ordered_model_seeds = cfg.model_seeds(:);
    checkpoint.ordered_cell_keys = cfg.diagnostic_cell_names(:);
    checkpoint.lag_vector = cfg.lags(:);
    checkpoint.input_hashes = input_hashes;
    checkpoint.completed_keys = {};
    checkpoint.result_hashes = struct();
    checkpoint.completed_cell_seed_keys = {};
    checkpoint.completed_shared_task_controls = false;
    checkpoint.completed_conventional_keys = {};
    checkpoint.completed_no_recurrent_keys = {};
    checkpoint.completed_shuffled_keys = {};
    checkpoint.Win_hashes_by_seed = struct();
    checkpoint.status = 'running';
    checkpoint.can_authorize_publication = false;
    checkpoint.publication_ready = false;
    checkpoint.publication_evidence = false;
    checkpoint.created_utc = char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
    checkpoint = write_temporal_memory_development_checkpoint(run_dir, checkpoint);
end

function checkpoint = ensure_shared_task_controls(run_dir, checkpoint, cfg, ...
        splits, Y_train, Y_val, Y_test, use_synthetic)
    key = temporal_memory_checkpoint_key('shared_task_controls');
    path = fullfile(run_dir, 'shared', 'task_controls.mat');
    if key_completed(checkpoint, key)
        return;
    end
    if use_synthetic
        task = struct();
        task.current_input_only = synthesize_control_curve(cfg.lags, ...
            'current_input_only', 0);
        task.exact_history = synthesize_control_curve(cfg.lags, ...
            'exact_history', 1);
    else
        payload = struct();
        payload.splits = splits;
        payload.lags = cfg.lags(:);
        payload.lambda_grid = cfg.lambda_grid(:);
        payload.Y_train = Y_train;
        payload.Y_val = Y_val;
        payload.Y_test = Y_test;
        payload.cell_name = '';
        % Only task controls: omit Win / esn / reference features
        ctr = compute_temporal_memory_controls(payload, cfg, struct());
        task = struct();
        task.current_input_only = slim_control(ctr.current_input_only);
        task.exact_history = slim_control(ctr.exact_history);
    end
    atomic_save_results(path, struct('task_controls', task));
    rh = canonical_sha256(struct( ...
        'current', control_hash_payload(task.current_input_only), ...
        'exact', control_hash_payload(task.exact_history)));
    checkpoint = mark_key_complete(checkpoint, key, rh, 'shared_task');
    checkpoint.completed_shared_task_controls = true;
    checkpoint = write_temporal_memory_development_checkpoint(run_dir, checkpoint);
end

function scored = evaluate_mesn_cell(cfg, cell_spec, seed, allow_fixture, fixture)
    fit_opts = struct();
    if allow_fixture
        fit_opts.allow_test_fixture = true;
        for f = {'washout_steps', 'train_samples', 'validation_samples', ...
                'test_samples', 'lags', 'lambda_grid'}
            if isfield(fixture, f{1})
                fit_opts.(f{1}) = fixture.(f{1});
            end
        end
    end
    bundle = fit_temporal_memory_seed(cfg, cell_spec, seed, fit_opts);
    scored = score_temporal_memory_seed(bundle, bundle.Y_test_protocol, struct());
    scored.W_in = bundle.W_in;
    scored.W_in_hash = canonical_sha256(bundle.W_in);
    scored.W = bundle.W;
    % Retain reference-control inputs for later shared reference computation
    if strcmp(char(scored.cell_name), 'reference_r')
        scored.mesn_features = bundle.mesn_features;
        scored.esn = bundle.esn;
        scored.Y_train = bundle.Y_train;
        scored.Y_val = bundle.Y_val;
        scored.Y_test = bundle.Y_test_protocol;
        scored.lambda_grid = bundle.lambda_grid;
        scored.splits = bundle.splits;
    end
end

function scored = synthesize_seed_cell_result(cfg, cell_spec, seed)
    lags = cfg.lags(:);
    n = numel(lags);
    cell_name = char(cell_spec.diagnostic_name);
    cell_idx = find(strcmp(cell_name, cfg.diagnostic_cell_names), 1);
    if isempty(cell_idx); cell_idx = 1; end

    per_lag = repmat(struct( ...
        'lag', NaN, ...
        'selected_lambda', NaN, ...
        'numerical_rank', NaN, ...
        'coefficient_norm', NaN, ...
        'metrics', struct()), n, 1);
    mc = zeros(n, 1);
    lag_metrics = repmat(struct('nrmse', NaN, 'r2', NaN, 'pearson', NaN, ...
        'memory_coefficient', NaN, 'rmse', NaN), n, 1);
    for i = 1:n
        lag = lags(i);
        base = 0.05 * cell_idx + 0.001 * seed + 0.01 * lag;
        m = struct();
        m.nrmse = 0.4 + base;
        m.r2 = max(0, 0.9 - base);
        m.pearson = sqrt(max(0, m.r2));
        m.memory_coefficient = m.pearson^2;
        m.rmse = 0.2 + 0.5 * base;
        per_lag(i).lag = lag;
        per_lag(i).selected_lambda = 1e-6;
        per_lag(i).selected_at_grid_boundary = false;
        per_lag(i).numerical_rank = 4;
        per_lag(i).coefficient_norm = 1 + base;
        per_lag(i).metrics = m;
        mc(i) = m.memory_coefficient;
        lag_metrics(i) = m;
    end
    summary = summarize_temporal_memory_curve(lags, mc, lag_metrics);
    fd = struct();
    fd.numerical_rank = 4;
    fd.feature_covariance_effective_rank = 4;
    fd.participation_ratio = 3.5;
    fd.feature_participation_ratio = 3.5;
    fd.fraction_numerically_near_constant_features = 0.01;
    fd.mean_feature_standard_deviation = 0.2;
    fd.median_feature_standard_deviation = 0.18;
    fd.mean_firing_rate = 0.4;
    fd.saturation_fraction = 0.05;
    fd.silence_fraction = 0.05;

    scored = struct();
    scored.model_seed = seed;
    scored.cell_name = cell_name;
    scored.cell_key = char(cell_spec.cell_key);
    scored.lags = lags;
    scored.per_lag = per_lag;
    scored.summary = summary;
    scored.memory_coefficients = mc;
    scored.feature_diagnostics = fd;
    scored.n_lags = n;
    scored.W_in_hash = canonical_sha256(struct('model_seed', seed, ...
        'synthetic_shared_win', true));
    scored.is_test_fixture = true;
    scored.synthetic_provenance = true;
    scored.provenance = 'synthetic_test_fixture';
end

function persist_cell_result(art_path, scored)
    slim = scored;
    % Drop bulky objects from non-reference cells; keep hash identity
    if ~strcmp(char(local_get(slim, 'cell_name', '')), 'reference_r')
        drop = {'esn', 'mesn_features', 'splits', 'Y_train', 'Y_val', 'Y_test', 'W'};
        for i = 1:numel(drop)
            if isfield(slim, drop{i})
                slim = rmfield(slim, drop{i});
            end
        end
    end
    % Never embed conventional fit bundles in cell artifacts
    if isfield(slim, 'controls')
        slim = rmfield(slim, 'controls');
    end
    atomic_save_results(art_path, struct('seed_cell_result', slim));
end

function verify_win_hashes_for_seed(hash_map, cell_names, seed)
    hashes = {};
    for i = 1:numel(cell_names)
        cn = char(cell_names{i});
        if ~isfield(hash_map, cn) || isempty(hash_map.(cn))
            error('run_temporal_memory_development_diagnostics:WinHashMissing', ...
                'Missing W_in hash for cell %s seed %d.', cn, seed);
        end
        hashes{end+1} = char(hash_map.(cn)); %#ok<AGROW>
    end
    if numel(unique(hashes)) ~= 1
        error('run_temporal_memory_development_diagnostics:WinHashMismatch', ...
            'W_in content hashes differ across cells for seed %d.', seed);
    end
end

function checkpoint = ensure_conventional_for_seed(run_dir, checkpoint, cfg, ...
        seed, splits, Y_train, Y_val, Y_test, win_map, cell_names, ...
        use_synthetic, allow_fixture, fixture)
    key = temporal_memory_checkpoint_key('conventional', seed);
    path = fullfile(run_dir, 'shared', 'conventional', ...
        sprintf('seed_%d_conventional.mat', seed));
    if key_completed(checkpoint, key)
        % Resume: validate existing conventional identity/hash; never silently replace.
        validate_temporal_memory_conventional_artifact(run_dir, seed, cfg);
        return;
    end

    if use_synthetic
        bundle = synthesize_conventional_bundle(cfg, seed);
        scored = score_synthetic_conventional(bundle, Y_test);
    else
        % Recover W_in from any completed cell artifact
        ref_name = char(cell_names{1});
        S = load(cell_artifact_path(run_dir, seed, ref_name), 'seed_cell_result');
        if ~isfield(S.seed_cell_result, 'W_in')
            % Fall back to re-fitting reference for W_in only is forbidden; require W_in
            error('run_temporal_memory_development_diagnostics:MissingWin', ...
                'Cell artifact missing W_in for conventional fit seed %d.', seed);
        end
        mesn_Win = S.seed_cell_result.W_in;
        fit_opts = struct();
        if isfield(cfg, 'conventional_memory_baseline')
            fit_opts.conventional_memory_baseline = cfg.conventional_memory_baseline;
        end
        % Production: do NOT pass conventional_config, selection_lags, tie_tolerance,
        % inject_candidates, allow_test_fixture, or length overrides.
        if allow_fixture
            fit_opts.allow_test_fixture = true;
            if isfield(fixture, 'inject_candidates')
                fit_opts.inject_candidates = fixture.inject_candidates;
            end
        end
        bundle = fit_conventional_memory_curve(splits, Y_train, Y_val, ...
            cfg.lags(:), cfg.lambda_grid(:), mesn_Win, seed, fit_opts);
        scored = score_conventional_memory_curve(bundle, Y_test);
    end
    scored.bundle_content_hash = conventional_bundle_content_hash(scored);
    scored.reused_shared_baseline = true;
    atomic_save_results(path, struct('conventional_bundle', scored));
    rh = scored.bundle_content_hash;
    checkpoint = mark_key_complete(checkpoint, key, rh, 'conventional');
    checkpoint = write_temporal_memory_development_checkpoint(run_dir, checkpoint);
end

function checkpoint = ensure_reference_controls_for_seed(run_dir, checkpoint, ...
        cfg, seed, splits, Y_train, Y_val, Y_test, use_synthetic, ...
        allow_fixture, fixture)
    key_nr = temporal_memory_checkpoint_key('no_recurrent', seed);
    key_sh = temporal_memory_checkpoint_key('shuffled_target', seed);
    path_nr = fullfile(run_dir, 'shared', 'reference_controls', ...
        sprintf('seed_%d_no_recurrent.mat', seed));
    path_sh = fullfile(run_dir, 'shared', 'reference_controls', ...
        sprintf('seed_%d_shuffled_target.mat', seed));

    need_nr = ~key_completed(checkpoint, key_nr);
    need_sh = ~key_completed(checkpoint, key_sh);
    if ~need_nr && ~need_sh
        return;
    end

    if use_synthetic
        if need_nr
            nr = synthesize_control_curve(cfg.lags, 'no_recurrent_coupling', seed);
            atomic_save_results(path_nr, struct('no_recurrent_control', nr));
            rh = canonical_sha256(control_hash_payload(nr));
            checkpoint = mark_key_complete(checkpoint, key_nr, rh, 'no_recurrent');
            checkpoint = write_temporal_memory_development_checkpoint(run_dir, checkpoint);
        end
        if need_sh
            sh = synthesize_control_curve(cfg.lags, 'shuffled_target', seed + 7);
            atomic_save_results(path_sh, struct('shuffled_target_control', sh));
            rh = canonical_sha256(control_hash_payload(sh));
            checkpoint = mark_key_complete(checkpoint, key_sh, rh, 'shuffled');
            checkpoint = write_temporal_memory_development_checkpoint(run_dir, checkpoint);
        end
        return;
    end

    S = load(cell_artifact_path(run_dir, seed, 'reference_r'), 'seed_cell_result');
    ref = S.seed_cell_result;
    payload = struct();
    payload.splits = splits;
    payload.lags = cfg.lags(:);
    payload.lambda_grid = cfg.lambda_grid(:);
    payload.Y_train = local_get(ref, 'Y_train', Y_train);
    payload.Y_val = local_get(ref, 'Y_val', Y_val);
    payload.Y_test = local_get(ref, 'Y_test', Y_test);
    payload.mesn_features = ref.mesn_features;
    payload.esn = ref.esn;
    payload.cell_name = 'reference_r';
    payload.model_seed = seed;
    payload.W_original = ref.esn.W;
    payload.W_original_copy = ref.esn.W;
    % Skip conventional here — already shared
    payload.conventional_precomputed = struct('status', 'skipped', ...
        'reason', 'shared_separately');

    ctrl_opts = struct();
    if allow_fixture
        ctrl_opts.allow_test_fixture = true;
    end
    ctr = compute_temporal_memory_controls(payload, cfg, ctrl_opts);

    if need_nr
        nr = slim_control(ctr.no_recurrent_coupling);
        atomic_save_results(path_nr, struct('no_recurrent_control', nr));
        rh = canonical_sha256(control_hash_payload(nr));
        checkpoint = mark_key_complete(checkpoint, key_nr, rh, 'no_recurrent');
        checkpoint = write_temporal_memory_development_checkpoint(run_dir, checkpoint);
    end
    if need_sh
        sh = slim_control(ctr.shuffled_target);
        atomic_save_results(path_sh, struct('shuffled_target_control', sh));
        rh = canonical_sha256(control_hash_payload(sh));
        checkpoint = mark_key_complete(checkpoint, key_sh, rh, 'shuffled');
        checkpoint = write_temporal_memory_development_checkpoint(run_dir, checkpoint);
    end
end

function controls = assemble_controls_for_tables(run_dir, seeds)
    St = load(fullfile(run_dir, 'shared', 'task_controls.mat'), 'task_controls');
    controls = struct();
    controls.current_input_only = St.task_controls.current_input_only;
    controls.exact_history = St.task_controls.exact_history;
    controls.conventional = struct();
    controls.no_recurrent = struct();
    controls.shuffled_target = struct();
    for is = 1:numel(seeds)
        seed = seeds(is);
        sf = sprintf('seed_%d', seed);
        Sc = load(fullfile(run_dir, 'shared', 'conventional', ...
            sprintf('seed_%d_conventional.mat', seed)), 'conventional_bundle');
        controls.conventional.(sf) = Sc.conventional_bundle;
        Sn = load(fullfile(run_dir, 'shared', 'reference_controls', ...
            sprintf('seed_%d_no_recurrent.mat', seed)), 'no_recurrent_control');
        controls.no_recurrent.(sf) = Sn.no_recurrent_control;
        Ss = load(fullfile(run_dir, 'shared', 'reference_controls', ...
            sprintf('seed_%d_shuffled_target.mat', seed)), 'shuffled_target_control');
        controls.shuffled_target.(sf) = Ss.shuffled_target_control;
    end
end

%% helpers -----------------------------------------------------------------
function tf = key_completed(checkpoint, key)
    keys = cellstr(string(local_get(checkpoint, 'completed_keys', {})));
    tf = any(strcmp(keys, key));
end

function checkpoint = mark_key_complete(checkpoint, key, result_hash, kind)
    keys = cellstr(string(local_get(checkpoint, 'completed_keys', {})));
    if any(strcmp(keys, key))
        error('run_temporal_memory_development_diagnostics:DuplicateKey', ...
            'Checkpoint key already completed: %s', key);
    end
    checkpoint.completed_keys = [keys; {key}];
    field = key_to_field(key);
    if ~isfield(checkpoint, 'result_hashes') || isempty(checkpoint.result_hashes)
        checkpoint.result_hashes = struct();
    end
    checkpoint.result_hashes.(field) = result_hash;
    switch kind
        case 'cell'
            ck = cellstr(string(local_get(checkpoint, 'completed_cell_seed_keys', {})));
            checkpoint.completed_cell_seed_keys = [ck; {key}];
        case 'conventional'
            ck = cellstr(string(local_get(checkpoint, 'completed_conventional_keys', {})));
            checkpoint.completed_conventional_keys = [ck; {key}];
        case 'no_recurrent'
            ck = cellstr(string(local_get(checkpoint, 'completed_no_recurrent_keys', {})));
            checkpoint.completed_no_recurrent_keys = [ck; {key}];
        case 'shuffled'
            ck = cellstr(string(local_get(checkpoint, 'completed_shuffled_keys', {})));
            checkpoint.completed_shuffled_keys = [ck; {key}];
        case 'shared_task'
            checkpoint.completed_shared_task_controls = true;
    end
end

function field = key_to_field(key)
    field = regexprep(key, '[^A-Za-z0-9]', '_');
    if ~isempty(field) && field(1) >= '0' && field(1) <= '9'
        field = ['k_', field];
    end
end

function path = cell_artifact_path(run_dir, seed, cell_name)
    path = fullfile(run_dir, 'seed_cell_results', ...
        sprintf('seed_%d__%s.mat', seed, cell_name));
end

function out = slim_control(ctrl)
    out = struct();
    out.name = local_get(ctrl, 'name', '');
    out.status = local_get(ctrl, 'status', 'computed');
    out.per_lag = ctrl.per_lag;
    out.summary = ctrl.summary;
    if isfield(ctrl, 'scored')
        out.scored = struct('per_lag', ctrl.scored.per_lag, ...
            'summary', ctrl.scored.summary);
    end
end

function payload = seed_result_hash_payload(scored)
    payload = struct();
    payload.cell_name = scored.cell_name;
    payload.model_seed = scored.model_seed;
    payload.lags = scored.lags(:)';
    n = numel(scored.per_lag);
    payload.nrmse = zeros(n, 1);
    payload.mc = zeros(n, 1);
    for i = 1:n
        payload.nrmse(i) = scored.per_lag(i).metrics.nrmse;
        payload.mc(i) = scored.per_lag(i).metrics.memory_coefficient;
    end
end

function payload = control_hash_payload(ctrl)
    if isfield(ctrl, 'per_lag')
        per_lag = ctrl.per_lag;
    else
        per_lag = ctrl.scored.per_lag;
    end
    n = numel(per_lag);
    payload = struct('n', n, 'nrmse', zeros(n, 1));
    for i = 1:n
        payload.nrmse(i) = per_lag(i).metrics.nrmse;
    end
end

function hex = conventional_bundle_content_hash(b)
    payload = struct();
    payload.model_seed = b.model_seed;
    payload.selected_candidate_index = b.selected_candidate_index;
    payload.selected_candidate_content_hash = ...
        local_get(b, 'selected_candidate_content_hash', '');
    payload.n_candidates = b.n_candidates;
    payload.selection_lags = b.selection_lags(:)';
    payload.same_reservoir_for_all_lags = b.same_reservoir_for_all_lags;
    hex = canonical_sha256(payload);
end

function ctrl = synthesize_control_curve(lags, name, salt)
    lags = lags(:);
    n = numel(lags);
    per_lag = repmat(struct('lag', NaN, 'metrics', struct()), n, 1);
    mc = zeros(n, 1);
    lag_metrics = repmat(struct('nrmse', NaN, 'r2', NaN, 'pearson', NaN, ...
        'memory_coefficient', NaN, 'rmse', NaN), n, 1);
    for i = 1:n
        base = 0.02 * salt + 0.015 * lags(i);
        m = struct();
        m.nrmse = 0.5 + base;
        m.r2 = max(0, 0.8 - base);
        m.pearson = sqrt(max(0, m.r2));
        m.memory_coefficient = m.pearson^2;
        m.rmse = 0.25 + base;
        per_lag(i).lag = lags(i);
        per_lag(i).metrics = m;
        mc(i) = m.memory_coefficient;
        lag_metrics(i) = m;
    end
    ctrl = struct();
    ctrl.name = name;
    ctrl.status = 'computed';
    ctrl.per_lag = per_lag;
    ctrl.summary = summarize_temporal_memory_curve(lags, mc, lag_metrics);
    ctrl.is_test_fixture = true;
end

function bundle = synthesize_conventional_bundle(cfg, seed)
    lags = cfg.lags(:);
    n = numel(lags);
    n_cand = cfg.conventional_memory_baseline.candidate_count;
    sel = 1;
    per_lag = repmat(struct( ...
        'lag', NaN, ...
        'selected_candidate_index', sel, ...
        'selected_lambda', 1e-6, ...
        'metrics', struct()), n, 1);
    for i = 1:n
        per_lag(i).lag = lags(i);
        per_lag(i).selected_candidate_index = sel;
        per_lag(i).selected_lambda = 1e-6;
        per_lag(i).metrics = struct('nrmse', NaN, 'r2', NaN, 'pearson', NaN, ...
            'memory_coefficient', NaN, 'rmse', NaN);
    end
    bundle = struct();
    bundle.name = 'conventional_leaky_esn';
    bundle.status = 'fitted';
    bundle.model_seed = seed;
    bundle.lags = lags;
    bundle.n_candidates = n_cand;
    bundle.selected_candidate_index = sel;
    bundle.selected_candidate_content_hash = canonical_sha256(struct( ...
        'seed', seed, 'sel', sel));
    bundle.selection_lags = cfg.conventional_memory_baseline.selection_lags(:);
    bundle.same_reservoir_for_all_lags = true;
    bundle.test_targets_used_for_selection = false;
    bundle.provenance = 'synthetic_test_fixture';
    bundle.is_test_fixture = true;
    bundle.per_lag = per_lag;
    bundle.protocol_version = 'matched_conventional_memory_curve_v1';
end

function scored = score_synthetic_conventional(bundle, Y_test) %#ok<INUSD>
    scored = bundle;
    scored.status = 'computed';
    lags = bundle.lags(:);
    n = numel(lags);
    mc = zeros(n, 1);
    lag_metrics = repmat(struct('nrmse', NaN, 'r2', NaN, 'pearson', NaN, ...
        'memory_coefficient', NaN, 'rmse', NaN), n, 1);
    for i = 1:n
        base = 0.03 * bundle.model_seed / 1000 + 0.01 * lags(i);
        m = struct();
        m.nrmse = 0.45 + base;
        m.r2 = max(0, 0.85 - base);
        m.pearson = sqrt(max(0, m.r2));
        m.memory_coefficient = m.pearson^2;
        m.rmse = 0.22 + base;
        scored.per_lag(i).metrics = m;
        mc(i) = m.memory_coefficient;
        lag_metrics(i) = m;
    end
    scored.summary = summarize_temporal_memory_curve(lags, mc, lag_metrics);
    scored.memory_coefficients = mc;
end

function atomic_save_if_absent(path, variables)
    if isfile(path)
        return;
    end
    parent = fileparts(path);
    if ~isempty(parent) && ~isfolder(parent)
        mkdir(parent);
    end
    atomic_save_results(path, variables);
end

function mkdir_p(p)
    if ~isfolder(p)
        mkdir(p);
    end
end

function sha = try_git_head()
    [status, out] = system('git rev-parse HEAD');
    if status == 0
        sha = strtrim(out);
    else
        sha = 'unknown';
    end
end

function repo_root = find_repo_root_local()
    this_file = mfilename('fullpath');
    cand = fileparts(fileparts(fileparts(this_file)));
    if isfolder(fullfile(cand, 'src'))
        repo_root = cand;
        return;
    end
    error('run_temporal_memory_development_diagnostics:RepoRoot', ...
        'Could not locate repository root.');
end

function vals = flatten_numeric(S)
    vals = [];
    if isnumeric(S)
        vals = S(:);
        return;
    end
    if ~isstruct(S) || numel(S) ~= 1
        return;
    end
    fn = fieldnames(S);
    for i = 1:numel(fn)
        vals = [vals; flatten_numeric(S.(fn{i}))]; %#ok<AGROW>
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
