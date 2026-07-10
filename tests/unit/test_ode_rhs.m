function tests = test_ode_rhs
tests = functiontests(localfunctions);
end

function testHandComputedDerivatives(testCase)
    params = make_test_params(struct( ...
        'n_a_E', 2, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0, 'lags', []));
    params.W = zeros(params.n);
    params.c_a_E = [0.2, 0.15];
    params.c_total_E = sum(params.c_a_E);
    params = validate_MESN_params(params);

    state = struct();
    state.a_E = [0.1 0.2; 0.3 0.4; 0.5 0.6];
    state.a_I = zeros(params.n_I, 0);
    state.b_E = zeros(0, 1);
    state.b_I = zeros(0, 1);
    state.x = (1:params.n)';

    S = pack_state(state, params);
    u_const = 0.05 * ones(params.n, 1);
    u_fun = @(t) u_const;

    dS = SRNN_reservoir(0, S, u_fun, params);
    dstate = unpack_state(dS, params);

    sum_a_E = state.a_E * params.c_a_E(:);
    q = state.x;
    q(params.E_indices) = q(params.E_indices) - sum_a_E;
    r = params.activation_function(q);

    expected_dx = (-state.x + u_const) / params.tau_d;
    testCase.verifyEqual(dstate.x, expected_dx, 'RelTol', 1e-12);

    expected_da = (r(params.E_indices) - state.a_E) ./ params.tau_a_E;
    testCase.verifyEqual(dstate.a_E, expected_da, 'RelTol', 1e-12);
end

function testNoPersistentInSource(testCase)
    text = fileread(fullfile(find_repo_root(), 'src', 'SRNN_reservoir.m'));
    testCase.verifyTrue(isempty(regexp(text, '\mpersistent\b', 'once')));
end

function root = find_repo_root()
    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
