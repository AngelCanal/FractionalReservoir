function tests = test_adaptation_coupling
tests = functiontests(localfunctions);
end

function testMatrixMultiplicationMatchesHandCalculation(testCase)
    params = make_test_params(struct('n_a_E', 3, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0));
    params.c_a_E = [0.1, 0.25, 0.05];
    params.c_total_E = sum(params.c_a_E);
    params = validate_MESN_params(params);

    state = struct();
    state.a_E = [0.2 0.1 0.3; 0.4 0.5 0.6; 0.1 0.2 0.3];
    state.a_I = zeros(params.n_I, 0);
    state.b_E = zeros(0, 1);
    state.b_I = zeros(0, 1);
    state.x = (1:params.n)';

    q = compute_effective_q(state, params);
    expected = state.x;
    expected(params.E_indices) = expected(params.E_indices) - state.a_E * params.c_a_E(:);
    testCase.verifyEqual(q, expected, 'RelTol', 1e-12);
end

function testOneTimescaleMatchesLegacyScalar(testCase)
    params = make_test_params(struct('n_a_E', 1, 'n_a_I', 0));
    params = rmfield(params, {'c_a_E', 'c_a_I', 'c_total_E', 'c_total_I'});
    params.c_E = 0.2;
    params = validate_MESN_params(params);

    esn = SRNN_ESN(params);
    esn.resetState();
    state = unpack_state(esn.S0, params);

    q_new = compute_effective_q(state, params);
    q_legacy = state.x;
    q_legacy(params.E_indices) = q_legacy(params.E_indices) - 0.2 * state.a_E;
    testCase.verifyEqual(q_new, q_legacy, 'RelTol', 1e-12);
end

function testFixedTotalWhenAddingFilters(testCase)
    p1 = default_MESN_config(struct('n_a_E', 1, 'n_a_I', 0));
    p3 = default_MESN_config(struct('n_a_E', 3, 'n_a_I', 0));
    testCase.verifyEqual(p1.c_total_E, p3.c_total_E, 'RelTol', 1e-12);
    testCase.verifyEqual(sum(p3.c_a_E), p3.c_total_E, 'RelTol', 1e-12);
end

function testAmbiguousLegacyAndNewFieldsError(testCase)
    params = make_test_params();
    params.c_E = 0.1;
    testCase.verifyError(@() validate_MESN_params(params), ...
        'MESN:AmbiguousAdaptationCoupling');
end

function testLegacyPathWarnsAndPreservesBehavior(testCase)
    params = make_test_params(struct('n_a_E', 2, 'n_a_I', 0));
    params = rmfield(params, {'c_a_E', 'c_total_E'});
    params.c_E = 0.2;

    lastwarn('');
    params = validate_MESN_params(params);
    [warn_msg, warn_id] = lastwarn;
    testCase.verifyEqual(warn_id, 'MESN:LegacyAdaptationCoupling');
    testCase.verifyEqual(params.c_a_E, [0.2, 0.2]);

    state = struct();
    state.a_E = [0.3 0.1; 0.2 0.4; 0.5 0.6];
    state.a_I = zeros(params.n_I, 0);
    state.b_E = zeros(0, 1);
    state.b_I = zeros(0, 1);
    state.x = ones(params.n, 1);

    q = compute_effective_q(state, params);
    q_expected = state.x;
    q_expected(params.E_indices) = q_expected(params.E_indices) - 0.2 * sum(state.a_E, 2);
    testCase.verifyEqual(q, q_expected, 'RelTol', 1e-12);
    testCase.verifyNotEmpty(warn_msg);
end

function testOdeAndDdeUseSameCoupling(testCase)
    base = make_test_params(struct('n_a_E', 2, 'n_a_I', 1, 'lags', 0.05));
    base.c_a_E = [0.12, 0.08];
    base.c_a_I = [0.05];
    base.c_total_E = sum(base.c_a_E);
    base.c_total_I = sum(base.c_a_I);
    base = validate_MESN_params(base);

    esn = SRNN_ESN(base);
    esn.resetState();
    params = esn.exportParams();
    params.W_components = esn.W_components;
    params.lags = esn.lags;

    state = unpack_state(esn.S0, params);
    S = pack_state(state, params);
    Z = S;
    u_fun = @(t) zeros(params.n, 1);

    q_ode = compute_effective_q(state, params);
    q_dde = compute_effective_q(state, params);
    testCase.verifyEqual(q_dde, q_ode, 'RelTol', 1e-12);

    dS_ode = SRNN_reservoir(0, S, u_fun, params);
    dS_dde = SRNN_reservoir_DDE(0, S, Z, u_fun, params);
    dstate_ode = unpack_state(dS_ode, params);
    dstate_dde = unpack_state(dS_dde, params);
    testCase.verifyEqual(dstate_dde.a_E, dstate_ode.a_E, 'RelTol', 1e-12);
    testCase.verifyEqual(dstate_dde.a_I, dstate_ode.a_I, 'RelTol', 1e-12);
end
