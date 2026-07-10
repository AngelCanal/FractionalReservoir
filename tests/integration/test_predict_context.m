function tests = test_predict_context
tests = functiontests(localfunctions);
end

function testUntrainedErrors(testCase)
    params = make_test_params(struct('lags', []));
    esn = SRNN_ESN(params);
    testCase.verifyError(@() esn.predict(randn(10, 1)), 'SRNN_ESN:NotTrained');
end

function testRepeatedDefaultPredictionIdentical(testCase)
    rng(1729);
    params = make_test_params(struct('lags', []));
    esn = SRNN_ESN(params);
    T = 80;
    U = randn(T, 1);
    Y = [0; U(1:end-1)];
    esn.trainReadout(U, Y, struct('train_ratio', 0.5, 'val_ratio', 0.3, ...
        'washout_steps', 5, 'lambda_grid', 1e-4));
    U_test = randn(20, 1);
    [Y1, ~, info1] = esn.predict(U_test);
    [Y2, ~, info2] = esn.predict(U_test);
    testCase.verifyEqual(Y1, Y2, 'AbsTol', 0);
    testCase.verifyTrue(info1.reset_before);
    testCase.verifyEqual(info2.n_context, 0);
end

function testContextRowsRemoved(testCase)
    rng(1);
    params = make_test_params(struct('lags', []));
    esn = SRNN_ESN(params);
    T = 90;
    U = randn(T, 1);
    Y = U;
    esn.trainReadout(U, Y, struct('train_ratio', 0.5, 'val_ratio', 0.3, ...
        'washout_steps', 5, 'lambda_grid', 0));
    context = randn(15, 1);
    U_test = randn(10, 1);
    [Y_ctx, X_ctx, info] = esn.predict(U_test, struct('context_U', context));
    testCase.verifyEqual(info.n_context, 15);
    testCase.verifyEqual(size(Y_ctx, 1), 10);
    testCase.verifyEqual(size(X_ctx, 1), 10);
end

function testOrderIndependenceAcrossSamples(testCase)
    rng(2);
    params = make_test_params(struct('lags', []));
    esn = SRNN_ESN(params);
    T = 90;
    U = randn(T, 1);
    Y = U;
    esn.trainReadout(U, Y, struct('train_ratio', 0.5, 'val_ratio', 0.3, ...
        'washout_steps', 5, 'lambda_grid', 0));
    A = randn(8, 1);
    B = randn(8, 1);
    Ya = esn.predict(A);
    Yb = esn.predict(B);
    Ya2 = esn.predict(A);
    testCase.verifyEqual(Ya, Ya2, 'AbsTol', 0);
    testCase.verifyGreaterThan(max(abs(Ya - Yb)), 0);
end
