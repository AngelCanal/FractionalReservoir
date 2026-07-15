function tests = test_aggregation_artifacts
% test_aggregation_artifacts  Phase 5A aggregation I/O + readiness flags.
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

function testWritesAllRequiredAggregationFiles(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    agg_dir = fullfile(run_dir, 'aggregation');
    required = { ...
        'aggregation_manifest.mat', ...
        'raw_cell_table.mat', 'raw_cell_table.csv', ...
        'autonomous_fixed_horizon_table.mat', 'autonomous_fixed_horizon_table.csv', ...
        'unique_seed_baseline_table.mat', 'unique_seed_baseline_table.csv', ...
        'seed_contrast_table.mat', 'seed_contrast_table.csv', ...
        'benchmark_contrast_table.mat', 'benchmark_contrast_table.csv', ...
        'dale_resolution_table.mat', 'dale_resolution_table.csv', ...
        'aggregate_seed_contrasts.mat'};
    for i = 1:numel(required)
        testCase.verifyTrue(isfile(fullfile(agg_dir, required{i})), required{i});
    end
end

function testAggregationManifestHasRequiredFields(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', true));
    M = agg.aggregation_manifest;
    required = { ...
        'aggregation_protocol_version', 'source_run_directory', ...
        'source_protocol_fingerprint', 'active_analysis_set', ...
        'expected_seeds', 'expected_cell_keys', 'expected_pair_count', ...
        'observed_pair_count', 'table_row_counts', 'no_inference', ...
        'inference_status', 'table_content_hashes', ...
        'matched_seed_contrast_structure_complete', ...
        'aggregation_inference_complete', 'created_utc'};
    for i = 1:numel(required)
        testCase.verifyTrue(isfield(M, required{i}), required{i});
    end
    testCase.verifyEqual(M.inference_status, 'deferred_to_phase_5b');
    testCase.verifyTrue(M.no_inference);
    testCase.verifyFalse(M.aggregation_inference_complete);
end

function testAggregateInferenceStatusDeferred(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    testCase.verifyEqual(agg.inference_status, 'deferred_to_phase_5b');
    testCase.verifyTrue(agg.matched_seed_contrast_structure_complete);
    testCase.verifyFalse(agg.aggregation_inference_complete);
end

function testPublicationReadinessStructureMayPassInferenceFalse(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', true));
    cfg = load_cfg(run_dir);

    % Build options as a scalar struct (avoid struct('cell_records', {}) → 0x0).
    eval_opts = struct();
    eval_opts.cell_records = struct([]);
    eval_opts.has_manifest = true;
    eval_opts.has_commit_sha = true;
    eval_opts.has_artifact_hashes = false;
    eval_opts.run_dir = run_dir;
    eval_opts.aggregation = agg;
    eval_opts.aggregation_inference_complete = false;
    report = evaluate_publication_readiness(cfg, eval_opts);

    testCase.verifyTrue(report.matched_seed_contrast_structure_complete);
    testCase.verifyFalse(report.aggregation_inference_complete);
    testCase.verifyFalse(report.publication_ready);

    names = {report.checks.name};
    idx = find(strcmp(names, 'aggregation_inference_complete'), 1);
    testCase.verifyFalse(report.checks(idx).pass);
    idx2 = find(strcmp(names, 'matched_seed_contrast_structure_complete'), 1);
    testCase.verifyTrue(report.checks(idx2).pass);
end

function testRuntimeTimestampsNotInScientificHashes(testCase)
    cfg_a = mechanism_ablation_config('smoke', 'confirmatory');
    cfg_b = cfg_a;
    cfg_b.created_utc = '2099-12-31T23:59:59Z';
    testCase.verifyNotEqual(cfg_a.created_utc, cfg_b.created_utc);
    testCase.verifyEqual(compute_protocol_fingerprint(cfg_a), ...
        compute_protocol_fingerprint(cfg_b));

    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg1 = aggregate_ablation_results(run_dir, struct('save', true));
    h1 = agg1.table_content_hashes.seed_contrast_table;
    m1 = agg1.aggregation_manifest.created_utc;

    pause(1.1);  % ensure created_utc can differ
    agg2 = aggregate_ablation_results(run_dir, struct('save', true));
    h2 = agg2.table_content_hashes.seed_contrast_table;
    m2 = agg2.aggregation_manifest.created_utc;
    testCase.verifyEqual(h1, h2);
    % Manifest timestamps may differ but content hashes must not
    testCase.verifyTrue(ischar(m1) || isstring(m1));
    testCase.verifyTrue(ischar(m2) || isstring(m2));
end

function testAggregatePairedSchemaSuperseded(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    stub_path = fullfile(run_dir, 'aggregate_paired.mat');
    testCase.verifyTrue(isfile(stub_path));
    S = load(stub_path);
    testCase.verifyTrue(logical(S.schema_superseded) || ...
        (isfield(S, 'stub') && logical(S.stub.schema_superseded)));
    if isfield(S, 'schema_superseded')
        testCase.verifyTrue(S.schema_superseded);
        testCase.verifyEqual(S.replacement, 'aggregation/aggregate_seed_contrasts.mat');
        testCase.verifyEqual(S.inference_status, 'deferred_to_phase_5b');
    end
end

%% helpers
function cfg = load_cfg(run_dir)
    S = load(fullfile(run_dir, 'preregistered_config.mat'), 'cfg');
    cfg = S.cfg;
end
