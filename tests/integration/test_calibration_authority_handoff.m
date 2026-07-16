function tests = test_calibration_authority_handoff
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testValidSyntheticArtifactAuthorizesHandoff(testCase)
    cal_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(cal_dir), 's')); %#ok<NASGU>
    val = validate_operating_point_calibration(cal_dir);
    testCase.verifyTrue(val.valid);
    testCase.verifyTrue(val.authorizes_publication_run);

    cfg = mechanism_ablation_config('publication', 'confirmatory');
    cfg.frozen_operating_point = val.frozen_operating_point;
    cfg.frozen_operating_point_provenance = struct( ...
        'schema_version', 'publication_operating_point_calibration_artifact_v1', ...
        'calibration_protocol_version', 'publication_operating_point_calibration_v1', ...
        'calibration_protocol_fingerprint', val.calibration_protocol_fingerprint, ...
        'calibration_manifest_hash', val.calibration_manifest_hash, ...
        'validation_status', 'valid', ...
        'scientific_overrides_used', false);
    cfg.protocol_fingerprint = compute_protocol_fingerprint(cfg);

    tmp = tempname;
    mkdir(tmp);
    pub_run = fullfile(tmp, 'pub_run');
    mkdir(pub_run);
    cleanup2 = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>
    copy_calibration_authority(cal_dir, pub_run);
    auth_report = validate_operating_point_calibration( ...
        fullfile(pub_run, 'calibration_authority'));
    testCase.verifyTrue(auth_report.valid);
    testCase.verifyTrue(auth_report.authorizes_publication_run);
end

function testCopiedAuthorityValidatesIndependently(testCase)
    cal_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(cal_dir), 's')); %#ok<NASGU>
    tmp = tempname;
    mkdir(tmp);
    pub_run = fullfile(tmp, 'pub_run');
    mkdir(pub_run);
    copy_calibration_authority(cal_dir, pub_run);
    report = validate_operating_point_calibration(fullfile(pub_run, 'calibration_authority'));
    testCase.verifyTrue(report.valid);
end

function testMissingCalibrationArtifactRejected(testCase)
    opts = struct('max_cells', 0, 'max_seeds', 1, 'save_results', false, 'verbose', false);
    testCase.verifyError(@() run_mechanism_ablation_full(opts), ...
        'run_mechanism_ablation_full:MissingCalibrationArtifact');
end

function testInvalidArtifactCannotStartFullRunner(testCase)
    cal_dir = make_synthetic_calibration_artifact(struct('tamper_hash', true));
    cleanup = onCleanup(@() rmdir(fileparts(cal_dir), 's')); %#ok<NASGU>
    opts = struct( ...
        'calibration_run_dir', cal_dir, ...
        'max_cells', 0, ...
        'max_seeds', 1, ...
        'save_results', false, ...
        'verbose', false);
    testCase.verifyError(@() run_mechanism_ablation_full(opts), ...
        'run_mechanism_ablation_full:InvalidCalibrationArtifact');
end

function testExpectedPublicationFingerprintConstructedInternally(testCase)
    cal_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(cal_dir), 's')); %#ok<NASGU>
    tmp = tempname;
    mkdir(tmp);
    pub_run = fullfile(tmp, 'pub_run');
    mkdir(pub_run);
    cleanup2 = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>
    copy_calibration_authority(cal_dir, pub_run);

    val = validate_operating_point_calibration(cal_dir);
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    cfg.frozen_operating_point = val.frozen_operating_point;
    cfg.frozen_operating_point_provenance = struct( ...
        'schema_version', 'publication_operating_point_calibration_artifact_v1', ...
        'calibration_protocol_version', 'publication_operating_point_calibration_v1', ...
        'calibration_protocol_fingerprint', val.calibration_protocol_fingerprint, ...
        'calibration_manifest_hash', val.calibration_manifest_hash, ...
        'validation_status', 'valid', ...
        'scientific_overrides_used', false);
    cfg.protocol_fingerprint = compute_protocol_fingerprint(cfg);

    readiness = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', struct([]), ...
        'has_manifest', true, ...
        'has_commit_sha', true, ...
        'run_dir', pub_run));
    names = {readiness.checks.name};
    testCase.verifyTrue(any(strcmp(names, 'publication_reference_constructed_internally')));
    idx = find(strcmp(names, 'fingerprint_matches_publication_reference'), 1);
    testCase.verifyTrue(readiness.checks(idx).pass);
end

function testCallerExpectedCfgForbidden(testCase)
    cfg = mechanism_ablation_config('publication');
    testCase.verifyError(@() evaluate_publication_readiness(cfg, ...
        struct('expected_cfg', cfg)), ...
        'evaluate_publication_readiness:ExpectedCfgOverrideForbidden');
end

function testReducedViaFullDoesNotRequireCalibration(testCase)
    opts = struct( ...
        'max_cells', 0, ...
        'max_seeds', 1, ...
        'save_results', false, ...
        'verbose', false, ...
        'use_reduced_lengths', true);
    [result, ~] = run_mechanism_ablation_full(opts);
    testCase.verifyEqual(result.cfg.protocol_tier, 'smoke');
end
