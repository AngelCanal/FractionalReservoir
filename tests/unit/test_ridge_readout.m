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
    testCase.verifyTrue(model.zero_variance_mask(1));
    testCase.verifyFalse(model.constant_feature(2));
    Z = (X - model.feature_mean) ./ model.feature_scale;
    testCase.verifyEqual(Z(:, 1), zeros(size(Z, 1), 1), 'AbsTol', 0);
    Y_hat = apply_ridge_readout(model, X);
    testCase.verifyLessThan(max(abs(Y_hat - Y)), 1e-10);
    testCase.verifyTrue(isfinite(model.coefficient_norm));
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
    testCase.verifyEqual(model.intercept, mean(Y), 'AbsTol', 1e-12);
end

function testConstantTargetRecoveredByIntercept(testCase)
    X = randn(50, 3);
    Y = 7.5 * ones(50, 1);
    model = fit_ridge_readout(X, Y, 10);
    testCase.verifyEqual(model.intercept, 7.5, 'AbsTol', 1e-12);
    testCase.verifyLessThan(norm(model.coefficients), 1e-10);
    Y_hat = apply_ridge_readout(model, X);
    testCase.verifyLessThan(max(abs(Y_hat - 7.5)), 1e-10);
end

function testWrongDimensionError(testCase)
    model = fit_ridge_readout(randn(20, 3), randn(20, 1), 0);
    testCase.verifyError(@() apply_ridge_readout(model, randn(5, 2)), ...
        'apply_ridge_readout:FeatureCount');
end

