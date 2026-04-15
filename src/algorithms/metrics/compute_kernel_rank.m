function krgr = compute_kernel_rank(esn_or_params, options)
% compute_kernel_rank
% Compute Kernel Rank (KR) and Generalisation Rank (GR) using state responses
% to ensembles of input sequences (Buesing et al., 2010 style).
%
% Usage:
%   krgr = compute_kernel_rank(params);
%   krgr = compute_kernel_rank(esn, struct('M',200,'L',200));
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct
%   options - struct (optional)
%       .M              (default 200)   number of sequences for KR
%       .L              (default 200)   length of each sequence
%       .washout        (default 50)
%       .input_type     (default 'binary') 'binary' or 'gaussian'
%       .input_scale    (default 1.0)
%       .rank_tol       (default 1e-6) relative to max singular value
%       .feature_mode   (default 'x')
%       .GR_classes     (default 20) number of base sequences
%       .GR_repeats     (default 10) repeats per class with small noise
%       .GR_noise       (default 0.05) noise level added to inputs for GR
%       .seed           (default 1)
%
% Output:
%   krgr - struct:
%       .KR, .GR
%       .sv_KR, .sv_GR
%       .options

    if nargin < 2 || isempty(options)
        options = struct();
    end

    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
    else
        esn = SRNN_ESN(esn_or_params);
    end

    M = getFieldOrDefault(options, 'M', 200);
    L = getFieldOrDefault(options, 'L', 200);
    washout = getFieldOrDefault(options, 'washout', 50);
    input_type = getFieldOrDefault(options, 'input_type', 'binary');
    input_scale = getFieldOrDefault(options, 'input_scale', 1.0);
    rank_tol = getFieldOrDefault(options, 'rank_tol', 1e-6);
    feature_mode = getFieldOrDefault(options, 'feature_mode', 'x');
    GR_classes = getFieldOrDefault(options, 'GR_classes', 20);
    GR_repeats = getFieldOrDefault(options, 'GR_repeats', 10);
    GR_noise = getFieldOrDefault(options, 'GR_noise', 0.05);
    seed = getFieldOrDefault(options, 'seed', 1);

    esn.which_states = feature_mode;
    esn.include_input = false;

    rng(seed);

    % -------------------------
    % Kernel Rank (distinct sequences)
    % -------------------------
    X_end = zeros(M, esn.n);
    for i = 1:M
        U = make_input(L, input_type, input_scale);
        esn.resetState();
        [X, ~] = esn.runReservoir(U);
        X_use = X((washout+1):end, :);
        X_end(i, :) = X_use(end, :);
    end

    K = X_end * X_end';
    sv = svd(K);
    KR = sum(sv > rank_tol * max(sv));

    % -------------------------
    % Generalisation Rank (repeated prototypes)
    % -------------------------
    Mgr = GR_classes * GR_repeats;
    Xg = zeros(Mgr, esn.n);
    row = 0;
    for c = 1:GR_classes
        U0 = make_input(L, input_type, input_scale);
        for r = 1:GR_repeats
            row = row + 1;
            U = U0 + GR_noise * randn(size(U0));
            esn.resetState();
            [X, ~] = esn.runReservoir(U);
            X_use = X((washout+1):end, :);
            Xg(row, :) = X_use(end, :);
        end
    end

    Kg = Xg * Xg';
    sv_g = svd(Kg);
    GR = sum(sv_g > rank_tol * max(sv_g));

    krgr = struct();
    krgr.options = options;
    krgr.KR = KR;
    krgr.GR = GR;
    krgr.sv_KR = sv;
    krgr.sv_GR = sv_g;
end

function U = make_input(L, input_type, input_scale)
    switch lower(input_type)
        case 'binary'
            U = input_scale * (2 * (rand(L, 1) > 0.5) - 1);
        case 'gaussian'
            U = input_scale * randn(L, 1);
        otherwise
            error('compute_kernel_rank:InvalidInputType', ...
                'input_type must be ''binary'' or ''gaussian''');
    end
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

