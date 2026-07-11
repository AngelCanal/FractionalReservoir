function bench = narma_benchmark(esn_or_params, options)
% narma_benchmark
% Evaluate reservoir on NARMA-n benchmark (n=10 or 20).
%
% Usage:
%   bench = narma_benchmark(params, struct('order',10));
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct
%   options - struct (optional)
%       .order          (default 10)   10 or 20
%       .T              (default 6000)
%       .washout_steps  (default 200)
%       .train_ratio    (default 0.6)
%       .val_ratio      (default 0.2)
%       .lambda_grid    (optional) ridge candidates for trainReadout
%       .seed           (default 1)
%       .u_range        (default [0, 0.5])
%       .feature_mode   (default 'x')
%
% Output:
%   bench - struct with configuration, split indices, selected lambda,
%           train/val/test metrics, predictions, targets, baselines, seed,
%           prediction_mode, and status.

    if nargin < 2 || isempty(options)
        options = struct();
    end

    order = getFieldOrDefault(options, 'order', 10);
    T = getFieldOrDefault(options, 'T', 6000);
    washout_steps = getFieldOrDefault(options, 'washout_steps', ...
        getFieldOrDefault(options, 'washout', 200));
    train_ratio = getFieldOrDefault(options, 'train_ratio', 0.6);
    val_ratio = getFieldOrDefault(options, 'val_ratio', 0.2);
    seed = getFieldOrDefault(options, 'seed', 1);
    u_range = getFieldOrDefault(options, 'u_range', [0, 0.5]);
    feature_mode = getFieldOrDefault(options, 'feature_mode', 'x');

    if ~(order == 10 || order == 20)
        error('narma_benchmark:InvalidOrder', 'order must be 10 or 20');
    end

    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
    else
        esn = SRNN_ESN(esn_or_params);
    end

    esn.which_states = feature_mode;
    esn.include_input = false;

    rng(seed);
    u = u_range(1) + (u_range(2) - u_range(1)) * rand(T, 1);
    y = generate_narma(u, order);

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

    baselines = narma_baselines(u, y, split, washout_steps, order);

    config = struct( ...
        'order', order, ...
        'T', T, ...
        'washout_steps', washout_steps, ...
        'train_ratio', train_ratio, ...
        'val_ratio', val_ratio, ...
        'seed', seed, ...
        'u_range', u_range, ...
        'feature_mode', feature_mode);
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
    bench.baselines = baselines;
    bench.seed = seed;
    bench.order = order;
    bench.u = u;
    bench.y = y;
    bench.prediction_mode = 'reset_with_context';
    bench.status = 'ok';
end

function baselines = narma_baselines(u, y, split, washout_steps, order)
    train_fit_idx = split.train_idx(washout_steps+1:end);
    y_train = y(train_fit_idx);
    y_val = y(split.val_idx);
    y_test = y(split.test_idx);

    mu = mean(y_train);
    mean_pred_train = mu * ones(size(y_train));
    mean_pred_val = mu * ones(size(y_val));
    mean_pred_test = mu * ones(size(y_test));

    baselines = struct();
    baselines.target_mean = struct( ...
        'metrics_train', compute_metrics(mean_pred_train, y_train), ...
        'metrics_val', compute_metrics(mean_pred_val, y_val), ...
        'metrics_test', compute_metrics(mean_pred_test, y_test));

    n_lags = order;
    [Phi, valid] = input_lag_features(u, n_lags);
    fit_mask = false(size(u));
    fit_mask(train_fit_idx) = true;
    fit_mask = fit_mask & valid;

    X_fit = Phi(fit_mask, :);
    y_fit = y(fit_mask);
    X_design = [X_fit, ones(size(X_fit, 1), 1)];
    w = X_design \ y_fit;

    ar_pred = nan(size(y));
    ar_pred(valid) = [Phi(valid, :), ones(nnz(valid), 1)] * w;

    baselines.linear_input_ar = struct( ...
        'n_lags', n_lags, ...
        'metrics_train', metrics_on_valid(ar_pred, y, train_fit_idx, valid), ...
        'metrics_val', metrics_on_valid(ar_pred, y, split.val_idx, valid), ...
        'metrics_test', metrics_on_valid(ar_pred, y, split.test_idx, valid));
end

function metrics = metrics_on_valid(pred, y, idx, valid)
    keep = idx(valid(idx));
    metrics = compute_metrics(pred(keep), y(keep));
end

function [Phi, valid] = input_lag_features(u, n_lags)
    T = size(u, 1);
    Phi = zeros(T, n_lags);
    valid = false(T, 1);
    for t = n_lags:T
        Phi(t, :) = u(t:-1:(t-n_lags+1), 1)';
        valid(t) = true;
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

function y = generate_narma(u, order)
    T = numel(u);
    y = zeros(T, 1);
    y(1:order) = 0.1;

    for t = order:(T-1)
        y_sum = sum(y((t-order+1):t));
        y(t+1) = 0.3*y(t) + 0.05*y(t)*y_sum + 1.5*u(t-order+1)*u(t) + 0.1;
    end
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end
