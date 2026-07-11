function krgr = compute_kernel_rank(esn_or_params, options)
% compute_kernel_rank
% Kernel Rank (KR) and Generalisation Rank (GR) from independent reset
% simulations of reservoir endpoint features (Buesing et al., 2010 style).
%
% Feature definition (explicit):
%   After washout, take the endpoint state row X(end,:) of each independent
%   reset simulation. Do not concatenate a changing number of time samples.
%
% Usage:
%   krgr = compute_kernel_rank(params);
%   krgr = compute_kernel_rank(esn, struct('M',200,'L',200));
%
% Options:
%   .M, .L, .washout, .input_type, .input_scale, .rank_tol
%   .feature_mode, .GR_classes, .GR_repeats, .GR_noise, .seed
%   .feature_definition (default 'endpoint')  % or 'time_average'
%   .standardize (default true)
%
% Output includes algebraic ranks, effective ranks, singular values
% (standardized and raw), input distances, condition numbers, and
% saturation fractions.

    if nargin < 2 || isempty(options)
        options = struct();
    end

    if isa(esn_or_params, 'SRNN_ESN')
        esn_template = esn_or_params;
        params = esn_template.params;
    else
        params = esn_or_params;
        esn_template = [];
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
    feature_definition = getFieldOrDefault(options, 'feature_definition', 'endpoint');
    do_standardize = getFieldOrDefault(options, 'standardize', true);
    inject_features = getFieldOrDefault(options, 'inject_features', struct());
    inject_inputs = getFieldOrDefault(options, 'inject_inputs', struct());

    stream = RandStream('mt19937ar', 'Seed', seed);

    % -------------------------
    % Kernel Rank ensemble
    % -------------------------
    if isstruct(inject_features) && isfield(inject_features, 'KR')
        X_end = inject_features.KR;
        if isfield(inject_inputs, 'KR')
            U_list = inject_inputs.KR;
        else
            U_list = {};
        end
    elseif isfield(options, 'override_KR_inputs') && ~isempty(options.override_KR_inputs)
        U_list = options.override_KR_inputs;
        assert_inputs_distinct(U_list, 'KR');
        X_end = simulate_endpoints(esn_template, params, U_list, washout, ...
            feature_mode, feature_definition);
    else
        U_list = cell(M, 1);
        for i = 1:M
            U_list{i} = make_input(L, input_type, input_scale, stream);
        end
        assert_inputs_distinct(U_list, 'KR');
        X_end = simulate_endpoints(esn_template, params, U_list, washout, ...
            feature_mode, feature_definition);
    end

    [KR, sv_KR, sv_KR_raw, eff_KR, cond_KR, sat_KR, mu_KR, sig_KR] = ...
        rank_from_features(X_end, rank_tol, do_standardize);

    % -------------------------
    % Generalisation Rank ensemble
    % -------------------------
    if isstruct(inject_features) && isfield(inject_features, 'GR')
        Xg = inject_features.GR;
        if isfield(inject_inputs, 'GR')
            Ug = inject_inputs.GR;
        else
            Ug = {};
        end
        if isfield(inject_inputs, 'GR_input_distances')
            d_in_GR = inject_inputs.GR_input_distances;
        else
            d_in_GR = input_pairwise_mean_distance(Ug);
        end
    else
        Mgr = GR_classes * GR_repeats;
        Ug = cell(Mgr, 1);
        row = 0;
        for c = 1:GR_classes
            U0 = make_input(L, input_type, input_scale, stream);
            for r = 1:GR_repeats
                row = row + 1;
                Ug{row} = U0 + GR_noise * randn(stream, size(U0));
            end
        end
        Xg = simulate_endpoints(esn_template, params, Ug, washout, ...
            feature_mode, feature_definition);
        d_in_GR = input_pairwise_mean_distance(Ug);
    end

    [GR, sv_GR, sv_GR_raw, eff_GR, cond_GR, sat_GR, mu_GR, sig_GR] = ...
        rank_from_features(Xg, rank_tol, do_standardize);

    krgr = struct();
    krgr.options = options;
    krgr.feature_definition = feature_definition;
    krgr.KR = KR;
    krgr.GR = GR;
    krgr.KR_effective = eff_KR;
    krgr.GR_effective = eff_GR;
    krgr.sv_KR = sv_KR;
    krgr.sv_GR = sv_GR;
    krgr.sv_KR_unstandardized = sv_KR_raw;
    krgr.sv_GR_unstandardized = sv_GR_raw;
    krgr.rank_tol = rank_tol;
    krgr.KR_feature_mean = mu_KR;
    krgr.KR_feature_std = sig_KR;
    krgr.GR_feature_mean = mu_GR;
    krgr.GR_feature_std = sig_GR;
    krgr.KR_condition_number = cond_KR;
    krgr.GR_condition_number = cond_GR;
    krgr.KR_saturation_fraction = sat_KR;
    krgr.GR_saturation_fraction = sat_GR;
    krgr.KR_input_mean_distance = input_pairwise_mean_distance(U_list);
    krgr.GR_input_mean_distance = d_in_GR;
    krgr.KR_definition = 'distinct_independent_reset_inputs';
    krgr.GR_definition = 'small_perturbations_of_common_prototypes';
    krgr.seed = seed;
    if KR > 0 && eff_KR < 0.5 * KR
        krgr.interpretation_warning = [ ...
            'Algebraic KR is much larger than effective rank; full algebraic ', ...
            'rank should not be read as high-dimensional usable computation.'];
    end
