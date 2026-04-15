function [params, meta] = default_MESN_config(overrides)
% default_MESN_config
% Shared reference configuration for the MESN/SRNN reservoir used throughout
% the characterisation suite.
%
% Usage:
%   [params, meta] = default_MESN_config();                 % defaults
%   [params, meta] = default_MESN_config(struct('n',300));  % override fields
%
% Notes:
% - Defaults are aligned to the "full-biology" preset in test_reservoir_dynamics.m
%   (multi-timescale adaptation, STD enabled, inhibitory delay enabled).
% - Weight scaling uses the spectral abscissa convention:
%       gamma = 1 / max(real(eig(W0)))
%       W = level_of_chaos * gamma * W0

    if nargin < 1 || isempty(overrides)
        overrides = struct();
    end

    % -------------------------
    % Base scalar defaults
    % -------------------------
    cfg = struct();
    cfg.n = 100;
    cfg.fraction_E = 0.5;

    cfg.dt = 0.1;
    cfg.tau_d = 0.55;

    % Adaptation (SFA)
    cfg.n_a_E = 3;
    cfg.n_a_I = 1;
    cfg.tau_a_E = logspace(log10(0.25), log10(25), cfg.n_a_E);
    cfg.tau_a_I = logspace(log10(0.25), log10(25), cfg.n_a_I);
    cfg.c_E = 0.1/7;
    cfg.c_I = 0.1/4;

    % STD
    cfg.n_b_E = 1;
    cfg.n_b_I = 1;
    cfg.tau_b_E_rec = 0.6;
    cfg.tau_b_E_rel = 0.1;
    cfg.tau_b_I_rec = 0.4;
    cfg.tau_b_I_rel = 0.5;

    % Inhibitory delay (DDE mode) - scalar or vector of lags in seconds
    cfg.lags = 0.03;

    % Nonlinearity
    cfg.S_a = 0.85;
    cfg.S_c = 0.4;

    % Input weights
    cfg.input_scaling = 0.75;
    cfg.input_sparsity = 0.8; % fraction of rows set to zero (rand > 0.2 in test script)

    % Recurrent weights
    cfg.level_of_chaos = 1.7;
    cfg.weight_rng_seed = 42;
    cfg.input_rng_seed = 43; % by convention: weight_rng_seed + 1
    cfg.row_center_W = true;
    cfg.dale = true;
    cfg.W_scale_method = 'abscissa'; % 'abscissa' or 'radius'

    % ESN config
    cfg.which_states = 'x';
    cfg.include_input = false;
    cfg.lambda = 1e-6;

    % Allow overrides at the cfg level (before building W/W_in)
    cfg = apply_overrides(cfg, overrides);

    % Derived sizes
    n = cfg.n;
    n_E = round(n * cfg.fraction_E);
    n_I = n - n_E;
    E_indices = 1:n_E;
    I_indices = (n_E+1):n;

    % -------------------------
    % Build recurrent weights W
    % -------------------------
    rng(cfg.weight_rng_seed);
    W0 = randn(n, n);
    if cfg.dale
        W0(:, E_indices) = abs(W0(:, E_indices));
        W0(:, I_indices) = -abs(W0(:, I_indices));
    end
    if cfg.row_center_W
        W0 = W0 - mean(W0, 2);
    end

    W = scale_W(W0, cfg.level_of_chaos, cfg.W_scale_method);

    % -------------------------
    % Build input weights W_in
    % -------------------------
    rng(cfg.input_rng_seed);
    n_inputs = getFieldOrDefault(overrides, 'n_inputs', 1);
    W_in = (2 * rand(n, n_inputs) - 1) * cfg.input_scaling;
    if cfg.input_sparsity > 0
        mask = rand(n, n_inputs) < (1 - cfg.input_sparsity);
        W_in = W_in .* mask;
    end

    % -------------------------
    % Pack SRNN_ESN params
    % -------------------------
    activation_function = @(x) piecewiseSigmoid(x, cfg.S_a, cfg.S_c);
    activation_function_derivative = @(x) piecewiseSigmoidDerivative(x, cfg.S_a, cfg.S_c);

    params = struct();
    params.n = n;
    params.n_E = n_E;
    params.n_I = n_I;
    params.E_indices = E_indices;
    params.I_indices = I_indices;

    params.W = W;
    params.W_in = W_in;

    params.tau_d = cfg.tau_d;
    params.dt = cfg.dt;

    params.n_a_E = cfg.n_a_E;
    params.n_a_I = cfg.n_a_I;
    params.tau_a_E = cfg.tau_a_E;
    params.tau_a_I = cfg.tau_a_I;
    params.c_E = cfg.c_E;
    params.c_I = cfg.c_I;

    params.n_b_E = cfg.n_b_E;
    params.n_b_I = cfg.n_b_I;
    params.tau_b_E_rec = cfg.tau_b_E_rec;
    params.tau_b_E_rel = cfg.tau_b_E_rel;
    params.tau_b_I_rec = cfg.tau_b_I_rec;
    params.tau_b_I_rel = cfg.tau_b_I_rel;

    params.lags = cfg.lags;
    params.activation_function = activation_function;
    params.activation_function_derivative = activation_function_derivative;

    params.which_states = cfg.which_states;
    params.include_input = cfg.include_input;
    params.lambda = cfg.lambda;

    % Final field-level overrides (after packing), so callers can directly
    % override any SRNN_ESN params including W/W_in if desired.
    params = apply_overrides(params, overrides);

    meta = struct();
    meta.cfg = cfg;
    meta.W0 = W0;
end

% -------------------------
% Local helpers
% -------------------------
function s = apply_overrides(s, overrides)
    if isempty(overrides)
        return;
    end
    f = fieldnames(overrides);
    for i = 1:numel(f)
        s.(f{i}) = overrides.(f{i});
    end
end

function W = scale_W(W0, level_of_chaos, method)
    W = W0;
    W_eigs = eig(W);
    switch lower(method)
        case 'abscissa'
            abscissa_0 = max(real(W_eigs));
            if abscissa_0 == 0
                gamma = 1;
            else
                gamma = 1 / abscissa_0;
            end
            W = level_of_chaos * gamma * W;
        case 'radius'
            rho0 = max(abs(W_eigs));
            if rho0 == 0
                gamma = 1;
            else
                gamma = 1 / rho0;
            end
            W = level_of_chaos * gamma * W;
        otherwise
            error('default_MESN_config:InvalidScaleMethod', ...
                'Unknown W_scale_method: %s (use ''abscissa'' or ''radius'')', method);
    end
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

