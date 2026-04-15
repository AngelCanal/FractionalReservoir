function fit = fit_memory_decay(lags, y, options)
% fit_memory_decay
% Fit candidate decay models to a memory curve (MC spectrum or Fisher curve).
%
% Models:
%   1) Exponential:         y = A * exp(-k/tau)
%   2) Power law:           y = A * k^(-alpha)
%   3) Stretched exponential y = A * exp(-(k/tau)^beta)
%
% Usage:
%   fit = fit_memory_decay(lags, curve);
%
% Inputs:
%   lags    - vector of positive lags (e.g. 1:K)
%   y       - vector of same size (nonnegative)
%   options - struct (optional)
%       .min_y       (default 1e-12) clamp floor for log transforms
%       .fit_range   (default [])    [k_min k_max] subset of lags
%       .do_plots    (default false)
%
% Output:
%   fit - struct containing parameter estimates and AIC/BIC per model and
%         the selected best model by BIC.

    if nargin < 3 || isempty(options)
        options = struct();
    end

    min_y = getFieldOrDefault(options, 'min_y', 1e-12);
    fit_range = getFieldOrDefault(options, 'fit_range', []);
    do_plots = getFieldOrDefault(options, 'do_plots', false);

    lags = lags(:);
    y = y(:);
    if numel(lags) ~= numel(y)
        error('fit_memory_decay:SizeMismatch', 'lags and y must have same length');
    end

    if ~isempty(fit_range)
        kmin = fit_range(1);
        kmax = fit_range(2);
        sel = (lags >= kmin) & (lags <= kmax);
        lags = lags(sel);
        y = y(sel);
    end

    % Filter nonpositive lags
    sel = lags > 0 & isfinite(lags) & isfinite(y);
    lags = lags(sel);
    y = y(sel);

    % Clamp y for log-domain fits
    y_clamped = max(y, min_y);

    n = numel(lags);
    if n < 10
        error('fit_memory_decay:TooFewPoints', 'Need at least 10 points to fit reliably');
    end

    % --- Exponential fit (log-linear) ---
    % log y = log A - k/tau
    Xexp = [ones(n,1), -lags];
    bexp = Xexp \ log(y_clamped);
    logA_exp = bexp(1);
    inv_tau = bexp(2);
    tau_exp = 1 / max(inv_tau, eps);
    A_exp = exp(logA_exp);
    yhat_exp = A_exp * exp(-lags / tau_exp);
    sse_exp = sum((y - yhat_exp).^2);
    k_exp = 2;

    % --- Power law fit (log-log) ---
    % log y = log A - alpha log k
    Xpow = [ones(n,1), -log(lags)];
    bpow = Xpow \ log(y_clamped);
    logA_pow = bpow(1);
    alpha_pow = bpow(2);
    A_pow = exp(logA_pow);
    yhat_pow = A_pow * (lags .^ (-alpha_pow));
    sse_pow = sum((y - yhat_pow).^2);
    k_pow = 2;

    % --- Stretched exponential fit (nonlinear least squares) ---
    % params p = [logA, logtau, logit_beta] with beta in (0, 2)
    beta0 = 0.7;
    p0 = [log(max(y_clamped)), log(median(lags)), log(beta0/(2-beta0))];
    obj = @(p) sse_stretched(p, lags, y);
    p_opt = fminsearch(obj, p0, optimset('Display','off'));
    [A_str, tau_str, beta_str, yhat_str, sse_str] = unpack_stretched(p_opt, lags, y);
    k_str = 3;

    % AIC/BIC (Gaussian errors, constant variance)
    aic_exp = aic(sse_exp, n, k_exp);
    bic_exp = bic(sse_exp, n, k_exp);
    aic_pow = aic(sse_pow, n, k_pow);
    bic_pow = bic(sse_pow, n, k_pow);
    aic_str = aic(sse_str, n, k_str);
    bic_str = bic(sse_str, n, k_str);

    fit = struct();
    fit.options = options;
    fit.n = n;
    fit.lags = lags;
    fit.y = y;

    fit.exponential = struct('A', A_exp, 'tau', tau_exp, 'sse', sse_exp, 'aic', aic_exp, 'bic', bic_exp, 'yhat', yhat_exp);
    fit.powerlaw = struct('A', A_pow, 'alpha', alpha_pow, 'sse', sse_pow, 'aic', aic_pow, 'bic', bic_pow, 'yhat', yhat_pow);
    fit.stretched = struct('A', A_str, 'tau', tau_str, 'beta', beta_str, 'sse', sse_str, 'aic', aic_str, 'bic', bic_str, 'yhat', yhat_str);

    % Select best by BIC
    bics = [bic_exp, bic_pow, bic_str];
    [~, idx] = min(bics);
    names = {'exponential','powerlaw','stretched'};
    fit.best_model = names{idx};

    if do_plots
        figure('Color','w');
        loglog(lags, max(y, min_y), 'k.', 'MarkerSize', 10); hold on;
        loglog(lags, max(yhat_exp, min_y), 'r-', 'LineWidth', 1.5);
        loglog(lags, max(yhat_pow, min_y), 'b-', 'LineWidth', 1.5);
        loglog(lags, max(yhat_str, min_y), 'g-', 'LineWidth', 1.5);
        grid on;
        xlabel('lag k');
        ylabel('memory curve');
        legend('data','exp','power','stretched','Location','best');
        title(sprintf('Best (BIC): %s', fit.best_model), 'Interpreter','none');
    end
end

function sse = sse_stretched(p, lags, y)
    [~, ~, ~, yhat, ~] = unpack_stretched(p, lags, y);
    sse = sum((y - yhat).^2);
end

function [A, tau, beta, yhat, sse] = unpack_stretched(p, lags, y)
    logA = p(1);
    logtau = p(2);
    % beta in (0,2) via scaled logistic
    beta = 2 * (1 ./ (1 + exp(-p(3))));
    A = exp(logA);
    tau = exp(logtau);
    yhat = A * exp(- (lags ./ tau) .^ beta);
    sse = sum((y - yhat).^2);
end

function v = aic(sse, n, k)
    v = n * log(max(sse / n, eps)) + 2 * k;
end

function v = bic(sse, n, k)
    v = n * log(max(sse / n, eps)) + k * log(n);
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

