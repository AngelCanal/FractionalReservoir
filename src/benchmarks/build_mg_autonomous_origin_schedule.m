function schedule = build_mg_autonomous_origin_schedule(split, rollout_cfg)
% BUILD_MG_AUTONOMOUS_ORIGIN_SCHEDULE  Deterministic held-out MG forecast origins.
%
%   schedule = build_mg_autonomous_origin_schedule(split, rollout_cfg)
%
% Pure helper: no model, predictions, or performance metrics.
% Errors if the requested origin/horizon allocation cannot be satisfied.
% Never silently shortens horizon or origin count.

    if ~isstruct(split) || ~isfield(split, 'test_idx')
        error('build_mg_autonomous_origin_schedule:InvalidSplit', ...
            'split.test_idx is required.');
    end
    if ~isstruct(rollout_cfg)
        error('build_mg_autonomous_origin_schedule:InvalidCfg', ...
            'rollout_cfg must be a struct.');
    end

    H = double(rollout_cfg.forecast_horizon_steps);
    n_origins = double(rollout_cfg.n_forecast_origins);
    if ~(isscalar(H) && H >= 1 && H == floor(H))
        error('build_mg_autonomous_origin_schedule:BadHorizon', ...
            'forecast_horizon_steps must be a positive integer.');
    end
    if ~(isscalar(n_origins) && n_origins >= 1 && n_origins == floor(n_origins))
        error('build_mg_autonomous_origin_schedule:BadOriginCount', ...
            'n_forecast_origins must be a positive integer.');
    end

    test_idx = split.test_idx(:);
    if isempty(test_idx)
        error('build_mg_autonomous_origin_schedule:EmptyTest', ...
            'Test block is empty; cannot allocate forecast origins.');
    end

    first_origin = test_idx(1);
    last_origin = test_idx(end) - H + 1;
    if last_origin < first_origin
        error('build_mg_autonomous_origin_schedule:InsufficientTestLength', ...
            ['Test block length %d cannot allocate horizon %d ', ...
             '(need at least %d contiguous test targets).'], ...
            numel(test_idx), H, H);
    end

    span = last_origin - first_origin;
    if n_origins > span + 1
        error('build_mg_autonomous_origin_schedule:InsufficientOriginSlots', ...
            ['Cannot place %d unique origins in inclusive range [%d,%d] ', ...
             '(%d slots).'], n_origins, first_origin, last_origin, span + 1);
    end

    raw = round(linspace(first_origin, last_origin, n_origins));
    origins = unique(raw(:), 'stable');
    if numel(origins) ~= n_origins
        error('build_mg_autonomous_origin_schedule:NonUniqueOrigins', ...
            ['linspace rounding collapsed to %d unique origins; ', ...
             'requested %d. Widen the test block or reduce n_forecast_origins.'], ...
            numel(origins), n_origins);
    end
    if any(diff(origins) <= 0)
        error('build_mg_autonomous_origin_schedule:NonMonotonic', ...
            'Origin schedule must be strictly increasing.');
    end

    test_rel = zeros(size(origins));
    for k = 1:numel(origins)
        i = origins(k);
        if i < test_idx(1) || (i + H - 1) > test_idx(end)
            error('build_mg_autonomous_origin_schedule:OutsideTest', ...
                'Origin %d with horizon %d leaves the held-out test block.', i, H);
        end
        rel = find(test_idx == i, 1);
        if isempty(rel)
            error('build_mg_autonomous_origin_schedule:OriginNotInTest', ...
                'Origin %d is not a member of split.test_idx.', i);
        end
        test_rel(k) = rel;
        % All scored targets i:i+H-1 must lie in the test block
        for t = 0:(H - 1)
            if ~ismember(i + t, test_idx)
                error('build_mg_autonomous_origin_schedule:TargetOutsideTest', ...
                    'Target index %d for origin %d is outside the test block.', ...
                    i + t, i);
            end
        end
    end

    schedule = struct();
    schedule.protocol_version = char(rollout_cfg.protocol_version);
    schedule.origin_policy = char(rollout_cfg.origin_policy);
    schedule.forecast_horizon_steps = H;
    schedule.n_forecast_origins = n_origins;
    schedule.first_origin = first_origin;
    schedule.last_origin = last_origin;
    schedule.origin_indices = origins(:)';
    schedule.origin_test_relative_indices = test_rel(:);
    schedule.test_idx_first = test_idx(1);
    schedule.test_idx_last = test_idx(end);
    schedule.n_test = numel(test_idx);
end