function testWellConditionedEquivalencePositiveLambda(testCase)
    rng(9);
    n = 120;
    p = 4;
    X = randn(n, p);
    Y = X * [1; -0.5; 0.25; 2] + 0.3 + 0.01 * randn(n, 1);
    lambda = 1e-2;
    model = fit_ridge_readout(X, Y, lambda);

    mu = mean(X, 1);
    scale = std(X, 0, 1);
    Z = (X - mu) ./ scale;
    Yc = Y - mean(Y);
    [U, S, V] = svd(Z, 'econ');
    s = diag(S);
    gain = s ./ (s.^2 + lambda);
    B_ref = V * (gain .* (U' * Yc));
    intercept_ref = mean(Y);

    Y_hat = apply_ridge_readout(model, X);
    Y_ref = Z * B_ref + intercept_ref;
    testCase.verifyLessThan(max(abs(Y_hat - Y_ref)), 1e-10);
    testCase.verifyLessThan(max(abs(model.coefficients - B_ref)), 1e-10);

    % Trusted normal-equation reference on well-conditioned centered design
    B_ne = (Z' * Z + lambda * eye(p)) \ (Z' * Yc);
    testCase.verifyLessThan(max(abs(B_ref - B_ne)), 1e-8);
    testCase.verifyEqual(model.conditioning_status, 'well_conditioned');
end

function testDuplicateColumnsFiniteNoWarning(testCase)
    rng(10);
    X = randn(80, 2);
    X = [X, X(:, 1)];
    Y = X(:, 1:2) * [1; -1] + 0.2;
    lastwarn('');
    warn_state = warning('error', 'MATLAB:nearlySingularMatrix');
    cleanup = onCleanup(@() warning(warn_state));
    warning('error', 'MATLAB:singularMatrix');
    model = fit_ridge_readout(X, Y, 1e-3);
    Y_hat = apply_ridge_readout(model, X);
    testCase.verifyTrue(all(isfinite(model.coefficients(:))));
    testCase.verifyTrue(all(isfinite(Y_hat(:))));
    testCase.verifyTrue(contains(string(model.conditioning_status), "rank_deficient") || ...
        model.numerical_rank < size(X, 2));
end

function testNearDuplicateColumnsFinite(testCase)
    rng(11);
    X = randn(60, 2);
    X = [X, X(:, 1) + 1e-12 * randn(60, 1)];
    Y = sum(X(:, 1:2), 2);
    warn_state = warning('error', 'MATLAB:nearlySingularMatrix');
    cleanup = onCleanup(@() warning(warn_state)); %#ok<NASGU>
    warning('error', 'MATLAB:singularMatrix');
    model = fit_ridge_readout(X, Y, 1e-4);
    Y_hat = apply_ridge_readout(model, X);
    testCase.verifyTrue(all(isfinite(model.coefficients(:))));
    testCase.verifyTrue(all(isfinite(Y_hat(:))));
end

function testMoreFeaturesThanSamples(testCase)
    rng(12);
    X = randn(20, 40);
    Y = X(:, 1:3) * [1; -1; 0.5] + 0.05 * randn(20, 1);
    warn_state = warning('error', 'MATLAB:nearlySingularMatrix');
    cleanup = onCleanup(@() warning(warn_state)); %#ok<NASGU>
    warning('error', 'MATLAB:singularMatrix');
    model = fit_ridge_readout(X, Y, 1.0);
    testCase.verifyTrue(all(isfinite(model.coefficients(:))));
    testCase.verifyLessThanOrEqual(model.numerical_rank, min(size(X)));
    testCase.verifyGreaterThan(model.numerical_rank, 0);
    testCase.verifyEqual(model.conditioning_status, 'rank_deficient_stable_ridge');
    testCase.verifyGreaterThan(model.regularized_condition_estimate, 0);
    testCase.verifyTrue(isfinite(model.regularized_condition_estimate));
    % Null directions contribute lambda to the regularized spectrum
    s_max = model.largest_singular_value;
    expected_reg = (s_max^2 + 1.0) / 1.0;
    testCase.verifyEqual(model.regularized_condition_estimate, expected_reg, ...
        'AbsTol', 1e-10 * max(1, expected_reg));
end

function testLambdaZeroMinimumNorm(testCase)
    rng(13);
    X = randn(15, 8);
    X = [X, X(:, 1)]; % exact duplicate -> nullspace
    Y = X(:, 1:2) * [1; 2];
    warn_state = warning('error', 'MATLAB:nearlySingularMatrix');
    cleanup = onCleanup(@() warning(warn_state)); %#ok<NASGU>
    warning('error', 'MATLAB:singularMatrix');
    model = fit_ridge_readout(X, Y, 0);

    mu = model.feature_mean;
    scale = model.feature_scale;
    Z = (X - mu) ./ scale;
    Yc = Y - model.target_mean;
    B_lsq = lsqminnorm(Z, Yc);
    testCase.verifyLessThan(norm(model.coefficients - B_lsq, 'fro'), 1e-8);
    testCase.verifyEqual(model.conditioning_status, 'rank_deficient_minimum_norm');
    testCase.verifyTrue(all(isfinite(apply_ridge_readout(model, X))));
end

function testTrainingOnlyPreprocessingImmutable(testCase)
    rng(14);
    X_train = randn(40, 3);
    Y_train = X_train * [1; -1; 0.5] + 0.1;
    model = fit_ridge_readout(X_train, Y_train, 1e-2);
    mu0 = model.feature_mean;
    scale0 = model.feature_scale;
    coef0 = model.coefficients;
    b0 = model.intercept;

    X_val = randn(40, 3) + 5;
    Y_val = randn(40, 1) + 100; %#ok<NASGU>
    Y_hat = apply_ridge_readout(model, X_val); %#ok<NASGU>

    testCase.verifyEqual(model.feature_mean, mu0);
    testCase.verifyEqual(model.feature_scale, scale0);
    testCase.verifyEqual(model.coefficients, coef0);
    testCase.verifyEqual(model.intercept, b0);
end

function testDeterministicFit(testCase)
    rng(15);
    X = randn(50, 4);
    Y = X * randn(4, 1) + 0.2;
    m1 = fit_ridge_readout(X, Y, 1e-3);
    m2 = fit_ridge_readout(X, Y, 1e-3);
    testCase.verifyEqual(m1.coefficients, m2.coefficients);
    testCase.verifyEqual(m1.intercept, m2.intercept);
    testCase.verifyEqual(m1.singular_values, m2.singular_values);
    testCase.verifyEqual(m1.numerical_rank, m2.numerical_rank);
    testCase.verifyEqual(m1.conditioning_status, m2.conditioning_status);
end

function testRejectsNonfiniteInputs(testCase)
    X = randn(10, 2);
    Y = randn(10, 1);
    X(1) = NaN;
    testCase.verifyError(@() fit_ridge_readout(X, Y, 1e-2), 'fit_ridge_readout:NonFinite');
end

function testRejectsNegativeLambda(testCase)
    testCase.verifyError(@() fit_ridge_readout(randn(10, 2), randn(10, 1), -1), ...
        'fit_ridge_readout:InvalidLambda');
end

function testDiagnosticsPresent(testCase)
    model = fit_ridge_readout(randn(30, 3), randn(30, 1), 0.1);
    required = {'solver_method', 'lambda', 'n_samples', 'n_features', ...
        'numerical_rank', 'rank_tolerance', 'singular_values', ...
        'largest_singular_value', 'smallest_retained_singular_value', ...
        'zero_variance_mask', 'n_zero_variance_features', ...
        'raw_condition_estimate', 'regularized_condition_estimate', ...
        'coefficient_norm', 'feature_mean', 'feature_scale', 'target_mean', ...
        'conditioning_status'};
    for i = 1:numel(required)
        testCase.verifyTrue(isfield(model, required{i}), required{i});
    end
end
