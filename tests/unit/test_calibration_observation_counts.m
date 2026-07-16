function tests = test_calibration_observation_counts
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testSyntheticArtifactObservationCounts(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    St = load(fullfile(run_dir, 'calibration_trial_table.mat'));
    T = St.calibration_trial_table;
    testCase.verifyEqual(T.n_eval_time_points(1), 700);
    testCase.verifyEqual(T.n_neurons(1), 40);
    testCase.verifyEqual(T.n_rate_observations(1), 28000);
    testCase.verifyGreaterThanOrEqual(T.packed_state_dimension(1), 40);
    report = validate_operating_point_calibration(run_dir);
    names = {report.checks.name};
    idx = find(strcmp(names, 'observation_counts_exact'), 1);
    testCase.verifyTrue(report.checks(idx).pass);
end

function testInconsistentObservationCountRejected(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    St = load(fullfile(run_dir, 'calibration_trial_table.mat'));
    T = St.calibration_trial_table;
    T.n_rate_observations(1) = 27999;
    p = fullfile(run_dir, 'calibration_trial_table.mat');
    delete(p);
    calibration_trial_table = T; %#ok<NASGU>
    save(p, 'calibration_trial_table');
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
    testCase.verifyTrue(any(strcmp(report.reasons, 'observation_count_mismatch')));
end

function testWrongNeuronCountRejected(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    St = load(fullfile(run_dir, 'calibration_trial_table.mat'));
    T = St.calibration_trial_table;
    T.n_neurons(:) = size(T, 1);
    p = fullfile(run_dir, 'calibration_trial_table.mat');
    delete(p);
    calibration_trial_table = T; %#ok<NASGU>
    save(p, 'calibration_trial_table');
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
end

function testMissingObservationColumnsRejected(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    St = load(fullfile(run_dir, 'calibration_trial_table.mat'));
    T = St.calibration_trial_table;
    T = removevars(T, 'n_rate_observations');
    p = fullfile(run_dir, 'calibration_trial_table.mat');
    delete(p);
    calibration_trial_table = T; %#ok<NASGU>
    save(p, 'calibration_trial_table');
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
end

function testWrongEvalTimePointsRejected(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    St = load(fullfile(run_dir, 'calibration_trial_table.mat'));
    T = St.calibration_trial_table;
    T.n_eval_time_points(:) = 699;
    T.n_rate_observations(:) = 699 * 40;
    p = fullfile(run_dir, 'calibration_trial_table.mat');
    delete(p);
    calibration_trial_table = T; %#ok<NASGU>
    save(p, 'calibration_trial_table');
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
end

function testPackedStateWidthNotUsedAsNeuronCount(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    St = load(fullfile(run_dir, 'calibration_trial_table.mat'));
    T = St.calibration_trial_table;
    wide = T(T.packed_state_dimension > 40, :);
    testCase.verifyGreaterThan(height(wide), 0);
    testCase.verifyEqual(wide.n_neurons(1), 40);
    testCase.verifyNotEqual(wide.n_neurons(1), wide.packed_state_dimension(1));
end
