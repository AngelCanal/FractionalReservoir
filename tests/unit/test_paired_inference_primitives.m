function tests = test_paired_inference_primitives
% test_paired_inference_primitives  Hand-checkable inference helper tests.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
end

function testHolmHandCheck(testCase)
    raw = [0.01, 0.03, 0.04];
    out = holm_bonferroni_adjust(raw, 0.05);
    testCase.verifyEqual(out.p_adjusted, [0.03; 0.06; 0.06], 'AbsTol', 1e-12);
    testCase.verifyEqual(out.holm_reject, [true; false; false]);
    testCase.verifyEqual(out.family_size, 3);
end

function testHolmOrderRestorationAndTies(testCase)
    raw = [0.04, 0.01, 0.03];
    out = holm_bonferroni_adjust(raw, 0.05);
    testCase.verifyEqual(out.p_adjusted(2), 0.03, 'AbsTol', 1e-12);
    tied = [0.02, 0.02, 0.05];
    out2 = holm_bonferroni_adjust(tied, 0.05);
    testCase.verifyEqual(out2.p_adjusted(1), out2.p_adjusted(2));
end

function testHolmBoundaryPvalues(testCase)
    out0 = holm_bonferroni_adjust(0, 0.05);
    testCase.verifyEqual(out0.p_adjusted, 0);
    testCase.verifyTrue(out0.holm_reject);
    out1 = holm_bonferroni_adjust(1, 0.05);
    testCase.verifyEqual(out1.p_adjusted, 1);
    testCase.verifyFalse(out1.holm_reject);
end

function testHolmNanRejects(testCase)
    testCase.verifyError(@() holm_bonferroni_adjust([0.1, NaN]), ...
        'holm_bonferroni_adjust:NaNPValue');
end

function testExactSignFlipMatchesBruteForce(testCase)
    effects = [0.2; -0.1; 0.05; -0.3];
    helper = paired_sign_flip_test(effects, struct('exact_max_n', 16));
    brute = brute_force_sign_flip(effects);
    testCase.verifyEqual(helper.p_value, brute.p_value, 'AbsTol', 1e-15);
    testCase.verifyEqual(helper.method, 'exact');
end

function testSignFlipAllPositiveAllZeroSymmetry(testCase)
    pos = paired_sign_flip_test([1, 2, 3], struct('exact_max_n', 16));
    neg = paired_sign_flip_test([-1, -2, -3], struct('exact_max_n', 16));
    testCase.verifyEqual(pos.p_value, neg.p_value, 'AbsTol', 1e-15);

    zero = paired_sign_flip_test([0, 0, 0], struct('exact_max_n', 16));
    testCase.verifyEqual(zero.p_value, 1);
    testCase.verifyEqual(zero.status, 'all_zero');
end

function testMonteCarloSignFlipDeterministic(testCase)
    effects = repmat(0.1, 20, 1);
    ns = struct( ...
        'protocol_version', 'seed_level_inference_v1', ...
        'analysis_set', 'confirmatory', ...
        'contrast_id', 'std_main_effect', ...
        'endpoint_id', 'mc_total', ...
        'operation', 'sign_flip');
    [s1, ~] = derive_inference_rng_seed(ns, 55021);
    [s2, ~] = derive_inference_rng_seed(ns, 55021);
    o1 = paired_sign_flip_test(effects, struct( ...
        'exact_max_n', 16, 'mc_replicates', 100000, 'stream', s1));
    o2 = paired_sign_flip_test(effects, struct( ...
        'exact_max_n', 16, 'mc_replicates', 100000, 'stream', s2));
    testCase.verifyEqual(o1.p_value, o2.p_value);
    testCase.verifyEqual(o1.method, 'monte_carlo');
    testCase.verifyEqual(o1.permutations_evaluated, 100000);

    ns2 = ns;
    ns2.endpoint_id = 'narma_test_nrmse';
    [s3, ~] = derive_inference_rng_seed(ns2, 55021);
    o3 = paired_sign_flip_test(effects, struct( ...
        'exact_max_n', 16, 'mc_replicates', 100000, 'stream', s3));
    testCase.verifyNotEqual(s1.Seed, s3.Seed);
    % Different namespace should generally yield different p (not guaranteed but seed differs)
    testCase.verifyGreaterThanOrEqual(o3.p_value, 0);
    testCase.verifyLessThanOrEqual(o3.p_value, 1);
end

function testBootstrapDeterministicAndShape(testCase)
    effects = [0.1, -0.2, 0.3, -0.05, 0.15];
    ns = struct('operation', 'bootstrap', 'contrast_id', 'a', 'endpoint_id', 'b');
    [stream, ~] = derive_inference_rng_seed(ns, 55021);
    b1 = bootstrap_seed_effect_ci(effects, 20000, 0.05, stream);
    [stream2, ~] = derive_inference_rng_seed(ns, 55021);
    b2 = bootstrap_seed_effect_ci(effects, 20000, 0.05, stream2);
    testCase.verifyEqual(b1.mean_ci, b2.mean_ci, 'AbsTol', 1e-12);
    testCase.verifyEqual(b1.n_replicates, 20000);
    testCase.verifyEqual(numel(b1.mean_ci), 2);
    testCase.verifyEqual(numel(b1.median_ci), 2);
    testCase.verifyEqual(b1.mean_point, mean(effects));
end

function testBootstrapConstantVector(testCase)
    effects = ones(8, 1) * 0.5;
    [stream, ~] = derive_inference_rng_seed(struct('op', 'boot_const'), 55021);
    b = bootstrap_seed_effect_ci(effects, 20000, 0.05, stream);
    testCase.verifyEqual(b.mean_ci(1), 0.5, 'AbsTol', 1e-12);
    testCase.verifyEqual(b.mean_ci(2), 0.5, 'AbsTol', 1e-12);
end

function testEffectSizesRankBiserialAndDz(testCase)
    pos = compute_paired_effect_summary([1, 2, 3], 1);
    testCase.verifyEqual(pos.rank_biserial, 1, 'AbsTol', 1e-12);

    neg = compute_paired_effect_summary([-1, -2, -3], 1);
    testCase.verifyEqual(neg.rank_biserial, -1, 'AbsTol', 1e-12);

    bal = compute_paired_effect_summary([1, -1, 2, -2], 1);
    testCase.verifyEqual(bal.rank_biserial, 0, 'AbsTol', 1e-12);

    with_zero = compute_paired_effect_summary([1, 0, -1], 1);
    testCase.verifyEqual(with_zero.rank_biserial_n_nonzero, 2);

    const = compute_paired_effect_summary(ones(5, 1), 1);
    testCase.verifyTrue(isnan(const.dz));
    testCase.verifyEqual(const.dz_status, 'zero_variance_undefined');
    testCase.verifyFalse(isinf(const.dz));

    cl = compute_paired_effect_summary([1, 0, -1], 1);
    testCase.verifyEqual(cl.common_language_favorable_probability, ...
        mean([1, 0, -1] > 0) + 0.5 * mean([1, 0, -1] == 0), 'AbsTol', 1e-12);
end

function out = brute_force_sign_flip(effects)
    effects = effects(:);
    n = numel(effects);
    obs = abs(mean(effects));
    tol = 1e-12;
    count_ge = 0;
    n_perm = 2^n;
    for mask = 0:(n_perm - 1)
        signs = 2 * bitget(mask, 1:n) - 1;
        if abs(mean(signs(:) .* effects)) >= obs - tol
            count_ge = count_ge + 1;
        end
    end
    out = struct('p_value', count_ge / n_perm);
end
