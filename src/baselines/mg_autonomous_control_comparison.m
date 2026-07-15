function cmp = mg_autonomous_control_comparison(model_metrics, baseline_metrics)
% MG_AUTONOMOUS_CONTROL_COMPARISON  Descriptive MESN-vs-control autonomous metrics.
%
%   improvement_nrmse = baseline - model  (positive => MESN lower error)
%   ratio_nrmse = model / baseline        (<1 => MESN lower error)
%   difference_restricted_valid_horizon = model - baseline
% Comparisons are descriptive pending paired seed-level aggregation.

    cmp = struct();
    cmp.label = 'descriptive_pending_paired_seed_aggregation';
    cmp.sign_convention = [ ...
        'improvement_nrmse = baseline_nrmse - model_nrmse; ', ...
        'ratio_nrmse = model_nrmse / baseline_nrmse; ', ...
        'difference_restricted_valid_horizon = model_vh - baseline_vh'];

    b_fixed = local_vec(baseline_metrics, 'pooled_nrmse_at_fixed_horizons');
    m_fixed = local_vec(model_metrics, 'pooled_nrmse_at_fixed_horizons');
    n = min(numel(b_fixed), numel(m_fixed));
    cmp.fixed_report_horizons = local_vec(model_metrics, 'fixed_report_horizons');
    if isempty(cmp.fixed_report_horizons)
        cmp.fixed_report_horizons = local_vec(baseline_metrics, 'fixed_report_horizons');
    end
    cmp.improvement_nrmse_at_fixed_horizons = nan(n, 1);
    cmp.ratio_nrmse_at_fixed_horizons = nan(n, 1);
    cmp.ratio_status_at_fixed_horizons = cell(n, 1);
    for i = 1:n
        cmp.improvement_nrmse_at_fixed_horizons(i) = b_fixed(i) - m_fixed(i);
        [cmp.ratio_nrmse_at_fixed_horizons(i), cmp.ratio_status_at_fixed_horizons{i}] = ...
            safe_ratio(m_fixed(i), b_fixed(i));
    end

    b_full = local_num(baseline_metrics, 'pooled_nrmse_full_horizon');
    m_full = local_num(model_metrics, 'pooled_nrmse_full_horizon');
    cmp.model_nrmse_full_horizon = m_full;
    cmp.baseline_nrmse_full_horizon = b_full;
    cmp.improvement_nrmse_full_horizon = b_full - m_full;
    [cmp.ratio_nrmse_full_horizon, cmp.ratio_status_full_horizon] = safe_ratio(m_full, b_full);

    b_vh = local_num(baseline_metrics, 'median_valid_horizon');
    m_vh = local_num(model_metrics, 'median_valid_horizon');
    cmp.model_median_restricted_valid_horizon = m_vh;
    cmp.baseline_median_restricted_valid_horizon = b_vh;
    cmp.difference_restricted_valid_horizon = m_vh - b_vh;
    cmp.model_fraction_right_censored = local_num(model_metrics, 'fraction_right_censored');
    cmp.baseline_fraction_right_censored = local_num(baseline_metrics, 'fraction_right_censored');
end

function [r, status] = safe_ratio(model_v, baseline_v)
    if ~(isfinite(baseline_v) && baseline_v ~= 0 && isfinite(model_v))
        r = NaN;
        status = 'undefined_nonfinite_denominator';
    else
        r = model_v / baseline_v;
        status = 'defined';
    end
end

function v = local_num(s, name)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = double(s.(name));
    else
        v = NaN;
    end
end

function v = local_vec(s, name)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = double(s.(name)(:));
    else
        v = [];
    end
end
