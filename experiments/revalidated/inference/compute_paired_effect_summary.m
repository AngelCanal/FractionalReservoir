function summary = compute_paired_effect_summary(delta_raw, orientation_multiplier)
%COMPUTE_PAIRED_EFFECT_SUMMARY  Paired seed-level effect size summary.
%
%   summary = compute_paired_effect_summary(delta_raw)
%   summary = compute_paired_effect_summary(delta_raw, orientation_multiplier)
%
% delta_raw_i = treatment_i - control_i
% effect_oriented_i = orientation_multiplier * delta_raw_i

    if nargin < 2 || isempty(orientation_multiplier)
        orientation_multiplier = 1;
    end

    delta_raw = delta_raw(:);
    if isempty(delta_raw)
        error('compute_paired_effect_summary:EmptyInput', ...
            'delta_raw must be non-empty.');
    end
    if ~all(isfinite(delta_raw))
        error('compute_paired_effect_summary:NonFinite', ...
            'delta_raw must be finite.');
    end

    effect_oriented = orientation_multiplier * delta_raw;

    summary = struct();
    summary.delta_raw = delta_raw;
    summary.effect_oriented = effect_oriented;
    summary.orientation_multiplier = orientation_multiplier;
    summary.mean_delta_raw = mean(delta_raw);
    summary.mean_oriented_effect = mean(effect_oriented);
    summary.median_oriented_effect = median(effect_oriented);
    summary.n = numel(effect_oriented);

    sample_std = std(effect_oriented, 0);
    if sample_std == 0
        summary.dz = NaN;
        summary.dz_status = 'zero_variance_undefined';
    else
        summary.dz = summary.mean_oriented_effect / sample_std;
        summary.dz_status = 'defined';
    end

    summary.common_language_favorable_probability = ...
        mean(effect_oriented > 0) + 0.5 * mean(effect_oriented == 0);

    rb = paired_rank_biserial(effect_oriented);
    summary.rank_biserial = rb.r_rank_biserial;
    summary.rank_biserial_status = rb.status;
    summary.rank_biserial_n_nonzero = rb.n_nonzero;
end
