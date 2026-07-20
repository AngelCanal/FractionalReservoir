function run_dir = make_synthetic_temporal_memory_diagnostic_run(opts)
%MAKE_SYNTHETIC_TEMPORAL_MEMORY_DIAGNOSTIC_RUN  Production-shaped validator fixture.
%
%   run_dir = make_synthetic_temporal_memory_diagnostic_run()
%   run_dir = make_synthetic_temporal_memory_diagnostic_run(opts)
%
% Builds a complete run directory under temp with 1200/24/550 deterministic rows.
% Tamper options: corrupt_hash, missing_row, duplicate_key, protocol_mismatch,
% commit_mismatch, reserved_seed, publication_ready_true, fixture_flag_true.

    if nargin < 1 || isempty(opts)
        opts = struct();
    end

    cfg = temporal_memory_development_config();
    commit_sha = git_head_sha();
    if isfield(opts, 'commit_mismatch') && opts.commit_mismatch
        commit_sha = 'deadbeef_commit_mismatch';
    end

    root = tempname;
    mkdir(root);
    run_dir = fullfile(root, 'synthetic_tm_run');
    mkdir(run_dir);
    mkdir(fullfile(run_dir, 'shared', 'conventional'));
    mkdir(fullfile(run_dir, 'shared', 'reference_controls'));
    mkdir(fullfile(run_dir, 'seed_cell_results'));

    cells = cfg.diagnostic_cell_names(:);
    seeds = cfg.model_seeds(:);
    lags = cfg.lags(:);
    if isfield(opts, 'reserved_seed') && opts.reserved_seed
        seeds = [seeds(:); 11003]; %#ok<*AGROW> % reserved future gate seed
        % Keep geometry broken intentionally for reserved-seed tests via long table
    end

    % Shared splits (deterministic short synthetics with production lengths identity)
    splits = build_temporal_memory_development_splits(cfg, struct( ...
        'washout_steps', 5, 'train_samples', 20, 'validation_samples', 10, ...
        'test_samples', 10, 'max_lag', 50));
    % Note: lengths differ from production but hashes are self-consistent for fixture
    input_hashes = struct( ...
        'split_train', canonical_sha256(splits.train.U), ...
        'split_validation', canonical_sha256(splits.validation.U), ...
        'split_test', canonical_sha256(splits.test.U));
    save(fullfile(run_dir, 'shared', 'splits.mat'), 'splits', 'input_hashes');

    seed_results = {};
    completed_keys = {};
    result_hashes = struct();
    completed_cell_seed_keys = {};
    completed_conventional_keys = {};
    completed_no_recurrent_keys = {};
    completed_shuffled_keys = {};
    Win_hashes_by_seed = struct();

    for is = 1:numel(cfg.model_seeds)
        seed = cfg.model_seeds(is);
        sf = sprintf('seed_%d', seed);
        Win_hashes_by_seed.(sf) = struct();
        win_hash = canonical_sha256(struct('model_seed', seed, 'synthetic', true));

        for ic = 1:numel(cells)
            cell_name = cells{ic};
            cell_spec = cfg.diagnostic_cells.(cell_name);
            scored = synthesize_cell(cfg, cell_spec, seed);
            scored.W_in_hash = win_hash;
            scored.provenance = 'production';
            scored.is_test_fixture = false;
            scored.synthetic_provenance = false;
            seed_cell_result = scored; %#ok<NASGU>
            save(fullfile(run_dir, 'seed_cell_results', ...
                sprintf('seed_%d__%s.mat', seed, cell_name)), 'seed_cell_result');

            seed_results{end+1} = scored; %#ok<AGROW>
            key = temporal_memory_checkpoint_key('cell', cell_name, seed);
            completed_keys{end+1} = key; %#ok<AGROW>
            completed_cell_seed_keys{end+1} = key; %#ok<AGROW>
            result_hashes.(key_to_field(key)) = ...
                temporal_memory_seed_result_content_hash(scored);
            Win_hashes_by_seed.(sf).(cell_name) = win_hash;
        end

        conv = synthesize_conventional(cfg, seed);
        conventional_bundle = conv; %#ok<NASGU>
        save(fullfile(run_dir, 'shared', 'conventional', ...
            sprintf('seed_%d_conventional.mat', seed)), 'conventional_bundle');
        key = temporal_memory_checkpoint_key('conventional', seed);
        completed_keys{end+1} = key; %#ok<AGROW>
        completed_conventional_keys{end+1} = key; %#ok<AGROW>
        result_hashes.(key_to_field(key)) = conv.bundle_content_hash;

        nr = synthesize_control(lags, 'no_recurrent_coupling', seed);
        no_recurrent_control = nr; %#ok<NASGU>
        save(fullfile(run_dir, 'shared', 'reference_controls', ...
            sprintf('seed_%d_no_recurrent.mat', seed)), 'no_recurrent_control');
        key = temporal_memory_checkpoint_key('no_recurrent', seed);
        completed_keys{end+1} = key; %#ok<AGROW>
        completed_no_recurrent_keys{end+1} = key; %#ok<AGROW>
        result_hashes.(key_to_field(key)) = temporal_memory_control_content_hash(nr, ...
            struct('control_name', 'no_recurrent_coupling', ...
            'execution_scope', 'reference_cell_per_model_seed', 'model_seed', seed));

        sh = synthesize_control(lags, 'shuffled_target', seed + 3);
        shuffled_target_control = sh; %#ok<NASGU>
        save(fullfile(run_dir, 'shared', 'reference_controls', ...
            sprintf('seed_%d_shuffled_target.mat', seed)), 'shuffled_target_control');
        key = temporal_memory_checkpoint_key('shuffled_target', seed);
        completed_keys{end+1} = key; %#ok<AGROW>
        completed_shuffled_keys{end+1} = key; %#ok<AGROW>
        result_hashes.(key_to_field(key)) = temporal_memory_control_content_hash(sh, ...
            struct('control_name', 'shuffled_target', ...
            'execution_scope', 'reference_cell_per_model_seed', 'model_seed', seed));
    end

    task_controls = struct();
    task_controls.current_input_only = synthesize_control(lags, 'current_input_only', 0);
    task_controls.exact_history = synthesize_control(lags, 'exact_history', 1);
    save(fullfile(run_dir, 'shared', 'task_controls.mat'), 'task_controls');
    key = temporal_memory_checkpoint_key('shared_task_controls');
    completed_keys{end+1} = key;
    result_hashes.(key_to_field(key)) = canonical_sha256(struct( ...
        'current', temporal_memory_control_content_hash(task_controls.current_input_only, ...
            struct('control_name', 'current_input_only', ...
            'execution_scope', 'shared_task', 'shared_task_identity', 'task')), ...
        'exact', temporal_memory_control_content_hash(task_controls.exact_history, ...
            struct('control_name', 'exact_history', ...
            'execution_scope', 'shared_task', 'shared_task_identity', 'task'))));

    if isfield(opts, 'duplicate_key') && opts.duplicate_key
        completed_keys{end+1} = completed_keys{1};
    end

    controls = struct();
    controls.current_input_only = task_controls.current_input_only;
    controls.exact_history = task_controls.exact_history;
    controls.conventional = struct();
    controls.no_recurrent = struct();
    controls.shuffled_target = struct();
    controls.mesn_cell_seed_fits = 24;
    for is = 1:numel(cfg.model_seeds)
        seed = cfg.model_seeds(is);
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

    tables = build_temporal_memory_development_tables(cfg, seed_results, controls);

    if isfield(opts, 'missing_row') && opts.missing_row
        tables.long_table(1, :) = [];
    end
    if isfield(opts, 'reserved_seed') && opts.reserved_seed
        % Inject a reserved seed into one long-table row
        tables.long_table.model_seed(1) = 11003;
    end

    protocol_fp = cfg.protocol_fingerprint;
    if isfield(opts, 'protocol_mismatch') && opts.protocol_mismatch
        protocol_fp = '0'; % force mismatch
        protocol_fp = [protocol_fp, repmat('f', 1, 63)];
    end

    result = struct();
    result.schema_version = 'temporal_memory_development_result_v1';
    result.protocol_version = char(cfg.protocol_version);
    result.protocol_fingerprint = protocol_fp;
    result.code_commit_sha = commit_sha;
    result.model_seeds = cfg.model_seeds(:)';
    result.diagnostic_cell_names = cfg.diagnostic_cell_names(:)';
    result.lags = cfg.lags(:)';
    result.n_long_rows = height(tables.long_table);
    result.n_summary_rows = height(tables.summary_table);
    result.n_control_long_rows = height(tables.control_long_table);
    result.control_allocation = tables.control_summary.allocation;
    result.publication_evidence = false;
    result.publication_ready = false;
    result.can_authorize_publication = false;
    result.is_test_fixture = false;
    result.synthetic_provenance = false;
    result.global_rng_restored = true;
    result.status = 'complete';
    if isfield(opts, 'publication_ready_true') && opts.publication_ready_true
        result.publication_ready = true;
    end
    if isfield(opts, 'fixture_flag_true') && opts.fixture_flag_true
        result.is_test_fixture = true;
        result.synthetic_provenance = true;
    end

    cfg_save = cfg;
    cfg_save.is_test_fixture = false;
    diagnostic_config = cfg_save; %#ok<NASGU>
    save(fullfile(run_dir, 'diagnostic_config.mat'), 'diagnostic_config');

    write_temporal_memory_development_artifacts(run_dir, struct( ...
        'cfg', cfg, ...
        'tables', tables, ...
        'control_summary', tables.control_summary, ...
        'result', result, ...
        'commit_sha', commit_sha, ...
        'is_test_fixture', logical(local_get(opts, 'fixture_flag_true', false))));

    % Fix manifest fingerprint if protocol mismatch requested
    if isfield(opts, 'protocol_mismatch') && opts.protocol_mismatch
        Sm = load(fullfile(run_dir, 'diagnostic_manifest.mat'), 'diagnostic_manifest');
        manifest = Sm.diagnostic_manifest;
        manifest.protocol_fingerprint = protocol_fp;
        diagnostic_manifest = manifest; %#ok<NASGU>
        save(fullfile(run_dir, 'diagnostic_manifest.mat'), 'diagnostic_manifest');
        fid = fopen(fullfile(run_dir, 'diagnostic_manifest.json'), 'w');
        fprintf(fid, '%s', jsonencode(manifest));
        fclose(fid);
        diagnostic_result = result; %#ok<NASGU>
        save(fullfile(run_dir, 'diagnostic_result.mat'), 'diagnostic_result');
    end

    if isfield(opts, 'publication_ready_true') && opts.publication_ready_true
        Sm = load(fullfile(run_dir, 'diagnostic_manifest.mat'), 'diagnostic_manifest');
        manifest = Sm.diagnostic_manifest;
        manifest.publication_ready = true;
        diagnostic_manifest = manifest; %#ok<NASGU>
        save(fullfile(run_dir, 'diagnostic_manifest.mat'), 'diagnostic_manifest');
        diagnostic_result = result; %#ok<NASGU>
        save(fullfile(run_dir, 'diagnostic_result.mat'), 'diagnostic_result');
    end

    checkpoint = struct();
    checkpoint.schema_version = 'temporal_memory_development_checkpoint_v1';
    checkpoint.protocol_version = char(cfg.protocol_version);
    checkpoint.protocol_fingerprint = char(cfg.protocol_fingerprint);
    if isfield(opts, 'protocol_mismatch') && opts.protocol_mismatch
        checkpoint.protocol_fingerprint = protocol_fp;
    end
    checkpoint.code_commit_sha = commit_sha;
    checkpoint.ordered_model_seeds = cfg.model_seeds(:);
    checkpoint.ordered_cell_keys = cfg.diagnostic_cell_names(:);
    checkpoint.lag_vector = cfg.lags(:);
    checkpoint.input_hashes = input_hashes;
    checkpoint.completed_keys = completed_keys(:);
    checkpoint.result_hashes = result_hashes;
    checkpoint.file_hashes = struct();
    checkpoint.artifact_roles = struct();
    checkpoint.completed_cell_seed_keys = completed_cell_seed_keys(:);
    checkpoint.completed_shared_task_controls = true;
    checkpoint.completed_conventional_keys = completed_conventional_keys(:);
    checkpoint.completed_no_recurrent_keys = completed_no_recurrent_keys(:);
    checkpoint.completed_shuffled_keys = completed_shuffled_keys(:);
    checkpoint.Win_hashes_by_seed = Win_hashes_by_seed;
    checkpoint.status = 'complete';
    checkpoint.can_authorize_publication = false;
    checkpoint.publication_ready = false;
    checkpoint.publication_evidence = false;
    if isfield(opts, 'publication_ready_true') && opts.publication_ready_true
        checkpoint.publication_ready = true;
    end
    checkpoint.created_utc = char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
    write_temporal_memory_development_checkpoint(run_dir, checkpoint);

    if isfield(opts, 'corrupt_hash') && opts.corrupt_hash
        Sm = load(fullfile(run_dir, 'diagnostic_manifest.mat'), 'diagnostic_manifest');
        manifest = Sm.diagnostic_manifest;
        manifest.table_content_hashes.long_table = '0';
        manifest.table_content_hashes.long_table = [ ...
            manifest.table_content_hashes.long_table, repmat('a', 1, 63)];
        diagnostic_manifest = manifest; %#ok<NASGU>
        save(fullfile(run_dir, 'diagnostic_manifest.mat'), 'diagnostic_manifest');
    end
