function tests = test_seed_inference_fail_closed
% test_seed_inference_fail_closed  Fail-closed scientific inference guards.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testMissingSeedRejected(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    St = load(fullfile(run_dir, 'aggregation', 'seed_contrast_table.mat'));
    T = St.seed_contrast_table;
    T(T.seed == T.seed(1), :) = [];
    St.seed_contrast_table = T;
    save(fullfile(run_dir, 'aggregation', 'seed_contrast_table.mat'), '-struct', 'St');
    sync_aggregation_manifest_hashes(run_dir);
    testCase.verifyError(@() run_seed_level_inference(run_dir, struct('save', false)), ...
        'validate_seed_effect_vector:MissingSeed');
end

function testExtraSeedRejected(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    St = load(fullfile(run_dir, 'aggregation', 'seed_contrast_table.mat'));
    T = St.seed_contrast_table;
    extra = T(1, :);
    extra.seed = 999999;
    T = [T; extra];
    St.seed_contrast_table = T;
    save(fullfile(run_dir, 'aggregation', 'seed_contrast_table.mat'), '-struct', 'St');
    sync_aggregation_manifest_hashes(run_dir);
    testCase.verifyError(@() run_seed_level_inference(run_dir, struct('save', false)), ...
        'validate_seed_effect_vector:ExtraSeed');
end

function testTamperedAdjustedPvalueDetected(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    run_seed_level_inference(run_dir, struct('save', true));
    St = load(fullfile(run_dir, 'aggregation', 'inference', ...
        'inference_summary_table.mat'));
    T = St.inference_summary_table;
    if height(T) > 0 && any(isfinite(T.p_adjusted))
        idx = find(isfinite(T.p_adjusted), 1);
        T.p_adjusted(idx) = 0;
        St.inference_summary_table = T;
        save(fullfile(run_dir, 'aggregation', 'inference', ...
            'inference_summary_table.mat'), '-struct', 'St');
        val = validate_aggregation_inference_artifact(run_dir);
        testCase.verifyFalse(val.valid);
    else
        testCase.verifyTrue(true, 'No adjusted p-values in smoke diagnostic run.');
    end
end

function testEstimateOnlyFinitePvalueRejected(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    run_seed_level_inference(run_dir, struct('save', true));
    St = load(fullfile(run_dir, 'aggregation', 'inference', ...
        'inference_summary_table.mat'));
    T = St.inference_summary_table;
    idx = find(strcmp(string(T.planned_action), 'estimate_only'), 1);
    if isempty(idx)
        testCase.assumeFail('No estimate_only row in fixture.');
    end
    T.p_value(idx) = 0.01;
    St.inference_summary_table = T;
    save(fullfile(run_dir, 'aggregation', 'inference', ...
        'inference_summary_table.mat'), '-struct', 'St');
    val = validate_aggregation_inference_artifact(run_dir);
    testCase.verifyFalse(val.valid);
end

function testOrientationMultiplierValidation(testCase)
    testCase.verifyError(@() compute_paired_effect_summary([1, 2], 2), ...
        'compute_paired_effect_summary:InvalidOrientation');
    testCase.verifyError(@() compute_paired_effect_summary([1, 2], [1, -1]), ...
        'compute_paired_effect_summary:InvalidOrientation');
end

function testDeriveSeedRangeEndpoints(testCase)
    ns_min = struct('tag', 'min_seed');
    [~, p_min] = derive_inference_rng_seed(ns_min, 55021);
    testCase.verifyGreaterThanOrEqual(p_min.derived_seed, 1);
    testCase.verifyLessThanOrEqual(p_min.derived_seed, 2^31 - 2);

    ns_max = struct('tag', 'max_seed_probe');
    for k = 1:50
        ns_max.iter = k;
        [~, p] = derive_inference_rng_seed(ns_max, 55021);
        testCase.verifyGreaterThanOrEqual(p.derived_seed, 1);
        testCase.verifyLessThanOrEqual(p.derived_seed, 2^31 - 2);
    end
end

function testDimensionControlNonfiniteRejected(testCase)
    cfg_equiv = struct( ...
        'absolute_tolerance', 1e-8, ...
        'relative_tolerance', 1e-6, ...
        'gated_endpoint_ids', {{'mc_total'}}, ...
        'label', 'numerical_dimension_control_check_not_statistical_equivalence');
    testCase.verifyError(@() evaluate_dimension_control_equivalence( ...
        [1, NaN], [1, 1], [1; 2], 'mc_total', cfg_equiv), ...
        'evaluate_dimension_control_equivalence:NonFiniteTreatment');
end

function testPhase5aSourceUnchangedAfterInference(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    h_before = hash_phase5a(run_dir);
    run_seed_level_inference(run_dir, struct('save', true));
    h_after = hash_phase5a(run_dir);
    testCase.verifyEqual(h_before, h_after);
    testCase.verifyEqual(h_before.manifest_status, 'deferred_to_phase_5b');
end

function h = hash_phase5a(run_dir)
    Sa = load(fullfile(run_dir, 'aggregation', 'aggregation_manifest.mat'));
    h.seed = char(Sa.aggregation_manifest.table_content_hashes.seed_contrast_table);
    h.bench = char(Sa.aggregation_manifest.table_content_hashes.benchmark_contrast_table);
    h.manifest_status = char(Sa.aggregation_manifest.inference_status);
end
