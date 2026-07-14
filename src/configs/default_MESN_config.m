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
%
% Publication protocols must supply explicit tau_a_* (see mechanism_ablation_config).
% The logspace defaults below remain for legacy/non-publication callers only.
%
% input_mask_mode:
%   'bernoulli'   — legacy independent Bernoulli mask (backward compatible)
%   'fixed_count' — exactly k=max(1,round((1-input_sparsity)*n)) driven neurons
%                   per input channel (publication-safe)
%
% adaptation_initialization_mode:
%   'legacy_independent'     — independent random a per filter (legacy)
%   'paired_weighted_match'  — one base value/neuron, repeated across filters so
%                              sum(c_k a_k) matches the single-filter control

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
    cfg.state_rng_seed = 42;

    cfg.dt = 0.1;
    cfg.tau_d = 0.55;

    cfg.tau_b_E_rec = 0.6;
    cfg.tau_b_E_rel = 0.1;
    cfg.tau_b_I_rec = 0.4;
    cfg.tau_b_I_rel = 0.5;

    cfg.lags = 0.03;

    cfg.S_a = 0.85;
    cfg.S_c = 0.4;

    cfg.input_scaling = 0.75;
    cfg.input_sparsity = 0.8;
    cfg.input_mask_mode = 'bernoulli';  % legacy default; publication uses fixed_count

    cfg.level_of_chaos = 1.7;
    cfg.row_center_W = false;
    cfg.dale = true;
    cfg.W_scale_method = 'abscissa';

    cfg.which_states = 'x';
    cfg.include_input = false;
    cfg.lambda = 1e-6;
    cfg.adaptation_initialization_mode = 'legacy_independent';

    % -------------------------
    % 2. Structural overrides
    % -------------------------
    structural_fields = {'n', 'fraction_E', 'n_a_E', 'n_a_I', 'n_b_E', 'n_b_I', ...
        'n_inputs', 'weight_rng_seed', 'input_rng_seed', 'state_rng_seed'};
    cfg = apply_selected_overrides(cfg, overrides, structural_fields);

    % -------------------------
    % 3. Derived sizes and default tau arrays
    % -------------------------
    n = cfg.n;
    n_E = round(n * cfg.fraction_E);
    n_I = n - n_E;
    E_indices = 1:n_E;
    I_indices = (n_E+1):n;

    % Legacy default only: publication profiles always override tau_a_* explicitly.
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
    nonstructural_fields = {'dt', 'tau_d', 'c_E', 'c_I', 'c_a_E', 'c_a_I', ...
        'tau_b_E_rec', 'tau_b_E_rel', 'tau_b_I_rec', 'tau_b_I_rel', ...
        'lags', 'S_a', 'S_c', 'input_scaling', 'input_sparsity', ...
        'input_mask_mode', 'adaptation_initialization_mode', ...
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

    input_driven_indices = {};
    input_nnz_per_channel = zeros(1, 0);
    if isfield(overrides, 'W_in')
        W_in = overrides.W_in;
        input_driven_indices = cell(1, size(W_in, 2));
        input_nnz_per_channel = zeros(1, size(W_in, 2));
        for j = 1:size(W_in, 2)
            input_driven_indices{j} = find(W_in(:, j) ~= 0);
            input_nnz_per_channel(j) = numel(input_driven_indices{j});
        end
    else
        input_stream = RandStream('mt19937ar', 'Seed', cfg.input_rng_seed);
        W_in = (2 * rand(input_stream, n, cfg.n_inputs) - 1) * cfg.input_scaling;
        [W_in, input_driven_indices, input_nnz_per_channel] = apply_input_mask( ...
            W_in, cfg.input_mask_mode, cfg.input_sparsity, input_stream);
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
    params.input_mask_mode = cfg.input_mask_mode;
    params.input_sparsity = cfg.input_sparsity;
    params.input_driven_indices = input_driven_indices;
    params.input_nnz_per_channel = input_nnz_per_channel;

    params.tau_d = cfg.tau_d;
    params.dt = cfg.dt;

    params.n_a_E = cfg.n_a_E;
    params.n_a_I = cfg.n_a_I;
    params.tau_a_E = cfg.tau_a_E;
    params.tau_a_I = cfg.tau_a_I;

    if isfield(cfg, 'c_a_E')
        params.c_a_E = cfg.c_a_E;
    end
    if isfield(cfg, 'c_a_I')
        params.c_a_I = cfg.c_a_I;
    end
    if isfield(cfg, 'c_E')
        params.c_E = cfg.c_E;
    end
    if isfield(cfg, 'c_I')
        params.c_I = cfg.c_I;
    end

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
    params.state_rng_seed = cfg.state_rng_seed;
    params.adaptation_initialization_mode = cfg.adaptation_initialization_mode;

    % -------------------------
    % 6. Final validation
    % -------------------------
    params = validate_MESN_params(params);

    meta = struct();
    meta.cfg = cfg;
    meta.W0 = W0;
    meta.sign_violations_E = sum(W(:, E_indices) < 0, 'all');
    meta.sign_violations_I = sum(W(:, I_indices) > 0, 'all');
    meta.input_mask_mode = cfg.input_mask_mode;
    meta.input_driven_indices = input_driven_indices;
    meta.input_nnz_per_channel = input_nnz_per_channel;
    meta.adaptation_initialization_mode = cfg.adaptation_initialization_mode;
    if cfg.dale && w_generated
        assert(meta.sign_violations_E == 0 && meta.sign_violations_I == 0);
    end
end

function [W_in, driven_indices, nnz_per_channel] = apply_input_mask( ...
        W_in, mode, input_sparsity, input_stream)
    n = size(W_in, 1);
    n_inputs = size(W_in, 2);
    driven_indices = cell(1, n_inputs);
    nnz_per_channel = zeros(1, n_inputs);
    mode = char(mode);

    switch mode
        case 'bernoulli'
            if input_sparsity > 0
                mask = rand(input_stream, n, n_inputs) < (1 - input_sparsity);
                W_in = W_in .* mask;
            end
            for j = 1:n_inputs
                driven_indices{j} = find(W_in(:, j) ~= 0);
                nnz_per_channel(j) = numel(driven_indices{j});
            end
        case 'fixed_count'
            k = max(1, round((1 - input_sparsity) * n));
            for j = 1:n_inputs
                perm = randperm(input_stream, n);
                idx = sort(perm(1:k));
                mask = false(n, 1);
                mask(idx) = true;
                W_in(:, j) = W_in(:, j) .* mask;
                driven_indices{j} = idx(:);
                nnz_per_channel(j) = k;
            end
            if any(nnz_per_channel < 1)
                error('default_MESN_config:EmptyInputMask', ...
                    'fixed_count input mask produced a zero column in W_in.');
            end
        otherwise
            error('default_MESN_config:InvalidInputMaskMode', ...
                'input_mask_mode must be ''bernoulli'' or ''fixed_count'', got %s.', mode);
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
