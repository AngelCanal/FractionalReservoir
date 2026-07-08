function pa = compute_phase_advance(X, u, options)
% compute_phase_advance
% Quantify whether reservoir features lead (predict) or lag the input, using
% the lag of the peak cross-correlation between each feature and the input.
%
% For a purely integrating/memory reservoir, features correlate with PAST
% input (positive lag). Adaptation (SFA) introduces a derivative-like,
% phase-advancing component, which can make features correlate with FUTURE
% input (negative lag) -- the "phase advance useful for input prediction"
% hypothesis from the project notes.
%
% Convention: for each feature f_i we compute the cross-correlation
%   R_i(k) = corr( f_i(t), u(t + k) )
% and record the lag k* maximising |R_i|. k* < 0 means the feature leads the
% input (phase advance / prediction); k* > 0 means it lags (memory).
%
% Usage:
%   pa = compute_phase_advance(X, u);
%   pa = compute_phase_advance(X, u, struct('max_lag', 40));
%
% Inputs:
%   X       - (T x n) feature matrix (e.g. reservoir x or r), post-washout
%   u       - (T x 1) input aligned with X
%   options - struct (optional)
%       .max_lag      (default 50)   search lags in [-max_lag, +max_lag]
%       .washout      (default 0)    drop first samples before analysis
%       .max_neurons  (default 100)  subsample features for speed
%       .seed         (default 1)
%
% Output:
%   pa - struct
%       .lags               (1 x (2*max_lag+1))
%       .xcorr_mean         mean |R| over features vs lag
%       .peak_lag_per_unit  (n_use x 1) k* per feature
%       .mean_peak_lag      mean k* (negative => net phase advance)
%       .frac_leading       fraction of features with k* < 0
%       .options

    if nargin < 3 || isempty(options)
        options = struct();
    end
    max_lag = getFieldOrDefault(options, 'max_lag', 50);
    washout = getFieldOrDefault(options, 'washout', 0);
    max_neurons = getFieldOrDefault(options, 'max_neurons', 100);
    seed = getFieldOrDefault(options, 'seed', 1);

    u = u(:);
    T = size(X, 1);
    if numel(u) ~= T
        error('compute_phase_advance:SizeMismatch', 'u and X must share length T');
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

    % Normalise to zero mean / unit variance for correlation interpretation
    u = u - mean(u);
    u = u / max(std(u), eps);
    X = X - mean(X, 1);
    X = X ./ max(std(X, 0, 1), eps);

    lags = -max_lag:max_lag;
    n_lag = numel(lags);
    R = zeros(n_use, n_lag);

    for li = 1:n_lag
        k = lags(li);
        % Align f_i(t) with u(t + k): positive k -> future input
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
    peak_lag = lags(imax)';

    pa = struct();
    pa.lags = lags;
    pa.xcorr_mean = mean(abs(R), 1);
    pa.peak_lag_per_unit = peak_lag;
    pa.mean_peak_lag = mean(peak_lag);
    pa.frac_leading = mean(peak_lag < 0);
    pa.options = options;
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end
