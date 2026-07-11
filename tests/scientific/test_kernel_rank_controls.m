function tests = test_kernel_rank_controls
tests = functiontests(localfunctions);
end

function testOrthogonalEndpointFeaturesRecoverRank(testCase)
    % Tall synthetic orthogonal endpoint features recover expected rank
    rng(1);
    R = 5;
    [Q, ~] = qr(randn(40, R), 0);
    inj = struct('KR', Q, 'GR', Q);
    kr = compute_kernel_rank(struct(), struct( ...
        'inject_features', inj, ...
        'rank_tol', 1e-8, ...
        'seed', 1));
    testCase.verifyEqual(kr.KR, R);
    testCase.verifyGreaterThan(kr.KR_effective, R - 0.25);
end

function testDuplicatedInputsOrFeaturesReduceRank(testCase)
    rng(2);
    R = 4;
    [Q, ~] = qr(randn(30, R), 0);
    X = [Q; Q]; % duplicated feature rows
    inj = struct('KR', X, 'GR', X);
    kr = compute_kernel_rank(struct(), struct( ...
        'inject_features', inj, 'rank_tol', 1e-8));
    testCase.verifyEqual(kr.KR, R);
    testCase.verifyLessThan(kr.KR, size(X, 1));
end

function testEqualSizedDifferentReservoirInputsDiffer(testCase)
    params = make_test_params(struct( ...
        'n', 8, 'n_a_E', 1, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0, ...
        'lags', [], 'level_of_chaos', 0.8));
    opts = struct('M', 6, 'L', 80, 'washout', 20, 'GR_classes', 3, ...
        'GR_repeats', 2, 'seed', 42, 'feature_mode', 'x');
    kr = compute_kernel_rank(params, opts);
    testCase.verifyGreaterThan(kr.KR_input_mean_distance, 0);
    testCase.verifyGreaterThan(kr.KR, 1);
end

function testRepeatedSeededExecutionIdentical(testCase)
    params = make_test_params(struct( ...
        'n', 6, 'n_a_E', 1, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0, ...
        'lags', [], 'level_of_chaos', 0.7));
    opts = struct('M', 5, 'L', 60, 'washout', 15, 'GR_classes', 2, ...
        'GR_repeats', 2, 'seed', 99, 'feature_mode', 'x');
    kr1 = compute_kernel_rank(params, opts);
    kr2 = compute_kernel_rank(params, opts);
    testCase.verifyEqual(kr1.KR, kr2.KR);
    testCase.verifyEqual(kr1.GR, kr2.GR);
    testCase.verifyEqual(kr1.sv_KR, kr2.sv_KR, 'AbsTol', 1e-12);
    testCase.verifyEqual(kr1.KR_effective, kr2.KR_effective, 'AbsTol', 1e-12);
end

function testDuplicateFeatureRowsCollapseRank(testCase)
    rng(3);
    v = randn(1, 5);
    Xdup = [v; v; v];
    kr = compute_kernel_rank(struct(), struct( ...
        'inject_features', struct('KR', Xdup, 'GR', Xdup), ...
        'rank_tol', 1e-8, ...
        'standardize', false));
    testCase.verifyEqual(kr.KR, 1);
end

function testDuplicateInputSequencesRejected(testCase)
    params = make_test_params(struct( ...
        'n', 4, 'n_a_E', 0, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0, 'lags', []));
    U = ones(40, 1);
    testCase.verifyError(@() compute_kernel_rank(params, struct( ...
        'override_KR_inputs', {{U, U}}, ...
        'washout', 5, ...
        'GR_classes', 1, 'GR_repeats', 1, ...
        'seed', 1)), ...
        'compute_kernel_rank:DuplicateInputs');
end
