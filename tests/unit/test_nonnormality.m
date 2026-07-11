function tests = test_nonnormality
tests = functiontests(localfunctions);
end

function testNormalDiagonalStable(testCase)
    A = diag([-1, -2, -3]);
    nn = compute_nonnormality(A, struct( ...
        'do_transient', false, ...
        'eta_grid', logspace(-2, 1, 20), ...
        'omega_grid', linspace(-5, 5, 41)));
    testCase.verifyEqual(nn.departure_F_norm, 0, 'AbsTol', 1e-12);
    testCase.verifyTrue(nn.is_stable);
    testCase.verifyEqual(nn.status, 'ok');
    testCase.verifyGreaterThan(nn.kreiss_lb, 0.5);
    testCase.verifyLessThan(nn.kreiss_lb, 1.5);
end

function testStableJordanBlockPositiveDeparture(testCase)
    A = [-1, 10; 0, -1];
    nn = compute_nonnormality(A, struct( ...
        'do_transient', true, ...
        't_grid', linspace(0, 5, 80), ...
        'eta_grid', logspace(-2, 1, 24), ...
        'omega_grid', linspace(-8, 8, 61)));
    testCase.verifyGreaterThan(nn.departure_F_norm, 0.1);
    testCase.verifyTrue(nn.is_stable);
    testCase.verifyGreaterThan(nn.kreiss_lb, 1.0);
    testCase.verifyGreaterThan(nn.max_transient_growth, 1.5);

    A_normal = diag([-1, -1]);
    nn_n = compute_nonnormality(A_normal, struct( ...
        'do_transient', false, ...
        'eta_grid', logspace(-2, 1, 20), ...
        'omega_grid', linspace(-5, 5, 41)));
    testCase.verifyGreaterThan(nn.kreiss_lb, nn_n.kreiss_lb);
end

function testUnstableRejectedForKreiss(testCase)
    A = [0.5, 1; 0, 0.2];
    nn = compute_nonnormality(A, struct('do_transient', false));
    testCase.verifyEqual(nn.status, 'unstable_not_applicable');
    testCase.verifyTrue(isnan(nn.kreiss_lb));
    testCase.verifyFalse(nn.is_stable);
end

function testScalarScalingLeavesNormalizedHenrici(testCase)
    A = [-1, 4; 0, -2];
    nn1 = compute_nonnormality(A, struct('do_transient', false));
    nn2 = compute_nonnormality(3 * A, struct('do_transient', false));
    testCase.verifyEqual(nn1.departure_F_norm, nn2.departure_F_norm, 'AbsTol', 1e-12);
end

function testZeroMatrixHandled(testCase)
    A = zeros(2);
    nn = compute_nonnormality(A, struct('do_transient', false));
    testCase.verifyEqual(nn.departure_F_norm, 0);
    testCase.verifyEqual(nn.status, 'unstable_not_applicable');
    testCase.verifyTrue(isnan(nn.kreiss_lb));
end
