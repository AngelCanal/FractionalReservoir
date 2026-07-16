function out = holm_bonferroni_adjust(p_values, alpha)
%HOLM_BONFERRONI_ADJUST  Holm-Bonferroni step-down adjustment for one family.
%
%   out = holm_bonferroni_adjust(p_values)
%   out = holm_bonferroni_adjust(p_values, alpha)
%
% NaN p-values are not silently omitted; they fail validation.

    if nargin < 2 || isempty(alpha)
        alpha = 0.05;
    end

    p_values = p_values(:);
    m = numel(p_values);

    if any(isnan(p_values))
        error('holm_bonferroni_adjust:NaNPValue', ...
            'NaN p-values are not allowed in a testing family.');
    end
    if any(p_values < 0) || any(p_values > 1)
        error('holm_bonferroni_adjust:InvalidPValue', ...
            'p_values must lie in [0, 1].');
    end

    [sorted_p, sort_idx] = sort(p_values, 'ascend');
    ranks = zeros(m, 1);
    ranks(sort_idx) = (1:m)';

    adjusted_sorted = zeros(m, 1);
    running_max = 0;
    for j = 1:m
        adj = sorted_p(j) * (m - j + 1);
        running_max = max(running_max, adj);
        adjusted_sorted(j) = min(running_max, 1);
    end

    p_adjusted = zeros(m, 1);
    p_adjusted(sort_idx) = adjusted_sorted;
    holm_reject = p_adjusted <= alpha;

    out = struct();
    out.p_adjusted = p_adjusted;
    out.holm_ranks = ranks;
    out.holm_reject = holm_reject;
    out.family_size = m;
    out.alpha = alpha;
    out.method = 'holm_bonferroni';
end
