function bench = mackey_glass_benchmark(esn_or_params, options)
% mackey_glass_benchmark
% Mackey-Glass prediction benchmark (one-step and optional autonomous rollout).
%
% Usage:
%   bench = mackey_glass_benchmark(params);
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct
%   options - struct (optional)
%       .tau            (default 17)
%       .dt_mg          (default 1.0)
%       .T              (default 6000)
%       .discard        (default 1000)
%       .washout_steps  (default 200)
%       .train_ratio    (default 0.6)
%       .val_ratio      (default 0.2)
%       .lambda_grid    (optional)
%       .seed           (default 1)
%       .feature_mode   (default 'x')
%       .do_rollout     (default true)
%       .rollout_steps  (default 500)
%       .ar_lags        (default 10)
%
% Output:
%   bench - standardized benchmark struct (see narma_benchmark).
%           Autonomous rollout is reported separately and is ODE-only.

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

    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
    else
        esn = SRNN_ESN(esn_or_params);
    end

    esn.which_states = feature_mode;
    esn.include_input = false;

    rng(seed);
    [t, x] = generate_mackey_glass('tau', tau, 'dt', dt_mg, 'n_samples', T, 'discard', discard);

    u = x(1:end-1);
    y = x(2:end);
    u = u(:);
    y = y(:);

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

    pred_opts = struct( ...
        'reset_before', true, ...
        'context_U', u(1:split.test_idx(1)-1, :));
    y_pred_test = esn.predict(u(split.test_idx, :), pred_opts);
    y_pred_train = predict_segment(esn, u, split.train_idx, washout_steps);
    y_pred_val = predict_segment(esn, u, split.val_idx, 0);

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
    baseline_opts = struct( ...
        'task', 'mackey_glass_onestep', ...
        'mesn_Win', esn.W_in, ...
        'base_seed', base_seed, ...
        'seed', seed, ...
        'feature_mode', feature_mode, ...
        'lambda_grid', lambda_grid, ...
        'ar_lags', ar_lags, ...
        'model_test_nrmse', metrics_test.nrmse, ...
        'benchmark_baselines', bb);
    baselines = compute_matched_onestep_baselines(u, y, split, washout_steps, baseline_opts);

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
        'ar_lags', ar_lags, ...
        'resolved_lambda_grid', lambda_grid(:), ...
        'matched_baselines_protocol', bb.protocol_version);
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
    bench.status = 'ok';
    if isfield(baselines, 'conventional_leaky_esn') && ...
            ~strcmp(char(baselines.conventional_leaky_esn.status), 'computed')
        bench.status = 'failed_required_baseline';
        bench.failure_status = sprintf('conventional_leaky_esn:%s', ...
            char(baselines.conventional_leaky_esn.status));
    end

    teacher_forced_ok = isempty(esn.lags) ...
        && esn.n_inputs == 1 ...
        && esn.n_outputs == 1 ...
        && isfinite(metrics_test.nrmse) ...
        && isfinite(metrics_test.rmse);
    if do_rollout && teacher_forced_ok
        init_len = max(2*washout_steps, 200);
        init_len = min(init_len, numel(split.test_idx) - 1);
        if init_len < 2 || (init_len + rollout_steps) > numel(split.test_idx)
            bench.rollout = struct( ...
                'status', 'skipped', ...
                'reason', 'Test segment too short for requested autonomous rollout.', ...
                'prediction_mode', 'ode_autonomous');
        else
            u_test = u(split.test_idx);
            y_test_full = y(split.test_idx);
            init_data = u_test(1:init_len);
            [y_roll, ~] = esn.generateAutonomous(init_data, rollout_steps);
            y_true = y_test_full((init_len+1):(init_len+rollout_steps));
            y_true = y_true(:);
            bench.rollout = struct();
            bench.rollout.status = 'computed';
            bench.rollout.prediction_mode = 'ode_autonomous';
            bench.rollout.init_len = init_len;
            bench.rollout.y_roll = y_roll;
            bench.rollout.y_true = y_true;
            bench.rollout.metrics = compute_metrics(y_roll, y_true);
        end
    elseif do_rollout
        bench.rollout = struct( ...
            'status', 'skipped', ...
            'reason', 'Autonomous rollout requires ODE mode, scalar I/O, and finite one-step test metrics.', ...
            'prediction_mode', 'ode_autonomous');
    end
end

function y_pred = predict_segment(esn, u, idx, washout_discard)
    if isempty(idx)
        y_pred = zeros(0, esn.n_outputs);
        return;
    end
    if idx(1) == 1
        context_U = zeros(0, size(u, 2));
    else
        context_U = u(1:idx(1)-1, :);
    end
    y_all = esn.predict(u(idx, :), struct('reset_before', true, 'context_U', context_U));
    if washout_discard > 0
        y_pred = y_all(washout_discard+1:end, :);
    else
        y_pred = y_all;
    end
end

function split = make_split_struct(train_info, washout_steps)
    split = struct();
    split.train_idx = train_info.train_idx;
    split.val_idx = train_info.val_idx;
    split.test_idx = train_info.test_idx;
    split.washout_steps = washout_steps;
    split.n_train_after_washout = numel(train_info.train_idx) - washout_steps;
    split.n_val = numel(train_info.val_idx);
    split.n_test = numel(train_info.test_idx);
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end
