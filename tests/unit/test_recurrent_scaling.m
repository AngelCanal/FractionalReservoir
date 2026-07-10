function tests = test_recurrent_scaling
tests = functiontests(localfunctions);
end

function testRadiusScalingDiagonal(testCase)
    W0 = diag([2, -1, 0.5]);
    target = 1.25;
    [W, meta] = scale_recurrent_matrix(W0, target, 'radius');
    testCase.verifyEqual(meta.scaled_radius, target, 'RelTol', 1e-12);
    testCase.verifyEqual(W, (target / 2) * W0, 'RelTol', 1e-12);
end

function testAbscissaScalingDiagonal(testCase)
    W0 = diag([0.5, 0.25, 0.1]);
    target = 2.0;
    [W, meta] = scale_recurrent_matrix(W0, target, 'abscissa');
    testCase.verifyEqual(meta.scaled_abscissa, target, 'RelTol', 1e-12);
    testCase.verifyEqual(W, 4 * W0, 'RelTol', 1e-12);
end

function testZeroMatrixAbscissaError(testCase)
    testCase.verifyError(@() scale_recurrent_matrix(zeros(3), 1.0, 'abscissa'), ...
        'MESN:InvalidAbscissaScale');
end

function testNegativeAbscissaError(testCase)
    W0 = diag([-1, -2]);
    testCase.verifyError(@() scale_recurrent_matrix(W0, 1.0, 'abscissa'), ...
        'MESN:InvalidAbscissaScale');
end

function testInvalidTargetError(testCase)
    testCase.verifyError(@() scale_recurrent_matrix(eye(2), -1, 'radius'), ...
        'MESN:InvalidScaleTarget');
end

function testDaleSignsPreserved(testCase)
    % Presynaptic Dale: E columns nonnegative, I columns nonpositive.
    W0 = [1, -2; 3, -4];
    [W, ~] = scale_recurrent_matrix(W0, 1.5, 'radius');
    testCase.verifyGreaterThanOrEqual(W(:, 1), 0);
    testCase.verifyLessThanOrEqual(W(:, 2), 0);
end

function testLegacyFieldNamesMatch(testCase)
    [~, meta] = scale_recurrent_matrix(diag(2), 1.7, 'radius');
    testCase.verifyEqual(meta.level_of_chaos, meta.recurrent_scale_target);
end

function testDefaultConfigUsesScalingHelper(testCase)
    [params, ~] = default_MESN_config(struct( ...
        'n', 12, 'level_of_chaos', 1.4, 'W_scale_method', 'radius'));
    testCase.verifyEqual(max(abs(eig(params.W))), 1.4, 'RelTol', 1e-10);
end
