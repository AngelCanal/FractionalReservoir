function tests = test_inference_rng_isolation
% test_inference_rng_isolation  Global MATLAB RNG must not mutate.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
end

function testHelpersDoNotMutateGlobalRng(testCase)
    rng(12345, 'twister');
    rand(1, 3);  % advance global stream
    s_before_helpers = rng;

    effects = [0.2, -0.1, 0.05, 0.3, -0.2, 0.1, -0.15, 0.25];
    ns_boot = struct('operation', 'bootstrap', 'contrast_id', 'c1', 'endpoint_id', 'e1');
    ns_flip = struct('operation', 'sign_flip', 'contrast_id', 'c1', 'endpoint_id', 'e1');
    [sb, ~] = derive_inference_rng_seed(ns_boot, 55021);
    [sf, ~] = derive_inference_rng_seed(ns_flip, 55021);

    bootstrap_seed_effect_ci(effects, 20000, 0.05, sb, ns_boot);
    paired_sign_flip_test(effects, struct('exact_max_n', 16, ...
        'mc_replicates', 100000, 'stream', sf));
    holm_bonferroni_adjust([0.01, 0.04, 0.03], 0.05);
    compute_paired_effect_summary(effects, -1);
    paired_rank_biserial(effects);
    derive_inference_rng_seed(struct('operation', 'derive', 'id', 'x'), 55021);
    validate_seed_effect_vector((1:5)', effects(1:5), (1:5)', 'pilot', 'estimate_only');
    cfg_equiv = struct( ...
        'absolute_tolerance', 1e-8, ...
        'relative_tolerance', 1e-6, ...
        'gated_endpoint_ids', {{'mc_total'}}, ...
        'label', 'numerical_dimension_control_check_not_statistical_equivalence');
    evaluate_dimension_control_equivalence(ones(3, 1), ones(3, 1), [1; 2; 3], ...
        'mc_total', cfg_equiv);

    s_after_helpers = rng;
    testCase.verifyEqual(s_before_helpers, s_after_helpers);

    continuation = rand(1, 4);
    rng(12345, 'twister');
    rand(1, 3);
    reference_continuation = rand(1, 4);
    testCase.verifyEqual(continuation, reference_continuation, 'AbsTol', 0);
end
