function bench = mackey_glass_benchmark(esn_or_params, options)
% mackey_glass_benchmark
% Mackey-Glass prediction benchmark (one-step and optional autonomous rollout).
%
% When options.shared_baseline_bundle is provided, task/split hashes are verified
% against the seed-shared bundle. Standalone local baselines use
% executed_cell_local provenance (not publication shared-bundle provenance).
%
% Autonomous ODE rollout uses options.mg_autonomous_rollout (or
% options.cfg.mg_autonomous_rollout): full-history context, deterministic
% held-out origins, corrected one-step-to-autonomous alignment. DDE models
% emit unsupported_not_computed (never skipped/computed/NaN-without-status).

    if nargin < 2 || isempty(options)
        options = struct();
    end

    tau = getFieldOrDefault(options, 'tau', 17);
    dt_mg = getFieldOrDefault(options, 'dt_mg', 1.0);
    T = getFieldOrDefault(options, 'T', 6000);
    discard = getFieldOrDefault(options, 'discard', 1000);
    washout_steps = getFieldOrDefault(options, 'washout_steps', ...
        getFieldOrDefault(options, 'washout', 200));
    train_ratio = getFieldOrDefault(options, 'train_ratio', 0.6);
    val_ratio = getFieldOrDefault(options, 'val_ratio', 0.2);
    seed = getFieldOrDefault(options, 'seed', 1);
    feature_mode = getFieldOrDefault(options, 'feature_mode', 'x');
    do_rollout = getFieldOrDefault(options, 'do_rollout', true);
    rollout_steps = getFieldOrDefault(options, 'rollout_steps', 500);
    ar_lags = getFieldOrDefault(options, 'ar_lags', 10);
    rollout_cfg = resolve_mg_rollout_cfg(options, do_rollout, rollout_steps);

    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
    else
        esn = SRNN_ESN(esn_or_params);
    end

    esn.which_states = feature_mode;
    esn.include_input = false;

    task = build_mackey_glass_onestep_task_dataset(struct( ...
        'tau', tau, ...
        'dt_mg', dt_mg, ...
        'T', T, ...
        'discard', discard, ...
        'washout_steps', washout_steps, ...
        'train_ratio', train_ratio, ...
        'val_ratio', val_ratio, ...
        'seed', seed));
    u = task.U;
    y = task.Y;
    t = task.t;
    x = task.x;
    expected_split = task.split;

    shared = getFieldOrDefault(options, 'shared_baseline_bundle', []);
    if ~isempty(shared)
        verify_shared_task_identity(shared, task, options, esn.W_in);
    end

    train_opts = struct( ...
        'train_ratio', train_ratio, ...
        'val_ratio', val_ratio, ...
        'washout_steps', washout_steps);
    if isfield(options, 'lambda_grid')
        train_opts.lambda_grid = options.lambda_grid;
    end
    for fn = {'ode_reltol','ode_abstol','dde_reltol','dde_abstol','ode_solver'}
        if isfield(options, fn{1})
            train_opts.(fn{1}) = options.(fn{1});
        end
    end

    train_info = esn.trainReadout(u, y, train_opts);
    split = make_split_struct(train_info, washout_steps);
    if ~isequal(split.train_idx(:), expected_split.train_idx(:)) || ...
            ~isequal(split.val_idx(:), expected_split.val_idx(:)) || ...
            ~isequal(split.test_idx(:), expected_split.test_idx(:))
        error('mackey_glass_benchmark:SplitMismatch', ...
            'trainReadout split diverged from shared task helper split.');
    end

    pred_opts = struct( ...
        'reset_before', true, ...
        'context_U', u(1:split.test_idx(1)-1, :));
    for fn = {'ode_reltol','ode_abstol','dde_reltol','dde_abstol','ode_solver'}
        if isfield(train_opts, fn{1})
            pred_opts.(fn{1}) = train_opts.(fn{1});
        end
    end
    y_pred_test = esn.predict(u(split.test_idx, :), pred_opts);
    y_pred_train = predict_segment(esn, u, split.train_idx, washout_steps, train_opts);
    y_pred_val = predict_segment(esn, u, split.val_idx, 0, train_opts);

    y_train = y(split.train_idx(washout_steps+1:end), :);
    y_val = y(split.val_idx, :);
    y_test = y(split.test_idx, :);

    metrics_train = compute_metrics(y_pred_train, y_train);
    metrics_val = compute_metrics(y_pred_val, y_val);
    metrics_test = compute_metrics(y_pred_test, y_test);

    lambda_grid = resolve_baseline_lambda_grid(options, []);
    if isfield(options, 'cfg')
        lambda_grid = resolve_baseline_lambda_grid(options, options.cfg);
    end
    base_seed = getFieldOrDefault(options, 'base_seed', seed);
    if isfield(options, 'benchmark_baselines') && ~isempty(options.benchmark_baselines)
        bb = options.benchmark_baselines;
    else
        bb = build_matched_task_baselines_config(struct('base', struct('n', size(esn.W_in, 1))));
    end

    failure_reasons = {};
    if ~isempty(shared)
        baselines = attach_shared_baselines_for_cell( ...
            shared.mackey_glass_onestep, metrics_test.nrmse, feature_mode, bb, ...
            shared.bundle_id);
        baselines.task_data_hash = task.task_data_hash;
        baselines.split_hash = task.split_hash;
        [ok, vrep] = validate_matched_task_baselines(baselines, 'mackey_glass_onestep', ...
            struct('lambda_grid', lambda_grid, ...
                'task_data_hash', task.task_data_hash, ...
                'split_hash', task.split_hash, ...
                'feature_mode', feature_mode, ...
                'dale_mesn_control_keys', bb.dale_mesn_control_keys, ...
                'require_dale', true, ...
                'require_comparisons', true, ...
                'require_candidate_table', false));
        if ~ok
            failure_reasons = vrep.reasons;
        end
    else
        baseline_opts = struct( ...
            'task', 'mackey_glass_onestep', ...
            'mesn_Win', esn.W_in, ...
            'base_seed', base_seed, ...
            'seed', seed, ...
            'feature_mode', feature_mode, ...
            'lambda_grid', lambda_grid, ...
            'ar_lags', ar_lags, ...
            'model_test_nrmse', metrics_test.nrmse, ...
            'benchmark_baselines', bb, ...
            'task_data_hash', task.task_data_hash, ...
            'split_hash', task.split_hash);
        baselines = compute_matched_onestep_baselines(u, y, split, washout_steps, baseline_opts);
        baselines.evaluation_provenance = struct( ...
            'mode', 'executed_cell_local', ...
            'publication_shared_bundle', false);
        baselines.bundle_id = '';
        [ok, vrep] = validate_matched_task_baselines(baselines, 'mackey_glass_onestep', ...
            struct('lambda_grid', lambda_grid, ...
                'task_data_hash', task.task_data_hash, ...
                'split_hash', task.split_hash, ...
                'feature_mode', feature_mode, ...
                'dale_mesn_control_keys', bb.dale_mesn_control_keys, ...
                'require_dale', true, ...
                'require_comparisons', true, ...
                'require_candidate_table', true));
        if ~ok
            failure_reasons = vrep.reasons;
        end
    end

    config = struct( ...
        'tau', tau, ...
        'dt_mg', dt_mg, ...
        'T', T, ...
        'discard', discard, ...
        'washout_steps', washout_steps, ...
        'train_ratio', train_ratio, ...
        'val_ratio', val_ratio, ...
        'seed', seed, ...
        'base_seed', base_seed, ...
        'feature_mode', feature_mode, ...
        'do_rollout', do_rollout, ...
        'rollout_steps', rollout_steps, ...
        'mg_autonomous_rollout', rollout_cfg, ...
        'ar_lags', ar_lags, ...
        'resolved_lambda_grid', lambda_grid(:), ...
        'matched_baselines_protocol', bb.protocol_version, ...
        'task_data_hash', task.task_data_hash, ...
        'split_hash', task.split_hash);
    if isfield(options, 'lambda_grid')
        config.lambda_grid = options.lambda_grid;
    end

    bench = struct();
    bench.configuration = config;
    bench.options = options;
    bench.split = split;
    bench.selected_lambda = train_info.selected_lambda;
    bench.metrics = struct('train', metrics_train, 'val', metrics_val, 'test', metrics_test);
    bench.metrics_train = metrics_train;
    bench.metrics_val = metrics_val;
    bench.metrics_test = metrics_test;
    bench.predictions = struct('train', y_pred_train, 'val', y_pred_val, 'test', y_pred_test);
    bench.targets = struct('train', y_train, 'val', y_val, 'test', y_test);
    bench.y_pred_test = y_pred_test;
    bench.y_test = y_test;
    bench.baselines = baselines;
    bench.seed = seed;
    bench.base_seed = base_seed;
    bench.t = t;
    bench.x = x;
    bench.prediction_mode = 'reset_with_context';
    bench.task_data_hash = task.task_data_hash;
    bench.split_hash = task.split_hash;
    if isempty(failure_reasons)
        bench.status = 'ok';
    else
        bench.status = 'failed_required_baseline';
        bench.failure_status = strjoin(failure_reasons, ',');
        bench.baseline_failure_reasons = failure_reasons;
    end

    rollout_enabled = do_rollout;
    if ~isempty(rollout_cfg) && isfield(rollout_cfg, 'enabled')
        rollout_enabled = do_rollout && logical(rollout_cfg.enabled);
    end
    if rollout_enabled
        bench.rollout = evaluate_mg_autonomous_rollout(esn, u, y, split, y_pred_test, ...
            metrics_test, train_opts, rollout_cfg);
        if strcmp(bench.rollout.status, 'failed_required_autonomous_endpoint') && ...
                strcmp(bench.status, 'ok')
            bench.status = 'failed_required_autonomous_endpoint';
            if isfield(bench.rollout, 'failure_reasons')
                bench.failure_status = strjoin(bench.rollout.failure_reasons, ',');
            else
                bench.failure_status = 'failed_required_autonomous_endpoint';
            end
        end
        bench.rollout = attach_mg_controls_to_rollout( ...
            bench.rollout, shared, baselines, u, y, split, task, ...
            feature_mode, bb, base_seed, rollout_cfg, options);
    end
