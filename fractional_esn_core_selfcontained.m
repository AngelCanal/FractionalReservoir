%% FRACTIONAL_ESN_CORE_SELFCONTAINED
% Self-contained reference for the FractionalReservoir ESN dynamical core.
% No addpath, no other project files — paste this single .m file as documentation
% or runnable sanity check.
%
% "Fractional" here = multiple parallel spike-frequency adaptation variables per
% neuron with distinct time constants tau_a (power-law-like memory in time), not
% a Caputo fractional derivative in the mathematical sense. Dynamics are
% first-order ODEs (same structure as src/SRNN_reservoir.m).
%
% State vector S = [ a_E(:); a_I(:); b_E(:); b_I(:); x(:) ]
%   a_*  — adaptation states (n_E x n_a_E) and (n_I x n_a_I) vectorized
%   b_*  — short-term depression (STD) resources in [0,1], per neuron if enabled
%   x    — dendritic / synaptic drive (low-pass filtered by tau_d)
%
% Equations (continuous time):
%   x_eff_i = x_i - c_E*sum_k a_E(i,k)   on E indices, analogous on I with c_I
%   r_i     = phi(x_eff_i)               firing rate nonlinearity
%   dx/dt   = ( -x + W * (b .* r) + u(t) ) / tau_d
%   da_E/dt = ( r_E - a_E ) ./ tau_a_E   elementwise/broadcast (n_E x n_a_E)
%   da_I/dt = ( r_I - a_I ) ./ tau_a_I
%   db_E/dt = (1-b_E)/tau_rec - (b_E .* r_E)/tau_rel   (if STD on E; same pattern for I)
%
% STD: b_i multiplies presynaptic rate in the recurrent term W*(b.*r); b=1 if STD off.
%
% Matrix W (Dale's law + chaos margin):
%   Random Gaussian, E columns >= 0, I columns <= 0, row-mean removed,
%   scaled to spectral radius rho(W)=spectral_radius, then
%   W_final = level_of_chaos * gamma * W  with gamma = 1 / max(real(eig(W_scaled)))
%   so the scaled matrix has abscissa max Re(lambda) = level_of_chaos.
%
% Optional transmission delay (DDE-style): for discrete lags lag_k (seconds),
% use W_components{1}=W0 (instantaneous), W_components{k+1}=Wk, and
%   input_rec = W0*(b.*r)(t) + sum_k Wk * (b.*r)(t - lag_k)
% with a DDE solver; da/db still use r(t). Default run below uses instantaneous W only.
%
% No plots, readout training, Jacobians, sensitivity, or memory capacity.

%% --- Architecture & hyperparameters (edit freely) ---
n           = 40;
fraction_E  = 0.5;
n_E         = round(n * fraction_E);
n_I         = n - n_E;
E_indices   = 1:n_E;
I_indices   = (n_E + 1):n;

% Multiple adaptation timescales (the "fractional" richness)
n_a_E       = 3;
n_a_I       = 2;
tau_a_E     = logspace(log10(0.25), log10(25), n_a_E);
tau_a_I     = logspace(log10(0.25), log10(25), n_a_I);
c_E         = 0.1 / max(n_a_E, 1);
c_I         = 0.1;

% Short-term depression (STD): set n_b_E = 0 to disable
n_b_E       = 1;
n_b_I       = 0;
tau_b_E_rec = 2.0;   % recovery time constant
tau_b_E_rel = 0.5;   % release / usage time constant
tau_b_I_rec = inf;
tau_b_I_rel = inf;

% Dendritic low-pass (sets effective integration / "delay" of x vs input+recurrence)
tau_d       = 0.1;

% Input channel
n_inputs    = 1;
input_scaling = 0.5;
rng_seed    = 42;

% Recurrent weights
spectral_radius = 1.0;
level_of_chaos  = 1.5;

% Activation: hard-sigmoid with threshold (example from example_srnn_esn.m)
a0_thresh   = 0.5;
activation_function = @(x) min(max(0, x - a0_thresh), 1);

%% --- Build W, W_in, chaos scaling ---
rng(rng_seed);
[W, chaos_info] = build_recurrent_W(n, n_E, n_I, spectral_radius, level_of_chaos);
W_in = build_input_weights(n, n_inputs, input_scaling);

%% --- Pack params for RHS ---
params = struct();
params.n = n;
params.n_E = n_E;
params.n_I = n_I;
params.E_indices = E_indices;
params.I_indices = I_indices;
params.n_a_E = n_a_E;
params.n_a_I = n_a_I;
params.n_b_E = n_b_E;
params.n_b_I = n_b_I;
params.W = W;
params.tau_d = tau_d;
params.tau_a_E = tau_a_E;
params.tau_a_I = tau_a_I;
params.tau_b_E_rec = tau_b_E_rec;
params.tau_b_E_rel = tau_b_E_rel;
params.tau_b_I_rec = tau_b_I_rec;
params.tau_b_I_rel = tau_b_I_rel;
params.c_E = c_E;
params.c_I = c_I;
params.activation_function = activation_function;

%% --- Initial state (b = 1 = no depression) ---
S0 = initial_state(n, n_E, n_I, n_a_E, n_a_I, n_b_E, n_b_I);

%% --- Minimal drive: short random input trajectory, one ODE solve ---
n_steps = 80;
dt      = 1.0;
t_u     = (0:n_steps-1)' * dt;
U_in    = randn(n_steps, n_inputs);              % raw inputs
u_ex    = W_in * U_in';                           % n x n_steps drive to neurons

t_span  = [t_u(1), t_u(end)];
odefun  = @(t, S) esn_reservoir_rhs(t, S, t_u, u_ex, params);
opts    = odeset('RelTol', 1e-6, 'AbsTol', 1e-8);
[~, S_hist] = ode23s(odefun, t_span, S0, opts);

S_final = S_hist(end, :)';
% Base workspace now holds W, W_in, params, chaos_info, S_final, S_hist, etc.

% -------------------------------------------------------------------------
function [W, info] = build_recurrent_W(n, n_E, n_I, spectral_radius, level_of_chaos)
    W = randn(n, n);
    W(:, 1:n_E) = abs(W(:, 1:n_E));
    W(:, n_E+1:end) = -abs(W(:, n_E+1:end));
    W = W - mean(W, 2);
    lam = eig(W);
    rho = max(abs(lam));
    W = (spectral_radius / rho) * W;
    abscissa_0 = max(real(eig(W)));
    gamma = 1 / abscissa_0;
    W = level_of_chaos * gamma * W;
    info = struct('spectral_radius_target', spectral_radius, ...
        'rho_before_chaos_scale', rho, ...
        'abscissa_after_rho_scale', abscissa_0, ...
        'gamma', gamma, ...
        'level_of_chaos', level_of_chaos);
end

function W_in = build_input_weights(n, n_inputs, input_scaling)
    W_in = (2 * rand(n, n_inputs) - 1) * input_scaling;
end

function S0 = initial_state(n, n_E, n_I, n_a_E, n_a_I, n_b_E, n_b_I)
    len_a_E = n_E * n_a_E;
    len_a_I = n_I * n_a_I;
    len_b_E = n_E * n_b_E;
    len_b_I = n_I * n_b_I;
    len_x = n;
    S0 = zeros(len_a_E + len_a_I + len_b_E + len_b_I + len_x, 1);
    if n_b_E > 0
        i0 = len_a_E + len_a_I;
        S0(i0 + (1:len_b_E)) = 1;
    end
    if n_b_I > 0
        i0 = len_a_E + len_a_I + len_b_E;
        S0(i0 + (1:len_b_I)) = 1;
    end
end

function dS_dt = esn_reservoir_rhs(t, S, t_ex, u_ex, params)
    % Interpolate drive u(t) from columns of u_ex (n x T) at times t_ex.
    if numel(t_ex) < 2
        u = u_ex(:, 1);
    else
        u = interp1(t_ex, u_ex', t, 'linear', 'extrap')';
    end

    n = params.n;
    n_E = params.n_E;
    n_I = params.n_I;
    E_indices = params.E_indices;
    I_indices = params.I_indices;
    n_a_E = params.n_a_E;
    n_a_I = params.n_a_I;
    n_b_E = params.n_b_E;
    n_b_I = params.n_b_I;
    W = params.W;
    tau_d = params.tau_d;
    tau_a_E = params.tau_a_E;
    tau_a_I = params.tau_a_I;
    tau_b_E_rec = params.tau_b_E_rec;
    tau_b_E_rel = params.tau_b_E_rel;
    tau_b_I_rec = params.tau_b_I_rec;
    tau_b_I_rel = params.tau_b_I_rel;
    c_E = params.c_E;
    c_I = params.c_I;
    phi = params.activation_function;

    current_idx = 0;
    len_a_E = n_E * n_a_E;
    if len_a_E > 0
        a_E = reshape(S(current_idx + (1:len_a_E)), n_E, n_a_E);
    else
        a_E = [];
    end
    current_idx = current_idx + len_a_E;

    len_a_I = n_I * n_a_I;
    if len_a_I > 0
        a_I = reshape(S(current_idx + (1:len_a_I)), n_I, n_a_I);
    else
        a_I = [];
    end
    current_idx = current_idx + len_a_I;

    len_b_E = n_E * n_b_E;
    if len_b_E > 0
        b_E = S(current_idx + (1:len_b_E));
    else
        b_E = [];
    end
    current_idx = current_idx + len_b_E;

    len_b_I = n_I * n_b_I;
    if len_b_I > 0
        b_I = S(current_idx + (1:len_b_I));
    else
        b_I = [];
    end
    current_idx = current_idx + len_b_I;

    x = S(current_idx + (1:n));

    x_eff = x;
    if n_E > 0 && n_a_E > 0 && ~isempty(a_E)
        x_eff(E_indices) = x_eff(E_indices) - c_E * sum(a_E, 2);
    end
    if n_I > 0 && n_a_I > 0 && ~isempty(a_I)
        x_eff(I_indices) = x_eff(I_indices) - c_I * sum(a_I, 2);
    end

    b = ones(n, 1);
    if n_b_E > 0 && ~isempty(b_E)
        b(E_indices) = b_E;
    end
    if n_b_I > 0 && ~isempty(b_I)
        b(I_indices) = b_I;
    end

    r = phi(x_eff);
    dx_dt = (-x + W * (b .* r) + u) / tau_d;

    da_E_dt = [];
    if n_E > 0 && n_a_E > 0 && ~isempty(a_E)
        da_E_dt = (r(E_indices) - a_E) ./ tau_a_E;
    end

    da_I_dt = [];
    if n_I > 0 && n_a_I > 0 && ~isempty(a_I)
        da_I_dt = (r(I_indices) - a_I) ./ tau_a_I;
    end

    db_E_dt = [];
    if n_E > 0 && n_b_E > 0 && ~isempty(b_E)
        db_E_dt = (1 - b_E) / tau_b_E_rec - (b_E .* r(E_indices)) / tau_b_E_rel;
    end

    db_I_dt = [];
    if n_I > 0 && n_b_I > 0 && ~isempty(b_I)
        db_I_dt = (1 - b_I) / tau_b_I_rec - (b_I .* r(I_indices)) / tau_b_I_rel;
    end

    dS_dt = [da_E_dt(:); da_I_dt(:); db_E_dt(:); db_I_dt(:); dx_dt];
end
