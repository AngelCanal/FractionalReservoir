function tests = test_dde_rhs
tests = functiontests(localfunctions);
end

function testDelayedRecurrentTermIsolation(testCase)
    params = make_test_params(struct( ...
        'n', 3, 'fraction_E', 2/3, 'n_a_E', 0, 'n_a_I', 0, ...
        'n_b_E', 0, 'n_b_I', 0, 'lags', 0.05, 'n_inputs', 1));

    W_inst = diag([1, 2, 3]);
    W_delayed = diag([4, 5, 6]);
    params.W = W_inst + W_delayed;
    params.W_components = {W_inst, W_delayed};

    state_now = struct();
    state_now.a_E = zeros(params.n_E, 0);
    state_now.a_I = zeros(params.n_I, 0);
    state_now.b_E = zeros(0, 1);
    state_now.b_I = zeros(0, 1);
    state_now.x = [0.1; 0.2; 0.3];

    state_del = state_now;
    state_del.x = [0.4; 0.5; 0.6];

    S = pack_state(state_now, params);
    Z = pack_state(state_del, params);
    u_fun = @(t) zeros(params.n, 1);

    dS = SRNN_reservoir_DDE(0, S, Z, u_fun, params);
    dstate = unpack_state(dS, params);

    r_now = params.activation_function(state_now.x);
    r_del = params.activation_function(state_del.x);
    expected_recurrent = W_inst * r_now + W_delayed * r_del;
    expected_dx = (-state_now.x + expected_recurrent) / params.tau_d;

    testCase.verifyEqual(dstate.x, expected_dx, 'RelTol', 1e-12);

    dS_swap = SRNN_reservoir_DDE(0, Z, S, u_fun, params);
    dstate_swap = unpack_state(dS_swap, params);
    expected_swap = (-state_del.x + W_inst * r_del + W_delayed * r_now) / params.tau_d;
    testCase.verifyEqual(dstate_swap.x, expected_swap, 'RelTol', 1e-12);
end

function testNoPersistentInSource(testCase)
    text = fileread(fullfile(find_repo_root(), 'src', 'SRNN_reservoir_DDE.m'));
    testCase.verifyTrue(isempty(regexp(text, '\mpersistent\b', 'once')));
end

function root = find_repo_root()
    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
