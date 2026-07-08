%% run_parameter_grid
% Multi-parameter grid characterisation of the MESN reservoir (Result 2).
%
% Generalisation of run_parameter_sweep.m from a single 1D sweep to an
% N-dimensional grid over any subset of MESN parameters. For each network in
% the grid it records:
%   - largest Lyapunov exponent (Benettin) and, optionally, the QR spectrum
%   - dynamical regime (classify_dynamical_regime)
%   - Echo State Property (verify_echo_state_property)
%   - spectral + non-normality properties of W (Kreiss, departure, transient)
%   - linear memory capacity (for the memory-vs-nonnormality correlation)
%
% This is the "simulate a lot of networks and relate time constant and SFA/STD
% to the Lyapunov exponent" experiment from the project notes.
%
% Configure the `grid_params` struct below: each field is a parameter name
% mapped to a vector of values. The full Cartesian product is swept with a
% flattened parfor loop.
%
% Output: results/parameter_grid/grid_<timestamp>.mat plus summary figures.

clear; clc;

if exist('setup_paths', 'file') == 2
    setup_paths();
end

out_dir = fullfile(pwd, 'results', 'parameter_grid');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

%% -------------------------
% Grid definition (edit here)
% -------------------------
% Any subset of default_MESN_config fields. Vectors of arbitrary length.
grid_params = struct();
grid_params.tau_d          = [0.30, 0.55, 0.90];     % membrane time constant
grid_params.c_E            = (0.1/7) * [0, 1, 2, 4]; % SFA strength (E); scale c_I with it
grid_params.level_of_chaos = linspace(0.9, 2.7, 8);  % spectral scaling of W

% c_I is tied to c_E via a fixed ratio (Dale-consistent adaptation scaling).
cI_over_cE = (0.1/4) / (0.1/7);

%% -------------------------
% Analysis configuration
% -------------------------
dt = 0.1;
T_total = 4000;
T_washout = 1000;
rng(123);
U = 0.2 * randn(T_total, 1);

do_lyapunov = true;
lya_method = 'benettin';          % 'benettin' (LLE) or 'qr' (full spectrum)
do_esp = true;
do_memory = true;                 % linear memory capacity per network
do_nonnormality = true;

ode_opts = odeset('RelTol', 1e-6, 'AbsTol', 1e-8);

%% -------------------------
% Build the Cartesian product
% -------------------------
pnames = fieldnames(grid_params);
n_dims = numel(pnames);
dim_sizes = cellfun(@(f) numel(grid_params.(f)), pnames);
n_cells = prod(dim_sizes);

