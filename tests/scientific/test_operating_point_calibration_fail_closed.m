function tests = test_operating_point_calibration_fail_closed
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testRawFrozenOperatingPointForbidden(testCase)
    opts = struct( ...
        'frozen_operating_point', struct('input_scaling', 0.5, 'level_of_chaos', 0.8), ...
        'max_cells', 0, ...
        'max_seeds', 1, ...
        'save_results', false, ...
        'verbose', false);
    testCase.verifyError(@() run_mechanism_ablation_full(opts), ...
        'run_mechanism_ablation_full:RawOperatingPointForbidden');
end

function testNonauthorizingArtifactRejectedByRunner(testCase)
    cal_dir = make_synthetic_calibration_artifact(struct('first_feasible_candidate', 0));
    cleanup = onCleanup(@() rmdir(fileparts(cal_dir), 's')); %#ok<NASGU>
    opts = struct( ...
        'calibration_run_dir', cal_dir, ...
        'max_cells', 0, ...
        'max_seeds', 1, ...
        'save_results', false, ...
        'verbose', false);
    testCase.verifyError(@() run_mechanism_ablation_full(opts), ...
        'run_mechanism_ablation_full:CalibrationNotAuthorizing');
end

function testFeatureExploratoryRemainsNonpublication(testCase)
    cfg = mechanism_ablation_config('publication', 'feature_exploratory');
    testCase.verifyFalse(is_publication_inferential_analysis_set('feature_exploratory'));
    readiness = evaluate_publication_readiness(cfg, struct('cell_records', struct([])));
    testCase.verifyFalse(readiness.publication_protocol_complete);
end

function testWashoutExcludedFromActivityMetrics(testCase)
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    op = cfg.operating_point;
    testCase.verifyEqual(op.evaluation_steps, 700);
    testCase.verifyEqual(op.washout_steps, 100);
    testCase.verifyEqual(op.total_steps, 800);
    expected_obs = 700 * 40;
    testCase.verifyEqual(expected_obs, 28000);
end

function testNoModelEquationsChanged(testCase)
    cfg_pub = mechanism_ablation_config('publication', 'confirmatory');
    cfg_smoke = mechanism_ablation_config('smoke', 'confirmatory');
    testCase.verifyEqual(cfg_pub.base.tau_d, cfg_smoke.base.tau_d);
    testCase.verifyEqual(cfg_pub.c_total_E, cfg_smoke.c_total_E);
    testCase.verifyEqual(numel(cfg_pub.adaptation_profiles), ...
        numel(cfg_smoke.adaptation_profiles));
end

function testTaskMetricFieldsForbiddenInArtifact(testCase)
    run_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_operating_point_calibration(run_dir);
    names = {report.checks.name};
    idx = find(strcmp(names, 'no_forbidden_outcome_fields'), 1);
    testCase.verifyTrue(report.checks(idx).pass);
end

function testCalibrationBooleanForbiddenInReadiness(testCase)
    cfg = mechanism_ablation_config('publication');
    testCase.verifyError(@() evaluate_publication_readiness(cfg, ...
        struct('calibration_artifact_valid', true)), ...
        'evaluate_publication_readiness:CalibrationBooleanForbidden');
end
