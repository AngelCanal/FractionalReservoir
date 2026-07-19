function metrics = compute_temporal_memory_metrics(y_hat, y)
%COMPUTE_TEMPORAL_MEMORY_METRICS  Held-out memory metrics for one lag.
%
%   metrics = compute_temporal_memory_metrics(y_hat, y)
%
%   RMSE
%   NRMSE = RMSE / population std(y)   [std(y,1)]
%   R^2   (negative values retained)
%   Pearson correlation
%   memory_coefficient = Pearson^2
%
% Constant predictions (nonfinite Pearson): Pearson=0, memory_coefficient=0,
% constant_prediction=true. Rows are never discarded.

    y_hat = y_hat(:);
    y = y(:);
    if numel(y_hat) ~= numel(y)
        error('compute_temporal_memory_metrics:LengthMismatch', ...
            'Predictions and targets must have equal length.');
    end
    if any(~isfinite(y_hat)) || any(~isfinite(y))
        error('compute_temporal_memory_metrics:NonFinite', ...
            'Predictions and targets must be finite.');
    end

    err = y_hat - y;
    rmse = sqrt(mean(err.^2));
    s_pop = std(y, 1);
    if s_pop == 0
        error('compute_temporal_memory_metrics:ZeroTargetVariance', ...
            'Target population standard deviation is zero.');
    end
    nrmse = rmse / s_pop;

    ss_res = sum(err.^2);
    ss_tot = sum((y - mean(y)).^2);
    r2 = 1 - ss_res / ss_tot;

    constant_prediction = false;
    if (max(y_hat) - min(y_hat)) == 0 || std(y_hat, 1) == 0
        pearson = 0;
        constant_prediction = true;
    elseif std(y, 1) > 0
        C = corrcoef(y_hat, y);
        pearson = C(1, 2);
        if ~isfinite(pearson)
            pearson = 0;
            constant_prediction = true;
        end
    else
        pearson = 0;
        constant_prediction = true;
    end
    memory_coefficient = pearson^2;

    metrics = struct();
    metrics.rmse = rmse;
    metrics.nrmse = nrmse;
    metrics.r2 = r2;
    metrics.pearson = pearson;
    metrics.pearson_correlation = pearson;
    metrics.memory_coefficient = memory_coefficient;
    metrics.squared_correlation_memory_coefficient = memory_coefficient;
    metrics.constant_prediction = constant_prediction;
    metrics.n_samples = numel(y);
end
