function warp = evaluate_time_warp_generalization(esn_or_params, options)
% evaluate_time_warp_generalization
% Held-out time-warp generalization protocol.
%
% Warp definition (single, recorded):
%   'resample_fixed_waveform' — linearly resample a fixed continuous
%   waveform onto a warped time axis via interp1. This does NOT change the
%   ODE sample interval and does NOT apply additional smoothing.
%
% Train readout / hyperparameters only on the unwarped training realization
% (and optional preregistered training warp factors). Evaluate on disjoint
% input realizations and warp factors. Never fit and score the same warped
% sequence.
%
% Baselines (also trained only on the training realization):
%   persistence, linear input-history, ordinary ESN matched for state count
%   and training budget (no SFA/STD; same n).
%
% Options:
%   .T_base, .seed_train, .seed_val, .seed_test
%   .train_warps, .val_warps, .test_warps  (stored before simulation)
%   .target_delay, .smooth_width
%   .washout_steps, .train_ratio, .val_ratio
%   .context_len, .allow_train_test_leak (default false)
%   .force_same_sequence_fit_and_score (test-only leak flag)
%   .include_esn_baseline (default true)
%   .history_len, .input_scale

    if nargin < 2 || isempty(options)
        options = struct();
    end

    T_base = get_opt(options, 'T_base', 2000);
    seed_train = get_opt(options, 'seed_train', 11);
    seed_val = get_opt(options, 'seed_val', 22);
    seed_test = get_opt(options, 'seed_test', 33);
    train_warps = get_opt(options, 'train_warps', 1.0);
    val_warps = get_opt(options, 'val_warps', 1.0);
    test_warps = get_opt(options, 'test_warps', [0.5 0.75 1.0 1.5 2.0]);
    target_delay = get_opt(options, 'target_delay', 10);
    smooth_width = get_opt(options, 'smooth_width', 8);
    washout_steps = get_opt(options, 'washout_steps', 200);
    train_ratio = get_opt(options, 'train_ratio', 0.6);
    val_ratio = get_opt(options, 'val_ratio', 0.2);
    context_len = get_opt(options, 'context_len', 80);
    allow_leak = get_opt(options, 'allow_train_test_leak', false);
    history_len = get_opt(options, 'history_len', 20);
    input_scale = get_opt(options, 'input_scale', 0.2);
    include_esn = get_opt(options, 'include_esn_baseline', true);

    % Store protocol factors BEFORE any simulation
    protocol = struct();
    protocol.warp_definition = 'resample_fixed_waveform';
    protocol.train_warps = train_warps(:);
    protocol.val_warps = val_warps(:);
    protocol.test_warps = test_warps(:);
    protocol.seed_train = seed_train;
    protocol.seed_val = seed_val;
    protocol.seed_test = seed_test;
    protocol.T_base = T_base;

    assert_no_leak_option(options, allow_leak);
    if seed_train == seed_test || seed_train == seed_val || seed_val == seed_test
        error('evaluate_time_warp_generalization:SeedCollision', ...
            'Train/val/test input seeds must be disjoint.');
    end

    u_train = input_scale * randn(RandStream('mt19937ar', 'Seed', seed_train), T_base, 1);
    u_val = input_scale * randn(RandStream('mt19937ar', 'Seed', seed_val), T_base, 1);
    u_test = input_scale * randn(RandStream('mt19937ar', 'Seed', seed_test), T_base, 1);
    protocol.u_train_hash = local_hash(u_train);
    protocol.u_val_hash = local_hash(u_val);
    protocol.u_test_hash = local_hash(u_test);
    if isequal(u_train, u_test) || isequal(u_train, u_val) || isequal(u_val, u_test)
        error('evaluate_time_warp_generalization:InputCollision', ...
            'Train/val/test base inputs must be disjoint realizations.');
    end

    y_train = make_target(u_train, smooth_width, target_delay);
    y_test = make_target(u_test, smooth_width, target_delay);

    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
        mesn_params = esn.params;
    else
        mesn_params = esn_or_params;
        esn = SRNN_ESN(mesn_params);
    end

    if ~any(abs(protocol.train_warps - 1.0) < 1e-12)
        error('evaluate_time_warp_generalization:MissingUnitTrainWarp', ...
            'train_warps must include 1.0 (unwarped training sequence).');
    end

    train_opts = struct( ...
        'train_ratio', train_ratio, 'val_ratio', val_ratio, ...
        'washout_steps', washout_steps);

    esn.resetState();
    train_metrics = esn.trainReadout(u_train, y_train, train_opts);
    trained_model = esn.readout_model;
    trained_W = esn.W_out;
    trained_b = esn.b_out;

    protocol.additional_train_warps_noted = protocol.train_warps(abs(protocol.train_warps - 1) > 1e-12);

    % Linear history baseline: fit ONLY on training realization
    lin_beta = fit_linear_history(u_train, y_train, history_len, washout_steps);

    % Ordinary ESN baseline: matched n, no adaptation/STD, same train budget
    esn_base = [];
    if include_esn
        esn_base = build_ordinary_esn(mesn_params);
        esn_base.resetState();
        esn_base.trainReadout(u_train, y_train, train_opts);
    end

    n_tw = numel(protocol.test_warps);
    rows = repmat(struct( ...
        'warp', nan, 'nrmse_mesn', nan, 'nrmse_persistence', nan, ...
        'nrmse_linear_history', nan, 'nrmse_esn', nan, ...
        'delta_from_unwarped_mesn', nan, 'time_axis', [], 'U_len', nan, ...
        'worse_than_persistence', false, 'worse_than_linear', false, ...
        'worse_than_esn', false), n_tw, 1);

    nrmse_at_1 = nan;
    for i = 1:n_tw
        w = protocol.test_warps(i);
        [u_w, t_axis] = resample_fixed_waveform(u_test, w);
        y_w = resample_fixed_waveform(y_test, w);
        n = min(numel(u_w), numel(y_w));
        u_w = u_w(1:n); y_w = y_w(1:n);

        ctx_n = min(context_len, max(1, n - 2));
        context_U = u_w(1:ctx_n);
        U_eval = u_w(ctx_n+1:end);
        Y_eval = y_w(ctx_n+1:end);

        Y_pred = esn.predict(U_eval, struct('context_U', context_U, 'reset_before', true));
        e_mesn = nrmse(Y_pred, Y_eval);

        e_pers = nrmse([Y_eval(1); Y_eval(1:end-1)], Y_eval);
        e_lin = apply_linear_history(u_w, y_w, lin_beta, history_len, washout_steps);

        e_esn = nan;
        if ~isempty(esn_base)
            Y_esn = esn_base.predict(U_eval, struct('context_U', context_U, 'reset_before', true));
            e_esn = nrmse(Y_esn, Y_eval);
        end

        rows(i).warp = w;
        rows(i).nrmse_mesn = e_mesn;
        rows(i).nrmse_persistence = e_pers;
        rows(i).nrmse_linear_history = e_lin;
        rows(i).nrmse_esn = e_esn;
        rows(i).time_axis = t_axis;
        rows(i).U_len = n;
        rows(i).worse_than_persistence = e_mesn > e_pers;
        rows(i).worse_than_linear = e_mesn > e_lin;
        rows(i).worse_than_esn = isfinite(e_esn) && (e_mesn > e_esn);
        if abs(w - 1.0) < 1e-12
            nrmse_at_1 = e_mesn;
        end
    end
    for i = 1:n_tw
        rows(i).delta_from_unwarped_mesn = rows(i).nrmse_mesn - nrmse_at_1;
    end

    if ~isequaln(esn.readout_model, trained_model) || ...
            ~isequaln(esn.W_out, trained_W) || ~isequaln(esn.b_out, trained_b)
        error('evaluate_time_warp_generalization:ModelMutated', ...
            'Evaluation altered the trained readout model.');
    end

    warp = struct();
    warp.protocol = protocol;
    warp.train_metrics = train_metrics;
    warp.results = rows;
    warp.nrmse_by_warp = [rows.nrmse_mesn]';
    warp.test_warps = protocol.test_warps;
    warp.unwarped_nrmse = nrmse_at_1;
    warp.readout_snapshot = struct('W_out', trained_W, 'b_out', trained_b);
    warp.baselines = struct( ...
        'persistence', 'one_step_hold', ...
        'linear_history_len', history_len, ...
        'ordinary_esn_included', include_esn && ~isempty(esn_base));
