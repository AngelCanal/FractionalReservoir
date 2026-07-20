function hex = temporal_memory_control_content_hash(ctrl, identity)
%TEMPORAL_MEMORY_CONTROL_CONTENT_HASH  Canonical shared/reference control hash.
%
%   hex = temporal_memory_control_content_hash(ctrl)
%   hex = temporal_memory_control_content_hash(ctrl, identity)
%
% identity (optional struct) may include:
%   control_name, execution_scope, model_seed, shared_task_identity,
%   and other control-specific identity fields.

    if nargin < 1 || ~isstruct(ctrl)
        error('temporal_memory_control_content_hash:Invalid', ...
            'ctrl must be a struct.');
    end
    if nargin < 2 || isempty(identity)
        identity = struct();
    end
    hex = canonical_sha256(control_hash_payload(ctrl, identity));
end

function payload = control_hash_payload(ctrl, identity)
    payload = struct();
    payload.control_name = char(string(local_get(identity, 'control_name', ...
        local_get(ctrl, 'name', ''))));
    payload.execution_scope = char(string(local_get(identity, 'execution_scope', ...
        local_get(ctrl, 'execution_scope', ''))));
    payload.model_seed = local_get(identity, 'model_seed', ...
        local_get(ctrl, 'model_seed', NaN));
    payload.shared_task_identity = char(string(local_get(identity, ...
        'shared_task_identity', '')));
    payload.status = char(string(local_get(ctrl, 'status', '')));
    payload.provenance = char(string(local_get(ctrl, 'provenance', ...
        local_get(identity, 'provenance', ''))));
    payload.is_test_fixture = logical(local_get(ctrl, 'is_test_fixture', false));
    payload.synthetic_provenance = logical(local_get(ctrl, 'synthetic_provenance', false));
    payload.lambda_grid = local_get(ctrl, 'lambda_grid', ...
        local_get(identity, 'lambda_grid', []))';
    payload.fit_identity = local_get(ctrl, 'fit_identity', ...
        local_get(identity, 'fit_identity', struct()));

    if isfield(ctrl, 'exact_history_design')
        payload.exact_history_design = ctrl.exact_history_design;
    end
    if isfield(ctrl, 'max_lag')
        payload.max_lag = ctrl.max_lag;
    end
    if isfield(ctrl, 'column_recovers_target')
        payload.column_recovers_target = ctrl.column_recovers_target;
    end
    if isfield(ctrl, 'shuffle_seed')
        payload.shuffle_seed = ctrl.shuffle_seed;
    end
    if isfield(ctrl, 'shuffle_applied_cell')
        payload.shuffle_applied_cell = char(string(ctrl.shuffle_applied_cell));
    end
    if isfield(ctrl, 'W_is_exact_zero')
        payload.W_is_exact_zero = logical(ctrl.W_is_exact_zero);
    end
    if isfield(ctrl, 'original_W_unchanged')
        payload.original_W_unchanged = logical(ctrl.original_W_unchanged);
    end

    if isfield(ctrl, 'per_lag')
        per_lag = ctrl.per_lag;
    elseif isfield(ctrl, 'scored') && isfield(ctrl.scored, 'per_lag')
        per_lag = ctrl.scored.per_lag;
    else
        per_lag = [];
    end

    n = numel(per_lag);
    lag_rows = repmat(struct( ...
        'lag', NaN, ...
        'rmse', NaN, ...
        'nrmse', NaN, ...
        'r2', NaN, ...
        'pearson', NaN, ...
        'memory_coefficient', NaN, ...
        'constant_prediction', false, ...
        'selected_lambda', NaN, ...
        'grid_boundary_flag', false, ...
        'numerical_rank', NaN, ...
        'coefficient_norm', NaN, ...
        'intercept', NaN, ...
        'feature_mean_hash', '', ...
        'feature_scale_hash', '', ...
        'lambda_selection_table_hash', '', ...
        'model_readout_hash', '', ...
        'prediction_hash', ''), max(n, 1), 1);
    if n == 0
        lag_rows = lag_rows([]);
    else
        for i = 1:n
            pl = per_lag(i);
            m = local_get(pl, 'metrics', struct());
            lag_rows(i).lag = local_get(pl, 'lag', NaN);
            lag_rows(i).rmse = local_get(m, 'rmse', NaN);
            lag_rows(i).nrmse = local_get(m, 'nrmse', NaN);
            lag_rows(i).r2 = local_get(m, 'r2', NaN);
            lag_rows(i).pearson = local_get(m, 'pearson', NaN);
            lag_rows(i).memory_coefficient = local_get(m, 'memory_coefficient', NaN);
            lag_rows(i).constant_prediction = logical(local_get(m, ...
                'constant_prediction', false));
            lag_rows(i).selected_lambda = local_get(pl, 'selected_lambda', NaN);
            lag_rows(i).grid_boundary_flag = logical(local_get(pl, ...
                'selected_at_grid_boundary', local_get(pl, 'grid_boundary_flag', false)));
            lag_rows(i).numerical_rank = local_get(pl, 'numerical_rank', NaN);
            lag_rows(i).coefficient_norm = local_get(pl, 'coefficient_norm', NaN);
            lag_rows(i).intercept = local_get(pl, 'intercept', NaN);
            lag_rows(i).feature_mean_hash = content_hash_if_present(pl, 'feature_mean');
            lag_rows(i).feature_scale_hash = content_hash_if_present(pl, 'feature_scale');
            lag_rows(i).lambda_selection_table_hash = content_hash_if_present(pl, ...
                'lambda_selection_table');
            if isfield(pl, 'coefficients') && ~isempty(pl.coefficients)
                lag_rows(i).model_readout_hash = canonical_sha256(pl.coefficients);
            elseif isfield(pl, 'model') && ~isempty(pl.model)
                lag_rows(i).model_readout_hash = canonical_sha256(pl.model);
            else
                lag_rows(i).model_readout_hash = '';
            end
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
    payload.lag_identities = [lag_rows.lag]';

    if isfield(ctrl, 'summary')
        s = ctrl.summary;
    elseif isfield(ctrl, 'scored') && isfield(ctrl.scored, 'summary')
        s = ctrl.scored.summary;
    else
        s = struct();
    end
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

    extra = setdiff(fieldnames(identity), { ...
        'control_name', 'execution_scope', 'model_seed', 'shared_task_identity', ...
        'provenance', 'fit_identity', 'lambda_grid'});
    extra = sort(extra);
    for i = 1:numel(extra)
        payload.(['id_' extra{i}]) = identity.(extra{i});
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
