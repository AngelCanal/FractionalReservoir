function tests = test_operating_point_trial_matrix
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testSyntheticArtifactHas512Rows(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    St = load(fullfile(run_dir, 'calibration_trial_table.mat'));
    testCase.verifyEqual(height(St.calibration_trial_table), 512);
end

function testMissingRowRejected(testCase)
    run_dir = make_synthetic_calibration_artifact(struct('omit_row', 1));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
end

function testDuplicateRowRejected(testCase)
    run_dir = make_synthetic_calibration_artifact(struct('duplicate_row', 1));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
end

function testSameInputHashWithinSeed(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    St = load(fullfile(run_dir, 'calibration_trial_table.mat'));
    T = St.calibration_trial_table;
    for seed = [1729, 2718]
        sub = T(T.calibration_seed == seed, :);
        testCase.verifyEqual(numel(unique(sub.input_hash)), 1);
    end
end

function testDifferentInputHashAcrossSeeds(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    St = load(fullfile(run_dir, 'calibration_trial_table.mat'));
    T = St.calibration_trial_table;
    h1 = unique(T.input_hash(T.calibration_seed == 1729));
    h2 = unique(T.input_hash(T.calibration_seed == 2718));
    testCase.verifyNotEqual(h1{1}, h2{1});
end

function testNonfiniteMetricRejected(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    St = load(fullfile(run_dir, 'calibration_trial_table.mat'));
    T = St.calibration_trial_table;
    T.mean_rate(1) = NaN;
    p = fullfile(run_dir, 'calibration_trial_table.mat');
    delete(p);
    calibration_trial_table = T; %#ok<NASGU>
    save(p, 'calibration_trial_table');
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
end

function testSeedOverlapRejected(testCase)
    run_dir = make_synthetic_calibration_artifact(struct('overlap_seeds', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_operating_point_calibration(run_dir);
    testCase.verifyFalse(report.valid);
end

function testGlobalRngUnchangedDuringInputGeneration(testCase)
    s0 = rng;
    cleanup = onCleanup(@() rng(s0)); %#ok<NASGU>
    rng(42);
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    op = cfg.operating_point;
    seed = op.calibration_seeds(1);
    before = rng;
    stream = RandStream('mt19937ar', 'Seed', seed + op.input_seed_offset);
    rand(stream, op.total_steps, 1);
    after = rng;
    testCase.verifyEqual(before, after);
end
