function baselines = compute_matched_onestep_baselines(U, Y, split, washout_steps, opts)
% COMPUTE_MATCHED_ONESTEP_BASELINES  Canonical NARMA/MG one-step baselines.
%
%   baselines = compute_matched_onestep_baselines(U, Y, split, washout_steps, opts)
%
% opts.task = 'narma' | 'mackey_glass_onestep'
% opts.mesn_Win, opts.base_seed, opts.feature_mode, opts.lambda_grid
% opts.narma_order | opts.ar_lags
% opts.model_test_nrmse
% opts.benchmark_baselines (config struct)

    if nargin < 5 || isempty(opts)
        opts = struct();
    end
    task = char(local_get(opts, 'task', 'narma'));
    bb = local_get(opts, 'benchmark_baselines', struct());
    if isempty(fieldnames(bb))
        bb = build_matched_task_baselines_config(struct('base', struct('n', size(opts.mesn_Win, 1))));
    end
    lambda_grid = local_get(opts, 'lambda_grid', [0; logspace(-12, 2, 15)']);
    lambda_grid = lambda_grid(:);
    model_nrmse = local_get(opts, 'model_test_nrmse', NaN);
    feature_mode = char(local_get(opts, 'feature_mode', 'x'));
    mesn_Win = local_get(opts, 'mesn_Win', []);
    base_seed = local_get(opts, 'base_seed', local_get(opts, 'seed', 1));

    train_idx = split.train_idx(washout_steps+1:end);
    y_train = Y(train_idx, :);
    y_val = Y(split.val_idx, :);
    y_test = Y(split.test_idx, :);

    baselines = struct();

    switch task
        case 'narma'
            % 1) Training-target mean
            mu = mean(y_train, 1);
            pred_tr = repmat(mu, size(y_train, 1), 1);
            pred_va = repmat(mu, size(y_val, 1), 1);
            pred_te = repmat(mu, size(y_test, 1), 1);
            tm = pack_simple_baseline('training_target_mean', 'training_target_mean', ...
                compute_metrics(pred_tr, y_train), ...
                compute_metrics(pred_va, y_val), ...
                compute_metrics(pred_te, y_test), ...
                numel(train_idx), numel(split.val_idx), numel(split.test_idx));
            tm.hyperparameters = struct('mean', mu);
            tm.provenance = struct('estimated_from', 'train_targets_only', ...
                'lambda_grid', lambda_grid(:));
            tm.selected_lambda = NaN;
            tm.ridge_diagnostics = struct();
            tm.lambda_selection_table = [];
            tm.comparison = baseline_model_comparison(model_nrmse, tm.metrics_test.nrmse);
            baselines.training_target_mean = tm;
            baselines.target_mean = tm; % backward-compatible alias

            % 2) Linear input history
            n_lags = local_get(opts, 'narma_order', 10);
            lin = fit_phase4a_lag_baseline(U, Y, split, washout_steps, n_lags, ...
                lambda_grid, struct('name', 'linear_input_history', ...
                'model_family', 'linear_input_history'));
            lin.comparison = baseline_model_comparison(model_nrmse, ...
                local_nrmse(lin));
            baselines.linear_input_history = lin;
            baselines.linear_input_ar = lin; % backward-compatible alias

        case 'mackey_glass_onestep'
            % 1) Persistence y_hat(t)=u(t)
            pers = pack_simple_baseline('persistence', 'persistence', ...
                compute_metrics(U(train_idx), y_train), ...
                compute_metrics(U(split.val_idx), y_val), ...
                compute_metrics(U(split.test_idx), y_test), ...
                numel(train_idx), numel(split.val_idx), numel(split.test_idx));
            pers.hyperparameters = struct();
            pers.provenance = struct('rule', 'y_hat(t)=u(t)', ...
                'lambda_grid', lambda_grid(:));
            pers.selected_lambda = NaN;
            pers.ridge_diagnostics = struct();
            pers.lambda_selection_table = [];
            pers.comparison = baseline_model_comparison(model_nrmse, pers.metrics_test.nrmse);
            baselines.persistence = pers;

            % 2) Linear autoregression
            ar_lags = local_get(opts, 'ar_lags', 10);
            lar = fit_phase4a_lag_baseline(U, Y, split, washout_steps, ar_lags, ...
                lambda_grid, struct('name', 'linear_autoregression', ...
                'model_family', 'linear_autoregression'));
            lar.comparison = baseline_model_comparison(model_nrmse, local_nrmse(lar));
            baselines.linear_autoregression = lar;
            baselines.linear_ar = lar; % backward-compatible alias

        otherwise
            error('compute_matched_onestep_baselines:BadTask', 'Unknown task %s', task);
    end

    % 3) Conventional leaky ESN
    if isempty(mesn_Win)
        error('compute_matched_onestep_baselines:MissingWin', ...
            'opts.mesn_Win is required for conventional ESN baseline.');
    end
    ce_opts = struct( ...
        'conventional_config', bb.conventional_leaky_esn, ...
        'lambda_grid', lambda_grid, ...
        'base_seed', base_seed, ...
        'validation_tie_tolerance', bb.validation_tie_tolerance);
    conv = select_conventional_leaky_esn(U, Y, split, washout_steps, mesn_Win, ce_opts);
    conv.comparison = baseline_model_comparison(model_nrmse, local_nrmse(conv));
    baselines.conventional_leaky_esn = conv;

    % 4) Dale-only MESN paired-cell reference (not computed here)
    dale_key = dale_mesn_control_reference_key(feature_mode, bb.dale_mesn_control_keys);
    dale = struct();
    dale.name = 'dale_mesn_control';
    dale.status = 'pending_paired_aggregation';
    dale.role = 'paired_cell_reference';
    dale.protocol_version = 'matched_task_baselines_v1';
    dale.model_family = 'dale_mesn_control';
    dale.feature_dimension = NaN;
    dale.include_input = false;
    dale.train_rows = NaN;
    dale.validation_rows = NaN;
    dale.test_rows = NaN;
    dale.metrics = struct();
    dale.selected_lambda = NaN;
    dale.ridge_diagnostics = struct();
    dale.lambda_selection_table = [];
    dale.hyperparameters = struct();
    dale.provenance = struct( ...
        'dale_mesn_control_reference', dale_key, ...
        'note', 'Metric resolved from paired cell table in aggregation phase.', ...
        'not_conventional_esn', true);
    dale.dale_mesn_control_reference = dale_key;
    dale.comparison = struct( ...
        'status', 'pending_paired_aggregation', ...
        'dale_mesn_control_reference', dale_key);
    baselines.dale_mesn_control = dale;

    baselines.protocol_version = 'matched_task_baselines_v1';
    baselines.resolved_lambda_grid = lambda_grid(:);
    baselines.model_test_nrmse = model_nrmse;
end

function b = pack_simple_baseline(name, family, m_tr, m_va, m_te, n_tr, n_va, n_te)
    b = struct();
    b.name = name;
    b.status = 'computed';
    b.role = 'matched_task_baseline';
    b.protocol_version = 'matched_task_baselines_v1';
    b.model_family = family;
    b.feature_dimension = 0;
    b.include_input = false;
    b.train_rows = n_tr;
    b.validation_rows = n_va;
    b.test_rows = n_te;
    b.metrics = struct('train', m_tr, 'validation', m_va, 'test', m_te);
    b.metrics_train = m_tr;
    b.metrics_val = m_va;
    b.metrics_test = m_te;
end

function nrmse = local_nrmse(b)
    if isfield(b, 'metrics_test') && isfield(b.metrics_test, 'nrmse')
        nrmse = b.metrics_test.nrmse;
    elseif isfield(b, 'metrics') && isfield(b.metrics, 'test') && ...
            isfield(b.metrics.test, 'nrmse')
        nrmse = b.metrics.test.nrmse;
    else
        nrmse = NaN;
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