fprintf('Parameter grid: %d dimensions, sizes [%s], %d networks total\n', ...
    n_dims, num2str(dim_sizes(:)'), n_cells);

results(n_cells) = struct(); %#ok<SAGROW>

parfor lin = 1:n_cells
    % Recover the multi-index for this flat index
    sub = cell(1, n_dims);
    [sub{:}] = ind2sub(dim_sizes(:)', lin);

    overrides = struct();
    overrides.dt = dt;
    overrides.which_states = 'x';
    overrides.include_input = false;

    pv = struct();
    for d = 1:n_dims
        name = pnames{d};
        val = grid_params.(name)(sub{d});
        overrides.(name) = val;
        pv.(name) = val;
    end
    % Tie c_I to c_E if c_E is being swept
    if isfield(overrides, 'c_E')
        overrides.c_I = overrides.c_E * cI_over_cE;
        pv.c_I = overrides.c_I;
    end

    params = default_MESN_config(overrides);

    % N_sys_eqs (needed by the QR Lyapunov method)
    len_a_E = params.n_E * params.n_a_E;
    len_a_I = params.n_I * params.n_a_I;
    len_b_E = params.n_E * params.n_b_E;
    len_b_I = params.n_I * params.n_b_I;
    params.N_sys_eqs = len_a_E + len_a_I + len_b_E + len_b_I + params.n;

    esn = SRNN_ESN(params);
    esn.resetState();
    [X_feat, S_hist] = esn.runReservoir(U);
    x_post = X_feat((T_washout+1):end, :);

    % ---- Lyapunov ----
    LLE = nan;
    LE_spectrum = [];
    if do_lyapunov
        t_out = (0:(T_total-1))' * dt;
        fs = 1 / dt;
        T_interval = [t_out(T_washout+1), t_out(end)];
        t_ex = t_out;
        u_ex = params.W_in * U';
        rhs_func = @(t, S) SRNN_reservoir(t, S, t_ex, u_ex, params);
        lr = compute_lyapunov_exponents(lya_method, S_hist, t_out, dt, fs, ...
            T_interval, params, ode_opts, @ode23s, rhs_func, t_ex, u_ex);
        if isfield(lr, 'LLE')
            LLE = lr.LLE;
        elseif isfield(lr, 'LE_spectrum') && ~isempty(lr.LE_spectrum)
            LE_spectrum = lr.LE_spectrum;
            LLE = lr.LE_spectrum(1);
        end
    end

    % ---- Regime ----
    [regime, regime_diag] = classify_dynamical_regime(x_post, dt, LLE);

    % ---- Spectral + non-normality ----
    % Keep the per-network non-normality cost tractable across the grid:
    % skip the transient-growth expm envelope and use a coarser Kreiss grid.
    nn_opts = struct('do_nonnormality', do_nonnormality, ...
        'do_transient', false, 'n_eta', 12, 'n_omega', 61);
    specW = compute_spectral_properties(params.W, params, nn_opts);

    % ---- ESP ----
    esp_holds = NaN; esp_spread = NaN;
    if do_esp
        esp = verify_echo_state_property(esn, U, struct('n_ic', 10, ...
            'washout_steps', T_washout, 'eps_tol', 1e-3, 'feature_mode', 'x', ...
            'verbose', false));
        esp_holds = esp.esp_holds;
        esp_spread = esp.final_spread;
    end

    % ---- Memory capacity ----
    MC_total = NaN;
    if do_memory
        try
            mc = compute_memory_capacity(esn, struct('T', 4000, 'K_max', 120, ...
                'washout', 200, 'lambda', params.lambda, 'feature_mode', 'x'));
            MC_total = mc.MC_total;
        catch
            MC_total = NaN;
        end
    end

    r = struct();
    r.param_values = pv;
    r.LLE = LLE;
    r.LE_spectrum = LE_spectrum;
    r.regime = regime;
    r.regime_diag = regime_diag;
    r.specW = specW;
    r.esp_holds = esp_holds;
    r.esp_spread = esp_spread;
    r.MC_total = MC_total;
    results(lin) = r;
end

save_path = fullfile(out_dir, sprintf('grid_%s.mat', datestr(now, 'yyyymmdd_HHMMSS')));
save(save_path, 'grid_params', 'pnames', 'dim_sizes', 'results', ...
    'dt', 'U', 'T_total', 'T_washout', 'lya_method', '-v7.3');

%% -------------------------
% Quick summary figures
% -------------------------
LLEs = arrayfun(@(s) s.LLE, results(:));
MCs  = arrayfun(@(s) s.MC_total, results(:));
kreiss = arrayfun(@(s) getfield_safe(s.specW, 'nonnormality', 'kreiss_lb'), results(:));
esp_flags = arrayfun(@(s) double(s.esp_holds), results(:));

figure('Color', 'w');
subplot(1,2,1);
scatter(kreiss, LLEs, 30, esp_flags, 'filled');
xlabel('Kreiss constant (lower bound) of W');
ylabel('Largest Lyapunov exponent');
yline(0, 'r--'); grid on; colorbar;
title('LLE vs non-normality (color = ESP holds)');

subplot(1,2,2);
scatter(kreiss, MCs, 30, LLEs, 'filled');
xlabel('Kreiss constant (lower bound) of W');
ylabel('Total linear memory capacity');
grid on; cb = colorbar; ylabel(cb, 'LLE');
title('Memory vs non-normality');

fprintf('Saved parameter grid to %s\n', save_path);

% -------------------------------------------------------------------------
function v = getfield_safe(s, f1, f2)
    if isfield(s, f1) && isstruct(s.(f1)) && isfield(s.(f1), f2)
        v = s.(f1).(f2);
    else
        v = NaN;
    end
end
