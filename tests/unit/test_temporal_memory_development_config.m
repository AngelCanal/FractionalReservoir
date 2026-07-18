function tests = test_temporal_memory_development_config
% Phase 5D-A2 development diagnostic protocol and seed-role isolation.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'development')));
    addpath(genpath(fullfile(repo_root, 'tests')));
    testCase.TestData.repo_root = repo_root;
    testCase.TestData.cfg = temporal_memory_development_config();
end

%% 1. Exact expected seed lists
function testExactDevelopmentModelSeeds(testCase)
    cfg = testCase.TestData.cfg;
    testCase.verifyEqual(cfg.model_seeds(:)', [1729, 2718, 31415]);
    testCase.verifyEqual(cfg.seeds(:)', [1729, 2718, 31415]);
end

function testExactDevelopmentTaskAndShuffleSeeds(testCase)
    cfg = testCase.TestData.cfg;
    testCase.verifyEqual(cfg.task_seeds.train, 12001);
    testCase.verifyEqual(cfg.task_seeds.validation, 12002);
    testCase.verifyEqual(cfg.task_seeds.test, 12003);
    testCase.verifyEqual(cfg.shuffle_seeds.train, 12101);
    testCase.verifyEqual(cfg.shuffle_seeds.validation, 12102);
    testCase.verifyEqual(cfg.shuffle_seeds.test, 12103);
end

function testExactV1ObservedSeedLists(testCase)
    cfg = testCase.TestData.cfg;
    testCase.verifyEqual(cfg.v1_observed.model_seeds(:)', ...
        [1729, 2718, 31415, 10007, 10009]);
    testCase.verifyEqual(cfg.v1_observed.task_seeds(:)', [9001, 9002, 9003]);
    testCase.verifyEqual(cfg.v1_observed.shuffle_seeds(:)', [9101, 9102, 9103]);
    testCase.verifyEqual(cfg.v1_observed.calibration_seeds(:)', [1729, 2718]);
end

function testExactFutureV2SeedLists(testCase)
    cfg = testCase.TestData.cfg;
    fut = cfg.reserved_future_v2;
    testCase.verifyEqual(fut.gate_model_seeds(:)', ...
        [11003, 11027, 11047, 11057, 11069]);
    testCase.verifyEqual(fut.gate_task_seeds.train, 13001);
    testCase.verifyEqual(fut.gate_task_seeds.validation, 13003);
    testCase.verifyEqual(fut.gate_task_seeds.test, 13007);
    testCase.verifyEqual(fut.gate_shuffle_seeds.train, 13101);
    testCase.verifyEqual(fut.gate_shuffle_seeds.validation, 13103);
    testCase.verifyEqual(fut.gate_shuffle_seeds.test, 13107);
    testCase.verifyEqual(fut.calibration_seeds(:)', [14009, 14011]);
    expected_pub = [ ...
        10037, 10039, 10061, 10067, 10069, 10079, 10091, 10093, ...
        10099, 10103, 10111, 10133, 10139, 10141, 10151, 10159, ...
        10163, 10169, 10177, 10181, 10193, 10211, 10223, 10243, ...
        10247, 10253, 10259, 10267, 10271, 10273];
    testCase.verifyEqual(fut.full_publication_seeds(:)', expected_pub);
    testCase.verifyEqual(numel(fut.full_publication_seeds), 30);
    testCase.verifyEqual(numel(unique(fut.full_publication_seeds)), 30);
end

%% 2. Disjointness
function testDevelopmentSeedDisjointness(testCase)
    cfg = testCase.TestData.cfg;
    model = cfg.model_seeds(:)';
    task = [cfg.task_seeds.train, cfg.task_seeds.validation, cfg.task_seeds.test];
    shuf = [cfg.shuffle_seeds.train, cfg.shuffle_seeds.validation, ...
        cfg.shuffle_seeds.test];
    v1_task = cfg.v1_observed.task_seeds(:)';
    v1_shuf = cfg.v1_observed.shuffle_seeds(:)';
    cur_pub = cfg.seed_ledger.current_publication_seeds(:)';
    reserved = flatten_seeds(cfg.reserved_future_v2);

    testCase.verifyEmpty(intersect(model, task));
    testCase.verifyEmpty(intersect(model, shuf));
    testCase.verifyEmpty(intersect(task, shuf));
    testCase.verifyEmpty(intersect(task, v1_task));
    testCase.verifyEmpty(intersect(shuf, v1_shuf));
    testCase.verifyEmpty(intersect(task, cur_pub));
    testCase.verifyEmpty(intersect(shuf, cur_pub));
    testCase.verifyEmpty(intersect(model, cur_pub));
    testCase.verifyEmpty(intersect([model, task, shuf], reserved));
end

%% 3. Retirement of 10007 / 10009
function testSeeds10007And10009Retired(testCase)
    cfg = testCase.TestData.cfg;
    testCase.verifyEqual(sort(cfg.retired_from_future_publication(:)'), ...
        [10007, 10009]);
    testCase.verifyFalse(any(cfg.model_seeds == 10007));
    testCase.verifyFalse(any(cfg.model_seeds == 10009));
    fut = cfg.reserved_future_v2.full_publication_seeds(:)';
    testCase.verifyFalse(any(fut == 10007));
    testCase.verifyFalse(any(fut == 10009));
end

%% 4. Reserved seeds cannot be executed
function testReservedSeedsCannotBeExecuted(testCase)
    cfg = testCase.TestData.cfg;
    cfg.model_seeds = [1729, 2718, 11003];
    cfg.seeds = cfg.model_seeds;
    cfg.protocol_fingerprint = compute_temporal_memory_development_fingerprint(cfg);
    testCase.verifyError( ...
        @() validate_temporal_memory_development_config(cfg), ...
        'validate_temporal_memory_development_config:Failed');

    cfg = testCase.TestData.cfg;
    cfg.task_seeds.test = 13007;
    cfg.protocol_fingerprint = compute_temporal_memory_development_fingerprint(cfg);
    testCase.verifyError( ...
        @() validate_temporal_memory_development_config(cfg), ...
        'validate_temporal_memory_development_config:Failed');
end

%% 5. V1 test seed 9003 forbidden
function testV1TestSeed9003Forbidden(testCase)
    cfg = testCase.TestData.cfg;
    cfg.task_seeds.test = 9003;
    cfg.protocol_fingerprint = compute_temporal_memory_development_fingerprint(cfg);
    testCase.verifyError( ...
        @() validate_temporal_memory_development_config(cfg), ...
        'validate_temporal_memory_development_config:Failed');
end

%% 6–8. Cells, lags, include_input
function testExactlyEightDiagnosticCells(testCase)
    cfg = testCase.TestData.cfg;
    expected_names = { ...
        'reference_r', 'reference_x', 'delay_removed_r', 'std_removed_r', ...
        'std_and_delay_removed_r', 'single_moment_matched_r', ...
        'adaptation_removed_r', 'mechanisms_off_r'};
    testCase.verifyEqual(numel(cfg.cells), 8);
    testCase.verifyEqual(cfg.n_cells, 8);
    testCase.verifyEqual(cfg.diagnostic_cell_names, expected_names);
    keys = cellfun(@(c) c.cell_key, cfg.cells, 'UniformOutput', false);
    testCase.verifyEqual(numel(unique(keys)), 8);
    testCase.verifyEqual(cfg.cells{1}.cell_key, ...
        'adapt-three_timescales__std-on__delay-dde_on__feat-r');
    testCase.verifyEqual(cfg.cells{8}.cell_key, ...
        'adapt-off__std-off__delay-ode_off__feat-r');
end

function testExactlyFiftyLags(testCase)
    cfg = testCase.TestData.cfg;
    testCase.verifyEqual(cfg.lags(:)', 1:50);
    testCase.verifyEqual(numel(cfg.lags), 50);
    testCase.verifyEqual(cfg.primary_diagnostic_lag, 10);
end

function testIncludeInputFalse(testCase)
    cfg = testCase.TestData.cfg;
    testCase.verifyFalse(cfg.include_input);
    testCase.verifyFalse(cfg.base.include_input);
end

%% 9. Never publication ready
function testDevelopmentNeverPublicationReady(testCase)
    cfg = testCase.TestData.cfg;
    testCase.verifyEqual(cfg.protocol_tier, 'development');
    testCase.verifyFalse(cfg.publication_evidence);
    testCase.verifyFalse(cfg.can_satisfy_publication_readiness);
    testCase.verifyFalse(cfg.publication_ready);
    testCase.verifyTrue(cfg.pilot_not_for_publication);

    cfg.publication_ready = true;
    cfg.protocol_fingerprint = compute_temporal_memory_development_fingerprint(cfg);
    testCase.verifyError( ...
        @() validate_temporal_memory_development_config(cfg), ...
        'validate_temporal_memory_development_config:Failed');

    cfg = testCase.TestData.cfg;
    cfg.protocol_tier = 'publication';
    cfg.protocol_fingerprint = compute_temporal_memory_development_fingerprint(cfg);
    testCase.verifyError( ...
        @() validate_temporal_memory_development_config(cfg), ...
        'validate_temporal_memory_development_config:Failed');
end

%% 10–12. Fingerprint
function testFingerprintDeterminism(testCase)
    cfg1 = temporal_memory_development_config();
    cfg2 = temporal_memory_development_config();
    testCase.verifyEqual(cfg1.protocol_fingerprint, cfg2.protocol_fingerprint);
    testCase.verifyEqual(cfg1.protocol_fingerprint, ...
        compute_temporal_memory_development_fingerprint(cfg1));
    report = validate_temporal_memory_development_config(cfg1);
    testCase.verifyTrue(report.ok);
end

function testTimestampsAndPathsDoNotAffectFingerprint(testCase)
    cfg = testCase.TestData.cfg;
    fp0 = cfg.protocol_fingerprint;
    cfg2 = cfg;
    cfg2.created_utc = '2099-12-31T23:59:59Z';
    cfg2.run_dir = 'D:\other\path\run';
    cfg2.output_root = '/var/tmp/other';
    cfg2.host_name = 'other-host';
    cfg2.results_path = fullfile(tempdir, 'other_results_path');
    testCase.verifyEqual(fp0, compute_temporal_memory_development_fingerprint(cfg2));
end

function testScientificFieldsAffectFingerprint(testCase)
    cfg = testCase.TestData.cfg;
    fp0 = cfg.protocol_fingerprint;

    cfg_lag = cfg;
    cfg_lag.lags = 1:49;
    testCase.verifyNotEqual(fp0, compute_temporal_memory_development_fingerprint(cfg_lag));

    cfg_seed = cfg;
    cfg_seed.task_seeds.test = 12099;
    testCase.verifyNotEqual(fp0, compute_temporal_memory_development_fingerprint(cfg_seed));

    cfg_mat = cfg;
    cfg_mat.materiality_rules.nrmse_abs_paired_median_difference_min = 0.05;
    testCase.verifyNotEqual(fp0, compute_temporal_memory_development_fingerprint(cfg_mat));

    cfg_op = cfg;
    cfg_op.frozen_operating_point.input_scaling = 0.5;
    cfg_op.base.input_scaling = 0.5;
    testCase.verifyNotEqual(fp0, compute_temporal_memory_development_fingerprint(cfg_op));
end

%% Additional validator / geometry guards
function testValidatorRejectsIncludeInputTrue(testCase)
    cfg = testCase.TestData.cfg;
    cfg.include_input = true;
    cfg.base.include_input = true;
    cfg.protocol_fingerprint = compute_temporal_memory_development_fingerprint(cfg);
    testCase.verifyError( ...
        @() validate_temporal_memory_development_config(cfg), ...
        'validate_temporal_memory_development_config:Failed');
end

function testValidatorRejectsChangedLengthsOrOperatingPoint(testCase)
    cfg = testCase.TestData.cfg;
    cfg.lengths.train_samples = 3999;
    cfg.protocol_fingerprint = compute_temporal_memory_development_fingerprint(cfg);
    testCase.verifyError( ...
        @() validate_temporal_memory_development_config(cfg), ...
        'validate_temporal_memory_development_config:Failed');

    cfg = testCase.TestData.cfg;
    cfg.frozen_operating_point.level_of_chaos = 0.8;
    cfg.base.level_of_chaos = 0.8;
    cfg.protocol_fingerprint = compute_temporal_memory_development_fingerprint(cfg);
    testCase.verifyError( ...
        @() validate_temporal_memory_development_config(cfg), ...
        'validate_temporal_memory_development_config:Failed');
end

function testValidatorRejectsMissingFingerprint(testCase)
    cfg = testCase.TestData.cfg;
    cfg = rmfield(cfg, 'protocol_fingerprint');
    testCase.verifyError( ...
        @() validate_temporal_memory_development_config(cfg), ...
        'validate_temporal_memory_development_config:Failed');
end

function testValidatorRejectsUnknownProtocolVersion(testCase)
    cfg = testCase.TestData.cfg;
    cfg.protocol_version = 'temporal_memory_diagnostic_v999';
    cfg.protocol_fingerprint = compute_temporal_memory_development_fingerprint(cfg);
    testCase.verifyError( ...
        @() validate_temporal_memory_development_config(cfg), ...
        'validate_temporal_memory_development_config:Failed');
end

function testValidatorRejectsTaskModelOverlap(testCase)
    cfg = testCase.TestData.cfg;
    cfg.task_seeds.train = 1729;
    cfg.protocol_fingerprint = compute_temporal_memory_development_fingerprint(cfg);
    testCase.verifyError( ...
        @() validate_temporal_memory_development_config(cfg), ...
        'validate_temporal_memory_development_config:Failed');
end

function testMaterialityRulesFrozen(testCase)
    cfg = testCase.TestData.cfg;
    m = cfg.materiality_rules;
    testCase.verifyEqual(m.nrmse_abs_paired_median_difference_min, 0.02);
    testCase.verifyEqual(m.r2_abs_paired_median_difference_min, 0.03);
    testCase.verifyTrue(m.directional_consistency_requires_all_three_dev_seeds_same_sign);
    testCase.verifyTrue(m.formal_p_values_forbidden);
    testCase.verifyTrue(m.confirmatory_inference_with_n3_forbidden);
    testCase.verifyEqual(m.comparison_role, 'development_hypotheses_only');
end

function testProtocolIdentityFields(testCase)
    cfg = testCase.TestData.cfg;
    testCase.verifyEqual(cfg.protocol_version, 'temporal_memory_diagnostic_v1');
    testCase.verifyEqual(cfg.protocol_role, ...
        'development_only_architecture_diagnosis');
    testCase.verifyEqual(cfg.architecture_version, 'nonfractional_mesn_v1');
    testCase.verifyEqual(numel(cfg.per_lag_endpoints), 8);
    testCase.verifyEqual(numel(cfg.per_seed_endpoints), 14);
    testCase.verifyEqual(numel(cfg.controls), 5);
end

function testBuildAblationParamsWorksForDiagnosticCells(testCase)
    cfg = testCase.TestData.cfg;
    for i = 1:numel(cfg.cells)
        [params, meta] = build_ablation_params(cfg.cells{i}, cfg.model_seeds(1), cfg);
        testCase.verifyEqual(params.n, 40);
        testCase.verifyEqual(meta.input_scaling, 0.25);
        testCase.verifyEqual(meta.level_of_chaos, 0.60);
        testCase.verifyFalse(params.include_input);
    end
end

%% helpers
function vals = flatten_seeds(S)
    vals = [];
    if isnumeric(S)
        vals = S(:)';
        return;
    end
    if ~isstruct(S)
        return;
    end
    if numel(S) ~= 1
        for i = 1:numel(S)
            vals = [vals, flatten_seeds(S(i))]; %#ok<AGROW>
        end
        return;
    end
    fn = fieldnames(S);
    for i = 1:numel(fn)
        vals = [vals, flatten_seeds(S.(fn{i}))]; %#ok<AGROW>
    end
end
