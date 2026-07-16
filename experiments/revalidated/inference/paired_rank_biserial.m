function out = paired_rank_biserial(effect_oriented)
%PAIRED_RANK_BISERIAL  Matched-pairs rank-biserial correlation.
%
%   out = paired_rank_biserial(effect_oriented)
%
% Excludes exact zero differences. Uses average ranks for tied magnitudes.
% If all differences are zero, returns r=0 with status all_zero.

    effect_oriented = effect_oriented(:);
    if isempty(effect_oriented)
        error('paired_rank_biserial:EmptyInput', 'effect_oriented must be non-empty.');
    end

    out = struct();
    out.n = numel(effect_oriented);

    nz_mask = effect_oriented ~= 0;
    out.n_nonzero = sum(nz_mask);

    if out.n_nonzero == 0
        out.r_rank_biserial = 0;
        out.status = 'all_zero';
        out.Wplus = 0;
        out.Wminus = 0;
        return;
    end

    signed = effect_oriented(nz_mask);
    abs_vals = abs(signed);
    ranks = average_rank(abs_vals);

    pos_mask = signed > 0;
    neg_mask = signed < 0;

    Wplus = sum(ranks(pos_mask));
    Wminus = sum(ranks(neg_mask));
    denom = Wplus + Wminus;

    if denom == 0
        out.r_rank_biserial = 0;
        out.status = 'all_zero';
    else
        out.r_rank_biserial = (Wplus - Wminus) / denom;
        out.status = 'defined';
    end
    out.Wplus = Wplus;
    out.Wminus = Wminus;
end

function ranks = average_rank(values)
% Average ranks for tied absolute magnitudes (1-based).
    n = numel(values);
    [sorted, order] = sort(values);
    ranks = zeros(n, 1);
    i = 1;
    while i <= n
        j = i;
        while j < n && sorted(j + 1) == sorted(i)
            j = j + 1;
        end
        avg_rank = mean(i:j);
        ranks(order(i:j)) = avg_rank;
        i = j + 1;
    end
end
