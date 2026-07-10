function bench = frequency_discrimination_benchmark(esn_or_params, options)
% frequency_discrimination_benchmark
% Frequency discrimination: input is a sine whose frequency changes at random
% intervals; readout classifies the current frequency class.
%
% Usage:
%   bench = frequency_discrimination_benchmark(params);
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct
%   options - struct (optional)
%       .T              (default 8000)
%       .dt             (default 0.1)
%       .freq_set       (default [0.02 0.05 0.1 0.2 0.4])
%       .min_seg        (default 200)
%       .max_seg        (default 800)
%       .amplitude      (default 1.0)
%       .washout_steps  (default 200)
%       .train_ratio    (default 0.6)
%       .val_ratio      (default 0.2)
%       .lambda_grid    (optional)
%       .seed           (default 1)
%       .feature_mode   (default 'x')
%       .summary_window (default 50)
%
% Output:
%   bench - standardized classification benchmark struct.

    if nargin < 2 || isempty(options)
        options = struct();
    end

    T = getFieldOrDefault(options, 'T', 8000);
    dt = getFieldOrDefault(options, 'dt', 0.1);
    freq_set = getFieldOrDefault(options, 'freq_set', [0.02 0.05 0.1 0.2 0.4]);
    min_seg = getFieldOrDefault(options, 'min_seg', 200);
    max_seg = getFieldOrDefault(options, 'max_seg', 800);
    amplitude = getFieldOrDefault(options, 'amplitude', 1.0);
    washout_steps = getFieldOrDefault(options, 'washout_steps', ...
        getFieldOrDefault(options, 'washout', 200));
    train_ratio = getFieldOrDefault(options, 'train_ratio', 0.6);
    val_ratio = getFieldOrDefault(options, 'val_ratio', 0.2);
    seed = getFieldOrDefault(options, 'seed', 1);
    feature_mode = getFieldOrDefault(options, 'feature_mode', 'x');
    summary_window = getFieldOrDefault(options, 'summary_window', 50);

    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
    else
        esn = SRNN_ESN(esn_or_params);
    end

    esn.which_states = feature_mode;
    esn.include_input = false;

    rng(seed);

    u = zeros(T, 1);
    class_id = zeros(T, 1);
    t = (0:(T-1))' * dt;
    idx = 1;
    phase0 = 0;
    seg_info = [];
    freq_set = freq_set(:)';
    n_classes = numel(freq_set);

    while idx <= T
        seg_len = randi([min_seg, max_seg], 1, 1);
        seg_end = min(T, idx + seg_len - 1);
        c = randi(n_classes, 1, 1);
        f = freq_set(c);

        tt = t(idx:seg_end);
        u(idx:seg_end) = amplitude * sin(2*pi*f*(tt - tt(1)) + phase0);
        class_id(idx:seg_end) = c;

        phase0 = 2*pi*f*(tt(end) - tt(1) + dt) + phase0;
        seg_info = [seg_info; idx, seg_end, f, c]; %#ok<AGROW>
        idx = seg_end + 1;
    end

    Y = class_to_onehot(class_id, n_classes);

    train_opts = struct( ...
        'train_ratio', train_ratio, ...
        'val_ratio', val_ratio, ...
        'washout_steps', washout_steps);
    if isfield(options, 'lambda_grid')
        train_opts.lambda_grid = options.lambda_grid;
    end

    train_info = esn.trainReadout(u, Y, train_opts);
    split = make_split_struct(train_info, washout_steps);

    pred_opts = struct( ...
        'reset_before', true, ...
        'context_U', u(1:split.test_idx(1)-1, :));
    Y_pred_test = esn.predict(u(split.test_idx, :), pred_opts);
    Y_pred_train = predict_segment(esn, u, split.train_idx, washout_steps);
    Y_pred_val = predict_segment(esn, u, split.val_idx, 0);

    train_fit_idx = split.train_idx(washout_steps+1:end);
    y_train = class_id(train_fit_idx);
    y_val = class_id(split.val_idx);
    y_test = class_id(split.test_idx);

    pred_train = scores_to_class(Y_pred_train);
    pred_val = scores_to_class(Y_pred_val);
    pred_test = scores_to_class(Y_pred_test);

    metrics_train = classification_metrics(pred_train, y_train, Y_pred_train, Y(train_fit_idx, :));
    metrics_val = classification_metrics(pred_val, y_val, Y_pred_val, Y(split.val_idx, :));
    metrics_test = classification_metrics(pred_test, y_test, Y_pred_test, Y(split.test_idx, :));

    baselines = classification_baselines(u, class_id, split, washout_steps, ...
        n_classes, summary_window, @frequency_summary_features);

    config = struct( ...
        'T', T, ...
        'dt', dt, ...
        'freq_set', freq_set, ...
        'min_seg', min_seg, ...
        'max_seg', max_seg, ...
        'amplitude', amplitude, ...
        'washout_steps', washout_steps, ...
        'train_ratio', train_ratio, ...
        'val_ratio', val_ratio, ...
        'seed', seed, ...
        'feature_mode', feature_mode, ...
        'summary_window', summary_window, ...
        'n_classes', n_classes);
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
    bench.predictions = struct('train', pred_train, 'val', pred_val, 'test', pred_test, ...
        'train_scores', Y_pred_train, 'val_scores', Y_pred_val, 'test_scores', Y_pred_test);
    bench.targets = struct('train', y_train, 'val', y_val, 'test', y_test);
    bench.y_pred_test = pred_test;
    bench.y_test = y_test;
    bench.baselines = baselines;
    bench.seed = seed;
    bench.u = u;
    bench.class_id = class_id;
    bench.seg_info = seg_info;
    bench.prediction_mode = 'reset_with_context';
    bench.status = 'ok';
    bench.task_type = 'classification';