end

function rollout = attach_mg_controls_to_rollout(rollout, shared, baselines, u, y, split, task, ...
        feature_mode, bb, base_seed, rollout_cfg, options)
    if isfield(options, 'mg_autonomous_controls_override') && ...
            ~isempty(options.mg_autonomous_controls_override)
        error('mackey_glass_benchmark:InjectedAutonomousControls', ...
            'Caller-injected autonomous-control overrides are rejected.');
    end
    if ~isempty(shared) && isfield(shared, 'mackey_glass_autonomous')
        controls = attach_shared_mg_autonomous_controls_for_cell( ...
            shared.mackey_glass_autonomous, rollout, feature_mode, ...
            shared.bundle_id, rollout_cfg, bb);
        controls.evaluation_provenance.bundle_id = shared.bundle_id;
        controls.base_seed = shared.base_seed;
        controls.task_seed = shared.mackey_glass_task_seed;
        controls.task_data_hash = shared.mackey_glass_task_data_hash;
        controls.split_hash = shared.mackey_glass_split_hash;
        if isfield(shared.mackey_glass_autonomous, 'origin_schedule')
            controls.origin_schedule = shared.mackey_glass_autonomous.origin_schedule;
        end
        rollout.controls = controls;
        return;
    end
    % Standalone local path: reuse fitted one-step models; not publication provenance.
    task_local = task;
    task_local.U = u;
    task_local.Y = y;
    task_local.split = split;
    shared_local = compute_mg_autonomous_baseline_controls( ...
        task_local, baselines, rollout_cfg, base_seed, 'executed_cell_local', ...
        struct('autonomous_controls_config', bb.mackey_glass_autonomous_controls));
    controls = attach_shared_mg_autonomous_controls_for_cell( ...
        shared_local, rollout, feature_mode, '', rollout_cfg, bb);
    controls.evaluation_provenance.mode = 'executed_cell_local';
    controls.evaluation_provenance.publication_shared_bundle = false;
    controls.base_seed = base_seed;
    controls.task_seed = task.seed;
    controls.task_data_hash = task.task_data_hash;
    controls.split_hash = task.split_hash;
    if isfield(shared_local, 'origin_schedule')
        controls.origin_schedule = shared_local.origin_schedule;
    end
    rollout.controls = controls;
