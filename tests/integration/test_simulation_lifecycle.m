function tests = test_simulation_lifecycle
tests = functiontests(localfunctions);
end

function testEqualLengthDifferentInputs(testCase)
    params = make_test_params(struct('lags', []));
    esn = SRNN_ESN(params);
    n = 20;
    U1 = randn(n, size(params.W_in, 2));
    U2 = U1;
    U2(10, :) = U2(10, :) + 1;

    opts = struct('reset_before', true, 'update_internal_state', false, ...
        'ode_reltol', 1e-8, 'ode_abstol', 1e-10);
    [X1, ~] = esn.runReservoir(U1, opts);
    [X2, ~] = esn.runReservoir(U2, opts);
    testCase.verifyGreaterThan(max(abs(X1 - X2), [], 'all'), 1e-6);
end

function testIdenticalIndependentRuns(testCase)
    params = make_test_params(struct('lags', []));
    esn = SRNN_ESN(params);
    U = randn(15, size(params.W_in, 2));
    opts = struct('reset_before', true, 'update_internal_state', false, ...
        'ode_reltol', 1e-8, 'ode_abstol', 1e-10);
    [X1, ~] = esn.runReservoir(U, opts);
    [X2, ~] = esn.runReservoir(U, opts);
    testCase.verifyEqual(X1, X2, 'RelTol', 1e-10, 'AbsTol', 1e-10);
end

function testUpdateInternalStateFalse(testCase)
    params = make_test_params();
    esn = SRNN_ESN(params);
    S_before = esn.S;
    U = randn(10, size(params.W_in, 2));
    opts = struct('reset_before', true, 'update_internal_state', false);
    esn.runReservoir(U, opts);
    testCase.verifyEqual(esn.S, S_before, 'AbsTol', 0);
end

function testOdeContinuation(testCase)
    params = make_test_params(struct('lags', []));
    esn = SRNN_ESN(params);
    U = randn(30, size(params.W_in, 2));
    n1 = 12;
    opts1 = struct('reset_before', true, 'update_internal_state', true, ...
        'ode_reltol', 1e-8, 'ode_abstol', 1e-10);
    opts2 = struct('reset_before', false, 'update_internal_state', true, ...
        'ode_reltol', 1e-8, 'ode_abstol', 1e-10);
    [X_full, ~] = esn.runReservoir(U, struct('reset_before', true, ...
        'update_internal_state', true, 'ode_reltol', 1e-8, 'ode_abstol', 1e-10));

    esn.resetState();
    [X1, ~] = esn.runReservoir(U(1:n1, :), opts1);
    [X2, ~] = esn.runReservoir(U(n1:end, :), opts2);
    X_cat = [X1; X2(2:end, :)];
    testCase.verifyEqual(X_cat, X_full, 'RelTol', 2e-5, 'AbsTol', 2e-5);
end

function testDdeContinuationRejected(testCase)
    params = make_test_params(struct('lags', 0.05));
    esn = SRNN_ESN(params);
    U = randn(10, size(params.W_in, 2));
    esn.runReservoir(U, struct('reset_before', true, 'update_internal_state', true));
    testCase.verifyError(@() esn.runReservoir(U, struct('reset_before', false)), ...
        'SRNN_ESN:DDEContinuationUnsupported');
end

function testDdeInputIsolation(testCase)
    params = make_test_params(struct('lags', 0.05));
    esn = SRNN_ESN(params);
    n = 25;
    U1 = randn(n, 1);
    U2 = U1;
    U2(15) = U2(15) + 2;
    opts = struct('reset_before', true, 'update_internal_state', false, ...
        'dde_reltol', 1e-7, 'dde_abstol', 1e-9);
    [X1, ~] = esn.runReservoir(U1, opts);
    [X2, ~] = esn.runReservoir(U2, opts);
    testCase.verifyGreaterThan(max(abs(X1 - X2), [], 'all'), 1e-6);
end
