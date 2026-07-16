function tests = test_calibration_runtime_fail_closed
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testGlobalRngMutationDetectedAfterExecution(testCase)
    state_before = rng;
    mutate_global_rng_for_test();
    state_after = rng;
    testCase.verifyFalse(isequal(state_before, state_after));
    rng(state_before);
    testCase.verifyEqual(rng, state_before);
end

function testCalibrationRngAuditPattern(testCase)
    state_before = capture_calibration_rng_state();
    try
        stream = RandStream('mt19937ar', 'Seed', 4242);
        x = rand(stream, 5, 1); %#ok<NASGU>
        mutate_global_rng_for_test();
        mutated = ~calibration_rng_states_equal(state_before, capture_calibration_rng_state());
        testCase.verifyTrue(mutated);
    catch ME
        restore_calibration_rng_state(state_before);
        global_restored = calibration_rng_states_equal(state_before, capture_calibration_rng_state());
        testCase.verifyTrue(global_restored);
        rethrow(ME);
    end
    restore_calibration_rng_state(state_before);
    testCase.verifyTrue(calibration_rng_states_equal(state_before, capture_calibration_rng_state()));
end

function testSyntheticArtifactRequiresRngRestored(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_operating_point_calibration(run_dir);
    names = {report.checks.name};
    idx_mut = find(strcmp(names, 'global_rng_unmutated'), 1);
    idx_res = find(strcmp(names, 'global_rng_restored'), 1);
    testCase.verifyTrue(report.checks(idx_mut).pass);
    testCase.verifyTrue(report.checks(idx_res).pass);
    testCase.verifyTrue(report.authorizes_publication_run);
end

function testMutatedRngManifestRejected(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    Sm = load(fullfile(run_dir, 'calibration_manifest.mat'));
    manifest = Sm.calibration_manifest;
    manifest.global_rng_mutated = true;
    calibration_manifest = manifest; %#ok<NASGU>
    save(fullfile(run_dir, 'calibration_manifest.mat'), 'calibration_manifest');
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.authorizes_publication_run);
end

function testIncompleteTrialMatrixRejected(testCase)
    run_dir = make_synthetic_calibration_artifact(struct('omit_row', 512));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
    testCase.verifyFalse(report.authorizes_publication_run);
end

function testConfigArtifactTamperingRejected(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    Sc = load(fullfile(run_dir, 'calibration_config.mat'));
    cfg = Sc.calibration_config;
    cfg.base.n = 39;
    calibration_config = cfg; %#ok<NASGU>
    save(fullfile(run_dir, 'calibration_config.mat'), 'calibration_config');
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
end

function testResultArtifactTamperingRejected(testCase)
    run_dir = make_synthetic_calibration_artifact(struct('tamper_result', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
end

function testJsonMatManifestDisagreementRejected(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    json_path = fullfile(run_dir, 'calibration_manifest.json');
    txt = fileread(json_path);
    txt = strrep(txt, '"frozen"', '"tampered"');
    fid = fopen(json_path, 'w');
    fwrite(fid, txt);
    fclose(fid);
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
end

function testCopiedAuthorityManifestHashMatchesSource(testCase)
    cal_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(cal_dir), 's')); %#ok<NASGU>
    src = validate_operating_point_calibration(cal_dir);
    tmp = tempname;
    mkdir(tmp);
    pub_run = fullfile(tmp, 'pub_run');
    mkdir(pub_run);
    cleanup2 = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>
    copy_calibration_authority(cal_dir, pub_run);
    dest = validate_operating_point_calibration(fullfile(pub_run, 'calibration_authority'));
    testCase.verifyEqual(dest.calibration_manifest_hash, src.calibration_manifest_hash);
    testCase.verifyTrue(dest.valid);
    testCase.verifyTrue(dest.authorizes_publication_run);
end

function testResumeRequiresSaveResults(testCase)
    run_dir = make_synthetic_calibration_checkpoint(struct('n_rows', 1));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    testCase.verifyError(@() calibrate_operating_point(struct( ...
        'save_results', false, ...
        'resume_run_dir', run_dir)), ...
        'calibrate_operating_point:ResumeRequiresSave');
end