end

function scored = synthesize_cell(cfg, cell_spec, seed)
    lags = cfg.lags(:);
    n = numel(lags);
    cell_name = char(cell_spec.diagnostic_name);
    cell_idx = find(strcmp(cell_name, cfg.diagnostic_cell_names), 1);
    per_lag = repmat(struct('lag', NaN, 'selected_lambda', 1e-6, ...
        'selected_at_grid_boundary', false, ...
        'numerical_rank', 4, 'coefficient_norm', 1, 'metrics', struct()), n, 1);
    mc = zeros(n, 1);
    lag_metrics = repmat(struct('nrmse', NaN, 'r2', NaN, 'pearson', NaN, ...
        'memory_coefficient', NaN, 'rmse', NaN), n, 1);
    for i = 1:n
        base = 0.04 * cell_idx + 0.0005 * seed + 0.008 * lags(i);
        m = struct('nrmse', 0.35 + base, 'r2', max(0, 0.92 - base), ...
            'pearson', 0, 'memory_coefficient', 0, 'rmse', 0.18 + base);
        m.pearson = sqrt(max(0, m.r2));
        m.memory_coefficient = m.pearson^2;
        per_lag(i).lag = lags(i);
        per_lag(i).metrics = m;
        mc(i) = m.memory_coefficient;
        lag_metrics(i) = m;
    end
    scored = struct();
    scored.model_seed = seed;
    scored.cell_name = cell_name;
    scored.cell_key = char(cell_spec.cell_key);
    scored.lags = lags;
    scored.per_lag = per_lag;
    scored.summary = summarize_temporal_memory_curve(lags, mc, lag_metrics);
    scored.memory_coefficients = mc;
    for i = 1:n
        per_lag(i).intercept = 0.01;
        per_lag(i).coefficients = [1; 0.5; 0.25; 0.1];
        per_lag(i).feature_mean = zeros(1, 4);
        per_lag(i).feature_scale = ones(1, 4);
        per_lag(i).lambda_selection_table = struct('lambda', 1e-6, 'score', 0.1);
        per_lag(i).metrics.constant_prediction = false;
    end
    scored.feature_diagnostics = struct( ...
        'numerical_rank', 4, ...
        'feature_covariance_effective_rank', 4, ...
        'rank_tolerance', 1e-12, ...
        'participation_ratio', 3.2, ...
        'feature_participation_ratio', 3.2, ...
        'fraction_numerically_near_constant_features', 0.02, ...
        'mean_feature_standard_deviation', 0.25, ...
        'median_feature_standard_deviation', 0.22, ...
        'median_absolute_offdiag_feature_correlation', 0.1, ...
        'maximum_absolute_offdiag_feature_correlation', 0.4, ...
        'mean_firing_rate', 0.42, ...
        'saturation_fraction', 0.04, ...
        'silence_fraction', 0.06, ...
        'n_neurons', 40, ...
        'packed_state_dimension', 40, ...
        'activity_from_neuronal_rates', true, ...
        'packed_states_counted_as_neurons', false);
    scored.feature_mode = 'r';
    scored.feature_dimension = 40;
    scored.include_input = false;
    scored.simulations_per_split = 1;
    scored.n_reservoir_simulations = 3;
    scored.global_rng_unchanged = true;
    scored.n_lags = n;
    scored.per_lag = per_lag;
