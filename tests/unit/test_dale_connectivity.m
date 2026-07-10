function tests = test_dale_connectivity
tests = functiontests(localfunctions);
end

function testDefaultConfigHasZeroSignViolations(testCase)
    seeds = 1729:1748;
    for seed = seeds
        [~, meta] = default_MESN_config(struct( ...
            'n', 20 + mod(seed, 5), ...
            'fraction_E', 0.5, ...
            'weight_rng_seed', seed, ...
            'dale', true, ...
            'row_center_W', false));
        testCase.verifyEqual(meta.sign_violations_E, 0);
        testCase.verifyEqual(meta.sign_violations_I, 0);
    end
end

function testOddEvenPopulationSizes(testCase)
    configs = {
        struct('n', 21, 'fraction_E', 0.5)
        struct('n', 22, 'fraction_E', 0.45)
        struct('n', 30, 'fraction_E', 0.6)
        };
    for i = 1:numel(configs)
        [params, meta] = default_MESN_config(configs{i});
        testCase.verifyEqual(sum(params.W(:, params.E_indices) < 0, 'all'), 0);
        testCase.verifyEqual(sum(params.W(:, params.I_indices) > 0, 'all'), 0);
        testCase.verifyEqual(meta.sign_violations_E, 0);
        testCase.verifyEqual(meta.sign_violations_I, 0);
    end
end

function testBothScaleMethodsPreserveSigns(testCase)
    methods = {'abscissa', 'radius'};
    for i = 1:numel(methods)
        params = default_MESN_config(struct( ...
            'n', 16, 'W_scale_method', methods{i}, 'level_of_chaos', 1.3));
        testCase.verifyGreaterThanOrEqual(min(params.W(:, params.E_indices), 0), 0);
        testCase.verifyLessThanOrEqual(max(params.W(:, params.I_indices)), 0);
    end
end

function testCreateWMatrixPreservesDaleSigns(testCase)
    base = struct('n', 24, 'n_E', 12, 'n_I', 12, 'mu_E', 1, 'mu_I', -1, ...
        'G_stdev', 0.5, 'indegree', 8, 'dale', true, 'row_center_W', false);
    for seed = 1:10
        rng(seed);
        [W, ~, ~, ~, meta] = create_W_matrix(base);
        testCase.verifyEqual(meta.sign_violations_E, 0);
        testCase.verifyEqual(meta.sign_violations_I, 0);
        testCase.verifyGreaterThanOrEqual(min(W(:, 1:base.n_E), [], 'all'), 0);
        testCase.verifyLessThanOrEqual(max(W(:, base.n_E+1:end), [], 'all'), 0);
    end
end

function testCreatePairedWMatrixPreservesDaleSigns(testCase)
    base = struct('n', 20, 'n_E', 10, 'n_I', 10, 'mu_E', 1, 'mu_I', -1, ...
        'G_stdev', 0.4, 'indegree', 6, 'dale', true, 'row_center_W', false);
    for seed = 1:10
        rng(seed);
        [W, ~, ~, ~, meta] = create_paired_W_matrix(base);
        testCase.verifyEqual(meta.sign_violations_E, 0);
        testCase.verifyEqual(meta.sign_violations_I, 0);
        testCase.verifyGreaterThanOrEqual(min(W(:, 1:base.n_E), [], 'all'), 0);
        testCase.verifyLessThanOrEqual(max(W(:, base.n_E+1:end), [], 'all'), 0);
    end
end

function testScalingDoesNotFlipSigns(testCase)
    [params, meta] = default_MESN_config(struct('n', 18, 'weight_rng_seed', 31415));
    W0 = meta.W0;
    signs_E = sign(W0(:, params.E_indices));
    signs_I = sign(W0(:, params.I_indices));
    scaled_signs_E = sign(params.W(:, params.E_indices));
    scaled_signs_I = sign(params.W(:, params.I_indices));
    testCase.verifyEqual(scaled_signs_E(signs_E ~= 0), signs_E(signs_E ~= 0));
    testCase.verifyEqual(scaled_signs_I(signs_I ~= 0), signs_I(signs_I ~= 0));
end

function testDaleCenteringCombinationRejectedInConfig(testCase)
    testCase.verifyError(@() default_MESN_config(struct( ...
        'dale', true, 'row_center_W', true)), ...
        'default_MESN_config:DaleCenteringUnsupported');
end

function testDaleCenteringCombinationRejectedInCreateW(testCase)
    params = struct('n', 10, 'n_E', 5, 'n_I', 5, 'mu_E', 1, 'mu_I', -1, ...
        'G_stdev', 1, 'indegree', 4, 'dale', true, 'row_center_W', true);
    testCase.verifyError(@() create_W_matrix(params), ...
        'create_W_matrix:DaleCenteringUnsupported');
end

function testDaleCenteringCombinationRejectedInPairedW(testCase)
    params = struct('n', 10, 'n_E', 5, 'n_I', 5, 'mu_E', 1, 'mu_I', -1, ...
        'G_stdev', 1, 'indegree', 4, 'dale', true, 'row_center_W', true);
    testCase.verifyError(@() create_paired_W_matrix(params), ...
        'create_paired_W_matrix:DaleCenteringUnsupported');
end
