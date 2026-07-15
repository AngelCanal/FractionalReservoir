function result = fit_phase4a_lag_baseline(U, Y, split, washout_steps, n_lags, lambda_grid, meta)
% FIT_PHASE4A_LAG_BASELINE  Causal lag-feature ridge baseline via Phase 4A.
%
%   result = fit_phase4a_lag_baseline(U, Y, split, washout_steps, n_lags, lambda_grid, meta)
%
% Builds independent train/validation/test design matrices from current and past
% inputs only (no future leakage). Fits with select_ridge_lambda / fit_ridge_readout.

    if nargin < 7 || isempty(meta)
        meta = struct();
    end
    name = local_get(meta, 'name', 'linear_lag_baseline');
    model_family = local_get(meta, 'model_family', name);

    train_idx = split.train_idx(washout_steps+1:end);
    val_idx = split.val_idx(:);
    test_idx = split.test_idx(:);

    [Xtr, Ytr, n_tr] = lag_design(U, Y, train_idx, n_lags);
    [Xva, Yva, n_va] = lag_design(U, Y, val_idx, n_lags);
    [Xte, Yte, n_te] = lag_design(U, Y, test_idx, n_lags);

    result = struct();
    result.name = name;
    result.role = 'matched_task_baseline';
    result.protocol_version = 'matched_task_baselines_v1';
    result.model_family = model_family;
    result.feature_dimension = n_lags;
    result.include_input = false;
    result.hyperparameters = struct('n_lags', n_lags, 'history_length', n_lags);
    result.provenance = struct( ...
        'lambda_grid', lambda_grid(:), ...
        'feature_definition', 'u(t),u(t-1),...,u(t-n_lags+1)', ...
        'readout_solver', 'phase4a_economy_svd', ...
        'selection_scope', 'train_validation_only');

    if n_tr < 2 || n_va < 2 || n_te < 1
        result.status = 'failed';
        result.train_rows = n_tr;
        result.validation_rows = n_va;
        result.test_rows = n_te;
        result.metrics = struct('train', struct('nrmse', NaN), ...
            'validation', struct('nrmse', NaN), 'test', struct('nrmse', NaN));
        result.metrics_train = result.metrics.train;
        result.metrics_val = result.metrics.validation;
        result.metrics_test = result.metrics.test;
        result.selected_lambda = NaN;
        result.ridge_diagnostics = struct();
        result.lambda_selection_table = [];
        return;
    end

    sel = select_ridge_lambda(Xtr, Ytr, Xva, Yva, lambda_grid);
    yhat_tr = apply_ridge_readout(sel.selected_model, Xtr);
    yhat_va = apply_ridge_readout(sel.selected_model, Xva);
    yhat_te = apply_ridge_readout(sel.selected_model, Xte);
    m_tr = compute_metrics(yhat_tr, Ytr);
    m_va = compute_metrics(yhat_va, Yva);
    m_te = compute_metrics(yhat_te, Yte);

    result.status = 'computed';
    result.train_rows = n_tr;
    result.validation_rows = n_va;
    result.test_rows = n_te;
    result.metrics = struct('train', m_tr, 'validation', m_va, 'test', m_te);
    result.metrics_train = m_tr;
    result.metrics_val = m_va;
    result.metrics_test = m_te;
    result.selected_lambda = sel.selected_lambda;
    result.ridge_diagnostics = extract_ridge_diag(sel.selected_model);
    result.lambda_selection_table = compact_lambda_table(sel);
    result.n_lags = n_lags;
end

function [X, Yout, n_used] = lag_design(U, Y, idx, n_lags)
    idx = idx(:);
    keep = idx(idx >= n_lags);
    n_used = numel(keep);
    X = zeros(n_used, n_lags);
    Yout = zeros(n_used, size(Y, 2));
    for i = 1:n_used
        t = keep(i);
        X(i, :) = U(t:-1:(t - n_lags + 1), 1)';
        Yout(i, :) = Y(t, :);
    end
end

function d = extract_ridge_diag(model)
    d = struct();
    d.solver_method = local_field(model, 'solver_method', '');
    d.lambda = model.lambda;
    d.numerical_rank = local_field(model, 'numerical_rank', NaN);
    d.coefficient_norm = local_field(model, 'coefficient_norm', NaN);
    d.conditioning_status = local_field(model, 'conditioning_status', '');
    d.feature_mean = local_field(model, 'feature_mean', model.mu);
    d.feature_scale = local_field(model, 'feature_scale', model.sigma);
    d.intercept = model.intercept;
    d.coefficients = model.coefficients;
    d.n_features = model.n_features;
end

function rows = compact_lambda_table(selection)
    src = selection.table;
    n = numel(src);
    rows = repmat(struct( ...
        'candidate_lambda', NaN, ...
        'validation_nrmse', NaN, ...
        'status', 'rejected', ...
        'numerical_rank', NaN, ...
        'coefficient_norm', NaN, ...
        'selected_candidate', false), n, 1);
    for i = 1:n
        rows(i).candidate_lambda = src(i).lambda;
        rows(i).validation_nrmse = src(i).val_score;
        if logical(src(i).accepted)
            rows(i).status = 'accepted';
        else
            rows(i).status = 'rejected';
        end
        rows(i).numerical_rank = src(i).numerical_rank;
        rows(i).coefficient_norm = src(i).coefficient_norm;
        rows(i).selected_candidate = logical(src(i).accepted) && ...
            src(i).lambda == selection.selected_lambda;
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end

function v = local_field(s, name, default)
    v = local_get(s, name, default);
end
