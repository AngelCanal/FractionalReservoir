function summary = summarize_temporal_memory_curve(lags, memory_coefficients, lag_metrics)
%SUMMARIZE_TEMPORAL_MEMORY_CURVE  Descriptive MC sums and lag summaries.
%
%   summary = summarize_temporal_memory_curve(lags, memory_coefficients, lag_metrics)

    lags = lags(:);
    mc = memory_coefficients(:);
    if numel(lags) ~= numel(mc)
        error('summarize_temporal_memory_curve:LengthMismatch', ...
            'lags and memory_coefficients must match.');
    end

    summary = struct();
    summary.MC_1_10 = sum_mc_upto(lags, mc, 10);
    summary.MC_1_25 = sum_mc_upto(lags, mc, 25);
    summary.MC_1_50 = sum_mc_upto(lags, mc, 50);
    summary.memory_capacity_sum_lags_1_10 = summary.MC_1_10;
    summary.memory_capacity_sum_lags_1_25 = summary.MC_1_25;
    summary.memory_capacity_sum_lags_1_50 = summary.MC_1_50;

    [max_mc, imax] = max(mc);
    summary.maximum_memory_lag = lags(imax);
    summary.lag_of_maximum_memory_coefficient = lags(imax);
    summary.maximum_memory_coefficient = max_mc;

    below = find(mc < 0.1, 1, 'first');
    if isempty(below)
        summary.first_lag_memory_below_0_1 = NaN;
        summary.memory_crossing_right_censored_at_50 = true;
    else
        summary.first_lag_memory_below_0_1 = lags(below);
        summary.memory_crossing_right_censored_at_50 = false;
    end

    idx10 = find(lags == 10, 1);
    if isempty(idx10)
        summary.lag10_nrmse = NaN;
        summary.lag10_r2 = NaN;
        summary.lag10_rmse = NaN;
        summary.lag10_pearson = NaN;
        summary.lag10_memory_coefficient = NaN;
    else
        m10 = lag_metrics(idx10);
        summary.lag10_nrmse = m10.nrmse;
        summary.lag10_r2 = m10.r2;
        summary.lag10_rmse = m10.rmse;
        summary.lag10_pearson = m10.pearson;
        summary.lag10_memory_coefficient = m10.memory_coefficient;
    end
end

function s = sum_mc_upto(lags, mc, K)
    mask = lags >= 1 & lags <= K;
    s = sum(mc(mask));
end
