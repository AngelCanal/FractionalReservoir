function tests = test_calibration_resume
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testCompletedArtifactResumeSkipsRecomputation(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    before = validate_operating_point_calibration(run_dir);
    cal = calibrate_operating_point(struct( ...
        'save_results', true, ...
        'verbose', false, ...
        'resume_run_dir', run_dir));
    after = validate_operating_point_calibration(run_dir);
    testCase.verifyTrue(after.valid);
    testCase.verifyTrue(after.authorizes_publication_run);
    testCase.verifyEqual(cal.calibration_manifest_hash, before.calibration_manifest_hash);
end

function testPartialCheckpointValidatesForResume(testCase)
    run_dir = make_synthetic_calibration_checkpoint(struct('n_rows', 5));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    [probe_keys, ~] = build_operating_point_calibration_probe_keys(cfg);
    plan = build_calibration_test_plan(cfg, probe_keys, ...
        compute_calibration_protocol_fingerprint(cfg, probe_keys), ...
        compute_protocol_fingerprint(cfg));
    cp = load_and_validate_calibration_checkpoint(run_dir, plan, git_head_sha_for_tests());
    testCase.verifyEqual(cp.completed_row_count, 5);
    testCase.verifyEqual(cp.status, 'in_progress');
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.authorizes_publication_run);
end

function testResumeCompletesMissingTrialRow(testCase)
    run_dir = make_synthetic_calibration_checkpoint(struct('n_rows', 511));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    testCase.verifyFalse(isfile(fullfile(run_dir, 'calibration_manifest.mat')));
    calibrate_operating_point(struct( ...
        'save_results', true, ...
        'verbose', false, ...
        'resume_run_dir', run_dir));
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyTrue(report.valid);
    Sm = load(fullfile(run_dir, 'calibration_manifest.mat'));
    testCase.verifyEqual(Sm.calibration_manifest.observed_trial_row_count, 512);
    St = load(fullfile(run_dir, 'calibration_trial_table.mat'));
    testCase.verifyEqual(height(St.calibration_trial_table), 512);
    Sc = load(fullfile(run_dir, 'calibration_checkpoint.mat'));
    testCase.verifyEqual(Sc.calibration_checkpoint.status, 'complete');
end

function testUnknownTrialKeyRejected(testCase)
    run_dir = make_synthetic_calibration_checkpoint(struct('n_rows', 2));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    path = fullfile(run_dir, 'calibration_checkpoint.mat');
    S = load(path, 'calibration_checkpoint');
    cp = S.calibration_checkpoint;
    cp.completed_trial_keys{end+1} = '99|bogus|1729';
    cp.completed_row_count = numel(cp.completed_trial_keys);
    write_calibration_checkpoint(run_dir, cp);
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    [probe_keys, ~] = build_operating_point_calibration_probe_keys(cfg);
    plan = build_calibration_test_plan(cfg, probe_keys, ...
        compute_calibration_protocol_fingerprint(cfg, probe_keys), ...
        compute_protocol_fingerprint(cfg));
    testCase.verifyError(@() load_and_validate_calibration_checkpoint( ...
        run_dir, plan, git_head_sha_for_tests()), ...
        'load_and_validate_calibration_checkpoint:UnknownTrialKey');
end