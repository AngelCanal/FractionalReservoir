function bench = narma_benchmark(esn_or_params, options)
% narma_benchmark
% Evaluate reservoir on NARMA-n benchmark (n=10 or 20).
%
% Usage:
%   bench = narma_benchmark(params, struct('order',10));
%
% When options.shared_baseline_bundle is provided (seed-shared path), task/split
% hashes are verified against the bundle and compact baselines are attached.
% Standalone calls without a shared bundle compute baselines locally with
% provenance executed_cell_local (never publication shared-bundle provenance).

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

    task = build_narma_task_dataset(struct( ...
        'order', order, ...
        'T', T, ...
        'washout_steps', washout_steps, ...
        'train_ratio', train_ratio, ...
        'val_ratio', val_ratio, ...
        'seed', seed, ...
        'u_range', u_range));
    u = task.U;
    y = task.Y;
    expected_split = task.split;

    shared = getFieldOrDefault(options, 'shared_baseline_bundle', []);
    if ~isempty(shared)
        verify_shared_task_identity(shared, 'narma', task, options, esn.W_in);
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
        error('narma_benchmark:SplitMismatch', ...
            'trainReadout split diverged from shared task helper split.');
    end
    if ~strcmp(char(split.split_hash), char(task.split_hash))
        % recompute hash on make_split_struct output if missing
        if ~isfield(split, 'split_hash') || isempty(split.split_hash)
            split.split_hash = task.split_hash;
        end
    end

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

    failure_reasons = {};
    if ~isempty(shared)
        baselines = attach_shared_baselines_for_cell( ...
            shared.narma, metrics_test.nrmse, feature_mode, bb, shared.bundle_id);
        baselines.task_data_hash = task.task_data_hash;
        baselines.split_hash = task.split_hash;
        [ok, vrep] = validate_matched_task_baselines(baselines, 'narma', struct( ...
            'lambda_grid', lambda_grid, ...
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
            'task', 'narma', ...
            'mesn_Win', esn.W_in, ...
            'base_seed', base_seed, ...
            'seed', seed, ...
            'feature_mode', feature_mode, ...
            'lambda_grid', lambda_grid, ...
            'narma_order', order, ...
            'model_test_nrmse', metrics_test.nrmse, ...
            'benchmark_baselines', bb, ...
            'task_data_hash', task.task_data_hash, ...
            'split_hash', task.split_hash);
        baselines = compute_matched_onestep_baselines(u, y, split, washout_steps, baseline_opts);
        baselines.evaluation_provenance = struct( ...
            'mode', 'executed_cell_local', ...
            'publication_shared_bundle', false);
        baselines.bundle_id = '';
        [ok, vrep] = validate_matched_task_baselines(baselines, 'narma', struct( ...
            'lambda_grid', lambda_grid, ...
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
        'order', order, ...
        'T', T, ...
        'washout_steps', washout_steps, ...
        'train_ratio', train_ratio, ...
        'val_ratio', val_ratio, ...
        'seed', seed, ...
        'base_seed', base_seed, ...
        'u_range', u_range, ...
        'feature_mode', feature_mode, ...
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
    bench.baselines = baselines;
    bench.seed = seed;
    bench.base_seed = base_seed;
    bench.order = order;
    bench.u = u;
    bench.y = y;
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
end

function verify_shared_task_identity(shared, task_name, task, options, W_in)
    base_seed = getFieldOrDefault(options, 'base_seed', task.seed);
    cfg = getFieldOrDefault(options, 'cfg', struct());
    if ~isfield(cfg, 'protocol_fingerprint')
        error('narma_benchmark:MissingCfgFingerprint', ...
            'shared baselines require options.cfg.protocol_fingerprint.');
    end
    [ok, report] = validate_seed_matched_baseline_bundle(shared, cfg, base_seed, W_in);
    if ~ok
        error('narma_benchmark:SharedBundleInvalid', ...
            'Shared baseline bundle rejected: %s', strjoin(report.reasons, ','));
    end
    switch task_name
        case 'narma'
            if ~strcmp(char(task.task_data_hash), char(shared.narma_task_data_hash))
                error('narma_benchmark:TaskHashMismatch', ...
                    'Regenerated NARMA task_data_hash differs from shared bundle.');
            end
            if ~strcmp(char(task.split_hash), char(shared.narma_split_hash))
                error('narma_benchmark:SplitHashMismatch', ...
                    'Regenerated NARMA split_hash differs from shared bundle.');
            end
            if task.seed ~= shared.narma_task_seed
                error('narma_benchmark:TaskSeedMismatch', ...
                    'NARMA task seed differs from shared bundle.');
            end
        otherwise
            error('narma_benchmark:BadSharedTask', 'Unexpected task %s', task_name);
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