end

function bundle = synthesize_conventional(cfg, seed)
    lags = cfg.lags(:);
    n = numel(lags);
    sel = 2;
    per_lag = repmat(struct('lag', NaN, 'selected_candidate_index', sel, ...
        'selected_lambda', 1e-6, 'metrics', struct()), n, 1);
    mc = zeros(n, 1);
    lag_metrics = repmat(struct('nrmse', NaN, 'r2', NaN, 'pearson', NaN, ...
        'memory_coefficient', NaN, 'rmse', NaN), n, 1);
    for i = 1:n
        base = 0.01 * lags(i);
        m = struct('nrmse', 0.5 + base, 'r2', max(0, 0.7 - base), ...
            'pearson', 0, 'memory_coefficient', 0, 'rmse', 0.3 + base);
        m.pearson = sqrt(max(0, m.r2));
        m.memory_coefficient = m.pearson^2;
        per_lag(i).lag = lags(i);
        per_lag(i).selected_candidate_index = sel;
        per_lag(i).metrics = m;
        mc(i) = m.memory_coefficient;
        lag_metrics(i) = m;
    end
    bundle = struct();
    bundle.name = 'conventional_leaky_esn';
    bundle.status = 'computed';
    bundle.model_seed = seed;
    bundle.lags = lags;
    bundle.n_candidates = 27;
    bundle.selected_candidate_index = sel;
    bundle.selected_candidate_content_hash = canonical_sha256(struct('seed', seed, 'sel', sel));
    bundle.selection_lags = (1:50)';
    bundle.same_reservoir_for_all_lags = true;
    bundle.test_targets_used_for_selection = false;
    bundle.provenance = 'production';
    bundle.is_test_fixture = false;
    bundle.per_lag = per_lag;
    bundle.summary = summarize_temporal_memory_curve(lags, mc, lag_metrics);
    bundle.memory_coefficients = mc;
    bundle.protocol_version = 'matched_conventional_memory_curve_v1';
    bundle.engine = 'run_conventional_leaky_esn';
    bundle.candidate_grid_source = 'build_matched_task_baselines_config';
    bundle.reservoir_seed = seed + 2000;
    bundle.selection_metric = 'mean_validation_nrmse_over_all_preregistered_lags';
    bundle.tie_tolerance = 1e-12;
    bundle.tie_break = 'earliest_candidate_in_frozen_order';
    bundle.execution_scope = 'once_per_model_seed_shared_across_all_diagnostic_cells';
    bundle.selected_hyperparameters = struct('spectral_radius', 0.9, 'leak_rate', 0.5, 'input_scaling', 1);
    table_rows = repmat(struct('candidate_index', NaN, 'spectral_radius', NaN, ...
        'leak_rate', NaN, 'input_scaling', NaN, 'aggregate_validation_nrmse', NaN, ...
        'selected_candidate', false), 27, 1);
    for ic = 1:27
        table_rows(ic).candidate_index = ic;
        table_rows(ic).spectral_radius = 0.8 + 0.01 * ic;
        table_rows(ic).leak_rate = 0.5;
        table_rows(ic).input_scaling = 1;
        table_rows(ic).aggregate_validation_nrmse = 0.4 + 0.01 * ic;
        table_rows(ic).selected_candidate = (ic == sel);
    end
    bundle.candidate_selection_table = table_rows;
    bundle.aggregate_validation_nrmse = [table_rows.aggregate_validation_nrmse]';
    bundle.per_candidate_per_lag_validation_nrmse = zeros(27, n);
    bundle.Wres = eye(4);
    bundle.Win = ones(4, 1);
    bundle.X_test = zeros(10, 4);
    bundle.test_targets_used_for_fitting = false;
    bundle.used_narma_orchestrator = false;
    bundle.used_mackey_glass_orchestrator = false;
    for i = 1:n
        bundle.per_lag(i).hyperparameters = bundle.selected_hyperparameters;
        bundle.per_lag(i).numerical_rank = 4;
        bundle.per_lag(i).coefficient_norm = 1;
        bundle.per_lag(i).intercept = 0;
        bundle.per_lag(i).coefficients = [1; 0.5];
        bundle.per_lag(i).feature_mean = [0, 0];
        bundle.per_lag(i).feature_scale = [1, 1];
    end
    bundle.reused_shared_baseline = true;
    bundle.bundle_content_hash = temporal_memory_conventional_bundle_content_hash(bundle);
end

function ctrl = synthesize_control(lags, name, salt)
    lags = lags(:);
    n = numel(lags);
    per_lag = repmat(struct('lag', NaN, 'metrics', struct()), n, 1);
    mc = zeros(n, 1);
    lag_metrics = repmat(struct('nrmse', NaN, 'r2', NaN, 'pearson', NaN, ...
        'memory_coefficient', NaN, 'rmse', NaN), n, 1);
    for i = 1:n
        base = 0.02 * salt + 0.012 * lags(i);
        m = struct('nrmse', 0.55 + base, 'r2', max(0, 0.75 - base), ...
            'pearson', 0, 'memory_coefficient', 0, 'rmse', 0.28 + base);
        m.pearson = sqrt(max(0, m.r2));
        m.memory_coefficient = m.pearson^2;
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
end

function field = key_to_field(key)
    field = regexprep(key, '[^A-Za-z0-9]', '_');
    if ~isempty(field) && field(1) >= '0' && field(1) <= '9'
        field = ['k_', field];
    end
end

function sha = git_head_sha()
    [status, out] = system('git rev-parse HEAD');
    if status == 0
        sha = strtrim(out);
    else
        sha = 'unknown';
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
