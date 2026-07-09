function [regime, diagnostics] = classify_dynamical_regime(x_history, dt, LLE, options)
% classify_dynamical_regime
% Heuristic classification of long-term behaviour of a driven/un-driven
% reservoir trajectory into qualitative regimes.
%
% Usage:
%   [regime, diag] = classify_dynamical_regime(x_history, dt);
%   [regime, diag] = classify_dynamical_regime(x_history, dt, LLE);
%   [regime, diag] = classify_dynamical_regime(x_history, dt, LLE, options);
%
% Inputs:
%   x_history - (T x n) trajectory (typically post-transient)
%   dt        - sample spacing (seconds)
%   LLE       - (optional) largest Lyapunov exponent estimate
%   options   - struct (optional)
%       .var_tol_fixed     (default 1e-6)
%       .divergence_thresh (default 1e6)   % max abs(x) above => divergent
%       .peak_ratio_periodic (default 0.3) % peak power / total power
%       .entropy_low       (default 0.5)
%       .entropy_high      (default 0.8)
%
% Outputs:
%   regime      - 'fixed_point' | 'periodic' | 'quasiperiodic' | 'chaotic' | 'divergent'
%   diagnostics - struct with computed features

    if nargin < 3
        LLE = [];
    end
    if nargin < 4 || isempty(options)
        options = struct();
    end

    var_tol_fixed = getFieldOrDefault(options, 'var_tol_fixed', 1e-6);
    divergence_thresh = getFieldOrDefault(options, 'divergence_thresh', 1e6);
    peak_ratio_periodic = getFieldOrDefault(options, 'peak_ratio_periodic', 0.3);
    entropy_low = getFieldOrDefault(options, 'entropy_low', 0.5);
    entropy_high = getFieldOrDefault(options, 'entropy_high', 0.8);

    % Always populate the same fields so callers can store diagnostics in
    % structure arrays / parfor results without "dissimilar structures" errors.
    diagnostics = struct();
    diagnostics.has_nan_inf = any(~isfinite(x_history), 'all');
    diagnostics.max_abs = max(abs(x_history), [], 'all');
    diagnostics.LLE = LLE;
    diagnostics.variance = nan;
    diagnostics.dominant_freq = nan;
    diagnostics.peak_ratio = nan;
    diagnostics.spectral_entropy = nan;
    diagnostics.n_peaks_rel10 = nan;

    if diagnostics.has_nan_inf || diagnostics.max_abs > divergence_thresh
        regime = 'divergent';
        return;
    end

    % Use a scalar observable: mean population activity
    y = mean(x_history, 2);
    y = y(:);
    y = y - mean(y, 'omitnan');
    diagnostics.variance = var(y, 1);

    if diagnostics.variance <= var_tol_fixed
        regime = 'fixed_point';
        diagnostics.dominant_freq = 0;
        diagnostics.peak_ratio = 0;
        diagnostics.spectral_entropy = 0;
        diagnostics.n_peaks_rel10 = 0;
        return;
    end

    % Power spectrum (one-sided) using FFT
    fs = 1 / dt;
    T = numel(y);
    nfft = 2^nextpow2(T);
    Y = fft(y, nfft);
    P2 = (abs(Y) / T).^2;
    P1 = P2(1:(nfft/2 + 1));
    P1(2:end-1) = 2 * P1(2:end-1);
    f = fs * (0:(nfft/2)) / nfft;

    % Remove DC from spectrum for regime decisions
    if numel(P1) >= 2
        P_use = P1(2:end);
        f_use = f(2:end);
    else
        P_use = P1;
        f_use = f;
    end

    total_power = sum(P_use);
    if total_power <= 0 || ~isfinite(total_power)
        regime = 'fixed_point';
        diagnostics.dominant_freq = 0;
        diagnostics.peak_ratio = 0;
        diagnostics.spectral_entropy = 0;
        diagnostics.n_peaks_rel10 = 0;
        return;
    end

    [pmax, idx_max] = max(P_use);
    diagnostics.dominant_freq = f_use(idx_max);
    diagnostics.peak_ratio = pmax / total_power;

    % Spectral entropy (normalized 0..1)
    p = P_use / total_power;
    p = max(p, eps);
    H = -sum(p .* log(p));
    diagnostics.spectral_entropy = H / log(numel(p));

    % Multi-peak indicator: count peaks above 10% of max
    diagnostics.n_peaks_rel10 = sum(P_use >= (0.1 * pmax));

    % Decision logic
    if ~isempty(LLE) && isfinite(LLE) && (LLE > 0)
        regime = 'chaotic';
        return;
    end

    if diagnostics.peak_ratio >= peak_ratio_periodic && diagnostics.spectral_entropy <= entropy_low
        regime = 'periodic';
        return;
    end

    if diagnostics.n_peaks_rel10 >= 2 && diagnostics.spectral_entropy < entropy_high
        regime = 'quasiperiodic';
        return;
    end

    regime = 'chaotic';
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

