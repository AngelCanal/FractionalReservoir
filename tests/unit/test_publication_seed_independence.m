function tests = test_publication_seed_independence
% test_publication_seed_independence  Phase 5B-A publication seed policy.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
end

function testPublicationSeedSet(testCase)
    cfg = mechanism_ablation_config('publication');
    testCase.verifyEqual(numel(cfg.publication_seeds), 30);
    testCase.verifyEqual(numel(unique(cfg.publication_seeds)), 30);
    testCase.verifyEqual(cfg.full_n_seeds, 30);
    testCase.verifyEqual(cfg.seeds, cfg.publication_seeds);
end

function testNoOverlapDevelopmentOrCalibration(testCase)
    cfg = mechanism_ablation_config('publication');
    testCase.verifyTrue(isempty(intersect(cfg.publication_seeds, cfg.development_seeds)));
    testCase.verifyTrue(isempty(intersect(cfg.publication_seeds, ...
        cfg.operating_point.calibration_seeds)));
    testCase.verifyEqual(cfg.pilot_seeds, cfg.development_seeds);
end

function testSmokePilotUseDevelopmentSeeds(testCase)
    smoke = mechanism_ablation_config('smoke');
    pilot = mechanism_ablation_config('pilot');
    testCase.verifyEqual(smoke.seeds, smoke.development_seeds);
    testCase.verifyEqual(pilot.seeds, pilot.development_seeds);
    testCase.verifyTrue(smoke.pilot_not_for_publication);
    testCase.verifyTrue(pilot.pilot_not_for_publication);
end

function testDevelopmentSeedsExcludedFromPublication(testCase)
    cfg = mechanism_ablation_config('publication');
    for s = cfg.development_seeds
        testCase.verifyFalse(any(cfg.seeds == s));
    end
end

function testFingerprintChangesWithPublicationSeed(testCase)
    cfg_a = mechanism_ablation_config('publication');
    cfg_b = mechanism_ablation_config('publication');
    cfg_b.publication_seeds(end) = cfg_b.publication_seeds(end) + 2;
    cfg_b.seeds = cfg_b.publication_seeds;
    cfg_b.full_seeds = cfg_b.publication_seeds;
    fp_b = compute_protocol_fingerprint(cfg_b);
    testCase.verifyNotEqual(cfg_a.protocol_fingerprint, fp_b);
end

function testFingerprintChangesWithInferencePlan(testCase)
    cfg_a = mechanism_ablation_config('publication', 'confirmatory');
    cfg_b = cfg_a;
    cfg_b.aggregation_inference_plan.bootstrap_replicates = ...
        cfg_b.aggregation_inference_plan.bootstrap_replicates + 1;
    fp_b = compute_protocol_fingerprint(cfg_b);
    testCase.verifyNotEqual(cfg_a.protocol_fingerprint, fp_b);
end

function testValidatePublicationRequiresThirtySeeds(testCase)
    cfg = mechanism_ablation_config('publication');
    effects = randn(30, 1);
    validate_seed_effect_vector(cfg.publication_seeds(:), effects, ...
        cfg.publication_seeds(:), 'publication', 'test_and_holm');
    testCase.verifyError(@() validate_seed_effect_vector(cfg.publication_seeds(1:29), ...
        effects(1:29), cfg.publication_seeds(:), 'publication', 'test_and_holm'), ...
        'validate_seed_effect_vector:MissingSeed');
end