end

function F = frequency_summary_features(u, t, win)
    i0 = max(1, t - win + 1);
    seg = u(i0:t);
    F = zeros(1, 4);
    F(1) = mean(seg);
    F(2) = std(seg);
    F(3) = mean(abs(seg));
    F(4) = mean(abs(diff(seg > 0))); % zero-crossing rate proxy
end

function baselines = classification_baselines(u, class_id, split, washout_steps, ...
        n_classes, summary_window, feature_fn)
    train_fit_idx = split.train_idx(washout_steps+1:end);
    y_train = class_id(train_fit_idx);
    y_val = class_id(split.val_idx);
    y_test = class_id(split.test_idx);

    % Majority class from train (after washout)
    counts = accumarray(y_train, 1, [n_classes, 1], @sum, 0);
    [~, majority] = max(counts);
    maj_train = majority * ones(size(y_train));
    maj_val = majority * ones(size(y_val));
    maj_test = majority * ones(size(y_test));

    baselines = struct();
    baselines.majority_class = struct( ...
        'class', majority, ...
        'metrics_train', accuracy_only(maj_train, y_train), ...
        'metrics_val', accuracy_only(maj_val, y_val), ...
        'metrics_test', accuracy_only(maj_test, y_test));

    % Linear classifier on input summary features (fit on train only)
    n_feat = numel(feature_fn(u, train_fit_idx(1), summary_window));
    X_all = zeros(numel(u), n_feat);
    for t = 1:numel(u)
        X_all(t, :) = feature_fn(u, t, summary_window);
    end
    X_fit = X_all(train_fit_idx, :);
    Y_fit = class_to_onehot(y_train, n_classes);
    X_design = [X_fit, ones(size(X_fit, 1), 1)];
    n_feat = size(X_fit, 2);
    reg = 1e-8 * eye(n_feat + 1);
    reg(end, end) = 0;
    W = (X_design' * X_design + reg) \ (X_design' * Y_fit);

    scores = [X_all, ones(size(X_all, 1), 1)] * W;
    pred_all = scores_to_class(scores);

    baselines.linear_classifier = struct( ...
        'summary_window', summary_window, ...
        'metrics_train', accuracy_only(pred_all(train_fit_idx), y_train), ...
        'metrics_val', accuracy_only(pred_all(split.val_idx), y_val), ...
        'metrics_test', accuracy_only(pred_all(split.test_idx), y_test));
end

function metrics = classification_metrics(pred, target, scores, onehot)
    metrics = accuracy_only(pred, target);
    if nargin >= 4 && ~isempty(scores) && ~isempty(onehot)
        reg = compute_metrics(scores, onehot);
        metrics.mse = reg.mse;
        metrics.rmse = reg.rmse;
        metrics.nrmse = reg.nrmse;
    end
end

function metrics = accuracy_only(pred, target)
    metrics = struct();
    metrics.accuracy = mean(pred(:) == target(:));
    metrics.n_samples = numel(target);
end

function Y = class_to_onehot(class_id, n_classes)
    Y = zeros(numel(class_id), n_classes);
    for i = 1:numel(class_id)
        Y(i, class_id(i)) = 1;
    end
end

function c = scores_to_class(scores)
    [~, c] = max(scores, [], 2);
    c = c(:);
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
