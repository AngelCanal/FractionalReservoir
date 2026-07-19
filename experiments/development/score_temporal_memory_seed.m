function result = score_temporal_memory_seed(bundle, Y_test_by_lag, options)
%SCORE_TEMPORAL_MEMORY_SEED  Score a frozen temporal-memory fit bundle.
%
%   result = score_temporal_memory_seed(bundle, Y_test_by_lag)
%   result = score_temporal_memory_seed(bundle, Y_test_by_lag, options)
%
% Test targets may be replaced for isolation tests. Lambda, coefficients,
% intercept, normalization, numerical rank, and selection tables stay fixed.

    if nargin < 3 || isempty(options)
        options = struct();
    end
    if ~isstruct(bundle) || ~isfield(bundle, 'curve')
        error('score_temporal_memory_seed:InvalidBundle', ...
            'bundle must come from fit_temporal_memory_seed.');
    end

    scored = score_temporal_memory_curve(bundle.curve, Y_test_by_lag, ...
        struct('X_test', bundle.X_test));

    result = struct();
    result.model_seed = bundle.model_seed;
    result.cell_name = bundle.cell_name;
    result.cell_key = bundle.cell_key;
    result.lags = bundle.lags;
    result.per_lag = scored.per_lag;
    result.summary = scored.summary;
    result.memory_coefficients = scored.memory_coefficients;
    result.feature_diagnostics = bundle.feature_diagnostics;
    result.feature_dimension = bundle.feature_dimension;
    result.feature_mode = bundle.feature_mode;
    result.include_input = false;
    result.n_reservoir_simulations = bundle.n_reservoir_simulations;
    result.simulations_per_split = bundle.simulations_per_split;
    result.fit_identity = scored.fit_identity;
    result.n_lags = scored.n_lags;

    if isfield(options, 'include_controls') && logical(options.include_controls)
        payload = struct();
        payload.splits = bundle.splits;
        payload.lags = bundle.lags;
        payload.lambda_grid = bundle.lambda_grid;
        payload.mesn_features = bundle.mesn_features;
        payload.Y_train = bundle.Y_train;
        payload.Y_val = bundle.Y_val;
        payload.Y_test = Y_test_by_lag;
        payload.esn = bundle.esn;
        payload.cell_name = bundle.cell_name;
        payload.mesn_Win = bundle.W_in;
        payload.model_seed = bundle.model_seed;
        payload.W_original = bundle.W;
        payload.W_original_copy = bundle.W;
        cfg = local_get(options, 'cfg', struct());
        result.controls = compute_temporal_memory_controls(payload, cfg, options);
    end
end

function v = local_get(S, name, default)
    if isstruct(S) && isfield(S, name) && ~isempty(S.(name))
        v = S.(name);
    else
        v = default;
    end
end
