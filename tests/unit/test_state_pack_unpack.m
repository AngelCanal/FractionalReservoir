function tests = test_state_pack_unpack
tests = functiontests(localfunctions);
end

function testRoundTripMechanismCombinations(testCase)
    combos = { ...
        struct('n_a_E', 0, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0), ...
        struct('n_a_E', 2, 'n_a_I', 1, 'n_b_E', 0, 'n_b_I', 0), ...
        struct('n_a_E', 0, 'n_a_I', 0, 'n_b_E', 1, 'n_b_I', 1), ...
        struct('n_a_E', 2, 'n_a_I', 1, 'n_b_E', 1, 'n_b_I', 1) ...
    };

    stream = RandStream('mt19937ar', 'Seed', 1729);
    for c = 1:numel(combos)
        params = make_test_params(combos{c});
        state = random_state(params, stream);
        S = pack_state(state, params);
        state2 = unpack_state(S, params);
        S2 = pack_state(state2, params);
        testCase.verifyEqual(state2, state, 'AbsTol', 0);
        testCase.verifyEqual(S2, S, 'AbsTol', 0);
    end
end

function testTimescaleMajorOrdering(testCase)
    params = make_test_params(struct('n_a_E', 2, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0));
    state = struct();
    state.a_E = [10 100; 20 200; 30 300];
    state.a_I = zeros(params.n_I, 0);
    state.b_E = zeros(0, 1);
    state.b_I = zeros(0, 1);
    state.x = zeros(params.n, 1);

    S = pack_state(state, params);
    testCase.verifyEqual(S(1:6)', [10 20 30 100 200 300]);
end

function testInvalidShapeErrors(testCase)
    params = make_test_params();
    state = random_state(params, RandStream('mt19937ar', 'Seed', 1));
    state.x = state.x'; % row vector

    testCase.verifyError(@() pack_state(state, params), 'MESN:InvalidStateShape');
end

function testInvalidLengthErrors(testCase)
    params = make_test_params();
    testCase.verifyError(@() unpack_state(zeros(params.n - 1, 1), params), ...
        'MESN:InvalidStateLength');
end

function testPackUnpackPackIdentical(testCase)
    params = make_test_params();
    state = random_state(params, RandStream('mt19937ar', 'Seed', 1729));
    S1 = pack_state(state, params);
    S2 = pack_state(unpack_state(S1, params), params);
    testCase.verifyEqual(S1, S2, 'AbsTol', 0);
end

function state = random_state(params, stream)
    state.a_E = rand(stream, params.n_E, params.n_a_E);
    state.a_I = rand(stream, params.n_I, params.n_a_I);
    if params.n_b_E > 0
        state.b_E = rand(stream, params.n_E * params.n_b_E, 1);
    else
        state.b_E = zeros(0, 1);
    end
    if params.n_b_I > 0
        state.b_I = rand(stream, params.n_I * params.n_b_I, 1);
    else
        state.b_I = zeros(0, 1);
    end
    state.x = rand(stream, params.n, 1);
end
