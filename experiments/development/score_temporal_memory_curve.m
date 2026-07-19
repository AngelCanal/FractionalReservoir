function result = score_temporal_memory_curve(bundle, Y_test_by_lag, options)
%SCORE_TEMPORAL_MEMORY_CURVE  Score frozen per-lag readouts on test targets.
%
%   result = score_temporal_memory_curve(bundle, Y_test_by_lag)
%   result = score_temporal_memory_curve(bundle, Y_test_by_lag, options)
%
% Uses train/validation-frozen models only. Test targets may differ from the
% protocol vector for isolation tests; only metrics change.

    if nargin < 2
        error('score_temporal_memory_curve:MissingArgs', ...
            'bundle and Y_test_by_lag are required.');
    end
    if nargin < 3 || isempty(options)
        options = struct();
    end
    if ~isstruct(bundle) || ~isfield(bundle, 'per_lag')
        error('score_temporal_memory_curve:InvalidBundle', ...
            'bundle must come from fit_temporal_memory_curve.');
    end
    if ~isfield(bundle, 'X_test') && ~(isfield(options, 'X_test'))
        error('score_temporal_memory_curve:MissingXTest', ...
            'bundle.X_test or options.X_test is required.');
    end
    if isfield(options, 'X_test')
        X_test = options.X_test;
    else
        X_test = bundle.X_test;
    end

    lags = bundle.lags(:);
    n_lags = numel(lags);
    if numel(Y_test_by_lag) ~= n_lags
        error('score_temporal_memory_curve:LagCount', ...
            'Y_test_by_lag must match numel(bundle.lags).');
    end

    blank = struct( ...
        'lag', NaN, ...
        'metrics', struct(), ...
        'selected_lambda', NaN, ...
        'selected_at_grid_boundary', false, ...
        'numerical_rank', NaN, ...
        'coefficient_norm', NaN, ...
        'intercept', NaN, ...
        'coefficients', [], ...
        'feature_mean', [], ...
        'feature_scale', [], ...
        'lambda_selection_table', [], ...
        'y_hat', []);
    per_lag = repmat(blank, n_lags, 1);
    mc = zeros(n_lags, 1);

    for i = 1:n_lags
        row_fit = bundle.per_lag(i);
        Yte = Y_test_by_lag{i}(:);
        if size(X_test, 1) ~= numel(Yte)
            error('score_temporal_memory_curve:RowMismatch', ...
                'Test feature/target rows mismatch at lag %d.', lags(i));
        end
        y_hat = apply_ridge_readout(row_fit.model, X_test);
        metrics = compute_temporal_memory_metrics(y_hat, Yte);

        row = blank;
        row.lag = lags(i);
        row.metrics = metrics;
        row.selected_lambda = row_fit.selected_lambda;
        row.selected_at_grid_boundary = row_fit.selected_at_grid_boundary;
        row.numerical_rank = row_fit.numerical_rank;
        row.coefficient_norm = row_fit.coefficient_norm;
        row.intercept = row_fit.intercept;
        row.coefficients = row_fit.coefficients;
        row.feature_mean = row_fit.feature_mean;
        row.feature_scale = row_fit.feature_scale;
        row.lambda_selection_table = row_fit.lambda_selection_table;
        row.y_hat = y_hat;
        per_lag(i) = row;
        mc(i) = metrics.memory_coefficient;
    end

    metrics_only = [per_lag.metrics];
    summary = summarize_temporal_memory_curve(lags, mc, metrics_only);

    result = struct();
    result.lags = lags;
    result.per_lag = per_lag;
    result.summary = summary;
    result.n_lags = n_lags;
    result.memory_coefficients = mc;
    result.fit_identity = pack_fit_identity(bundle);
end

function id = pack_fit_identity(bundle)
    n = numel(bundle.per_lag);
    id = repmat(struct( ...
        'lag', NaN, ...
        'selected_lambda', NaN, ...
        'coefficients', [], ...
        'intercept', NaN, ...
        'feature_mean', [], ...
        'feature_scale', [], ...
        'numerical_rank', NaN, ...
        'lambda_selection_table', []), n, 1);
    for i = 1:n
        r = bundle.per_lag(i);
        id(i).lag = r.lag;
        id(i).selected_lambda = r.selected_lambda;
        id(i).coefficients = r.coefficients;
        id(i).intercept = r.intercept;
        id(i).feature_mean = r.feature_mean;
        id(i).feature_scale = r.feature_scale;
        id(i).numerical_rank = r.numerical_rank;
        id(i).lambda_selection_table = r.lambda_selection_table;
    end
end
