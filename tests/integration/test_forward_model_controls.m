function tests = test_forward_model_controls
tests = functiontests(localfunctions);
end

function testLeakyIntegratorAnalyticalMatch(testCase)
    % W=0, linear activation: each neuron is an independent leaky integrator
    % dx/dt = (-x + u) / tau_d  =>  x(t) = x0*e^{-t/tau} + u*(1-e^{-t/tau})
    params = make_linear_activation_params(struct('n', 2, 'n_a_E', 0, 'n_a_I', 0, ...
        'n_b_E', 0, 'n_b_I', 0, 'lags', []));
    params.W = zeros(2);
    params = validate_MESN_params(params);

    esn = SRNN_ESN(params);
    esn.which_states = 'x';
    esn.state_rng_seed = 1729;
    esn.resetState();
    x0 = esn.S(end-1:end);  % x portion when no a/b

    T = 40;
    u_scalar = 0.35;
    U = u_scalar * ones(T, 1);
    neural_drive = params.W_in * U';  % n x T, but constant columns if W_in constant*U
    % For analytical: projected drive per neuron is constant
    u_proj = params.W_in * u_scalar;  % n x 1

    opts = struct('reset_before', true, 'update_internal_state', false, ...
        'ode_reltol', 1e-8, 'ode_abstol', 1e-10);
    [X, ~, info] = esn.runReservoir(U, opts);
    t = info.t(:);
    tau = params.tau_d;

    X_analytic = zeros(T, 2);
    for i = 1:2
        X_analytic(:, i) = x0(i) * exp(-t / tau) + u_proj(i) * (1 - exp(-t / tau));
    end

    denom = max(norm(X_analytic, 'fro'), eps);
    rel_err = norm(X - X_analytic, 'fro') / denom;
    testCase.verifyLessThan(rel_err, 1e-5);
end

function testStdResourcesStayInUnitInterval(testCase)
    params = make_test_params(struct('n_a_E', 0, 'n_a_I', 0, 'n_b_E', 1, 'n_b_I', 1, ...
        'lags', []));
    % Nonnegative rates via piecewise sigmoid already in [0,1]
    esn = SRNN_ESN(params);
    esn.which_states = 'all';
    U = 0.5 * abs(randn(80, 1));
    opts = struct('reset_before', true, 'update_internal_state', false, ...
        'ode_reltol', 1e-8, 'ode_abstol', 1e-10);
    [~, S_hist] = esn.runReservoir(U, opts);
    layout = state_layout(params);
    b_vals = [S_hist(:, layout.idx_b_E), S_hist(:, layout.idx_b_I)];
    violation = max(0, max(max(-b_vals, [], 'all'), max(b_vals - 1, [], 'all')));
    testCase.verifyLessThanOrEqual(violation, 1e-7);
end

function testTinyDelayDdeMatchesOde(testCase)
    % Documented modest tolerance 2e-3 for delay=1e-6 away from initial boundary.
    tiny_delay_tol = 2e-3;
    params_ode = make_linear_activation_params(struct('lags', [], 'dale', true));
    params_dde = params_ode;
    params_dde.lags = 1e-6;
    params_dde = validate_MESN_params(params_dde);

    % Smooth input
    T = 60;
    t_idx = (0:T-1)';
    U = 0.2 * sin(2 * pi * t_idx / 25);

    esn_ode = SRNN_ESN(params_ode);
    esn_ode.which_states = 'x';
    esn_dde = SRNN_ESN(params_dde);
    esn_dde.which_states = 'x';

    opts_ode = struct('reset_before', true, 'update_internal_state', false, ...
        'ode_reltol', 1e-8, 'ode_abstol', 1e-10);
    opts_dde = struct('reset_before', true, 'update_internal_state', false, ...
        'dde_reltol', 1e-7, 'dde_abstol', 1e-9);

    [X_ode, ~] = esn_ode.runReservoir(U, opts_ode);
    [X_dde, ~] = esn_dde.runReservoir(U, opts_dde);

    % Compare away from initial boundary (skip first 10 samples)
    skip = 10;
    rel = norm(X_ode(skip:end, :) - X_dde(skip:end, :), 'fro') / ...
        max(norm(X_ode(skip:end, :), 'fro'), eps);
    testCase.verifyLessThan(rel, tiny_delay_tol);
end

function testOdeDdeLocalDerivativesMatch(testCase)
    params_ode = make_test_params(struct('lags', [], 'n_a_E', 2, 'n_a_I', 1, ...
        'n_b_E', 1, 'n_b_I', 1));
    params_dde = params_ode;
    params_dde.lags = 0.05;
    esn_dde = SRNN_ESN(params_dde);
    params_dde = esn_dde.exportParams();
    params_dde.W_components = esn_dde.W_components;

    state = struct();
    state.a_E = 0.2 * ones(params_ode.n_E, params_ode.n_a_E);
    state.a_I = 0.1 * ones(params_ode.n_I, params_ode.n_a_I);
    state.b_E = 0.7 * ones(params_ode.n_E, 1);
    state.b_I = 0.8 * ones(params_ode.n_I, 1);
    state.x = 0.3 * ones(params_ode.n, 1);
    S = pack_state(state, params_ode);

    % Delayed state differs in x only
    state_d = state;
    state_d.x = -0.2 * ones(params_ode.n, 1);
    Z = pack_state(state_d, params_ode);

    u_fun = @(t) zeros(params_ode.n, 1);
    dS_ode = SRNN_reservoir(0, S, u_fun, params_ode);
    dS_dde = SRNN_reservoir_DDE(0, S, Z, u_fun, params_dde);

    layout = state_layout(params_ode);
    % Local SFA/STD derivatives (a and b rows) must match; only x may differ
    testCase.verifyEqual(dS_ode(layout.idx_a_E), dS_dde(layout.idx_a_E), ...
        'AbsTol', 1e-12, 'RelTol', 1e-12);
    testCase.verifyEqual(dS_ode(layout.idx_a_I), dS_dde(layout.idx_a_I), ...
        'AbsTol', 1e-12, 'RelTol', 1e-12);
    testCase.verifyEqual(dS_ode(layout.idx_b_E), dS_dde(layout.idx_b_E), ...
        'AbsTol', 1e-12, 'RelTol', 1e-12);
    testCase.verifyEqual(dS_ode(layout.idx_b_I), dS_dde(layout.idx_b_I), ...
        'AbsTol', 1e-12, 'RelTol', 1e-12);
    testCase.verifyGreaterThan(max(abs(dS_ode(layout.idx_x) - dS_dde(layout.idx_x))), 1e-8);
end
