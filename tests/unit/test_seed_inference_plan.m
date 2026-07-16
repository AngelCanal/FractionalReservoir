function tests = test_seed_inference_plan
% test_seed_inference_plan  Phase 5B-A frozen inference registry tests.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    testCase.TestData.repo_root = repo_root;
end

function testConfirmatoryFamilySizes(testCase)
    plan = build_seed_inference_plan('confirmatory');
    testCase.verifyEqual(plan.testing_families.confirmatory_primary_mechanism_performance.expected_count, 12);
    testCase.verifyEqual(plan.testing_families.conventional_esn_benchmark.expected_count, 4);
    testCase.verifyEqual(plan.testing_families.confirmatory_secondary_mechanism.expected_count, 27);

    counts = count_test_and_holm_by_family(plan);
    testCase.verifyEqual(counts.confirmatory_primary_mechanism_performance, 12);
    testCase.verifyEqual(counts.conventional_esn_benchmark, 4);
    testCase.verifyEqual(counts.confirmatory_secondary_mechanism, 27);
end

function testSfaSensitivityFamilySize(testCase)
    plan = build_seed_inference_plan('sfa_sensitivity');
    testCase.verifyEqual(plan.testing_families.sfa_sensitivity_performance.expected_count, 25);
    counts = count_test_and_holm_by_family(plan);
    testCase.verifyEqual(counts.sfa_sensitivity_performance, 25);
end

function testNoDuplicateTestedHypothesis(testCase)
    for analysis_set = {'confirmatory', 'sfa_sensitivity'}
        plan = build_seed_inference_plan(analysis_set{1});
        keys = {};
        for i = 1:numel(plan.hypothesis_registry)
            h = plan.hypothesis_registry{i};
            if strcmp(h.inference_action, 'test_and_holm')
                key = hypothesis_test_key(h);
                testCase.verifyFalse(ismember(key, keys), key);
                keys{end+1} = key; %#ok<AGROW>
            end
        end
    end
end

function testEveryTestedHypothesisHasEndpointAndSource(testCase)
    plan = build_seed_inference_plan('confirmatory');
    for i = 1:numel(plan.hypothesis_registry)
        h = plan.hypothesis_registry{i};
        if strcmp(h.inference_action, 'test_and_holm')
            testCase.verifyTrue(isfield(h, 'source_table') && ~isempty(h.source_table));
            testCase.verifyTrue(isfield(h, 'endpoint_id') && ~isempty(h.endpoint_id));
            testCase.verifyTrue(isfield(h, 'contrast_id') && ~isempty(h.contrast_id));
        end
    end
end

function testFixedHorizonsEstimateOnly(testCase)
    plan = build_seed_inference_plan('confirmatory');
    found = false;
    for i = 1:numel(plan.hypothesis_registry)
        h = plan.hypothesis_registry{i};
        if strcmp(h.endpoint_id, 'mg_autonomous_fixed_horizon_nrmse')
            found = true;
            testCase.verifyEqual(h.inference_action, 'estimate_only');
        end
    end
    testCase.verifyTrue(found, 'fixed_horizon registry entry required');
    % No test_and_holm on fixed horizon
    for i = 1:numel(plan.hypothesis_registry)
        h = plan.hypothesis_registry{i};
        if strcmp(h.endpoint_id, 'mg_autonomous_fixed_horizon_nrmse')
            testCase.verifyNotEqual(h.inference_action, 'test_and_holm');
        end
    end
end

function testSimpleBaselinesEstimateOnly(testCase)
    plan = build_seed_inference_plan('confirmatory');
    simple = {'linear_input_history', 'training_target_mean', ...
        'linear_autoregression', 'persistence'};
    for i = 1:numel(plan.hypothesis_registry)
        h = plan.hypothesis_registry{i};
        if isfield(h, 'baseline_name') && ismember(h.baseline_name, simple)
            testCase.verifyEqual(h.inference_action, 'estimate_only');
        end
    end
    % conventional_leaky_esn benchmark tests exist
    n_conv = 0;
    for i = 1:numel(plan.hypothesis_registry)
        h = plan.hypothesis_registry{i};
        if strcmp(h.inference_action, 'test_and_holm') && ...
                isfield(h, 'baseline_name') && ...
                strcmp(h.baseline_name, 'conventional_leaky_esn')
            n_conv = n_conv + 1;
        end
    end
    testCase.verifyEqual(n_conv, 4);
end

function testFeatureExploratoryNoTestingFamily(testCase)
    plan = build_seed_inference_plan('feature_exploratory');
    testCase.verifyTrue(isempty(fieldnames(plan.testing_families)));
    n_test = 0;
    for i = 1:numel(plan.hypothesis_registry)
        if strcmp(plan.hypothesis_registry{i}.inference_action, 'test_and_holm')
            n_test = n_test + 1;
        end
    end
    testCase.verifyEqual(n_test, 0);
end

function testFrozenProtocolFields(testCase)
    plan = build_seed_inference_plan('confirmatory');
    testCase.verifyEqual(plan.protocol_version, 'seed_level_inference_v1');
    testCase.verifyEqual(plan.independent_unit, 'base_seed');
    testCase.verifyEqual(plan.bootstrap_replicates, 20000);
    testCase.verifyEqual(plan.sign_flip_monte_carlo_replicates, 100000);
    testCase.verifyEqual(plan.rng_master_seed, 55021);
    testCase.verifyTrue(plan.global_rng_mutation_forbidden);
end

function testConfigAttachesInferencePlan(testCase)
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    testCase.verifyTrue(isfield(cfg, 'aggregation_inference_plan'));
    testCase.verifyEqual(cfg.aggregation_inference_plan.protocol_version, ...
        'seed_level_inference_v1');
    testCase.verifyEqual(cfg.aggregation_plan.protocol_version, ...
        'matched_seed_contrasts_v1');
end

function counts = count_test_and_holm_by_family(plan)
    counts = struct();
    for i = 1:numel(plan.hypothesis_registry)
        h = plan.hypothesis_registry{i};
        if strcmp(h.inference_action, 'test_and_holm')
            fam = h.multiplicity_family;
            if isfield(counts, fam)
                counts.(fam) = counts.(fam) + 1;
            else
                counts.(fam) = 1;
            end
        end
    end
end

function key = hypothesis_test_key(h)
    parts = {h.source_table, h.contrast_id, h.endpoint_id};
    if isfield(h, 'baseline_name')
        parts{end+1} = h.baseline_name;
    end
    if isfield(h, 'horizon_rule')
        parts{end+1} = h.horizon_rule;
    end
    key = strjoin(parts, '|');
end
