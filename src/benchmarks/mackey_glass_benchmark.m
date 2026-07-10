function bench = mackey_glass_benchmark(esn_or_params, options)
% mackey_glass_benchmark
% Mackey-Glass prediction benchmark (one-step and optional autonomous rollout).
%
% Usage:
%   bench = mackey_glass_benchmark(params);
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct
%   options - struct (optional)
%       .tau           (default 17)
%       .dt_mg         (default 1.0)
%       .T             (default 6000)
%       .discard       (default 1000)
%       .washout       (default 200)
%       .train_ratio   (default 0.6)
%       .lambda        (default 1e-6)
%       .seed          (default 1)
%       .feature_mode  (default 'x')
%       .do_rollout    (default true)
%       .rollout_steps (default 500)
%
% Output:
%   bench - struct with metrics and predictions

    if nargin < 2 || isempty(options)
        options = struct();
    end

    tau = getFieldOrDefault(options, 'tau', 17);
    dt_mg = getFieldOrDefault(options, 'dt_mg', 1.0);
    T = getFieldOrDefault(options, 'T', 6000);
    discard = getFieldOrDefault(options, 'discard', 1000);
    washout = getFieldOrDefault(options, 'washout', 200);
    train_ratio = getFieldOrDefault(options, 'train_ratio', 0.6);
    lambda = getFieldOrDefault(options, 'lambda', 1e-6);
    seed = getFieldOrDefault(options, 'seed', 1);
    feature_mode = getFieldOrDefault(options, 'feature_mode', 'x');
    do_rollout = getFieldOrDefault(options, 'do_rollout', true);
    rollout_steps = getFieldOrDefault(options, 'rollout_steps', 500);

    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
    else
        esn = SRNN_ESN(esn_or_params);
    end

    esn.which_states = feature_mode;
    esn.include_input = false;
    esn.lambda = lambda;

    rng(seed);
    [t, x] = generate_mackey_glass('tau', tau, 'dt', dt_mg, 'n_samples', T, 'discard', discard);

    % One-step prediction: input is x(t), target is x(t+1)
    % Force column vectors to keep metric shapes consistent (MATLAB may return row vectors)
    u = x(1:end-1);
    y = x(2:end);
    u = u(:);
    y = y(:);

    T2 = numel(u);
    n_train = floor(T2 * train_ratio);

    u_train = u(1:n_train);
    y_train = y(1:n_train);
    u_test  = u((n_train+1):end);
    y_test  = y((n_train+1):end);

    % Train ridge readout
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

    % Test (teacher-forced one-step)
    esn.resetState();
    [Xte, ~] = esn.runReservoir(u_test);
    Xte = Xte((washout+1):end, :);
    yte = y_test((washout+1):end, :);
    y_pred_test = Xte * Wout + bout;
    metrics_test = compute_metrics(y_pred_test, yte);

    bench = struct();
    bench.options = options;
    bench.t = t;
    bench.x = x;
    bench.metrics_train = metrics_train;
    bench.metrics_test = metrics_test;
    bench.y_pred_test = y_pred_test;
    bench.y_test = yte;
    bench.Wout = Wout;
    bench.bout = bout;

    % Optional autonomous rollout (ODE-only, after teacher-forced checks pass)
    teacher_forced_ok = isempty(esn.lags) ...
        && esn.n_inputs == 1 ...
        && size(Wout, 2) == 1 ...
        && isfinite(metrics_test.nrmse) ...
        && isfinite(metrics_test.rmse);
    if do_rollout && teacher_forced_ok
        esn.W_out = Wout;
        esn.b_out = bout(:);
        esn.is_trained = true;
        esn.n_outputs = size(Wout, 2);

        init_len = max(2*washout, 200);
        init_data = u_test(1:init_len);
        [y_roll, ~] = esn.generateAutonomous(init_data, rollout_steps);
        bench.rollout = struct();
        bench.rollout.status = 'computed';
        bench.rollout.init_len = init_len;
        bench.rollout.y_roll = y_roll;
        bench.rollout.y_true = y_test((init_len+1):(init_len+rollout_steps));
        bench.rollout.y_true = bench.rollout.y_true(:);
        bench.rollout.metrics = compute_metrics(y_roll, bench.rollout.y_true);
    elseif do_rollout
        bench.rollout = struct( ...
            'status', 'skipped', ...
            'reason', 'Autonomous rollout requires ODE mode, scalar I/O, and finite one-step test metrics.');
    end
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

