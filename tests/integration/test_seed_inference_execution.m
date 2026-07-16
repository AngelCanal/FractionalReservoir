function tests = test_seed_inference_execution
% test_seed_inference_execution  Integration tests for Phase 5B inference.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testSmokeDiagnosticInferenceExecution(testCase)
    run_dir = make_synthetic_aggregation_run(struct('protocol_tier', 'smoke'));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    inf = run_seed_level_inference(run_dir, struct('save', true));
    testCase.verifyEqual(inf.inference_status, 'complete');
    testCase.verifyFalse(inf.publication_inference_complete);
    testCase.verifyFalse(inf.aggregation_inference_complete);
    T = inf.inference_summary_table;
    testCase.verifyGreaterThan(height(T), 0);
    for r = 1:height(T)
        testCase.verifyEqual(char(string(T.executed_action(r))), ...
            'diagnostic_only_not_for_publication');
    end
end

function testIndependentValidationAfterExecution(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    run_seed_level_inference(run_dir, struct('save', true));
    val = validate_aggregation_inference_artifact(run_dir);
    testCase.verifyTrue(val.valid);
    testCase.verifyFalse(val.aggregation_inference_complete);
end

function testGlobalRngUnchangedAfterInference(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    rng(99999, 'twister');
    rand(1, 2);
    s_before = rng;
    run_seed_level_inference(run_dir, struct('save', true));
    s_after = rng;
    testCase.verifyEqual(s_before, s_after);
end

function testBenchmarkComparisonNotDoubleReversed(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    inf = run_seed_level_inference(run_dir, struct('save', false));
    key = build_inference_hypothesis_key('benchmark_contrast', ...
        'one_step_combined_architecture', 'narma_test_nrmse', ...
        'conventional_leaky_esn', '');
    T = inf.inference_summary_table;
    mask = strcmp(string(T.hypothesis_key), key);
    testCase.verifyTrue(any(mask));
    row = T(find(mask, 1), :);
    testCase.verifyEqual(char(string(row.effect_source_column)), 'comparison_value');
    St = load(fullfile(run_dir, 'aggregation', 'benchmark_contrast_table.mat'));
    bench_T = St.benchmark_contrast_table;
    mask2 = strcmp(string(bench_T.contrast_id), 'one_step_combined_architecture') & ...
        strcmp(string(bench_T.endpoint_id), 'narma_test_nrmse') & ...
        strcmp(string(bench_T.baseline_name), 'conventional_leaky_esn') & ...
        isnan(bench_T.horizon);
    sub = bench_T(mask2, :);
    testCase.verifyEqual(row.mean_oriented_effect, mean(sub.comparison_value), 'AbsTol', 1e-10);
end

function testDuplicateSeedRejected(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    St = load(fullfile(run_dir, 'aggregation', 'seed_contrast_table.mat'));
    T = St.seed_contrast_table;
    dup = T(1, :);
    T = [T; dup];
    St.seed_contrast_table = T;
    save(fullfile(run_dir, 'aggregation', 'seed_contrast_table.mat'), '-struct', 'St');
    sync_aggregation_manifest_hashes(run_dir);
    testCase.verifyError(@() run_seed_level_inference(run_dir, struct('save', false)), ...
        'validate_seed_effect_vector:DuplicateSeed');
end

function testNonfiniteEffectRejected(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    St = load(fullfile(run_dir, 'aggregation', 'seed_contrast_table.mat'));
    T = St.seed_contrast_table;
    T.effect_oriented(1) = NaN;
    St.seed_contrast_table = T;
    save(fullfile(run_dir, 'aggregation', 'seed_contrast_table.mat'), '-struct', 'St');
    sync_aggregation_manifest_hashes(run_dir);
    testCase.verifyError(@() run_seed_level_inference(run_dir, struct('save', false)), ...
        'validate_seed_effect_vector:NonFiniteEffect');
end
