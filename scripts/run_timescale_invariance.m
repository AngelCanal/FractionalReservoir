%% run_timescale_invariance
% Multi-timescale representation, temporal invariance, and response-lag
% analysis of the MESN reservoir (Result 3 of the paper workplan).
%
% Three experiments:
%   (A) Timescale spectrum vs number of SFA timescales (n_a_E). Multi-timescale
%       adaptation should broaden the memory/timescale spectrum -- more, longer
%       memory. Measured with linear memory capacity, MI-lag curve, and
%       decay-time fits (Fisher memory is quarantined).
%   (B) Temporal (time-shift) invariance and time-warp robustness. Shift
%       equivariance operationalises "temporal invariance"; time-warp tests
%       robustness of a trained readout to input dilation.
%   (C) Response lag: peak of R(k)=corr(feature(t),input(t+k)). k<0 means the
%       feature lags (past input); k>0 is apparent future association (flag
%       leakage under white noise). Compared with adaptation ON vs OFF.
%
% Output: results/timescale_invariance/timescale_<timestamp>.mat + figures.

if exist('setup_paths', 'file') == 2
    setup_paths();
end

out_dir = fullfile(pwd, 'results', 'timescale_invariance');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

dt = 0.1;
timestamp = datestr(now, 'yyyymmdd_HHMMSS');

%% =====================================================================
% (A) Timescale spectrum vs number of SFA timescales
% =====================================================================
n_a_list = [1, 2, 3, 5];
specA = struct('n_a_E', num2cell(n_a_list), ...
    'MC_total', [], 'MC_spectrum', [], 'MC_lags', [], ...
    'Fisher_curve', [], 'Fisher_lags', [], 'Fisher_tau', [], 'MC_tau', []);

for ii = 1:numel(n_a_list)
    na = n_a_list(ii);
    overrides = struct();
    overrides.dt = dt;
    overrides.n_a_E = na;
    overrides.tau_a_E = logspace(log10(0.25), log10(25), na);
    params = default_MESN_config(overrides);
    esn = SRNN_ESN(params);

    mc = compute_memory_capacity(esn, struct('T', 5000, 'K_max', 200, ...
        'washout', 300, 'lambda', params.lambda, 'feature_mode', 'x'));

    % Fisher memory is quarantined (docs/validation/FISHER_MEMORY_STATUS.md).
    fisher = struct('FI_curve', nan(200, 1), 'lags', (1:200)', ...
        'status', 'quarantined_not_computed', 'scientifically_valid', false);
    fisher_tau = nan;

    mc_fit = fit_memory_decay(mc.lags, mc.MC_spectrum, struct());

    specA(ii).MC_total = mc.MC_total;
    specA(ii).MC_spectrum = mc.MC_spectrum;
    specA(ii).MC_lags = mc.lags;
    specA(ii).Fisher_curve = fisher.FI_curve;
    specA(ii).Fisher_lags = fisher.lags;
    specA(ii).MC_tau = extract_tau(mc_fit);
    specA(ii).Fisher_tau = fisher_tau;

    fprintf('n_a_E=%d: MC_total=%.2f  MC_tau=%.1f  Fisher=quarantined\n', ...
        na, mc.MC_total, specA(ii).MC_tau);
end

%% =====================================================================
% (B) Temporal invariance (shift equivariance) + time-warp robustness
% =====================================================================
params = default_MESN_config(struct('dt', dt));
esn = SRNN_ESN(params);

% (B1) Shift equivariance
se = measure_shift_equivariance(esn, struct('T', 3000, 'washout', 800, ...
    'shifts', [2 5 10 20 40 80]));
