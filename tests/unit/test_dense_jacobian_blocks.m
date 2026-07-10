function tests = test_dense_jacobian_blocks
tests = functiontests(localfunctions);
end

function testDelayedJacobianUnsupported(testCase)
    params = hand_config();
    params.lags = 0.05;
    params = validate_MESN_params(params);
    S = pack_state(hand_state(params), params);
    testCase.verifyError(@() compute_Jacobian(S, params), ...
        'MESN:DelayedJacobianUnsupported');
end

function testJxxMatchesHandFormula(testCase)
    [params, state, S, layout, q, r, g, b] = setup_hand_case(); %#ok<ASGLU>
    J = compute_Jacobian(S, params);

    W = params.W;
    tau_d = params.tau_d;
    expected = (-eye(params.n) + W * diag(b .* g)) / tau_d;
    testCase.verifyEqual(J(layout.idx_x, layout.idx_x), expected, ...
        'AbsTol', 1e-12, 'RelTol', 1e-12);
end

function testDxDaEUsesPerTimescaleCouplingAndColumnMajor(testCase)
    [params, state, S, layout, q, r, g, b] = setup_hand_case(); %#ok<ASGLU>
    J = compute_Jacobian(S, params);

    W = params.W;
    tau_d = params.tau_d;
    E = params.E_indices(:);
    D_E = zeros(params.n, params.n_E);
    for i = 1:params.n_E
        D_E(E(i), i) = 1;
    end

    for k = 1:params.n_a_E
        cols = layout.map_a_E(:, k);
        expected = (W * diag(b .* g) * D_E) * (-params.c_a_E(k) / tau_d);
        testCase.verifyEqual(J(layout.idx_x, cols), expected, ...
            'AbsTol', 1e-12, 'RelTol', 1e-12);

        % Column-major identity: neuron i, timescale k -> i+(k-1)*n_E
        for i = 1:params.n_E
            packed = i + (k - 1) * params.n_E;
            testCase.verifyEqual(cols(i), packed);
        end
    end

    % Unequal couplings: column k=1 and k=2 must differ by c_a ratio
    cols1 = layout.map_a_E(:, 1);
    cols2 = layout.map_a_E(:, 2);
    ratio = params.c_a_E(2) / params.c_a_E(1);
    testCase.verifyEqual(J(layout.idx_x, cols2), ratio * J(layout.idx_x, cols1), ...
        'AbsTol', 1e-12, 'RelTol', 1e-12);
end

function testDxDbEMatchesHandFormula(testCase)
    [params, state, S, layout, q, r, g, b] = setup_hand_case(); %#ok<ASGLU>
    J = compute_Jacobian(S, params);

    E = params.E_indices(:);
    expected = (params.W(:, E) * diag(r(E))) / params.tau_d;
    testCase.verifyEqual(J(layout.idx_x, layout.idx_b_E), expected, ...
        'AbsTol', 1e-12, 'RelTol', 1e-12);
end

function testAdaptationSelfBlockHandEntries(testCase)
    [params, state, S, layout, q, r, g, b] = setup_hand_case(); %#ok<ASGLU>
    J = compute_Jacobian(S, params);

    % Neuron i=2 (E), timescale k=1 vs source l=2
    i = 2;
    k = 1;
    l = 2;
    row = layout.map_a_E(i, k);
    col = layout.map_a_E(i, l);
    g_i = g(params.E_indices(i));
    expected = -params.c_a_E(l) * g_i / params.tau_a_E(k);
    testCase.verifyEqual(J(row, col), expected, 'AbsTol', 1e-12, 'RelTol', 1e-12);

    % Matching timescale also has leak term
    col_self = layout.map_a_E(i, k);
    expected_self = -1 / params.tau_a_E(k) - params.c_a_E(k) * g_i / params.tau_a_E(k);
    testCase.verifyEqual(J(row, col_self), expected_self, ...
        'AbsTol', 1e-12, 'RelTol', 1e-12);
end

function testAdaptationDxHandEntry(testCase)
    [params, state, S, layout, q, r, g, b] = setup_hand_case(); %#ok<ASGLU>
    J = compute_Jacobian(S, params);

    i = 1;
    k = 2;
    row = layout.map_a_E(i, k);
    col = layout.idx_x(params.E_indices(i));
    expected = g(params.E_indices(i)) / params.tau_a_E(k);
    testCase.verifyEqual(J(row, col), expected, 'AbsTol', 1e-12, 'RelTol', 1e-12);
