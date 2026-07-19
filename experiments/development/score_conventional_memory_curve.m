function scored = score_conventional_memory_curve(bundle, Yte)
%SCORE_CONVENTIONAL_MEMORY_CURVE  Score frozen conventional curve on test targets.
%
%   scored = score_conventional_memory_curve(bundle, Yte)
%
% Only test metrics change when Yte changes. Reservoir candidate, lambdas,
% coefficients, intercepts, normalization, and selection tables stay fixed.

    if ~isstruct(bundle) || ~isfield(bundle, 'per_lag')
        error('score_conventional_memory_curve:InvalidBundle', ...
            'bundle must come from fit_conventional_memory_curve.');
    end
    n_lags = numel(bundle.lags);
    if numel(Yte) ~= n_lags
        error('score_conventional_memory_curve:LagCount', ...
            'Yte must match numel(bundle.lags).');
    end
    per_lag = bundle.per_lag;
    mc = zeros(n_lags, 1);
    for li = 1:n_lags
        y_hat = apply_ridge_readout(per_lag(li).model, bundle.X_test);
        metrics = compute_temporal_memory_metrics(y_hat, Yte{li});
        per_lag(li).metrics = metrics;
        per_lag(li).y_hat = y_hat;
        mc(li) = metrics.memory_coefficient;
    end
    scored = bundle;
    scored.status = 'computed';
    scored.per_lag = per_lag;
    scored.summary = summarize_temporal_memory_curve(bundle.lags, mc, [per_lag.metrics]);
    scored.memory_coefficients = mc;

    n = n_lags;
    id = struct();
    id.selected_candidate_index = bundle.selected_candidate_index;
    id.selected_hyperparameters = bundle.selected_hyperparameters;
    id.selected_candidate_content_hash = bundle.selected_candidate_content_hash;
    id.Wres = bundle.Wres;
    id.Win = bundle.Win;
    id.candidate_selection_table = bundle.candidate_selection_table;
    id.aggregate_validation_nrmse = bundle.aggregate_validation_nrmse;
    id.per_lag_lambda = zeros(n, 1);
    id.per_lag_coefficients = cell(n, 1);
    id.per_lag_intercept = cell(n, 1);
    id.per_lag_feature_mean = cell(n, 1);
    id.per_lag_feature_scale = cell(n, 1);
    for i = 1:n
        id.per_lag_lambda(i) = bundle.per_lag(i).selected_lambda;
        id.per_lag_coefficients{i} = bundle.per_lag(i).coefficients;
        id.per_lag_intercept{i} = bundle.per_lag(i).intercept;
        id.per_lag_feature_mean{i} = bundle.per_lag(i).feature_mean;
        id.per_lag_feature_scale{i} = bundle.per_lag(i).feature_scale;
    end
    scored.fit_identity = id;
end
