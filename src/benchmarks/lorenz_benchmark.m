function bench = lorenz_benchmark(esn_or_params, options)
% lorenz_benchmark
% Lorenz-63 one-step prediction benchmark from noisy observations.
%
% Usage:
%   bench = lorenz_benchmark(params);
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct
%   options - struct (optional)
%       .sigma        (default 10)
%       .rho          (default 28)
%       .beta         (default 8/3)
%       .dt           (default 0.01)
%       .T            (default 10000)  samples after discard
%       .discard      (default 2000)
%       .obs_noise    (default 0.0)    additive noise on observed input
%       .washout      (default 200)
%       .train_ratio  (default 0.6)
%       .lambda       (default 1e-6)
%       .seed         (default 1)
%       .feature_mode (default 'x')
%
% Output:
%   bench - struct with train/test metrics and predictions

    if nargin < 2 || isempty(options)
        options = struct();
    end

    sigma = getFieldOrDefault(options, 'sigma', 10);
    rho = getFieldOrDefault(options, 'rho', 28);
    beta = getFieldOrDefault(options, 'beta', 8/3);
    dt = getFieldOrDefault(options, 'dt', 0.01);
    T = getFieldOrDefault(options, 'T', 10000);
    discard = getFieldOrDefault(options, 'discard', 2000);
    obs_noise = getFieldOrDefault(options, 'obs_noise', 0.0);
    washout = getFieldOrDefault(options, 'washout', 200);
    train_ratio = getFieldOrDefault(options, 'train_ratio', 0.6);
    lambda = getFieldOrDefault(options, 'lambda', 1e-6);
    seed = getFieldOrDefault(options, 'seed', 1);
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
    x0 = [1; 1; 1] + 0.01 * randn(3,1);
    n_total = T + discard + 1;
    tspan = (0:(n_total-1)) * dt;

    rhs = @(t, x) lorenz_rhs(x, sigma, rho, beta);
    opts = odeset('RelTol', 1e-8, 'AbsTol', 1e-10);
    [~, X] = ode45(rhs, tspan, x0, opts);

    X = X((discard+1):end, :); % (T+1 x 3)
    x = X(:, 1);

    u = x(1:end-1);
    y = x(2:end);

    if obs_noise > 0
        u = u + obs_noise * randn(size(u));
    end

    T2 = numel(u);
    n_train = floor(T2 * train_ratio);

    u_train = u(1:n_train);
    y_train = y(1:n_train);
    u_test = u((n_train+1):end);
    y_test = y((n_train+1):end);

    esn.resetState();
    [Xtr, ~] = esn.runReservoir(u_train);
    Xtr = Xtr((washout+1):end, :);
    ytr = y_train((washout+1):end);

    n_feat = size(Xtr, 2);
    W_ridge = (Xtr' * Xtr) + lambda * eye(n_feat);
    Wout = W_ridge \ (Xtr' * ytr);
    bout = mean(ytr - Xtr * Wout, 1);

    y_pred_train = Xtr * Wout + bout;
    metrics_train = compute_metrics(y_pred_train, ytr);

    esn.resetState();
    [Xte, ~] = esn.runReservoir(u_test);
    Xte = Xte((washout+1):end, :);
    yte = y_test((washout+1):end);
    y_pred_test = Xte * Wout + bout;
    metrics_test = compute_metrics(y_pred_test, yte);

    bench = struct();
    bench.options = options;
    bench.X_lorenz = X;
    bench.u = u;
    bench.y = y;
    bench.metrics_train = metrics_train;
    bench.metrics_test = metrics_test;
    bench.y_pred_test = y_pred_test;
    bench.y_test = yte;
    bench.Wout = Wout;
    bench.bout = bout;
end

function dx = lorenz_rhs(x, sigma, rho, beta)
    dx = zeros(3,1);
    dx(1) = sigma * (x(2) - x(1));
    dx(2) = x(1) * (rho - x(3)) - x(2);
    dx(3) = x(1) * x(2) - beta * x(3);
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

