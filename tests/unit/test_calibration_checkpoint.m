function tests = test_calibration_checkpoint
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testCheckpointSchemaAndHash(testCase)
    run_dir = make_synthetic_calibration_checkpoint(struct('n_rows', 3));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    [probe_keys, ~] = build_operating_point_calibration_probe_keys(cfg);
    cal_fp = compute_calibration_protocol_fingerprint(cfg, probe_keys);
    base_fp = compute_protocol_fingerprint(cfg);
    plan = build_calibration_test_plan(cfg, probe_keys, cal_fp, base_fp);
    commit_sha = git_head_sha_for_tests();
    cp = load_and_validate_calibration_checkpoint(run_dir, plan, commit_sha);
    testCase.verifyEqual(cp.schema_version, ...
        'publication_operating_point_calibration_checkpoint_v1');
    testCase.verifyEqual(cp.expected_row_count, 512);
    testCase.verifyEqual(cp.completed_row_count, 3);
    testCase.verifyEqual(cp.status, 'in_progress');
end

function testDuplicateTrialKeyRejected(testCase)
    run_dir = make_synthetic_calibration_checkpoint(struct( ...
        'n_rows', 2, 'duplicate_key', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    [probe_keys, ~] = build_operating_point_calibration_probe_keys(cfg);
    plan = build_calibration_test_plan(cfg, probe_keys, ...
        compute_calibration_protocol_fingerprint(cfg, probe_keys), ...
        compute_protocol_fingerprint(cfg));
    testCase.verifyError(@() load_and_validate_calibration_checkpoint( ...
        run_dir, plan, git_head_sha_for_tests()), ...
        'load_and_validate_calibration_checkpoint:DuplicateTrialKey');
end

function testCorruptedCheckpointHashRejected(testCase)
    run_dir = make_synthetic_calibration_checkpoint(struct( ...
        'n_rows', 1, 'corrupt_hash', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    [probe_keys, ~] = build_operating_point_calibration_probe_keys(cfg);
    plan = build_calibration_test_plan(cfg, probe_keys, ...
        compute_calibration_protocol_fingerprint(cfg, probe_keys), ...
        compute_protocol_fingerprint(cfg));
    testCase.verifyError(@() load_and_validate_calibration_checkpoint( ...
        run_dir, plan, git_head_sha_for_tests()), ...
        'load_and_validate_calibration_checkpoint:CheckpointHashMismatch');
end

function testCommitMismatchRejected(testCase)
    run_dir = make_synthetic_calibration_checkpoint(struct( ...
        'n_rows', 1, 'tamper_commit', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    [probe_keys, ~] = build_operating_point_calibration_probe_keys(cfg);
    plan = build_calibration_test_plan(cfg, probe_keys, ...
        compute_calibration_protocol_fingerprint(cfg, probe_keys), ...
        compute_protocol_fingerprint(cfg));
    testCase.verifyError(@() load_and_validate_calibration_checkpoint( ...
        run_dir, plan, git_head_sha_for_tests()), ...
        'load_and_validate_calibration_checkpoint:CommitMismatch');
end

function testProtocolFingerprintMismatchRejected(testCase)
    run_dir = make_synthetic_calibration_checkpoint(struct( ...
        'n_rows', 1, 'tamper_fingerprint', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    [probe_keys, ~] = build_operating_point_calibration_probe_keys(cfg);
    plan = build_calibration_test_plan(cfg, probe_keys, ...
        compute_calibration_protocol_fingerprint(cfg, probe_keys), ...
        compute_protocol_fingerprint(cfg));
    testCase.verifyError(@() load_and_validate_calibration_checkpoint( ...
        run_dir, plan, git_head_sha_for_tests()), ...
        'load_and_validate_calibration_checkpoint:ProtocolFingerprintMismatch');
end

function testInputHashMismatchRejected(testCase)
    run_dir = make_synthetic_calibration_checkpoint(struct( ...
        'n_rows', 1, 'tamper_input_hash', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    [probe_keys, ~] = build_operating_point_calibration_probe_keys(cfg);
    plan = build_calibration_test_plan(cfg, probe_keys, ...
        compute_calibration_protocol_fingerprint(cfg, probe_keys), ...
        compute_protocol_fingerprint(cfg));
    testCase.verifyError(@() load_and_validate_calibration_checkpoint( ...
        run_dir, plan, git_head_sha_for_tests()), ...
        'load_and_validate_calibration_checkpoint:InputHashMismatch');
end

function testPartialCheckpointCannotAuthorize(testCase)
    run_dir = make_synthetic_calibration_checkpoint(struct('n_rows', 10));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
    testCase.verifyFalse(report.authorizes_publication_run);
end

function testTrialKeyFormat(testCase)
    key = build_calibration_trial_key(3, 'adapt-off__std-off__delay-ode_off__feat-x', 1729);
    testCase.verifyEqual(key, '3|adapt-off__std-off__delay-ode_off__feat-x|1729');
end