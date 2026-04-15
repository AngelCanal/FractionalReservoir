function nmc = compute_nonlinear_memory_capacity(esn_or_params, options)
% compute_nonlinear_memory_capacity
% Nonlinear memory capacity using polynomial targets of delayed inputs.
%
% Targets:
%   - Legendre polynomials P_d(u(t-k)) for d in degrees
%   - Optional cross terms u(t-k1)*u(t-k2)
%
% Usage:
%   nmc = compute_nonlinear_memory_capacity(params);
%   nmc = compute_nonlinear_memory_capacity(esn, struct('degrees',[2 3]));
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct for SRNN_ESN(params)
%   options - struct (optional)
%       .T            (default 5000)
%       .K_max        (default 100)
%       .washout      (default 200)
%       .train_ratio  (default 0.6)
%       .lambda       (default 1e-6)
%       .input_scale  (default 1.0)   u ~ U[-input_scale,input_scale]
%       .seed         (default 123)
%       .degrees      (default [2 3])
%       .include_cross_terms (default false)
%       .cross_max_pairs     (default 200)  % cap to avoid explosion
%       .feature_mode        (default 'x')
%
% Output:
%   nmc - struct
%       .degrees
%       .lags
%       .NMC_legendre   (numel(degrees) x K_max)
%       .NMC_cross      (n_pairs x 1) with metadata if enabled
%       .total_capacity
%       .options

    if nargin < 2 || isempty(options)
        options = struct();
    end

    T = getFieldOrDefault(options, 'T', 5000);
    K_max = getFieldOrDefault(options, 'K_max', 100);
    washout = getFieldOrDefault(options, 'washout', 200);
    train_ratio = getFieldOrDefault(options, 'train_ratio', 0.6);
    lambda = getFieldOrDefault(options, 'lambda', 1e-6);
    input_scale = getFieldOrDefault(options, 'input_scale', 1.0);
    seed = getFieldOrDefault(options, 'seed', 123);
    degrees = getFieldOrDefault(options, 'degrees', [2 3]);
    include_cross = getFieldOrDefault(options, 'include_cross_terms', false);
    cross_max_pairs = getFieldOrDefault(options, 'cross_max_pairs', 200);
    feature_mode = getFieldOrDefault(options, 'feature_mode', 'x');

    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
    else
        esn = SRNN_ESN(esn_or_params);
    end

    esn.which_states = feature_mode;
    esn.include_input = false;
    esn.lambda = lambda;

    rng(seed);
    u = (2 * rand(T, 1) - 1) * input_scale;

    esn.resetState();
    [X, ~] = esn.runReservoir(u);

    % Discard washout
    X = X((washout+1):end, :);
    u = u((washout+1):end, :);

    T2 = size(X, 1);
    n_train = floor(T2 * train_ratio);
    X_train = X(1:n_train, :);
    X_test  = X((n_train+1):end, :);
    u_train = u(1:n_train, 1);
    u_test  = u((n_train+1):end, 1);

    degs = degrees(:).';
    n_deg = numel(degs);
    NMC_leg = zeros(n_deg, K_max);

    n_feat = size(X_train, 2);
    for di = 1:n_deg
        d = degs(di);
        for k = 1:K_max
            % Targets (aligned)
            ytr_raw = u_train(1:(end-k));
            yte_raw = u_test(1:(end-k));
            y_train = legendreP(d, ytr_raw);
            y_test = legendreP(d, yte_raw);

            Xtr = X_train((k+1):end, :);
            Xte = X_test((k+1):end, :);

            Rk = (Xtr' * Xtr) + lambda * eye(n_feat);
            wk = Rk \ (Xtr' * y_train);

            y_pred = Xte * wk;
            c = corr(y_pred, y_test, 'Rows', 'complete');
            if ~isfinite(c)
                NMC_leg(di, k) = 0;
            else
                NMC_leg(di, k) = c^2;
            end
        end
    end

    nmc = struct();
    nmc.options = options;
    nmc.degrees = degs;
    nmc.lags = (1:K_max).';
    nmc.NMC_legendre = NMC_leg;

    total = sum(NMC_leg, 'all');

    if include_cross
        % Choose a capped set of lag pairs (k1 < k2) to avoid O(K^2).
        pairs = [];
        for k1 = 1:K_max
            for k2 = (k1+1):K_max
                pairs = [pairs; k1, k2]; %#ok<AGROW>
                if size(pairs, 1) >= cross_max_pairs
                    break;
                end
            end
            if size(pairs, 1) >= cross_max_pairs
                break;
            end
        end

        n_pairs = size(pairs, 1);
        NMC_cross = zeros(n_pairs, 1);

        for pi = 1:n_pairs
            k1 = pairs(pi, 1);
            k2 = pairs(pi, 2);
            k = max(k1, k2);

            ytr = u_train(1:(end-k1)) .* u_train(1:(end-k2));
            yte = u_test(1:(end-k1)) .* u_test(1:(end-k2));

            % Align feature matrix to the larger lag so time indices match
            Xtr = X_train((k+1):end, :);
            Xte = X_test((k+1):end, :);
            ytr = ytr((k+1):end);
            yte = yte((k+1):end);

            Rk = (Xtr' * Xtr) + lambda * eye(n_feat);
            wk = Rk \ (Xtr' * ytr);

            y_pred = Xte * wk;
            c = corr(y_pred, yte, 'Rows', 'complete');
            if ~isfinite(c)
                NMC_cross(pi) = 0;
            else
                NMC_cross(pi) = c^2;
            end
        end

        nmc.cross_pairs = pairs;
        nmc.NMC_cross = NMC_cross;
        total = total + sum(NMC_cross);
    end

    nmc.total_capacity = total;
end

function P = legendreP(d, x)
    % Legendre polynomials on [-1,1] (x is assumed in range; u is uniform)
    switch d
        case 0
            P = ones(size(x));
        case 1
            P = x;
        case 2
            P = 0.5 * (3*x.^2 - 1);
        case 3
            P = 0.5 * (5*x.^3 - 3*x);
        case 4
            P = (1/8) * (35*x.^4 - 30*x.^2 + 3);
        otherwise
            % Recurrence: (n+1)P_{n+1} = (2n+1)xP_n - nP_{n-1}
            Pn_1 = x;          % P1
            Pn_2 = ones(size(x)); % P0
            if d == 1
                P = Pn_1;
                return;
            end
            for n = 1:(d-1)
                Pn = ((2*n+1).*x.*Pn_1 - n.*Pn_2) ./ (n+1);
                Pn_2 = Pn_1;
                Pn_1 = Pn;
            end
            P = Pn_1;
    end
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

