function tests = test_operating_point_selection_rule
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testFirstFeasibleCandidateSelected(testCase)
    run_dir = make_synthetic_calibration_artifact(struct('first_feasible_candidate', 1));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    Sc = load(fullfile(run_dir, 'calibration_candidate_table.mat'));
    testCase.verifyTrue(Sc.calibration_candidate_table.selected(1));
    testCase.verifyEqual(sum(Sc.calibration_candidate_table.selected), 1);
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyTrue(report.authorizes_publication_run);
end

function testLaterFeasibleCannotReplaceFirst(testCase)
    run_dir = make_synthetic_calibration_artifact(struct('first_feasible_candidate', 3));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    Sc = load(fullfile(run_dir, 'calibration_candidate_table.mat'));
    testCase.verifyTrue(Sc.calibration_candidate_table.selected(3));
    testCase.verifyFalse(Sc.calibration_candidate_table.selected(5));
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyEqual(report.frozen_operating_point.candidate_index, 3);
end

function testNoFeasibleProducesNonauthorizingArtifact(testCase)
    run_dir = make_synthetic_calibration_artifact(struct('first_feasible_candidate', 0));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyTrue(report.valid);
    testCase.verifyFalse(report.authorizes_publication_run);
    testCase.verifyEqual(report.status, 'no_feasible_operating_point');
end

function testTamperedSelectedIndexRejected(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    Sc = load(fullfile(run_dir, 'calibration_candidate_table.mat'));
    C = Sc.calibration_candidate_table;
    C.selected(:) = false;
    C.selected(2) = true;
    p = fullfile(run_dir, 'calibration_candidate_table.mat');
    delete(p);
    calibration_candidate_table = C; %#ok<NASGU>
    save(p, 'calibration_candidate_table');
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
end

function testTamperedPassFlagRejected(testCase)
    run_dir = make_synthetic_calibration_artifact(struct('tamper_pass_row', 1));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
end

function testTamperedMetricRejected(testCase)
    run_dir = make_synthetic_calibration_artifact(struct('tamper_metric_row', 1));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
end

function testTamperedHashRejected(testCase)
    run_dir = make_synthetic_calibration_artifact(struct('tamper_hash', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
end
