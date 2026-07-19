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
    payload.fit_identity = local_get(ctrl, 'fit_identity', ...
        local_get(identity, 'fit_identity', struct()));

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
        'selected_lambda', NaN, ...
        'numerical_rank', NaN, ...
        'coefficient_norm', NaN, ...
        'intercept', NaN, ...
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
            lag_rows(i).selected_lambda = local_get(pl, 'selected_lambda', NaN);
            lag_rows(i).numerical_rank = local_get(pl, 'numerical_rank', NaN);
            lag_rows(i).coefficient_norm = local_get(pl, 'coefficient_norm', NaN);
            lag_rows(i).intercept = local_get(pl, 'intercept', NaN);
            if isfield(pl, 'coefficients') && ~isempty(pl.coefficients)
                lag_rows(i).model_readout_hash = canonical_sha256(pl.coefficients);
            elseif isfield(pl, 'model') && ~isempty(pl.model)
                lag_rows(i).model_readout_hash = canonical_sha256(pl.model);
            else
                lag_rows(i).model_readout_hash = '';
            end
            if isfield(pl, 'y_hat') && ~isempty(pl.y_hat)
                lag_rows(i).prediction_hash = canonical_sha256(pl.y_hat);
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
        'lag10_nrmse', local_get(s, 'lag10_nrmse', NaN), ...
        'lag10_r2', local_get(s, 'lag10_r2', NaN));

    % Bind any extra identity fields alphabetically for control-specific IDs
    extra = setdiff(fieldnames(identity), { ...
        'control_name', 'execution_scope', 'model_seed', 'shared_task_identity', ...
        'provenance', 'fit_identity'});
    extra = sort(extra);
    for i = 1:numel(extra)
        payload.(['id_' extra{i}]) = identity.(extra{i});
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
