function bench = narma_benchmark(esn_or_params, options)
% narma_benchmark
% Evaluate reservoir on NARMA-n benchmark (n=10 or 20).
%
% Usage:
%   bench = narma_benchmark(params, struct('order',10));
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct
%   options - struct (optional)
%       .order        (default 10)   10 or 20
%       .T            (default 6000)
%       .washout      (default 200)
%       .train_ratio  (default 0.6)
%       .lambda       (default 1e-6)
%       .seed         (default 1)
%       .u_range      (default [0, 0.5])
%       .feature_mode (default 'x')
%
% Output:
%   bench - struct with fields:
%       .metrics_train, .metrics_test
%       .order, .options
%       .u, .y, .y_pred_test

    if nargin < 2 || isempty(options)
        options = struct();
    end

    order = getFieldOrDefault(options, 'order', 10);
    T = getFieldOrDefault(options, 'T', 6000);
    washout = getFieldOrDefault(options, 'washout', 200);
    train_ratio = getFieldOrDefault(options, 'train_ratio', 0.6);
    lambda = getFieldOrDefault(options, 'lambda', 1e-6);
    seed = getFieldOrDefault(options, 'seed', 1);
    u_range = getFieldOrDefault(options, 'u_range', [0, 0.5]);
    feature_mode = getFieldOrDefault(options, 'feature_mode', 'x');

    if ~(order == 10 || order == 20)
        error('narma_benchmark:InvalidOrder', 'order must be 10 or 20');
    end

    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
    else
        esn = SRNN_ESN(esn_or_params);
    end

    esn.which_states = feature_mode;
    esn.include_input = false;

    rng(seed);
    u = u_range(1) + (u_range(2) - u_range(1)) * rand(T, 1);
    y = generate_narma(u, order);

    % Split train/test
    n_train = floor(T * train_ratio);
    u_train = u(1:n_train);
    y_train = y(1:n_train);
    u_test  = u((n_train+1):end);
    y_test  = y((n_train+1):end);

    % Train readout on train segment
    esn.lambda = lambda;
    esn.resetState();
    [Xtr, ~] = esn.runReservoir(u_train);
    Xtr = Xtr((washout+1):end, :);
    ytr = y_train((washout+1):end, :);

    n_feat = size(Xtr, 2);
    W_ridge = (Xtr' * Xtr) + lambda * eye(n_feat);
    Wout = W_ridge \ (Xtr' * ytr);
    bout = mean(ytr - Xtr * Wout, 1);

    y_pred_train = Xtr * Wout + bout;
    metrics_train = compute_metrics(y_pred_train, ytr);

    % Test
    esn.resetState();
    [Xte, ~] = esn.runReservoir(u_test);
    Xte = Xte((washout+1):end, :);
    yte = y_test((washout+1):end, :);
    y_pred_test = Xte * Wout + bout;
    metrics_test = compute_metrics(y_pred_test, yte);

    bench = struct();
    bench.options = options;
    bench.order = order;
    bench.u = u;
    bench.y = y;
    bench.metrics_train = metrics_train;
    bench.metrics_test = metrics_test;
    bench.y_pred_test = y_pred_test;
end

function y = generate_narma(u, order)
    T = numel(u);
    y = zeros(T, 1);
    % Initialize with small values
    y(1:order) = 0.1;

    for t = order:(T-1)
        y_sum = sum(y((t-order+1):t));
        % Common NARMA formulation (order=10/20)
        y(t+1) = 0.3*y(t) + 0.05*y(t)*y_sum + 1.5*u(t-order+1)*u(t) + 0.1;
    end
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

