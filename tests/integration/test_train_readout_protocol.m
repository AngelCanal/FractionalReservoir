function tests = test_train_readout_protocol
tests = functiontests(localfunctions);
end

function testSimulatesOnlyThroughValidation(testCase)
    params = make_test_params(struct('lags', []));
    esn = SpyESN(params);
    T = 100;
    U = randn(T, 1);
    Y = U;
    opts = struct('train_ratio', 0.5, 'val_ratio', 0.3, 'washout_steps', 5, ...
        'lambda_grid', [0, 1e-4]);
    esn.trainReadout(U, Y, opts);
    testCase.verifyEqual(esn.last_U_rows, 80);
    testCase.verifyEqual(esn.run_count, 1);
end

function testWashoutAppliedOnce(testCase)
    params = make_test_params(struct('lags', []));
    esn = SRNN_ESN(params);
    T = 120;
    U = randn(T, 1);
    Y = [0; U(1:end-1)];
    opts = struct('train_ratio', 0.5, 'val_ratio', 0.3, 'washout_steps', 10, ...
        'lambda_grid', [0, 1e-3]);
    metrics = esn.trainReadout(U, Y, opts);
    testCase.verifyEqual(metrics.washout_steps, 10);
    testCase.verifyTrue(esn.is_trained);
    testCase.verifyTrue(isstruct(esn.readout_model));
end

function testFailureDoesNotOverwriteExistingModel(testCase)
    params = make_test_params(struct('lags', []));
    esn = SRNN_ESN(params);
    T = 80;
    U = randn(T, 1);
    Y = U;
    opts = struct('train_ratio', 0.5, 'val_ratio', 0.3, 'washout_steps', 5, ...
        'lambda_grid', 1e-4);
    esn.trainReadout(U, Y, opts);
    model_before = esn.readout_model;
    W_before = esn.W_out;

    bad_opts = struct('train_ratio', 0.5, 'val_ratio', 0.3, 'washout_steps', 1000, ...
        'lambda_grid', 1e-4);
    testCase.verifyError(@() esn.trainReadout(U, Y, bad_opts), 'SRNN_ESN:InvalidWashout');
    testCase.verifyEqual(esn.readout_model.lambda, model_before.lambda);
    testCase.verifyEqual(esn.W_out, W_before);
    testCase.verifyTrue(esn.is_trained);
end

function testShuffledTargetsGivePoorHeldOut(testCase)
    rng(1729);
    params = make_test_params(struct('lags', [], 'n', 12, 'n_a_E', 1, 'n_a_I', 0, ...
        'n_b_E', 0, 'n_b_I', 0));
    esn = SRNN_ESN(params);
    T = 400;
    U = randn(T, 1);
    Y = [0; 0; U(1:end-2)];
    opts = struct('train_ratio', 0.5, 'val_ratio', 0.25, 'washout_steps', 20, ...
        'lambda_grid', [0, 1e-4, 1e-2]);
    metrics = esn.trainReadout(U, Y, opts);

    test_idx = metrics.test_idx;
    context = U(1:test_idx(1)-1, :);
    U_test = U(test_idx, :);
    Y_test = Y(test_idx, :);
    [X_all, ~] = esn.runReservoir([context; U_test], struct('reset_before', true));
    X_test = X_all(size(context, 1)+1:end, :);
    Y_pred = apply_ridge_readout(esn.readout_model, X_test);
    nrmse_real = sqrt(mean((Y_pred - Y_test).^2)) / max(std(Y_test), eps);

    Y_shuf = Y(randperm(T));
    esn2 = SRNN_ESN(params);
    esn2.trainReadout(U, Y_shuf, opts);
    [X_all2, ~] = esn2.runReservoir([context; U_test], struct('reset_before', true));
    X_test2 = X_all2(size(context, 1)+1:end, :);
    Y_pred2 = apply_ridge_readout(esn2.readout_model, X_test2);
    Y_test_shuf = Y_shuf(test_idx);
    nrmse_shuf = sqrt(mean((Y_pred2 - Y_test_shuf).^2)) / max(std(Y_test_shuf), eps);

    testCase.verifyLessThan(nrmse_real, nrmse_shuf);
    testCase.verifyFalse(isfield(metrics, 'test_nrmse'));
end
