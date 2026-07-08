%% run_meanfield_adaptation_bifurcation
% Reduced mean-field bifurcation analysis: how adaptation strength and the
% inhibitory delay move the E-I-STD-DDE model into the useful (stable,
% low-dimensional) regime (Result 4 of the paper workplan).
%
% This deliberately uses ONLY the reduced 4-variable mean-field model
% (meanfield_EI_STD_DDE.m); no large-network continuation is attempted, per
% the meeting note "forget about bifurcation analysis for big networks, maybe
% just for a single equation".
%
% Two figures:
%   (1) 1D bifurcation diagram vs adaptation strength c_a: for each c_a we
%       integrate the DDE, discard the transient, and plot the range
%       [min, max] of E(t). A collapse of the range to a point marks the
%       Hopf-like transition from oscillation to a stable fixed point -- the
%       adaptation-induced entry into the stable regime.
%   (2) 2D regime map in (c_a, tau_delay): oscillatory (variance above
%       threshold) vs fixed point, showing that both adaptation and delay
%       shape the boundary.
%
% Output: results/meanfield_bifurcation/adaptation_<timestamp>.mat + figures.

clear; clc;

if exist('setup_paths', 'file') == 2
    setup_paths();
end

out_dir = fullfile(pwd, 'results', 'meanfield_bifurcation');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

timestamp = datestr(now, 'yyyymmdd_HHMMSS');

%% Integration settings
tspan = [0, 600];
y0 = [0.1; 0.1; 0.0; 1.0];
history = @(t) y0;
opts = ddeset('RelTol', 1e-7, 'AbsTol', 1e-9);
dt_eval = 0.05;
tt = (tspan(1):dt_eval:tspan(2))';
keep = tt > 0.6 * tspan(2);   % discard transient

%% -------------------------
% (1) 1D bifurcation vs adaptation strength c_a
% -------------------------
ca_vals = linspace(0.0, 3.0, 40);
Emin = nan(numel(ca_vals), 1);
Emax = nan(numel(ca_vals), 1);
Evar = nan(numel(ca_vals), 1);
Efreq = nan(numel(ca_vals), 1);

for ii = 1:numel(ca_vals)
    mf = meanfield_EI_STD_DDE(struct('c_a', ca_vals(ii), 'tau_delay', 0.05));
    sol = dde23(mf.rhs_dde23, mf.lags, history, tspan, opts);
    yy = deval(sol, tt)';
    E = yy(keep, 1);
    Emin(ii) = min(E);
    Emax(ii) = max(E);
    Evar(ii) = var(E, 1);
    Efreq(ii) = dominant_freq(E, dt_eval);
end

%% -------------------------
% (2) 2D regime map in (c_a, tau_delay)
% -------------------------
ca_grid = linspace(0.0, 3.0, 24);
delay_grid = linspace(0.0, 0.20, 24);
VAR = nan(numel(ca_grid), numel(delay_grid));

for ic = 1:numel(ca_grid)
    for id = 1:numel(delay_grid)
        d = delay_grid(id);
        mf = meanfield_EI_STD_DDE(struct('c_a', ca_grid(ic), 'tau_delay', d));
        if d <= 0
            % Degenerates to an ODE; integrate with a tiny delay to reuse dde23
            mf = meanfield_EI_STD_DDE(struct('c_a', ca_grid(ic), 'tau_delay', 1e-4));
        end
        try
            sol = dde23(mf.rhs_dde23, mf.lags, history, tspan, opts);
            yy = deval(sol, tt)';
            E = yy(keep, 1);
            VAR(ic, id) = var(E, 1);
        catch
            VAR(ic, id) = NaN;
        end
    end
end

osc_thresh = 1e-5;   % variance above this => sustained oscillation
REGIME = double(VAR > osc_thresh);

%% Save
save_path = fullfile(out_dir, sprintf('adaptation_%s.mat', timestamp));
save(save_path, 'ca_vals', 'Emin', 'Emax', 'Evar', 'Efreq', ...
    'ca_grid', 'delay_grid', 'VAR', 'REGIME', 'osc_thresh', 'tspan');

%% Figures
figure('Color', 'w');
subplot(1,2,1); hold on;
plot(ca_vals, Emin, 'b.-', 'LineWidth', 1.2);
plot(ca_vals, Emax, 'r.-', 'LineWidth', 1.2);
xlabel('adaptation strength c_a');
ylabel('E(t) range [min, max] (post-transient)');
title('Mean-field bifurcation vs adaptation');
legend('min E', 'max E', 'Location', 'best'); grid on;

subplot(1,2,2);
imagesc(delay_grid, ca_grid, REGIME);
set(gca, 'YDir', 'normal');
colormap(gca, [0.4 0.7 0.9; 0.85 0.4 0.4]); % fixed point (blue) / oscillation (red)
cb = colorbar; cb.Ticks = [0.25 0.75]; cb.TickLabels = {'fixed point', 'oscillation'};
xlabel('inhibitory delay \tau_{delay}');
ylabel('adaptation strength c_a');
title('Regime map (c_a, \tau_{delay})');

fprintf('Saved mean-field adaptation bifurcation to %s\n', save_path);

% -------------------------------------------------------------------------
function f0 = dominant_freq(x, dt)
    x = x(:) - mean(x, 'omitnan');
    if numel(x) < 64
        f0 = 0; return;
    end
    fs = 1 / dt;
    nfft = 2^nextpow2(numel(x));
    X = fft(x, nfft);
    P1 = abs(X(1:nfft/2+1)).^2;
    f = fs * (0:nfft/2) / nfft;
    if numel(P1) > 1
        [~, idx] = max(P1(2:end));
        f0 = f(idx + 1);
    else
        f0 = 0;
    end
end
