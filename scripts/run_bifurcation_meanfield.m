%% run_bifurcation_meanfield
% Reduced mean-field bifurcation analysis scaffold.
%
% This script supports two modes:
%   1) If DDE-BIFTOOL is available on the MATLAB path, it prepares the
%      sys_funcs structure for continuation workflows (equilibria, Hopf, etc.).
%   2) If not available, it runs a "bifurcation-like" sweep using dde23 and
%      saves diagnostics (variance, dominant frequency) vs parameter.

clear; clc;

if exist('setup_paths', 'file') == 2
    setup_paths();
end

out_dir = fullfile(pwd, 'results', 'meanfield_bifurcation');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

% Build mean-field model (defaults can be overridden here)
mf = meanfield_EI_STD_DDE(struct('tau_delay', 0.05));
par = mf.par;

% Sweep parameter: IextE
idx_IextE = find(strcmp(mf.par_names, 'IextE'));
Iext_vals = linspace(0.0, 2.0, 40);

% Check for DDE-BIFTOOL presence (heuristic)
has_ddebiftool = exist('set_funcs', 'file') == 2 && exist('df_brnch', 'file') == 2;

if has_ddebiftool
    fprintf('DDE-BIFTOOL detected. Preparing sys_funcs scaffold...\n');

    % Minimal sys_funcs for a single-delay DDE:
    % - sys_rhs: rhs function
    % - sys_tau: returns delay(s)
    sys_rhs = @(xx, p) meanfield_EI_STD_DDE_rhs(xx, p);
    sys_tau = @(ind, p) p(13); % tau_delay

    funcs = set_funcs('sys_rhs', sys_rhs, 'sys_tau', sys_tau);

    % At this point you can proceed with standard DDE-BIFTOOL workflows:
    %  - Setup steady-state branch vs IextE
    %  - Continue equilibria, detect Hopf, continue periodic orbits, etc.
    %
    % For example (pseudo-code):
    %   [br, suc] = SetupStst(funcs, 'x', x0, 'parameter', par, ...
    %        'contpar', idx_IextE, 'max_step', [idx_IextE 0.05]);
    %   br = br_contn(funcs, br, 200);
    %   br = br_stabl(funcs, br, 0, 1);
    %
    % This repository does not vendor DDE-BIFTOOL; install it separately and add
    % it to your MATLAB path to use continuation.
    save(fullfile(out_dir, 'ddebiftool_scaffold.mat'), 'mf', 'funcs', 'idx_IextE', 'Iext_vals');
    fprintf('Saved scaffold to results/meanfield_bifurcation/\n');
else
    fprintf('DDE-BIFTOOL not found. Running dde23 sweep instead...\n');

    % dde23 sweep settings
    tspan = [0, 500];
    y0 = [0.1; 0.1; 0.0; 1.0];
    history = @(t) y0;
    opts = ddeset('RelTol', 1e-7, 'AbsTol', 1e-9);

    diagnostics = struct('IextE', num2cell(Iext_vals), ...
                         'varE', [], 'varI', [], 'domFreqE', [], 'domFreqI', []);

    for ii = 1:numel(Iext_vals)
        par2 = par;
        par2(idx_IextE) = Iext_vals(ii);

        sol = dde23(@(t, y, Z) mf.rhs_dde23(t, y, Z), mf.lags, history, tspan, opts);

        % Evaluate on a uniform grid
        dt_eval = 0.1;
        tt = (tspan(1):dt_eval:tspan(2))';
        yy = deval(sol, tt)'; % (T x 4)

        % Discard transient
        keep = tt > (tspan(2) * 0.5);
        E = yy(keep, 1);
        I = yy(keep, 2);

        diagnostics(ii).varE = var(E, 1);
        diagnostics(ii).varI = var(I, 1);
        diagnostics(ii).domFreqE = dominant_freq(E, dt_eval);
        diagnostics(ii).domFreqI = dominant_freq(I, dt_eval);
    end

    save_path = fullfile(out_dir, sprintf('dde23_sweep_%s.mat', datestr(now, 'yyyymmdd_HHMMSS')));
    save(save_path, 'mf', 'par', 'Iext_vals', 'diagnostics');

    figure('Color','w');
    subplot(2,1,1);
    plot(Iext_vals, [diagnostics.varE], 'r.-', 'LineWidth', 1.5); hold on;
    plot(Iext_vals, [diagnostics.varI], 'b.-', 'LineWidth', 1.5);
    xlabel('IextE'); ylabel('variance'); grid on; legend('E','I');
    title('Mean-field variance vs IextE');

    subplot(2,1,2);
    plot(Iext_vals, [diagnostics.domFreqE], 'r.-', 'LineWidth', 1.5); hold on;
    plot(Iext_vals, [diagnostics.domFreqI], 'b.-', 'LineWidth', 1.5);
    xlabel('IextE'); ylabel('dominant frequency (Hz)'); grid on; legend('E','I');
    title('Mean-field dominant frequency vs IextE');

    fprintf('Saved dde23 sweep to %s\n', save_path);
end

function f0 = dominant_freq(x, dt)
    x = x(:) - mean(x, 'omitnan');
    if numel(x) < 64
        f0 = 0;
        return;
    end
    fs = 1 / dt;
    nfft = 2^nextpow2(numel(x));
    X = fft(x, nfft);
    P2 = abs(X).^2;
    P1 = P2(1:nfft/2+1);
    f = fs*(0:nfft/2)/nfft;
    % ignore DC
    if numel(P1) > 1
        [~, idx] = max(P1(2:end));
        f0 = f(idx+1);
    else
        f0 = 0;
    end
end

