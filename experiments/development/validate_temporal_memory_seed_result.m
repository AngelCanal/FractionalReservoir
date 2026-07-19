function report = validate_temporal_memory_seed_result(result, cfg)
%VALIDATE_TEMPORAL_MEMORY_SEED_RESULT  Fail-closed seed-result checks.
%
%   report = validate_temporal_memory_seed_result(result, cfg)
%
% Rejects reserved future seeds, v1 test seed 9003, include_input=true,
% wrong lag counts, missing summaries, and packed-state activity misuse.

    if nargin < 2 || ~isstruct(cfg)
        error('validate_temporal_memory_seed_result:InvalidCfg', ...
            'cfg must be a struct.');
    end
    if ~isstruct(result)
        error('validate_temporal_memory_seed_result:InvalidResult', ...
            'result must be a struct.');
    end

    reasons = {};
    checks = {};

    seed = local_get(result, 'model_seed', NaN);
    seed_9003_ok = seed ~= 9003;
    checks{end+1} = make_check('v1_test_seed_9003_rejected', seed_9003_ok, ''); %#ok<*AGROW>
    if ~seed_9003_ok
        reasons{end+1} = 'v1_test_seed_9003_used';
    end

    reserved = flatten_numeric(local_get(cfg, 'reserved_future_v2', struct()));
    reserved_ok = ~any(reserved(:) == seed);
    checks{end+1} = make_check('reserved_future_seed_rejected', reserved_ok, '');
    if ~reserved_ok
        reasons{end+1} = 'reserved_future_seed_used';
    end

    lags_ok = isfield(result, 'lags') && ~isempty(result.lags) && ...
        numel(result.lags) == numel(unique(result.lags));
    checks{end+1} = make_check('lags_present', lags_ok, '');
    if ~lags_ok
        reasons{end+1} = 'lags_missing_or_invalid';
    end

    n50_ok = isfield(result, 'per_lag') && numel(result.per_lag) == numel(result.lags);
    checks{end+1} = make_check('per_lag_row_count', n50_ok, ...
        sprintf('n=%d', local_numel(result, 'per_lag')));
    if ~n50_ok
        reasons{end+1} = 'per_lag_row_count_mismatch';
    end

    inc_ok = isfield(result, 'include_input') && ~logical(result.include_input);
    checks{end+1} = make_check('include_input_false', inc_ok, '');
    if ~inc_ok
        reasons{end+1} = 'include_input_true';
    end

    sim_ok = isfield(result, 'simulations_per_split') && ...
        result.simulations_per_split == 1;
    checks{end+1} = make_check('one_simulation_per_split', sim_ok, '');
    if ~sim_ok
        reasons{end+1} = 'multiple_simulations_per_split';
    end

    act_ok = true;
    if isfield(result, 'feature_diagnostics')
        fd = result.feature_diagnostics;
        if isfield(fd, 'n_neurons') && isfinite(fd.n_neurons)
            act_ok = act_ok && (fd.n_neurons == cfg.base.n);
        end
        if isfield(fd, 'packed_states_counted_as_neurons')
            act_ok = act_ok && ~logical(fd.packed_states_counted_as_neurons);
        end
        if isfield(fd, 'activity_from_neuronal_rates')
            act_ok = act_ok && logical(fd.activity_from_neuronal_rates);
        end
        if isfield(fd, 'n_neurons') && isfield(fd, 'packed_state_dimension') && ...
                isfinite(fd.n_neurons) && isfinite(fd.packed_state_dimension)
            % Packed width may exceed n when SFA/STD present; must not equal
            % activity neuron count unless mechanisms are off.
            act_ok = act_ok && (fd.n_neurons == cfg.base.n);
        end
    end
    checks{end+1} = make_check('activity_uses_neuronal_rates', act_ok, 'n=40');
    if ~act_ok
        reasons{end+1} = 'activity_not_neuronal_rate_based';
    end

    sum_ok = isfield(result, 'summary') && ...
        isfield(result.summary, 'MC_1_50') && isfinite(result.summary.MC_1_50);
    checks{end+1} = make_check('memory_summaries_present', sum_ok, '');
    if ~sum_ok
        reasons{end+1} = 'memory_summaries_missing';
    end

    report = struct();
    report.ok = isempty(reasons);
    report.checks = [checks{:}];
    report.failure_reasons = reasons;
    report.model_seed = seed;

    if ~report.ok
        error('validate_temporal_memory_seed_result:Failed', ...
            'Seed result validation failed: %s', strjoin(reasons, ', '));
    end
end

function c = make_check(name, pass, detail)
    c = struct('name', name, 'pass', logical(pass), 'detail', char(string(detail)));
end

function v = local_get(S, name, default)
    if isstruct(S) && isfield(S, name)
        v = S.(name);
    else
        v = default;
    end
end

function n = local_numel(S, name)
    if isfield(S, name)
        n = numel(S.(name));
    else
        n = 0;
    end
end

function vals = flatten_numeric(S)
    vals = [];
    if isnumeric(S)
        vals = S(:)';
        return;
    end
    if ~isstruct(S) || numel(S) ~= 1
        return;
    end
    fn = fieldnames(S);
    for i = 1:numel(fn)
        vals = [vals, flatten_numeric(S.(fn{i}))]; %#ok<AGROW>
    end
end