end

function X_end = simulate_endpoints(esn_template, params, U_list, washout, ...
        feature_mode, feature_definition)
    M = numel(U_list);
    X_end = [];
    for i = 1:M
        if isempty(esn_template)
            esn = SRNN_ESN(params);
        else
            % Fresh object from the same params — never reuse leftover state
            esn = SRNN_ESN(esn_template.params);
        end
        esn.which_states = feature_mode;
        esn.include_input = false;
        esn.resetState();
        [X, ~] = esn.runReservoir(U_list{i});
        if washout >= size(X, 1)
            error('compute_kernel_rank:WashoutTooLong', ...
                'washout=%d exceeds trajectory length %d', washout, size(X, 1));
        end
        X_use = X((washout+1):end, :);
        switch lower(feature_definition)
            case 'endpoint'
                feat = X_use(end, :);
            case 'time_average'
                feat = mean(X_use, 1);
            otherwise
                error('compute_kernel_rank:InvalidFeatureDefinition', ...
                    'feature_definition must be ''endpoint'' or ''time_average''');
        end
        if isempty(X_end)
            X_end = zeros(M, numel(feat));
        end
        X_end(i, :) = feat;
    end
end

function [r_alg, sv, sv_raw, r_eff, condn, sat, mu, sig] = ...
        rank_from_features(X, rank_tol, do_standardize)
    sv_raw = svd(X, 'econ');
    mu = mean(X, 1);
    sig = std(X, 0, 1);
    sig(sig < eps) = 1;
    if do_standardize
        Xs = (X - mu) ./ sig;
    else
        Xs = X;
    end
    sv = svd(Xs, 'econ');
    if isempty(sv) || max(sv) == 0
        r_alg = 0;
    else
        r_alg = sum(sv > rank_tol * max(sv));
    end
    r_eff = effective_rank(sv);
    if numel(sv) >= 1 && sv(end) > 0
        condn = sv(1) / sv(end);
    else
        condn = Inf;
    end
    % Saturation: fraction of feature columns with near-zero variance pre-std
    sat = mean(std(X, 0, 1) < 1e-12);
end

function r = effective_rank(sv)
    e = sv.^2;
    e = e(e > 0);
    if isempty(e)
        r = 0;
        return;
    end
    p = e / sum(e);
    r = exp(-sum(p .* log(p)));
end

function assert_inputs_distinct(U_list, tag)
    M = numel(U_list);
    for i = 1:M
        for j = i+1:M
            if isequal(U_list{i}, U_list{j})
                error('compute_kernel_rank:DuplicateInputs', ...
                    '%s inputs %d and %d are identical; kernel-rank inputs must be distinct.', ...
                    tag, i, j);
            end
        end
    end
end

function dmean = input_pairwise_mean_distance(U_list)
    if isempty(U_list)
        dmean = nan;
        return;
    end
    M = numel(U_list);
    if M < 2
        dmean = 0;
        return;
    end
    acc = 0;
    cnt = 0;
    for i = 1:M
        for j = i+1:M
            acc = acc + norm(U_list{i}(:) - U_list{j}(:));
            cnt = cnt + 1;
        end
    end
    dmean = acc / cnt;
end

function U = make_input(L, input_type, input_scale, stream)
    switch lower(input_type)
        case 'binary'
            U = input_scale * (2 * (rand(stream, L, 1) > 0.5) - 1);
        case 'gaussian'
            U = input_scale * randn(stream, L, 1);
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
