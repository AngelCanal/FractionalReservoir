function tests = test_ridge_readout
tests = functiontests(localfunctions);
end

function testNoiselessAffineExact(testCase)
    rng(1729);
    n = 200;
    X = [randn(n, 1), 2 + 3 * randn(n, 1)];
    true_w = [1.5; -0.7];
    true_b = 0.3;
    Y = X * true_w + true_b;
    model = fit_ridge_readout(X, Y, 0);
    Y_hat = apply_ridge_readout(model, X);
    testCase.verifyLessThan(max(abs(Y_hat - Y)), 1e-10);
end

function testNoisyOverdetermined(testCase)
    rng(1729);
    n = 500;
    X = randn(n, 3);
    Y = X * [0.5; -1; 2] + 0.1 + 0.01 * randn(n, 1);
    model = fit_ridge_readout(X, Y, 1e-6);
    Y_hat = apply_ridge_readout(model, X);
    testCase.verifyLessThan(mean((Y_hat - Y).^2), 1e-3);
end

function testConstantFeature(testCase)
    rng(1);
    X = [ones(100, 1), randn(100, 1)];
    Y = 2 * X(:, 2) + 1;
    model = fit_ridge_readout(X, Y, 0);
    testCase.verifyTrue(model.constant_feature(1));
    testCase.verifyFalse(model.constant_feature(2));
    Y_hat = apply_ridge_readout(model, X);
    testCase.verifyLessThan(max(abs(Y_hat - Y)), 1e-10);
end

function testMultipleOutputs(testCase)
    rng(2);
    X = randn(80, 2);
    Y = [X * [1; 2] + 0.5, X * [-1; 0.5] - 1];
    model = fit_ridge_readout(X, Y, 0);
    Y_hat = apply_ridge_readout(model, X);
    testCase.verifyEqual(size(Y_hat), size(Y));
    testCase.verifyLessThan(max(abs(Y_hat - Y), [], 'all'), 1e-10);
end

function testTranslationInvarianceOfCoefficients(testCase)
    rng(3);
    X = randn(100, 2);
    Y = X * [1; -1] + 2;
    m1 = fit_ridge_readout(X, Y, 0);
    m2 = fit_ridge_readout(X + 5, Y, 0);
    testCase.verifyLessThan(max(abs(apply_ridge_readout(m1, X) - Y)), 1e-10);
    testCase.verifyLessThan(max(abs(apply_ridge_readout(m2, X + 5) - Y)), 1e-10);
end

function testInterceptNotShrunk(testCase)
    rng(4);
    X = randn(200, 2);
    Y = 5 + 0.01 * X * [1; 1];
    model = fit_ridge_readout(X, Y, 1e6);
    Y_hat = apply_ridge_readout(model, X);
    testCase.verifyEqual(mean(Y_hat), mean(Y), 'AbsTol', 1e-6);
    testCase.verifyLessThan(norm(model.coefficients), 1e-2);
end

function testWrongDimensionError(testCase)
    model = fit_ridge_readout(randn(20, 3), randn(20, 1), 0);
    testCase.verifyError(@() apply_ridge_readout(model, randn(5, 2)), ...
        'apply_ridge_readout:FeatureCount');
end
