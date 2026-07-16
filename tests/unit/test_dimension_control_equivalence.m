function tests = test_dimension_control_equivalence
% test_dimension_control_equivalence  Numerical dimension-control diagnostic.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    testCase.TestData.cfg_equiv = struct( ...
        'absolute_tolerance', 1e-8, ...
        'relative_tolerance', 1e-6, ...
        'gated_endpoint_ids', {{ ...
            'mc_total', 'narma_test_nrmse', 'mg_onestep_test_nrmse'}}, ...
        'label', 'numerical_dimension_control_check_not_statistical_equivalence');
end

function testExactEqualityPasses(testCase)
    cfg_equiv = testCase.TestData.cfg_equiv;
    r = evaluate_dimension_control_equivalence( ...
        [1, 2, 3], [1, 2, 3], [100; 101; 102], 'mc_total', cfg_equiv);
    testCase.verifyTrue(r.pass);
    testCase.verifyEqual(r.n_seeds_exceeding_tolerance, 0);
    testCase.verifyEqual(r.label, cfg_equiv.label);
end

function testBoundaryTolerancePasses(testCase)
    cfg_equiv = testCase.TestData.cfg_equiv;
    treatment = 1;
    control = 1 + cfg_equiv.absolute_tolerance;
    r = evaluate_dimension_control_equivalence(treatment, control, 100, ...
        'narma_test_nrmse', cfg_equiv);
    testCase.verifyTrue(r.pass);
    testCase.verifyLessThanOrEqual(r.max_absolute_discrepancy, ...
        cfg_equiv.absolute_tolerance + cfg_equiv.relative_tolerance * 1 + eps);
end

function testBeyondToleranceFails(testCase)
    cfg_equiv = testCase.TestData.cfg_equiv;
    treatment = 1;
    control = 1 + 1e-4;
    r = evaluate_dimension_control_equivalence(treatment, control, 100, ...
        'mg_onestep_test_nrmse', cfg_equiv);
    testCase.verifyFalse(r.pass);
    testCase.verifyEqual(r.n_seeds_exceeding_tolerance, 1);
end

function testAutonomousEndpointNotGated(testCase)
    cfg_equiv = testCase.TestData.cfg_equiv;
    r = evaluate_dimension_control_equivalence(1, 2, 100, ...
        'mg_autonomous_full_nrmse', cfg_equiv);
    testCase.verifyFalse(r.gated);
    testCase.verifyTrue(r.pass);
    testCase.verifyEqual(r.status, 'not_gated_endpoint');
end

function testProhibitedInterpretationsDocumented(testCase)
    cfg = mechanism_ablation_config('publication', 'sfa_sensitivity');
    equiv = cfg.aggregation_inference_plan.dimension_control_equivalence;
    testCase.verifyTrue(any(strcmp(equiv.prohibited_interpretations, ...
        'failure_to_reject_zero')));
    testCase.verifyTrue(any(strcmp(equiv.prohibited_interpretations, 'tost')));
end

function testPlanEquivalenceEntryIsEstimateOnly(testCase)
    plan = build_seed_inference_plan('sfa_sensitivity');
    found = false;
    for i = 1:numel(plan.hypothesis_registry)
        h = plan.hypothesis_registry{i};
        if strcmp(h.contrast_id, 'single_moment_vs_three_identical_equivalence_check')
            found = true;
            testCase.verifyEqual(h.inference_action, 'estimate_only');
        end
    end
    testCase.verifyTrue(found);
end
