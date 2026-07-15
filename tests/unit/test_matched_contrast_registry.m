function tests = test_matched_contrast_registry
% test_matched_contrast_registry  Phase 5A matched_seed_contrasts_v1 registries.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
    testCase.TestData.repo_root = repo_root;
end

function testConfirmatoryHasTenContrastsWithStrataCounts(testCase)
    plan = build_matched_aggregation_plan('confirmatory');
    testCase.verifyEqual(numel(plan.contrasts), 10);

    expect = { ...
        'sfa_timescale_distribution', 8, 4; ...
        'std_main_effect', 12, 6; ...
        'delay_main_effect', 12, NaN; ...
        'combined_architecture_system_contrast', 2, NaN; ...
        'sfa_presence_moment_matched', 8, 4; ...
        'combined_architecture_ode_analog', NaN, 2; ...
        'feature_r_vs_x', 12, 6; ...
        'sfa_distribution_x_std', 4, 2; ...
        'sfa_distribution_x_delay', 4, NaN; ...
        'std_x_delay', 6, NaN};
    ids = cellfun(@(c) c.contrast_id, plan.contrasts, 'UniformOutput', false);
    for i = 1:size(expect, 1)
        idx = find(strcmp(ids, expect{i, 1}), 1);
        testCase.verifyFalse(isempty(idx), expect{i, 1});
        c = plan.contrasts{idx};
        testCase.verifyEqual(c.expected_strata_nonautonomous, expect{i, 2});
        if isnan(expect{i, 3})
            testCase.verifyTrue(isnan(c.expected_strata_autonomous));
        else
            testCase.verifyEqual(c.expected_strata_autonomous, expect{i, 3});
        end
    end
end

function testDelayAutonomousProhibited(testCase)
    plan = build_matched_aggregation_plan('confirmatory');
    c = contrast_by_id(plan, 'delay_main_effect');
    testCase.verifyFalse(c.autonomous_allowed);
    testCase.verifyTrue(isnan(c.expected_strata_autonomous));
    auto_ids = plan.autonomous_endpoint_ids;
    for i = 1:numel(auto_ids)
        testCase.verifyFalse(any(strcmp(c.supported_endpoint_ids, auto_ids{i})));
    end
end

function testOdeAnalogAutonomousStrataTwoNonautoNan(testCase)
    plan = build_matched_aggregation_plan('confirmatory');
    c = contrast_by_id(plan, 'combined_architecture_ode_analog');
    testCase.verifyTrue(c.autonomous_allowed);
    testCase.verifyEqual(c.expected_strata_autonomous, 2);
    testCase.verifyTrue(isnan(c.expected_strata_nonautonomous));
    for i = 1:numel(plan.non_autonomous_endpoint_ids)
        testCase.verifyFalse(any(strcmp(c.supported_endpoint_ids, ...
            plan.non_autonomous_endpoint_ids{i})));
    end
end

function testSensitivityHasSixIncludingEquivalence(testCase)
    plan = build_matched_aggregation_plan('sfa_sensitivity');
    testCase.verifyEqual(numel(plan.contrasts), 6);
    ids = cellfun(@(c) c.contrast_id, plan.contrasts, 'UniformOutput', false);
    testCase.verifyTrue(any(strcmp(ids, ...
        'single_moment_vs_three_identical_equivalence_check')));
    eq = contrast_by_id(plan, 'single_moment_vs_three_identical_equivalence_check');
    testCase.verifyEqual(eq.role, 'equivalence_diagnostic');
    testCase.verifyEqual(eq.contrast_type, 'equivalence_diagnostic');
    testCase.verifyTrue(plan.inference_allowed);
    testCase.verifyTrue(isempty(plan.benchmark_contrasts));
end

function testFeatureExploratoryEmptyContrastsNoInference(testCase)
    plan = build_matched_aggregation_plan('feature_exploratory');
    testCase.verifyTrue(isempty(plan.contrasts));
    testCase.verifyTrue(isempty(plan.benchmark_contrasts));
    testCase.verifyFalse(plan.inference_allowed);
end

function testConfirmatoryAndSensitivityRegistriesSeparate(testCase)
    conf = build_matched_aggregation_plan('confirmatory');
    sens = build_matched_aggregation_plan('sfa_sensitivity');
    conf_ids = cellfun(@(c) c.contrast_id, conf.contrasts, 'UniformOutput', false);
    sens_ids = cellfun(@(c) c.contrast_id, sens.contrasts, 'UniformOutput', false);
    overlap = intersect(conf_ids, sens_ids);
    testCase.verifyTrue(isempty(overlap), ...
        sprintf('Unexpected id collision: %s', strjoin(overlap, ',')));
    testCase.verifyNotEqual(conf.analysis_set, sens.analysis_set);
end

function testProtocolVersionAndIndependentUnit(testCase)
    for as = {'confirmatory', 'sfa_sensitivity', 'feature_exploratory'}
        plan = build_matched_aggregation_plan(as{1});
        testCase.verifyEqual(plan.protocol_version, 'matched_seed_contrasts_v1');
        testCase.verifyEqual(plan.independent_unit, 'base_seed');
        testCase.verifyTrue(plan.inference_deferred_to_phase_5b);
    end
end

function testEndpointOrientations(testCase)
    plan = build_matched_aggregation_plan('confirmatory');
    ep = plan.endpoints;
    testCase.verifyEqual(ep.mc_total.orientation_multiplier, +1);
    testCase.verifyEqual(ep.mc_total.favorable_direction, 'higher');
    testCase.verifyEqual(ep.narma_test_nrmse.orientation_multiplier, -1);
    testCase.verifyEqual(ep.mg_onestep_test_nrmse.orientation_multiplier, -1);
    testCase.verifyEqual(ep.wall_time_seconds.orientation_multiplier, -1);
    testCase.verifyEqual(ep.wall_time_seconds.favorable_direction, 'lower');
    testCase.verifyEqual(ep.empirical_convergence_slope_per_time.orientation_multiplier, -1);
    testCase.verifyEqual(ep.empirical_convergence_slope_per_time.favorable_direction, ...
        'more_negative');
    testCase.verifyEqual(ep.mg_autonomous_full_nrmse.orientation_multiplier, -1);
    testCase.verifyEqual(ep.mg_autonomous_restricted_valid_horizon.orientation_multiplier, +1);
end

%% helpers
function c = contrast_by_id(plan, id)
    for i = 1:numel(plan.contrasts)
        if strcmp(plan.contrasts{i}.contrast_id, id)
            c = plan.contrasts{i};
            return;
        end
    end
    error('test_matched_contrast_registry:MissingContrast', 'No contrast %s', id);
end
