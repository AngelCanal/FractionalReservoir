function tests = test_default_config
tests = functiontests(localfunctions);
end

function testStructuralOverrideN(testCase)
    params = default_MESN_config(struct('n', 40, 'fraction_E', 0.5));
    testCase.verifyEqual(params.n, 40);
    testCase.verifyEqual(params.n_E, 20);
    testCase.verifyEqual(params.n_I, 20);
    testCase.verifySize(params.W, [40, 40]);
end

function testStructuralOverrideAdaptationCounts(testCase)
    params = default_MESN_config(struct('n_a_E', 5, 'n_a_I', 0));
    testCase.verifyEqual(params.n_a_E, 5);
    testCase.verifyEqual(params.n_a_I, 0);
    testCase.verifyEqual(numel(params.tau_a_E), 5);
    testCase.verifyEqual(numel(params.tau_a_I), 0);
end

function testStructuralOverrideStdCounts(testCase)
    params = default_MESN_config(struct('n_b_E', 0, 'n_b_I', 1));
    testCase.verifyEqual(params.n_b_E, 0);
    testCase.verifyEqual(params.n_b_I, 1);
end

function testStructuralOverrideNInputs(testCase)
    params = default_MESN_config(struct('n', 12, 'n_inputs', 4));
    testCase.verifySize(params.W_in, [12, 4]);
end

function testExplicitTauWithStructuralCounts(testCase)
    tau = [0.5, 2.0, 8.0];
    params = default_MESN_config(struct('n_a_E', 3, 'tau_a_E', tau));
    testCase.verifyEqual(params.tau_a_E, tau);
end

function testZeroAdaptationUsesEmptyTau(testCase)
    params = default_MESN_config(struct('n_a_E', 0, 'n_a_I', 0));
    testCase.verifyEqual(params.tau_a_E, zeros(1, 0));
end

function testGlobalRngUnchanged(testCase)
    rng_state_before = rng;
    default_MESN_config(struct('n', 24, 'weight_rng_seed', 999, 'input_rng_seed', 1000));
    rng_state_after = rng;
    testCase.verifyEqual(rng_state_before, rng_state_after);
end

function testInconsistentExplicitTauFailsValidation(testCase)
    testCase.verifyError(@() default_MESN_config(struct( ...
        'n_a_E', 3, 'tau_a_E', [1, 2])), 'MESN:InvalidTauA');
end

function testExplicitWOverride(testCase)
    W = eye(8);
    params = default_MESN_config(struct('n', 8, 'fraction_E', 0.5, 'W', W));
    testCase.verifyEqual(params.W, W);
end

function testExplicitWInOverride(testCase)
    W_in = ones(10, 2);
    params = default_MESN_config(struct('n', 10, 'W_in', W_in));
    testCase.verifyEqual(params.W_in, W_in);
end

function testDeterministicSeeds(testCase)
    p1 = default_MESN_config(struct('n', 15, 'weight_rng_seed', 1729, 'input_rng_seed', 1730));
    p2 = default_MESN_config(struct('n', 15, 'weight_rng_seed', 1729, 'input_rng_seed', 1730));
    testCase.verifyEqual(p1.W, p2.W);
    testCase.verifyEqual(p1.W_in, p2.W_in);
end
