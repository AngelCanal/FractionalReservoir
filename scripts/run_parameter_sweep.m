%% run_parameter_sweep
% 1D parameter sweeps for MESN reservoir dynamics characterisation.
%
% Outputs are saved under results/parameter_sweeps/.

clear; clc;

if exist('setup_paths', 'file') == 2
    setup_paths();
end

out_dir = fullfile(pwd, 'results', 'parameter_sweeps');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

% -------------------------
% Sweep definition
% -------------------------
sweep = struct();
sweep.param_name = 'level_of_chaos'; % {'level_of_chaos','lags','tau_b_E_rec','c_E','input_scaling'}
sweep.values = linspace(0.7, 2.5, 20);

% -------------------------
% Input protocol
% -------------------------
dt = 0.1;
T_total = 4000;
T_washout = 1000;
rng(123);
U = 0.2 * randn(T_total, 1); % representative driving input

% -------------------------
% Lyapunov settings
% -------------------------
do_lyapunov = true;
lya_method = 'benettin';
ode_opts = odeset('RelTol', 1e-6, 'AbsTol', 1e-8);

% -------------------------
% Run sweep (parfor compatible)
% -------------------------
n_vals = numel(sweep.values);
results(n_vals) = struct(); %#ok<SAGROW>

fprintf('Running parameter sweep: %s (%d values)\n', sweep.param_name, n_vals);

parfor ii = 1:n_vals
    v = sweep.values(ii);

    overrides = struct();
    overrides.dt = dt;
    overrides.(sweep.param_name) = v;

    % Keep features as x for dynamics diagnostics
    overrides.which_states = 'x';
    overrides.include_input = false;

    [params, meta] = default_MESN_config(overrides);
    esn = SRNN_ESN(params);

    esn.resetState();
    [X_feat, S_hist] = esn.runReservoir(U);

    % Post-transient window
    x_post = X_feat((T_washout+1):end, :);

    % LLE (optional)
    LLE = nan;
    lya_results = struct();
    if do_lyapunov
        t_out = (0:(T_total-1))' * dt;
        fs = 1 / dt;
        T_interval = [t_out(T_washout+1), t_out(end)];

        % External input as used by SRNN_reservoir: u_ex = W_in * U'
        t_ex = t_out;
        u_ex = params.W_in * U';
        rhs_func = @(t, S) SRNN_reservoir(t, S, t_ex, u_ex, params);

        lya_results = compute_lyapunov_exponents(lya_method, S_hist, t_out, dt, fs, ...
            T_interval, params, ode_opts, @ode23s, rhs_func, t_ex, u_ex);

        if isfield(lya_results, 'LLE')
            LLE = lya_results.LLE;
        elseif isfield(lya_results, 'LE_spectrum') && ~isempty(lya_results.LE_spectrum)
            LLE = lya_results.LE_spectrum(1);
        end
    end

    % Regime classification
    [regime, diag] = classify_dynamical_regime(x_post, dt, LLE);

    % Spectral properties of W
    specW = compute_spectral_properties(params.W, params);

    r = struct();
    r.param_name = sweep.param_name;
    r.param_value = v;
    r.regime = regime;
    r.regime_diag = diag;
    r.LLE = LLE;
    r.specW = specW;
    r.meta = meta; %#ok<PFOUS> % meta contains W0/cfg, helpful for provenance
    results(ii) = r;
end

save_path = fullfile(out_dir, sprintf('sweep_%s_%s.mat', sweep.param_name, datestr(now, 'yyyymmdd_HHMMSS')));
save(save_path, 'sweep', 'results', 'dt', 'U', 'T_total', 'T_washout', 'do_lyapunov', 'lya_method');

% -------------------------
% Plot quick summary
% -------------------------
vals = sweep.values(:);
LLEs = arrayfun(@(s) s.LLE, results(:));
regimes = string({results.regime}');

figure('Color', 'w');
subplot(2,1,1);
plot(vals, LLEs, 'k.-', 'LineWidth', 1.5, 'MarkerSize', 12);
yline(0, 'r--');
xlabel(sweep.param_name, 'Interpreter', 'none');
ylabel('Largest Lyapunov exponent');
grid on;
title('Lyapunov vs parameter');

subplot(2,1,2);
cats = categories(categorical(regimes));
reg_idx = double(categorical(regimes, cats));
plot(vals, reg_idx, 'b.-', 'LineWidth', 1.5, 'MarkerSize', 12);
yticks(1:numel(cats));
yticklabels(cats);
xlabel(sweep.param_name, 'Interpreter', 'none');
ylabel('Regime');
grid on;
title('Regime classification');

fprintf('Saved sweep to %s\n', save_path);

