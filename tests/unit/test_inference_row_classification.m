function tests = test_inference_row_classification
% test_inference_row_classification  Allowlist-based inference row classification.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    testCase.TestData.plan = build_seed_inference_plan('confirmatory');
end

function testRegisteredPrimaryClassifiedTestAndHolm(testCase)
    key = build_inference_hypothesis_key('seed_contrast', ...
        'sfa_timescale_distribution', 'mc_total', '', '');
    out = classify_inference_action(key, testCase.TestData.plan);
    testCase.verifyEqual(out.planned_action, 'test_and_holm');
    testCase.verifyEqual(out.multiplicity_family, ...
        'confirmatory_primary_mechanism_performance');
end

function testUnregisteredPrimaryLookingEstimateOnly(testCase)
    key = build_inference_hypothesis_key('seed_contrast', ...
        'origins_cell_comparison', 'mc_total', '', '');
    out = classify_inference_action(key, testCase.TestData.plan);
    testCase.verifyEqual(out.planned_action, 'estimate_only');
end

function testFixedHorizonEstimateOnly(testCase)
    key = build_inference_hypothesis_key('benchmark_contrast', ...
        'autonomous_ode_analog', 'mg_autonomous_fixed_horizon_nrmse', ...
        'conventional_leaky_esn', 'fixed_horizon');
    out = classify_inference_action(key, testCase.TestData.plan);
    testCase.verifyEqual(out.planned_action, 'estimate_only');
end

function testSimpleBaselineEstimateOnly(testCase)
    key = build_inference_hypothesis_key('benchmark_contrast', ...
        'one_step_combined_architecture', 'narma_test_nrmse', ...
        'linear_input_history', '');
    out = classify_inference_action(key, testCase.TestData.plan);
    testCase.verifyEqual(out.planned_action, 'estimate_only');
end

function testConventionalEsnRegistered(testCase)
    key = build_inference_hypothesis_key('benchmark_contrast', ...
        'one_step_combined_architecture', 'narma_test_nrmse', ...
        'conventional_leaky_esn', '');
    out = classify_inference_action(key, testCase.TestData.plan);
    testCase.verifyEqual(out.planned_action, 'test_and_holm');
end

function testDiagnosticEndpointEstimateOnly(testCase)
    key = build_inference_hypothesis_key('seed_contrast', ...
        'sfa_timescale_distribution', 'wall_time_seconds', '', '');
    out = classify_inference_action(key, testCase.TestData.plan);
    testCase.verifyEqual(out.planned_action, 'estimate_only');
end
