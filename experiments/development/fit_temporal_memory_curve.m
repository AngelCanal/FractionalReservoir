function bundle = fit_temporal_memory_curve(X_train, X_val, Y_train_by_lag, Y_val_by_lag, lags, lambda_grid, options)
%FIT_TEMPORAL_MEMORY_CURVE  Per-lag lambda selection + train+val refit (no test).
%
%   bundle = fit_temporal_memory_curve(X_train, X_val, Y_train_by_lag, ...
%       Y_val_by_lag, lags, lambda_grid)
%   bundle = fit_temporal_memory_curve(..., options)
%
% For each lag k:
%   1. select_ridge_lambda on train/validation only
%   2. refit_ridge on [train; validation] at selected lambda
%
% Test features/targets must not be passed. Optional options.X_test stores
% frozen test features for later scoring without refitting.

    if nargin < 6
        error('fit_temporal_memory_curve:MissingArgs', ...
            'X_train, X_val, Y_*_by_lag, lags, and lambda_grid are required.');
    end
    if nargin < 7 || isempty(options)
        options = struct();
    end
    lags = lags(:);
    lambda_grid = lambda_grid(:);
    n_lags = numel(lags);
    if numel(Y_train_by_lag) ~= n_lags || numel(Y_val_by_lag) ~= n_lags
        error('fit_temporal_memory_curve:LagCount', ...
            'Target cell arrays must match numel(lags).');
    end
    if isfield(options, 'Y_test_by_lag') || isfield(options, 'Y_test')
        error('fit_temporal_memory_curve:TestTargetForbidden', ...
            'Test targets must not be supplied to fitting.');
    end

    blank = struct( ...
        'lag', NaN, ...
        'selected_lambda', NaN, ...
        'selected_val_score', NaN, ...
        'selected_at_grid_boundary', false, ...
        'model', struct(), ...
        'selection', struct(), ...
        'lambda_selection_table', [], ...
        'numerical_rank', NaN, ...
        'coefficient_norm', NaN, ...
        'intercept', NaN, ...
        'coefficients', [], ...
        'feature_mean', [], ...
        'feature_scale', []);
    per_lag = repmat(blank, n_lags, 1);

    for i = 1:n_lags
        Ytr = Y_train_by_lag{i}(:);
        Yva = Y_val_by_lag{i}(:);
        if size(X_train, 1) ~= numel(Ytr) || size(X_val, 1) ~= numel(Yva)
            error('fit_temporal_memory_curve:RowMismatch', ...
                'Feature/target rows mismatch at lag %d.', lags(i));
        end
        sel = select_ridge_lambda(X_train, Ytr, X_val, Yva, lambda_grid);
        lam = sel.selected_lambda;
        model = fit_ridge_readout( ...
            [X_train; X_val], [Ytr; Yva], lam);

        row = blank;
        row.lag = lags(i);
        row.selected_lambda = lam;
        row.selected_val_score = sel.selected_val_score;
        grid = lambda_grid(:);
        row.selected_at_grid_boundary = isfinite(lam) && ...
            (lam == min(grid) || lam == max(grid));
        row.model = model;
        row.selection = sel;
        row.lambda_selection_table = compact_lambda_selection_table(sel);
        row.numerical_rank = model.numerical_rank;
        row.coefficient_norm = model.coefficient_norm;
        row.intercept = model.intercept;
        row.coefficients = model.coefficients;
        row.feature_mean = model.feature_mean;
        row.feature_scale = model.feature_scale;
        per_lag(i) = row;
    end

    bundle = struct();
    bundle.lags = lags;
    bundle.lambda_grid = lambda_grid;
    bundle.per_lag = per_lag;
    bundle.feature_dimension = size(X_train, 2);
    bundle.train_samples = size(X_train, 1);
    bundle.validation_samples = size(X_val, 1);
    bundle.n_reservoir_simulations_assumed = local_get(options, ...
        'n_reservoir_simulations', 1);
    bundle.fit_uses_test_targets = false;
    if isfield(options, 'X_test') && ~isempty(options.X_test)
        bundle.X_test = options.X_test;
    end
    if isfield(options, 'meta')
        bundle.meta = options.meta;
    end
end

function rows = compact_lambda_selection_table(selection)
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
        if isfinite(src(i).val_score)
            rows(i).validation_nrmse = src(i).val_score;
        elseif ~isempty(src(i).val_nrmse)
            rows(i).validation_nrmse = mean(src(i).val_nrmse);
        else
            rows(i).validation_nrmse = NaN;
        end
        if logical(src(i).accepted)
            rows(i).status = 'accepted';
        else
            rows(i).status = 'rejected';
        end
        rows(i).numerical_rank = src(i).numerical_rank;
        rows(i).coefficient_norm = src(i).coefficient_norm;
        rows(i).selected_candidate = logical(src(i).accepted) && ...
            isfinite(src(i).lambda) && isfinite(selection.selected_lambda) && ...
            src(i).lambda == selection.selected_lambda;
    end
end

function v = local_get(S, name, default)
    if isstruct(S) && isfield(S, name) && ~isempty(S.(name))
        v = S.(name);
    else
        v = default;
    end
end
