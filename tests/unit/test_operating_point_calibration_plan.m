function tests = test_operating_point_calibration_plan
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
    testCase.TestData.repo_root = repo_root;
end

function testPublicationCalibrationUsesN40(testCase)
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    testCase.verifyEqual(cfg.base.n, 40);
    testCase.verifyEqual(cfg.operating_point.network_size, 40);
    testCase.verifyEqual(cfg.protocol_tier, 'publication');
end

function testPilotN12RejectedByCalibration(testCase)
    testCase.verifyError(@() calibrate_operating_point(struct('cfg', ...
        mechanism_ablation_config('pilot'))), ...
        'calibrate_operating_point:ScientificOverrideForbidden');
    pilot = mechanism_ablation_config('pilot');
    testCase.verifyEqual(pilot.base.n, 12);
end

function testExact16CandidatePairs(testCase)
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    testCase.verifyEqual(numel(cfg.operating_point.candidate_order), 16);
    iscale = zeros(1, 16);
    loc = zeros(1, 16);
    for i = 1:16
        iscale(i) = cfg.operating_point.candidate_order{i}.input_scaling;
        loc(i) = cfg.operating_point.candidate_order{i}.level_of_chaos;
    end
    testCase.verifyEqual(unique(iscale), cfg.operating_point.candidate_input_scaling);
    testCase.verifyEqual(unique(loc), cfg.operating_point.candidate_level_of_chaos);
    idx = 0;
    for isc = 1:4
        for ilc = 1:4
            idx = idx + 1;
            testCase.verifyEqual(cfg.operating_point.candidate_order{idx}.input_scaling, ...
                cfg.operating_point.candidate_input_scaling(isc));
            testCase.verifyEqual(cfg.operating_point.candidate_order{idx}.level_of_chaos, ...
                cfg.operating_point.candidate_level_of_chaos(ilc));
        end
    end
end

function testExact16DynamicConditions(testCase)
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    [keys, ~] = build_operating_point_calibration_probe_keys(cfg);
    testCase.verifyEqual(numel(keys), 16);
    testCase.verifyEqual(keys, expected_operating_point_calibration_probe_keys());
end

function testCalibrationSeedsExact(testCase)
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    testCase.verifyEqual(cfg.operating_point.calibration_seeds, [1729, 2718]);
    testCase.verifyEmpty(intersect(cfg.operating_point.calibration_seeds, cfg.publication_seeds));
end

function testProtocolVersionFrozen(testCase)
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    testCase.verifyEqual(cfg.operating_point.protocol_version, ...
        'publication_operating_point_calibration_v1');
end

function testScientificOverridesRejected(testCase)
    opts = struct('mean_rate_band', [0, 1]);
    testCase.verifyError(@() calibrate_operating_point(opts), ...
        'calibrate_operating_point:ScientificOverrideForbidden');
    opts = struct('probe_cell_keys', {'adapt-off__std-off__delay-ode_off__feat-x'});
    testCase.verifyError(@() calibrate_operating_point(opts), ...
        'calibrate_operating_point:ScientificOverrideForbidden');
end

function testCalibrationProtocolFingerprintStable(testCase)
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    fp1 = compute_calibration_protocol_fingerprint(cfg);
    fp2 = compute_calibration_protocol_fingerprint(cfg);
    testCase.verifyEqual(fp1, fp2);
end

function testAbsolutePathDoesNotAlterFingerprint(testCase)
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    fp = compute_calibration_protocol_fingerprint(cfg);
    cfg2 = cfg;
    cfg2.some_absolute_path = 'C:\totally\different\path';
    fp2 = compute_calibration_protocol_fingerprint(cfg2);
    testCase.verifyEqual(fp, fp2);
end
