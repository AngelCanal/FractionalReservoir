function [params, meta] = default_MESN_config(overrides)
% default_MESN_config
% Shared reference configuration for the MESN/SRNN reservoir used throughout
% the characterisation suite.
%
% Usage:
%   [params, meta] = default_MESN_config();                 % defaults
%   [params, meta] = default_MESN_config(struct('n',300));  % override fields
%
% Construction order:
%   1. scalar base defaults
%   2. structural overrides (population counts, n_inputs, RNG seeds)
%   3. derived sizes, default tau_a arrays, generated W/W_in
%   4. nonstructural scalar overrides
%   5. explicit tau_a_*, W, and W_in overrides
%   6. validate_MESN_params

    if nargin < 1 || isempty(overrides)
        overrides = struct();
    end

    % -------------------------
    % 1. Scalar base defaults
    % -------------------------
    cfg = struct();
    cfg.n = 100;
    cfg.fraction_E = 0.5;
    cfg.n_inputs = 1;

    cfg.n_a_E = 3;
    cfg.n_a_I = 1;
    cfg.n_b_E = 1;
    cfg.n_b_I = 1;

    cfg.weight_rng_seed = 42;
    cfg.input_rng_seed = 43;

    cfg.dt = 0.1;
    cfg.tau_d = 0.55;

    cfg.c_E = 0.1/7;
    cfg.c_I = 0.1/4;

    cfg.tau_b_E_rec = 0.6;
    cfg.tau_b_E_rel = 0.1;
    cfg.tau_b_I_rec = 0.4;
    cfg.tau_b_I_rel = 0.5;

    cfg.lags = 0.03;

    cfg.S_a = 0.85;
    cfg.S_c = 0.4;

    cfg.input_scaling = 0.75;
    cfg.input_sparsity = 0.8;

    cfg.level_of_chaos = 1.7;
    cfg.row_center_W = false;
    cfg.dale = true;
    cfg.W_scale_method = 'abscissa';

    cfg.which_states = 'x';
    cfg.include_input = false;
    cfg.lambda = 1e-6;

    % -------------------------
    % 2. Structural overrides
    % -------------------------
    structural_fields = {'n', 'fraction_E', 'n_a_E', 'n_a_I', 'n_b_E', 'n_b_I', ...
        'n_inputs', 'weight_rng_seed', 'input_rng_seed'};
    cfg = apply_selected_overrides(cfg, overrides, structural_fields);

    % -------------------------
    % 3. Derived sizes and default tau arrays
    % -------------------------
    n = cfg.n;
    n_E = round(n * cfg.fraction_E);
    n_I = n - n_E;
    E_indices = 1:n_E;
    I_indices = (n_E+1):n;

    if cfg.n_a_E == 0
        cfg.tau_a_E = zeros(1, 0);
    else
        cfg.tau_a_E = logspace(log10(0.25), log10(25), cfg.n_a_E);
    end
    if cfg.n_a_I == 0
        cfg.tau_a_I = zeros(1, 0);
    else
        cfg.tau_a_I = logspace(log10(0.25), log10(25), cfg.n_a_I);
    end

    % -------------------------
    % 4. Nonstructural scalar overrides
    % -------------------------
    nonstructural_fields = {'dt', 'tau_d', 'c_E', 'c_I', ...
        'tau_b_E_rec', 'tau_b_E_rel', 'tau_b_I_rec', 'tau_b_I_rel', ...
        'lags', 'S_a', 'S_c', 'input_scaling', 'input_sparsity', ...
        'level_of_chaos', 'row_center_W', 'dale', 'W_scale_method', ...
        'which_states', 'include_input', 'lambda'};
    cfg = apply_selected_overrides(cfg, overrides, nonstructural_fields);

    if cfg.dale && cfg.row_center_W
        error('default_MESN_config:DaleCenteringUnsupported', ...
            'Row centering is incompatible with Dale sign constraints.');
    end

    if isfield(overrides, 'W')
        W0 = overrides.W;
        W = overrides.W;
        w_generated = false;
    else
        w_generated = true;
        weight_stream = RandStream('mt19937ar', 'Seed', cfg.weight_rng_seed);
        W0 = randn(weight_stream, n, n);
        if cfg.dale
            W0(:, E_indices) = abs(W0(:, E_indices));
            W0(:, I_indices) = -abs(W0(:, I_indices));
        end
        if cfg.row_center_W
            W0 = W0 - mean(W0, 2);
        end
        W = scale_recurrent_matrix(W0, cfg.level_of_chaos, cfg.W_scale_method);
    end

    if isfield(overrides, 'W_in')
        W_in = overrides.W_in;
    else
        input_stream = RandStream('mt19937ar', 'Seed', cfg.input_rng_seed);
        W_in = (2 * rand(input_stream, n, cfg.n_inputs) - 1) * cfg.input_scaling;
        if cfg.input_sparsity > 0
            mask = rand(input_stream, n, cfg.n_inputs) < (1 - cfg.input_sparsity);
            W_in = W_in .* mask;
        end
    end

    % -------------------------
    % 5. Explicit tau_a_* overrides
    % -------------------------
    if isfield(overrides, 'tau_a_E')
        cfg.tau_a_E = overrides.tau_a_E;
    end
    if isfield(overrides, 'tau_a_I')
        cfg.tau_a_I = overrides.tau_a_I;
    end

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

    % -------------------------
    % 6. Final validation
    % -------------------------
    params = validate_MESN_params(params);

    meta = struct();
    meta.cfg = cfg;
    meta.W0 = W0;
    meta.sign_violations_E = sum(W(:, E_indices) < 0, 'all');
    meta.sign_violations_I = sum(W(:, I_indices) > 0, 'all');
    if cfg.dale && w_generated
        assert(meta.sign_violations_E == 0 && meta.sign_violations_I == 0);
    end
end

function s = apply_selected_overrides(s, overrides, fields)
    for i = 1:numel(fields)
        field = fields{i};
        if isfield(overrides, field)
            s.(field) = overrides.(field);
        end
    end
end
