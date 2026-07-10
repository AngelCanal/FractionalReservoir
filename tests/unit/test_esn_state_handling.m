function tests = test_esn_state_handling
tests = functiontests(localfunctions);
end

function testResetStateDeterministic(testCase)
    params = make_test_params();
    esn = SRNN_ESN(params);
    esn.resetState();
    S1 = esn.S0;
    esn.resetState();
    testCase.verifyEqual(esn.S0, S1, 'AbsTol', 0);
end

function testResetStateDoesNotTouchGlobalRng(testCase)
    params = make_test_params();
    rng(999);
    s_before = rng;
    esn = SRNN_ESN(params);
    esn.resetState();
    s_after = rng;
    testCase.verifyEqual(s_before, s_after);
end

function testResourceStatesInitializedToOne(testCase)
    params = make_test_params();
    esn = SRNN_ESN(params);
    esn.resetState();
    state = unpack_state(esn.S0, params);
    if params.n_b_E > 0
        testCase.verifyEqual(state.b_E, ones(numel(state.b_E), 1));
    end
    if params.n_b_I > 0
        testCase.verifyEqual(state.b_I, ones(numel(state.b_I), 1));
    end
end

function testComputeRatesMatchesDirect(testCase)
    params = make_test_params(struct('n_a_E', 2));
    esn = SRNN_ESN(params);
    esn.resetState();
    [r_obj, ~] = esn.computeRates(esn.S);

    state = unpack_state(esn.S, esn.params);
    q = state.x;
    q(params.E_indices) = q(params.E_indices) - state.a_E * esn.params.c_a_E(:);
    if params.n_a_I > 0
        q(params.I_indices) = q(params.I_indices) - state.a_I * esn.params.c_a_I(:);
    end
    r_direct = params.activation_function(q);

    testCase.verifyEqual(r_obj, r_direct, 'RelTol', 1e-12);
end

function testInvalidStateLengthRejected(testCase)
    params = make_test_params();
    esn = SRNN_ESN(params);
    testCase.verifyError(@() esn.setState(zeros(params.n, 1)), ...
        'MESN:InvalidStateLength');
end