end

function rollout = evaluate_mg_autonomous_rollout(esn, u, y, split, y_pred_test, ...
        metrics_test, train_opts, rollout_cfg)
    is_dde = ~isempty(esn.lags);
    if is_dde
        rollout = struct();
        rollout.status = 'unsupported_not_computed';
        rollout.protocol_version = char(rollout_cfg.protocol_version);
        rollout.mode = 'DDE';
        rollout.reason = 'DDE autonomous continuation is not implemented';
        rollout.predictions = [];
        rollout.metrics = [];
        rollout.evaluation_provenance = struct('mode', 'unsupported');
        return;
    end

    failure_reasons = {};
    try
        if esn.n_inputs ~= 1 || esn.n_outputs ~= 1
            error('mackey_glass_benchmark:AutonomousIO', ...
                'MG autonomous rollout requires scalar I/O.');
        end
        if esn.include_input
            error('mackey_glass_benchmark:IncludeInput', ...
                'MG autonomous protocol requires include_input=false.');
        end
        if ~(isfinite(metrics_test.nrmse) && isfinite(metrics_test.rmse))
            error('mackey_glass_benchmark:NonfiniteOneStep', ...
                'One-step test metrics must be finite before autonomous rollout.');
        end

        schedule = build_mg_autonomous_origin_schedule(split, rollout_cfg);
        origins = schedule.origin_indices(:);
        H = schedule.forecast_horizon_steps;
        % Drive the same contiguous prefix used by one-step test prediction
        % (U through test_end). Stopping early at max(origin) changes adaptive
        % ODE meshing and breaks first-step alignment.
        drive_end = split.test_idx(end);

        run_opts = struct( ...
            'reset_before', true, ...
            'update_internal_state', false, ...
            'ode_reltol', getFieldOrDefault(train_opts, 'ode_reltol', 1e-6), ...
            'ode_abstol', getFieldOrDefault(train_opts, 'ode_abstol', 1e-8));
        if isfield(train_opts, 'ode_solver')
            run_opts.ode_solver = train_opts.ode_solver;
        elseif ~isempty(esn.ode_solver)
            run_opts.ode_solver = esn.ode_solver;
        end

        S_before = esn.S;
        [X_drv, S_hist] = esn.runReservoir(u(1:drive_end, :), run_opts);
        if ~isequaln(esn.S, S_before)
            error('mackey_glass_benchmark:StateMutation', ...
                'Teacher-forced trajectory mutated obj.S.');
        end

        auto_opts = struct( ...
            'return_features', true, ...
            'ode_reltol', run_opts.ode_reltol, ...
            'ode_abstol', run_opts.ode_abstol);
        if isfield(run_opts, 'ode_solver')
            auto_opts.ode_solver = run_opts.ode_solver;
        end

        align_tol = 1e-7;
        preds = cell(numel(origins), 1);
        align_ok = true(numel(origins), 1);
        for o = 1:numel(origins)
            i = origins(o);
            S_i = S_hist(i, :).';
            frozen = apply_ridge_readout(esn.readout_model, X_drv(i, :));
            test_rel = schedule.origin_test_relative_indices(o);
            frozen_bench = y_pred_test(test_rel, :);
            if max(abs(frozen(:) - frozen_bench(:))) > align_tol * max(1, max(abs(frozen_bench(:))))
                align_ok(o) = false;
                failure_reasons{end+1} = sprintf( ...
                    'frozen_one_step_mismatch_origin_%d', i); %#ok<AGROW>
            end

            [y_hat, ~, gen_info] = esn.generateAutonomousFromState( ...
                S_i, u(i, :), H, auto_opts);
            if ~isequaln(esn.S, S_before)
                error('mackey_glass_benchmark:StateMutation', ...
                    'Autonomous generation mutated obj.S at origin %d.', i);
            end
            if max(abs(y_hat(1, :) - frozen(:)')) > align_tol * max(1, max(abs(frozen(:))))
                align_ok(o) = false;
                failure_reasons{end+1} = sprintf( ...
                    'step1_alignment_failed_origin_%d', i); %#ok<AGROW>
            end
            if any(~isfinite(y_hat(:)))
                error('mackey_glass_benchmark:NonfiniteForecast', ...
                    'Nonfinite autonomous forecast at origin %d.', i);
            end
            preds{o} = y_hat(:);
            if o == 1
                first_gen_info = gen_info;
            end
        end

        if ~all(align_ok)
            error('mackey_glass_benchmark:AlignmentFailed', ...
                'First-step autonomous alignment failed: %s', ...
                strjoin(failure_reasons, ','));
        end

        scored = score_mg_autonomous_forecasts(preds, y, origins, split, rollout_cfg);

        rollout = struct();
        rollout.status = 'computed';
        rollout.protocol_version = char(rollout_cfg.protocol_version);
        rollout.role = char(rollout_cfg.role);
        rollout.mode = 'ODE';
        rollout.origin_schedule = schedule;
        rollout.forecast_horizon_steps = H;
        rollout.fixed_report_horizons = rollout_cfg.fixed_report_horizons(:);
        rollout.normalization_reference = char(rollout_cfg.normalization_reference);
        rollout.normalization_scale = scored.normalization_scale;
        rollout.per_origin = scored.per_origin;
        rollout.metrics = scored.metrics;
        rollout.predictions = preds;
        rollout.evaluation_provenance = struct( ...
            'mode', 'executed', ...
            'test_target_override_used', false, ...
            'origin_override_used', false, ...
            'model_refit_for_rollout', false, ...
            'lambda_reselected_for_rollout', false, ...
            'autonomous_performance_used_for_selection', false, ...
            'first_prediction_alignment_verified', true, ...
            'object_state_unchanged', true, ...
            'generation_info', first_gen_info);
        [vok, vrep] = validate_mg_autonomous_rollout_result(rollout, ...
            struct('mg_autonomous_rollout', rollout_cfg), 'ODE');
        if ~vok
            error('mackey_glass_benchmark:RolloutValidationFailed', ...
                'Rollout validation failed: %s', strjoin(vrep.reasons, ','));
        end
    catch ME
        rollout = struct();
        rollout.status = 'failed_required_autonomous_endpoint';
        rollout.protocol_version = char(rollout_cfg.protocol_version);
        rollout.role = char(rollout_cfg.role);
        rollout.mode = 'ODE';
        rollout.failure_reasons = unique([failure_reasons(:).', {ME.message}], 'stable');
        rollout.error_id = ME.identifier;
        rollout.predictions = [];
        rollout.metrics = [];
        rollout.evaluation_provenance = struct( ...
            'mode', 'failed', ...
            'test_target_override_used', false, ...
            'origin_override_used', false, ...
            'model_refit_for_rollout', false, ...
            'lambda_reselected_for_rollout', false, ...
            'autonomous_performance_used_for_selection', false, ...
            'first_prediction_alignment_verified', false);
    end
end

function rollout_cfg = resolve_mg_rollout_cfg(options, do_rollout, rollout_steps)
    rollout_cfg = [];
    if isfield(options, 'mg_autonomous_rollout') && ~isempty(options.mg_autonomous_rollout)
        rollout_cfg = options.mg_autonomous_rollout;
    elseif isfield(options, 'cfg') && isstruct(options.cfg) && ...
            isfield(options.cfg, 'mg_autonomous_rollout')
        rollout_cfg = options.cfg.mg_autonomous_rollout;
    end
    if isempty(rollout_cfg)
        if ~do_rollout
            return;
        end
        % Standalone/test fallback: smoke-sized protocol with requested horizon
        rollout_cfg = build_mg_autonomous_rollout_config('smoke');
        if ~isempty(rollout_steps) && isfinite(rollout_steps) && rollout_steps >= 1
            H = double(rollout_steps);
            rollout_cfg.forecast_horizon_steps = H;
            rollout_cfg.fixed_report_horizons = unique([1, min(5, H), min(10, H), H], 'stable');
            rollout_cfg.fixed_report_horizons = rollout_cfg.fixed_report_horizons( ...
                rollout_cfg.fixed_report_horizons >= 1 & rollout_cfg.fixed_report_horizons <= H);
        end
    end
end

function verify_shared_task_identity(shared, task, options, W_in)
    base_seed = getFieldOrDefault(options, 'base_seed', task.seed);
    cfg = getFieldOrDefault(options, 'cfg', struct());
    if ~isfield(cfg, 'protocol_fingerprint')
        error('mackey_glass_benchmark:MissingCfgFingerprint', ...
            'shared baselines require options.cfg.protocol_fingerprint.');
    end
    [ok, report] = validate_seed_matched_baseline_bundle(shared, cfg, base_seed, W_in);
    if ~ok
        error('mackey_glass_benchmark:SharedBundleInvalid', ...
            'Shared baseline bundle rejected: %s', strjoin(report.reasons, ','));
    end
    if ~strcmp(char(task.task_data_hash), char(shared.mackey_glass_task_data_hash))
        error('mackey_glass_benchmark:TaskHashMismatch', ...
            'Regenerated MG task_data_hash differs from shared bundle.');
    end
    if ~strcmp(char(task.split_hash), char(shared.mackey_glass_split_hash))
        error('mackey_glass_benchmark:SplitHashMismatch', ...
            'Regenerated MG split_hash differs from shared bundle.');
    end
    if task.seed ~= shared.mackey_glass_task_seed
        error('mackey_glass_benchmark:TaskSeedMismatch', ...
            'MG task seed differs from shared bundle.');
    end
end

function y_pred = predict_segment(esn, u, idx, washout_discard, train_opts)
    if nargin < 5
        train_opts = struct();
    end
    if isempty(idx)
        y_pred = zeros(0, esn.n_outputs);
        return;
    end
    if idx(1) == 1
        context_U = zeros(0, size(u, 2));
    else
        context_U = u(1:idx(1)-1, :);
    end
    pred_opts = struct('reset_before', true, 'context_U', context_U);
    for fn = {'ode_reltol','ode_abstol','dde_reltol','dde_abstol','ode_solver'}
        if isfield(train_opts, fn{1})
            pred_opts.(fn{1}) = train_opts.(fn{1});
        end
    end
    y_all = esn.predict(u(idx, :), pred_opts);
    if washout_discard > 0
        y_pred = y_all(washout_discard+1:end, :);
    else
        y_pred = y_all;
    end
end

function split = make_split_struct(train_info, washout_steps)
    split = struct();
    split.train_idx = train_info.train_idx(:);
    split.val_idx = train_info.val_idx(:);
    split.test_idx = train_info.test_idx(:);
    split.washout_steps = washout_steps;
    split.n_train_after_washout = numel(train_info.train_idx) - washout_steps;
    split.n_val = numel(train_info.val_idx);
    split.n_test = numel(train_info.test_idx);
    split.split_hash = canonical_sha256(struct( ...
        'train_idx', split.train_idx, ...
        'val_idx', split.val_idx, ...
        'test_idx', split.test_idx, ...
        'washout_steps', washout_steps));
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end
