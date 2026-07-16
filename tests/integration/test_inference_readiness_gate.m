function tests = test_inference_readiness_gate
% test_inference_readiness_gate  Publication readiness inference gate repair.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testCallerBooleanForbiddenForPublication(testCase)
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    testCase.verifyError(@() evaluate_publication_readiness(cfg, struct( ...
        'aggregation_inference_complete', true, 'run_dir', tempdir)), ...
        'evaluate_publication_readiness:AggregationInferenceBooleanForbidden');
end

function testNoArtifactMeansReadinessFalse(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    cfg = load_cfg(run_dir);
    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', struct([]), ...
        'run_dir', run_dir, ...
        'aggregation', struct('status', 'ok', ...
            'matched_seed_contrast_structure_complete', true, ...
            'inference_status', 'deferred_to_phase_5b')));
    testCase.verifyFalse(report.aggregation_inference_complete);
    testCase.verifyFalse(report.publication_ready);
end

function testSmokeInferenceDoesNotCompletePublicationReadiness(testCase)
    run_dir = make_synthetic_aggregation_run(struct('protocol_tier', 'smoke'));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    run_seed_level_inference(run_dir, struct('save', true));
    cfg = load_cfg(run_dir);
    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', struct([]), ...
        'run_dir', run_dir, ...
        'has_manifest', true, ...
        'has_commit_sha', true, ...
        'aggregation', struct('status', 'ok', ...
            'matched_seed_contrast_structure_complete', true, ...
            'inference_status', 'complete')));
    testCase.verifyFalse(report.aggregation_inference_complete);
    testCase.verifyFalse(report.publication_ready);
end

function testTemporalGateFailureKeepsPublicationReadyFalse(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    run_seed_level_inference(run_dir, struct('save', true));
    cfg = load_cfg(run_dir);
    gate = struct('status', 'complete', 'passed', false, ...
        'include_input', false, 'protocol_version', 'temporal_learning_gate_v1', ...
        'seed_results', []);
    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', struct([]), ...
        'run_dir', run_dir, ...
        'has_manifest', true, ...
        'has_commit_sha', true, ...
        'temporal_learning_gate', gate, ...
        'aggregation', struct('status', 'ok', ...
            'matched_seed_contrast_structure_complete', true, ...
            'inference_status', 'complete')));
    testCase.verifyFalse(report.publication_ready);
    idx = find(strcmp({report.checks.name}, 'temporal_learning_gate_passed'), 1);
    testCase.verifyFalse(report.checks(idx).pass);
end

function cfg = load_cfg(run_dir)
    S = load(fullfile(run_dir, 'preregistered_config.mat'), 'cfg');
    cfg = S.cfg;
end