end

function testResourceToXAndAdaptationHandEntries(testCase)
    [params, state, S, layout, q, r, g, b] = setup_hand_case(); %#ok<ASGLU>
    J = compute_Jacobian(S, params);

    i = 1;
    neuron = params.E_indices(i);
    row_b = layout.idx_b_E(i);

    % d(db)/dx
    expected_dx = -b(neuron) * g(neuron) / params.tau_b_E_rel;
    testCase.verifyEqual(J(row_b, layout.idx_x(neuron)), expected_dx, ...
        'AbsTol', 1e-12, 'RelTol', 1e-12);

    % resource self
    expected_self = -1 / params.tau_b_E_rec - r(neuron) / params.tau_b_E_rel;
    testCase.verifyEqual(J(row_b, row_b), expected_self, ...
        'AbsTol', 1e-12, 'RelTol', 1e-12);

    % d(db)/d(a_E(:,l))
    l = 2;
    col_a = layout.map_a_E(i, l);
    expected_a = b(neuron) * g(neuron) * params.c_a_E(l) / params.tau_b_E_rel;
    testCase.verifyEqual(J(row_b, col_a), expected_a, ...
        'AbsTol', 1e-12, 'RelTol', 1e-12);
end

function testInhibitoryAdaptationCoupling(testCase)
    [params, state, S, layout, q, r, g, b] = setup_hand_case(); %#ok<ASGLU>
    J = compute_Jacobian(S, params);

    i = 1;
    k = 1;
    row = layout.map_a_I(i, k);
    col_self = layout.map_a_I(i, k);
    g_i = g(params.I_indices(i));
    expected = -1 / params.tau_a_I(k) - params.c_a_I(k) * g_i / params.tau_a_I(k);
    testCase.verifyEqual(J(row, col_self), expected, ...
        'AbsTol', 1e-12, 'RelTol', 1e-12);
end

function [params, state, S, layout, q, r, g, b] = setup_hand_case()
    params = hand_config();
    state = hand_state(params);
    S = pack_state(state, params);
    layout = state_layout(params);
    q = compute_effective_q(state, params);
    r = params.activation_function(q);
    g = params.activation_function_derivative(q);
    b = ones(params.n, 1);
    b(params.E_indices) = state.b_E;
    b(params.I_indices) = state.b_I;
end

function params = hand_config()
    % Two E, one I; two E timescales; one I timescale; STD on both.
    n = 3;
    n_E = 2;
    n_I = 1;
    W = [0.5, 0.2, -0.4;
         0.1, 0.6, -0.3;
         0.3, 0.4, -0.5];
    W_in = [0.1; -0.2; 0.05];

    params = struct();
    params.n = n;
    params.n_E = n_E;
    params.n_I = n_I;
    params.E_indices = 1:n_E;
    params.I_indices = (n_E + 1):n;
    params.W = W;
    params.W_in = W_in;
    params.tau_d = 0.55;
    params.dt = 0.1;
    params.n_a_E = 2;
    params.n_a_I = 1;
    params.tau_a_E = [0.5, 2.0];
    params.tau_a_I = 1.0;
    params.c_a_E = [0.2, 0.05];
    params.c_a_I = 0.1;
    params.c_total_E = sum(params.c_a_E);
    params.c_total_I = sum(params.c_a_I);
    params.n_b_E = 1;
    params.n_b_I = 1;
    params.tau_b_E_rec = 0.6;
    params.tau_b_E_rel = 0.1;
    params.tau_b_I_rec = 0.4;
    params.tau_b_I_rel = 0.5;
    params.lags = [];
    params.S_a = 0.85;
    params.S_c = 0.4;
    params.activation_function = @(x) piecewiseSigmoid(x, params.S_a, params.S_c);
    params.activation_function_derivative = @(x) piecewiseSigmoidDerivative(x, params.S_a, params.S_c);
    params.which_states = 'x';
    params.include_input = false;
    params.lambda = 1e-6;
    params = validate_MESN_params(params);
end

function state = hand_state(params)
    state = struct();
    state.a_E = [0.2, 0.4; 0.1, 0.3];   % n_E x n_a_E
    state.a_I = 0.15;                    % n_I x n_a_I
    state.b_E = [0.8; 0.6];
    state.b_I = 0.7;
    state.x = [0.5; -0.2; 0.1];
end
