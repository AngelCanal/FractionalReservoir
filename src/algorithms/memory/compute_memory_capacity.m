function mc = compute_memory_capacity(esn_or_params, options)
% compute_memory_capacity
% Linear memory capacity spectrum (Jaeger 2001) for SISO input.
%
% Drives the reservoir with i.i.d. input u(t) and trains ridge readouts to
% reconstruct u(t-k) from the current reservoir features.
%
% Usage:
%   mc = compute_memory_capacity(params);
%   mc = compute_memory_capacity(esn, struct('T', 5000, 'K_max', 200));
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct for SRNN_ESN(params)
%   options - struct (optional)
%       .T             (default 5000)  total length
%       .K_max         (default 200)   max lag (samples)
%       .washout       (default 200)
%       .train_ratio   (default 0.6)
%       .lambda        (default 1e-6)
%       .input_scale   (default 1.0)   u ~ U[-input_scale, input_scale]
%       .seed          (default 123)
%       .feature_mode  (default 'x')   esn.which_states during evaluation
%
% Output:
%   mc - struct
%       .MC_spectrum  (K_max x 1)
%       .MC_total
%       .lags
%       .options
%
% Notes:
% - Uses MC_k = corr(y_pred, y_true)^2 on held-out test set.
% - SISO input assumed.

    if nargin < 2 || isempty(options)
        options = struct();
    end

    T = getFieldOrDefault(options, 'T', 5000);
    K_max = getFieldOrDefault(options, 'K_max', 200);
    washout = getFieldOrDefault(options, 'washout', 200);
    train_ratio = getFieldOrDefault(options, 'train_ratio', 0.6);
    lambda = getFieldOrDefault(options, 'lambda', 1e-6);
    input_scale = getFieldOrDefault(options, 'input_scale', 1.0);
    seed = getFieldOrDefault(options, 'seed', 123);
    feature_mode = getFieldOrDefault(options, 'feature_mode', 'x');

    if T <= (washout + K_max + 10)
        error('compute_memory_capacity:ShortT', ...
            'T=%d too short for washout=%d and K_max=%d', T, washout, K_max);
    end

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

    % Split train/test (temporal)
    T2 = size(X, 1);
    n_train = floor(T2 * train_ratio);
    if n_train <= K_max + 5
        error('compute_memory_capacity:TrainTooShort', ...
            'Train segment too short after washout; increase T or train_ratio');
    end

    X_train = X(1:n_train, :);
    X_test  = X((n_train+1):end, :);
    u_train = u(1:n_train, 1);
    u_test  = u((n_train+1):end, 1);

    % Precompute ridge matrix
    n_feat = size(X_train, 2);
    R = (X_train' * X_train) + lambda * eye(n_feat);
    R_inv_XT = R \ X_train';

    MC = zeros(K_max, 1);
    for k = 1:K_max
        % Align targets: y(t) = u(t-k). We evaluate on indices where defined.
        y_train = u_train(1:(end-k));
        y_test  = u_test(1:(end-k));

        Xtr = X_train((k+1):end, :);
        Xte = X_test((k+1):end, :);

        % Recompute ridge for the truncated Xtr (keeps things simple/robust)
        Rk = (Xtr' * Xtr) + lambda * eye(n_feat);
        wk = Rk \ (Xtr' * y_train);

        y_pred = Xte * wk;
        c = corr(y_pred, y_test, 'Rows', 'complete');
        if ~isfinite(c)
            MC(k) = 0;
        else
            MC(k) = c^2;
        end
    end

    mc = struct();
    mc.options = options;
    mc.lags = (1:K_max).';
    mc.MC_spectrum = MC;
    mc.MC_total = sum(MC);
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

