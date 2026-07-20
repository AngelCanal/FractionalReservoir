function hex = temporal_memory_conventional_bundle_content_hash(b)
%TEMPORAL_MEMORY_CONVENTIONAL_BUNDLE_CONTENT_HASH  Canonical conventional hash.
%
%   hex = temporal_memory_conventional_bundle_content_hash(b)
%
% Single source of truth for writing, resume, and independent validation.

    if nargin < 1 || ~isstruct(b)
        error('temporal_memory_conventional_bundle_content_hash:Invalid', ...
            'bundle must be a struct.');
    end
    hex = canonical_sha256(conventional_hash_payload(b));
end

function payload = conventional_hash_payload(b)
    payload = struct();
    payload.name = char(string(local_get(b, 'name', '')));
    payload.status = char(string(local_get(b, 'status', '')));
    payload.model_seed = local_get(b, 'model_seed', NaN);
    payload.protocol_version = char(string(local_get(b, 'protocol_version', '')));
    payload.engine = char(string(local_get(b, 'engine', '')));
    payload.candidate_grid_source = char(string(local_get(b, ...
        'candidate_grid_source', '')));
    payload.candidate_count = local_get(b, 'n_candidates', ...
        local_get(b, 'candidate_count', NaN));
    payload.n_reservoir_simulations = local_get(b, 'n_reservoir_simulations', NaN);
    payload.reusable_across_cells = logical(local_get(b, ...
        'reusable_across_cells', local_get(b, 'reused_shared_baseline', false)));
    payload.reservoir_seed = local_get(b, 'reservoir_seed', NaN);
    payload.lambda_grid = local_get(b, 'lambda_grid', [])';
    payload.selection_metric = char(string(local_get(b, 'selection_metric', '')));
    payload.selection_lags = local_get(b, 'selection_lags', [])';
    payload.tie_tolerance = local_get(b, 'tie_tolerance', NaN);
    payload.tie_break_rule = char(string(local_get(b, 'tie_break', ...
        local_get(b, 'tie_break_rule', ''))));
    payload.execution_scope = char(string(local_get(b, 'execution_scope', '')));
    payload.selected_candidate_index = local_get(b, 'selected_candidate_index', NaN);
    payload.selected_hyperparameters = local_get(b, 'selected_hyperparameters', struct());
    payload.Wres_content_hash = array_hash(local_get(b, 'Wres', []));
    payload.Win_content_hash = array_hash(local_get(b, 'Win', []));
    payload.X_test_content_hash = array_hash(local_get(b, 'X_test', []));
    payload.candidate_selection_table = local_get(b, 'candidate_selection_table', []);
    payload.aggregate_validation_scores = local_get(b, ...
        'aggregate_validation_nrmse', []);
    payload.per_candidate_per_lag_validation_scores = local_get(b, ...
        'per_candidate_per_lag_validation_nrmse', []);
    payload.selected_candidate_content_hash = char(string(local_get(b, ...
        'selected_candidate_content_hash', '')));
    payload.same_reservoir_for_all_lags = logical(local_get(b, ...
        'same_reservoir_for_all_lags', false));
    payload.test_targets_used_for_selection = logical(local_get(b, ...
        'test_targets_used_for_selection', false));
    payload.test_targets_used_for_fitting = logical(local_get(b, ...
        'test_targets_used_for_fitting', false));
    payload.used_narma_orchestrator = logical(local_get(b, ...
        'used_narma_orchestrator', false));
    payload.used_mackey_glass_orchestrator = logical(local_get(b, ...
        'used_mackey_glass_orchestrator', false));
    payload.provenance = char(string(local_get(b, 'provenance', '')));
    payload.is_test_fixture = logical(local_get(b, 'is_test_fixture', false));
    payload.synthetic_provenance = logical(local_get(b, 'synthetic_provenance', false));
    payload.lags = local_get(b, 'lags', [])';
    payload.memory_coefficients = local_get(b, 'memory_coefficients', [])';

    per_lag = local_get(b, 'per_lag', []);
    n = numel(per_lag);
    lag_rows = repmat(empty_lag_row(), max(n, 1), 1);
    if n == 0
        lag_rows = lag_rows([]);
    else
        for i = 1:n
            pl = per_lag(i);
            m = local_get(pl, 'metrics', struct());
            lag_rows(i).lag = local_get(pl, 'lag', NaN);
            lag_rows(i).candidate_index = local_get(pl, 'selected_candidate_index', NaN);
            lag_rows(i).hyperparameters = local_get(pl, 'hyperparameters', struct());
            lag_rows(i).lambda = local_get(pl, 'selected_lambda', NaN);
            lag_rows(i).grid_boundary_flag = logical(local_get(pl, ...
                'selected_at_grid_boundary', local_get(pl, 'grid_boundary_flag', false)));
            lag_rows(i).numerical_rank = local_get(pl, 'numerical_rank', NaN);
            lag_rows(i).coefficient_norm = local_get(pl, 'coefficient_norm', NaN);
            lag_rows(i).model_coefficients_hash = array_hash(local_get(pl, ...
                'coefficients', []));
            lag_rows(i).intercept = local_get(pl, 'intercept', NaN);
            lag_rows(i).feature_mean_hash = array_hash(local_get(pl, 'feature_mean', []));
            lag_rows(i).feature_scale_hash = array_hash(local_get(pl, 'feature_scale', []));
            lag_rows(i).lambda_selection_table_hash = content_hash_if_present(pl, ...
                'lambda_selection_table');
            lag_rows(i).rmse = local_get(m, 'rmse', NaN);
            lag_rows(i).nrmse = local_get(m, 'nrmse', NaN);
            lag_rows(i).r2 = local_get(m, 'r2', NaN);
            lag_rows(i).pearson = local_get(m, 'pearson', NaN);
            lag_rows(i).memory_coefficient = local_get(m, 'memory_coefficient', NaN);
            lag_rows(i).constant_prediction = logical(local_get(m, ...
                'constant_prediction', false));
            if isfield(pl, 'y_hat') && ~isempty(pl.y_hat)
                lag_rows(i).prediction_hash = canonical_sha256(pl.y_hat);
            elseif isfield(pl, 'predictions') && ~isempty(pl.predictions)
                lag_rows(i).prediction_hash = canonical_sha256(pl.predictions);
            else
                lag_rows(i).prediction_hash = '';
            end
        end
    end
    payload.per_lag = lag_rows;

    s = local_get(b, 'summary', struct());
    payload.summary = struct( ...
        'MC_1_10', local_get(s, 'MC_1_10', local_get(s, 'memory_capacity_sum_lags_1_10', NaN)), ...
        'MC_1_25', local_get(s, 'MC_1_25', local_get(s, 'memory_capacity_sum_lags_1_25', NaN)), ...
        'MC_1_50', local_get(s, 'MC_1_50', local_get(s, 'memory_capacity_sum_lags_1_50', NaN)), ...
        'maximum_memory_lag', local_get(s, 'maximum_memory_lag', ...
            local_get(s, 'lag_of_maximum_memory_coefficient', NaN)), ...
        'maximum_memory_coefficient', local_get(s, 'maximum_memory_coefficient', NaN), ...
        'first_crossing_below_0_1', local_get(s, 'first_lag_memory_below_0_1', NaN), ...
        'right_censoring_flag', logical(local_get(s, ...
            'memory_crossing_right_censored_at_50', false)), ...
        'lag10_nrmse', local_get(s, 'lag10_nrmse', NaN), ...
        'lag10_r2', local_get(s, 'lag10_r2', NaN), ...
        'lag10_rmse', local_get(s, 'lag10_rmse', NaN), ...
        'lag10_pearson', local_get(s, 'lag10_pearson', NaN), ...
        'lag10_memory_coefficient', local_get(s, 'lag10_memory_coefficient', NaN));
end

function row = empty_lag_row()
    row = struct( ...
        'lag', NaN, ...
        'candidate_index', NaN, ...
        'hyperparameters', struct(), ...
        'lambda', NaN, ...
        'grid_boundary_flag', false, ...
        'numerical_rank', NaN, ...
        'coefficient_norm', NaN, ...
        'model_coefficients_hash', '', ...
        'intercept', NaN, ...
        'feature_mean_hash', '', ...
        'feature_scale_hash', '', ...
        'lambda_selection_table_hash', '', ...
        'rmse', NaN, ...
        'nrmse', NaN, ...
        'r2', NaN, ...
        'pearson', NaN, ...
        'memory_coefficient', NaN, ...
        'constant_prediction', false, ...
        'prediction_hash', '');
end

function hex = array_hash(v)
    if isempty(v)
        hex = '';
    else
        hex = canonical_sha256(v);
    end
end

function hex = content_hash_if_present(s, field)
    if isfield(s, field) && ~isempty(s.(field))
        hex = canonical_sha256(s.(field));
    else
        hex = '';
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
