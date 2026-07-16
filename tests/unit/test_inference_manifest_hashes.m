function tests = test_inference_manifest_hashes
% test_inference_manifest_hashes  Inference artifact hash stability and binding.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testIdenticalArtifactIdenticalScientificHashes(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    h5a = hash_phase5a_tables(run_dir);
    inf1 = run_seed_level_inference(run_dir, struct('save', true));
    h1 = inf1.inference_manifest.output_table_hashes.inference_summary_table;
    pause(1.1);
    inf2 = run_seed_level_inference(run_dir, struct('save', true));
    h2 = inf2.inference_manifest.output_table_hashes.inference_summary_table;
    h5b = hash_phase5a_tables(run_dir);
    testCase.verifyEqual(h1, h2);
    testCase.verifyEqual(h5a.seed, h5b.seed);
    testCase.verifyEqual(h5a.bench, h5b.bench);
end

function testSourceHashMismatchRejected(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    run_seed_level_inference(run_dir, struct('save', true));
    Sm = load(fullfile(run_dir, 'aggregation', 'aggregation_manifest.mat'));
    Sm.aggregation_manifest.table_content_hashes.seed_contrast_table = 'deadbeef';
    save(fullfile(run_dir, 'aggregation', 'aggregation_manifest.mat'), '-struct', 'Sm');
    testCase.verifyError(@() run_seed_level_inference(run_dir, struct('save', false)), ...
        'run_seed_level_inference:SeedTableHashMismatch');
end

function testInferencePlanHashMismatchDetected(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    run_seed_level_inference(run_dir, struct('save', true));
    Sm = load(fullfile(run_dir, 'aggregation', 'inference', 'inference_manifest.mat'));
    Sm.inference_manifest.inference_plan_hash = 'deadbeef';
    save(fullfile(run_dir, 'aggregation', 'inference', 'inference_manifest.mat'), '-struct', 'Sm');
    val = validate_aggregation_inference_artifact(run_dir);
    testCase.verifyFalse(val.valid);
end

function h = hash_phase5a_tables(run_dir)
    Sa = load(fullfile(run_dir, 'aggregation', 'aggregation_manifest.mat'));
    h.seed = char(Sa.aggregation_manifest.table_content_hashes.seed_contrast_table);
    h.bench = char(Sa.aggregation_manifest.table_content_hashes.benchmark_contrast_table);
end
