function [Y_by_lag, meta] = build_temporal_memory_targets(split, lags)
%BUILD_TEMPORAL_MEMORY_TARGETS  Delayed targets y_k(t)=u(t-k) for shared indices.
%
%   [Y_by_lag, meta] = build_temporal_memory_targets(split, lags)
%
% Uses exact indexing against split.scored_idx (already past washout + max_lag):
%   y_k(t) = U(scored_idx(t) - k)

    if nargin < 2
        error('build_temporal_memory_targets:MissingArgs', ...
            'split and lags are required.');
    end
    lags = lags(:);
    U = split.U(:);
    idx = split.scored_idx(:);
    n = numel(idx);
    max_lag = max(lags);
    if any(idx - max_lag < 1)
        error('build_temporal_memory_targets:InsufficientHistory', ...
            'scored_idx does not leave enough history for max_lag=%d.', max_lag);
    end

    Y_by_lag = cell(numel(lags), 1);
    for i = 1:numel(lags)
        k = lags(i);
        if ~(isfinite(k) && k > 0 && k == floor(k))
            error('build_temporal_memory_targets:InvalidLag', ...
                'Each lag must be a positive integer.');
        end
        Y_by_lag{i} = U(idx - k);
    end

    meta = struct();
    meta.lags = lags;
    meta.n_samples = n;
    meta.indexing = 'y_k(t)=U(scored_idx(t)-k)';
    meta.U_scored = U(idx);
end
