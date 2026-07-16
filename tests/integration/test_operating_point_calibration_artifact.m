function tests = test_operating_point_calibration_artifact
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testSyntheticArtifactValidates(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyTrue(report.valid);
    testCase.verifyTrue(report.authorizes_publication_run);
    testCase.verifyEqual(report.status, 'frozen');
end

function testAllRequiredArtifactFilesPresent(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    files = {'calibration_config.mat', 'calibration_trial_table.mat', ...
        'calibration_trial_table.csv', 'calibration_candidate_table.mat', ...
        'calibration_candidate_table.csv', 'calibration_result.mat', ...
        'calibration_manifest.mat', 'calibration_manifest.json'};
    for i = 1:numel(files)
        testCase.verifyTrue(isfile(fullfile(run_dir, files{i})));
    end
end

function testManifestSchemaVersion(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    Sm = load(fullfile(run_dir, 'calibration_manifest.mat'));
    testCase.verifyEqual(Sm.calibration_manifest.schema_version, ...
        'publication_operating_point_calibration_artifact_v1');
end

function testCandidateTableHas16Rows(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    Sc = load(fullfile(run_dir, 'calibration_candidate_table.mat'));
    testCase.verifyEqual(height(Sc.calibration_candidate_table), 16);
end

function testValidatorReloadsFromDiskNotMemory(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyTrue(report.valid);
    St = load(fullfile(run_dir, 'calibration_trial_table.mat'));
    T = St.calibration_trial_table;
    T.mean_rate(1) = NaN;
    p = fullfile(run_dir, 'calibration_trial_table.mat');
    delete(p);
    calibration_trial_table = T; %#ok<NASGU>
    save(p, 'calibration_trial_table');
    report2 = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report2.valid);
end

function testNoRandStreamInArtifacts(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_operating_point_calibration(run_dir);
    names = {report.checks.name};
    idx = find(strcmp(names, 'no_randstream_objects'), 1);
    testCase.verifyTrue(report.checks(idx).pass);
end

function testScientificOverridesFalseInManifest(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    Sm = load(fullfile(run_dir, 'calibration_manifest.mat'));
    testCase.verifyFalse(Sm.calibration_manifest.scientific_overrides_used);
    testCase.verifyFalse(Sm.calibration_manifest.global_rng_mutated);
end