fprintf('\nShift-equivariance NRMSE: %s\n', mat2str(se.nrmse_per_shift', 3));

% (B2) Time-warp robustness of a trained readout.
% Task: reconstruct a delayed, smoothed version of the input (a simple
% timescale-sensitive functional). Train at warp=1, test at other warps.
warp_factors = [0.5 0.75 1.0 1.5 2.0];
warp_nrmse = zeros(numel(warp_factors), 1);

rng(7);
T_base = 6000;
u_base = 0.2 * randn(T_base, 1);
target_delay = 10;   % samples
target = smooth_causal(u_base, 8);
target = [zeros(target_delay,1); target(1:end-target_delay)];

esn.resetState();
train_metrics = esn.trainReadout(u_base, target, ...
    struct('train_ratio', 0.6, 'val_ratio', 0.2, 'washout_steps', 300, ...
           'lambda', params.lambda));

for wi = 1:numel(warp_factors)
    w = warp_factors(wi);
    % Warp the input timeline by resampling; warp the target consistently.
    u_w = resample_timeline(u_base, w);
    tgt_w = resample_timeline(target, w);
    n = min(size(u_w,1), size(tgt_w,1));
    u_w = u_w(1:n); tgt_w = tgt_w(1:n);

    y_pred = esn.predict(u_w);
    idx = 400:n;   % drop washout
    warp_nrmse(wi) = nrmse(y_pred(idx), tgt_w(idx));
    fprintf('warp=%.2f: readout NRMSE=%.3f\n', w, warp_nrmse(wi));
end

%% =====================================================================
% (C) Response lag: adaptation ON vs OFF
% =====================================================================
rng(21);
U = 0.2 * randn(4000, 1);

% Adaptation ON (default)
params_on = default_MESN_config(struct('dt', dt));
esn_on = SRNN_ESN(params_on); esn_on.which_states = 'x';
esn_on.resetState();
X_on = esn_on.runReservoir(U);
pa_on = compute_response_lag(X_on, U, struct('max_lag', 40, 'washout', 800, 'dt', dt));

% Adaptation OFF (c_E = c_I = 0, STD off)
params_off = default_MESN_config(struct('dt', dt, 'c_E', 0, 'c_I', 0, ...
    'n_b_E', 0, 'n_b_I', 0));
esn_off = SRNN_ESN(params_off); esn_off.which_states = 'x';
esn_off.resetState();
X_off = esn_off.runReservoir(U);
pa_off = compute_response_lag(X_off, U, struct('max_lag', 40, 'washout', 800, 'dt', dt));

fprintf('\nResponse lag (mean peak lag, samples): ON=%.2f  OFF=%.2f\n', ...
    pa_on.mean_peak_lag_samples, pa_off.mean_peak_lag_samples);
fprintf('Fraction negative-lag (memory-like) units: ON=%.2f  OFF=%.2f\n', ...
    pa_on.frac_negative_lag, pa_off.frac_negative_lag);
if pa_on.positive_lag_leakage_flag || pa_off.positive_lag_leakage_flag
    fprintf(['NOTE: significant positive mean peak lag under white noise ', ...
        'suggests leakage/alignment failure, not prediction.\n']);
end

%% Save
save_path = fullfile(out_dir, sprintf('timescale_%s.mat', timestamp));
save(save_path, 'specA', 'n_a_list', 'se', 'warp_factors', 'warp_nrmse', ...
    'train_metrics', 'pa_on', 'pa_off', 'dt');

%% Figures
figure('Color', 'w');
subplot(2,2,1); hold on;
for ii = 1:numel(n_a_list)
    plot(specA(ii).MC_lags, specA(ii).MC_spectrum, 'LineWidth', 1.3, ...
        'DisplayName', sprintf('n_a=%d', n_a_list(ii)));
end
xlabel('lag k'); ylabel('MC_k'); title('Memory spectrum vs SFA timescales');
legend('show'); grid on;

subplot(2,2,2);
plot(se.shifts, se.nrmse_per_shift, 'ko-', 'LineWidth', 1.5);
xlabel('shift (samples)'); ylabel('equivariance NRMSE');
title('Temporal (shift) invariance'); grid on;

subplot(2,2,3);
plot(warp_factors, warp_nrmse, 'bs-', 'LineWidth', 1.5);
xlabel('time-warp factor'); ylabel('readout NRMSE');
title('Time-warp robustness (trained at 1.0)'); grid on;

subplot(2,2,4); hold on;
plot(pa_on.lags, mean(abs(pa_on.correlation_by_lag), 1), 'r', 'LineWidth', 1.5, ...
    'DisplayName', 'adapt ON');
plot(pa_off.lags, mean(abs(pa_off.correlation_by_lag), 1), 'k', 'LineWidth', 1.5, ...
    'DisplayName', 'adapt OFF');
xline(0, 'k--');
xlabel('lag (samples; <0 = feature lags / past input)'); ylabel('mean |xcorr|');
title('Response lag'); legend('show'); grid on;

fprintf('Saved timescale/invariance results to %s\n', save_path);

% -------------------------------------------------------------------------
function tau = extract_tau(fit)
% Best-effort extraction of a characteristic decay time from fit_memory_decay.
    tau = NaN;
    if isstruct(fit)
        if isfield(fit, 'exponential') && isfield(fit.exponential, 'tau')
            tau = fit.exponential.tau;
        elseif isfield(fit, 'best') && isfield(fit.best, 'tau')
            tau = fit.best.tau;
        elseif isfield(fit, 'tau')
            tau = fit.tau;
        end
    end
end

function y = smooth_causal(u, w)
    % Causal moving average of window w.
    k = ones(w, 1) / w;
    y = filter(k, 1, u);
end

function y = resample_timeline(u, w)
    % Stretch/compress the timeline by factor w via linear interpolation.
    % w>1 stretches (slower), w<1 compresses (faster).
    T = numel(u);
    t = (1:T)';
    tq = (1:1/w:T)';
    y = interp1(t, u, tq, 'linear', 'extrap');
end

function e = nrmse(yp, yt)
    yp = yp(:); yt = yt(:);
    e = sqrt(mean((yp - yt).^2)) / max(std(yt), eps);
end