end

function assert_no_leak_option(options, allow_leak)
    if isfield(options, 'force_same_sequence_fit_and_score') && ...
            options.force_same_sequence_fit_and_score
        if allow_leak
            warning('evaluate_time_warp_generalization:AllowLeak', ...
                'allow_train_test_leak=true disables leak guards (test-only).');
            return;
        end
        error('evaluate_time_warp_generalization:LeakedProtocol', ...
            'Refusing to fit and score the same warped sequence.');
    end
end

function esn_base = build_ordinary_esn(mesn_params)
    n = mesn_params.n;
    overrides = struct( ...
        'n', n, ...
        'n_a_E', 0, 'n_a_I', 0, ...
        'n_b_E', 0, 'n_b_I', 0, ...
        'lags', [], ...
        'dt', mesn_params.dt, ...
        'weight_rng_seed', get_field_or(mesn_params, 'weight_rng_seed', 9001), ...
        'input_rng_seed', get_field_or(mesn_params, 'input_rng_seed', 9002));
    if isfield(mesn_params, 'level_of_chaos')
        overrides.level_of_chaos = mesn_params.level_of_chaos;
    end
    if isfield(mesn_params, 'fraction_E')
        overrides.fraction_E = mesn_params.fraction_E;
    end
    if isfield(mesn_params, 'lambda')
        overrides.lambda = mesn_params.lambda;
    end
    base_params = default_MESN_config(overrides);
    esn_base = SRNN_ESN(base_params);
end

function [y, tq] = resample_fixed_waveform(u, w)
    T = numel(u);
    t = (1:T)';
    tq = (1:(1/w):T)';
    y = interp1(t, u(:), tq, 'linear', 'extrap');
end

function y = make_target(u, smooth_width, target_delay)
    y = filter(ones(smooth_width, 1) / smooth_width, 1, u);
    y = [zeros(target_delay, 1); y(1:end-target_delay)];
end

function beta = fit_linear_history(u, y, hist_len, washout)
    T = numel(u);
    X = zeros(T, hist_len);
    for k = 1:hist_len
        X(k:end, k) = u(1:end-k+1);
    end
    idx = (washout+1):T;
    beta = X(idx, :) \ y(idx);
end

function e = apply_linear_history(u, y, beta, hist_len, washout)
    T = numel(u);
    X = zeros(T, hist_len);
    for k = 1:hist_len
        X(k:end, k) = u(1:end-k+1);
    end
    idx = (washout+1):T;
    if isempty(idx)
        e = nan;
        return;
    end
    yp = X(idx, :) * beta;
    e = nrmse(yp, y(idx));
end

function e = nrmse(yp, yt)
    yp = yp(:); yt = yt(:);
    e = sqrt(mean((yp - yt).^2)) / max(std(yt), eps);
end

function h = local_hash(u)
    h = sum(u(:)) + numel(u) * std(u(:));
end

function v = get_opt(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end

function v = get_field_or(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
