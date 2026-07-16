function tests = test_inference_artifact_schema
% test_inference_artifact_schema  Phase 5B inference artifact schema checks.
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

function testSmokeInferenceWritesRequiredFiles(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    inf = run_seed_level_inference(run_dir, struct('save', true));

    inf_dir = fullfile(run_dir, 'aggregation', 'inference');
    required = { ...
        'inference_summary_table.mat', 'inference_summary_table.csv', ...
        'multiplicity_table.mat', 'multiplicity_table.csv', ...
        'resampling_provenance_table.mat', 'resampling_provenance_table.csv', ...
        'dimension_control_diagnostic.mat', 'dimension_control_diagnostic.csv', ...
        'aggregate_seed_inference.mat', ...
        'inference_manifest.mat', 'inference_manifest.json'};
    for i = 1:numel(required)
        testCase.verifyTrue(isfile(fullfile(inf_dir, required{i})), required{i});
    end
    testCase.verifyEqual(inf.inference_status, 'complete');
    testCase.verifyFalse(inf.publication_inference_complete);
end

function testManifestSchemaVersion(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    run_seed_level_inference(run_dir, struct('save', true));
    S = load(fullfile(run_dir, 'aggregation', 'inference', 'inference_manifest.mat'));
    M = S.inference_manifest;
    testCase.verifyEqual(M.schema_version, 'seed_level_inference_artifact_v1');
    testCase.verifyEqual(M.provenance_mode, 'executed_from_immutable_phase5a_tables');
    testCase.verifyFalse(M.overrides_used);
    testCase.verifyFalse(M.synthetic_fixture);
    testCase.verifyFalse(M.global_rng_mutated);
end

function testNoRandStreamInArtifacts(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    run_seed_level_inference(run_dir, struct('save', true));
    val = validate_aggregation_inference_artifact(run_dir);
    idx = find(strcmp({val.checks.name}, 'no_mutable_stream_objects'), 1);
    testCase.verifyTrue(val.checks(idx).pass);
end

function testEstimateOnlyRowsHaveNaNPvalues(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    inf = run_seed_level_inference(run_dir, struct('save', false));
    T = inf.inference_summary_table;
    for r = 1:height(T)
        if strcmp(char(T.executed_action{r}), 'diagnostic_only_not_for_publication') || ...
                strcmp(char(T.planned_action{r}), 'estimate_only')
            testCase.verifyTrue(isnan(T.p_value(r)));
            testCase.verifyFalse(logical(T.holm_reject(r)));
        end
    end
end
