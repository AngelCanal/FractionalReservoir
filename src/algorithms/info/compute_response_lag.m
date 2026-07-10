function rl = compute_response_lag(X, u, options)
% compute_response_lag
% Peak lag of the feature-input cross-correlation (response lag).
%
% Definition (fixed):
%   R(k) = corr( feature(t), input(t+k) )
% Therefore:
%   k < 0  -> feature lags the input (associates with past input / memory)
%   k > 0  -> apparent future association (feature correlates with later input)
%   k = 0  -> contemporaneous association
%
% For i.i.d. white-noise drive, a statistically significant positive peak lag
% is flagged as probable leakage/alignment failure rather than "prediction".
%
% Usage:
%   rl = compute_response_lag(X, u);
%   rl = compute_response_lag(X, u, struct('max_lag', 40, 'dt', 0.1));
%
% Inputs:
%   X       - (T x n) feature matrix aligned with u
%   u       - (T x 1) input
%   options - struct (optional)
%       .max_lag      (default 50)   search lags in [-max_lag, +max_lag]
%       .washout      (default 0)    drop first samples before analysis
%       .max_neurons  (default 100)  subsample features for speed
%       .seed         (default 1)
%       .dt           (default 1)    sample period for peak_lag_time
%
% Output:
%   rl - struct
%       .lags                 (1 x (2*max_lag+1))
%       .correlation_by_lag   (n_use x n_lag) signed R_i(k)
%       .peak_lag_samples     (n_use x 1) argmax_k |R_i(k)|
%       .peak_lag_time        (n_use x 1) peak_lag_samples * dt
%       .mean_peak_lag_samples
%       .mean_peak_lag_time
%       .frac_negative_lag    fraction with peak_lag_samples < 0 (memory-like)
%       .frac_positive_lag    fraction with peak_lag_samples > 0
%       .positive_lag_leakage_flag  true if mean peak lag is significantly > 0
%       .options

    if nargin < 3 || isempty(options)
        options = struct();
    end
    max_lag = getFieldOrDefault(options, 'max_lag', 50);
    washout = getFieldOrDefault(options, 'washout', 0);
    max_neurons = getFieldOrDefault(options, 'max_neurons', 100);
    seed = getFieldOrDefault(options, 'seed', 1);
    dt = getFieldOrDefault(options, 'dt', 1);

    u = u(:);
    T = size(X, 1);
    if numel(u) ~= T
        error('compute_response_lag:SizeMismatch', 'u and X must share length T');
    end
    if ~(isscalar(max_lag) && max_lag >= 0 && max_lag == floor(max_lag))
        error('compute_response_lag:InvalidMaxLag', 'max_lag must be a nonnegative integer');
    end

    if washout > 0
        X = X((washout+1):end, :);
        u = u((washout+1):end);
        T = size(X, 1);
    end

    rng(seed);
    n = size(X, 2);
    n_use = min(max_neurons, n);
    idx = randperm(n, n_use);
    X = X(:, idx);

    % Zero-mean / unit-variance for correlation interpretation
    u = u - mean(u);
    u = u / max(std(u), eps);
    X = X - mean(X, 1);
    X = X ./ max(std(X, 0, 1), eps);

    lags = -max_lag:max_lag;
    n_lag = numel(lags);
    R = zeros(n_use, n_lag);

    for li = 1:n_lag
        k = lags(li);
        % Align feature(t) with input(t+k)
        if k >= 0
            a = 1:(T - k);
            b = (1 + k):T;
        else
            a = (1 - k):T;
            b = 1:(T + k);
        end
        Xa = X(a, :);
        ub = u(b);
        m = numel(ub);
        R(:, li) = (Xa' * ub) / max(m - 1, 1);
    end

    [~, imax] = max(abs(R), [], 2);
    peak_lag_samples = lags(imax)';
    peak_lag_time = peak_lag_samples * dt;
    mean_peak = mean(peak_lag_samples);

    % Under white-noise drive, significant positive mean peak lag suggests
    % leakage/alignment failure rather than genuine future prediction.
    if n_use > 1
        se = std(peak_lag_samples) / sqrt(n_use);
    else
        se = inf;
    end
    positive_lag_leakage_flag = isfinite(se) && (mean_peak > 2 * max(se, eps));

    rl = struct();
    rl.lags = lags;
    rl.correlation_by_lag = R;
    rl.peak_lag_samples = peak_lag_samples;
    rl.peak_lag_time = peak_lag_time;
    rl.mean_peak_lag_samples = mean_peak;
    rl.mean_peak_lag_time = mean_peak * dt;
    rl.frac_negative_lag = mean(peak_lag_samples < 0);
    rl.frac_positive_lag = mean(peak_lag_samples > 0);
    rl.positive_lag_leakage_flag = positive_lag_leakage_flag;
    rl.options = options;
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end
