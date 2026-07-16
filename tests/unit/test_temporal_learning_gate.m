function tests = test_temporal_learning_gate
% Phase 4B temporal learning gate: delayed i.i.d. input reconstruction.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
    testCase.TestData.repo_root = repo_root;

    % Official smoke gate once for independent-validation / persistence tests.
    cfg = mechanism_ablation_config('smoke');
    gate = evaluate_temporal_learning_gate(cfg);
    testCase.TestData.smoke_gate_cfg = cfg;
    testCase.TestData.smoke_gate_result = gate;
end

%% A. Target construction
function testDelayedTargetIndexingImpulse(testCase)
    k = 10;
    wash = 5;
    n = 20;
    U = zeros(wash + k + n, 1);
    U(wash + 1) = 1;  % impulse
    [y, scored_idx] = construct_delayed_input_target(U, k, wash, n);
    % y at first scored index equals U(scored(1)-k)
    testCase.verifyEqual(y(1), U(scored_idx(1) - k));
    % Find where scored targets pick up the impulse: scored_idx - k == wash+1
    hit = find(scored_idx - k == wash + 1, 1);
    testCase.verifyNotEmpty(hit);
    testCase.verifyEqual(y(hit), 1);
    testCase.verifyEqual(nnz(y), 1);
end

function testLagMustBePositive(testCase)
    U = randn(30, 1);
    testCase.verifyError(@() construct_delayed_input_target(U, 0, 5, 10), ...
        'construct_delayed_input_target:InvalidLag');
    testCase.verifyError(@() construct_delayed_input_target(U, -1, 5, 10), ...
        'construct_delayed_input_target:InvalidLag');
end

function testUsableCountsAndLagTime(testCase)
    cfg = mechanism_ablation_config('smoke');
    g = cfg.temporal_learning_gate;
    testCase.verifyEqual(g.target_lag_time, g.target_lag_steps * cfg.base.dt, 'AbsTol', 0);
    L = g.washout_steps + g.target_lag_steps + g.train_samples;
    U = randn(L, 1);
    [y, scored_idx] = construct_delayed_input_target( ...
        U, g.target_lag_steps, g.washout_steps, g.train_samples);
    testCase.verifyEqual(numel(y), g.train_samples);
    testCase.verifyEqual(numel(scored_idx), g.train_samples);
    testCase.verifyEqual(min(scored_idx), g.washout_steps + g.target_lag_steps + 1);
end

function testNoCrossSplitTargets(testCase)
    cfg = mechanism_ablation_config('smoke');
    g = cfg.temporal_learning_gate;
    stream_a = RandStream('mt19937ar', 'Seed', g.train_input_seed);
    stream_b = RandStream('mt19937ar', 'Seed', g.validation_input_seed);
    La = g.washout_steps + g.target_lag_steps + g.train_samples;
    Lb = g.washout_steps + g.target_lag_steps + g.validation_samples;
    Ua = g.input_min + (g.input_max - g.input_min) * rand(stream_a, La, 1);
    Ub = g.input_min + (g.input_max - g.input_min) * rand(stream_b, Lb, 1);
    [ya, idx_a] = construct_delayed_input_target(Ua, g.target_lag_steps, ...
        g.washout_steps, g.train_samples);
    [yb, idx_b] = construct_delayed_input_target(Ub, g.target_lag_steps, ...
        g.washout_steps, g.validation_samples);
    % Targets only reference indices within their own U
    testCase.verifyTrue(all(idx_a - g.target_lag_steps >= 1));
    testCase.verifyTrue(all(idx_b - g.target_lag_steps >= 1));
    testCase.verifyTrue(all(idx_a <= numel(Ua)));
    testCase.verifyTrue(all(idx_b <= numel(Ub)));
    testCase.verifyEqual(ya, Ua(idx_a - g.target_lag_steps));
    testCase.verifyEqual(yb, Ub(idx_b - g.target_lag_steps));
end

%% B/C. Config, exclusion, fingerprint
function testConfigExcludesInput(testCase)
    cfg = mechanism_ablation_config('publication');
    g = cfg.temporal_learning_gate;
    testCase.verifyFalse(g.include_input);
    testCase.verifyEqual(g.feature_mode, 'r');
    testCase.verifyEqual(g.target_lag_steps, 10);
    testCase.verifyEqual(numel(g.model_seeds), 5);
    testCase.verifyTrue(g.enabled);
    testCase.verifyEqual(g.protocol_version, 'temporal_learning_gate_v1');
    testCase.verifyEqual(g.reference_cell_key, ...
        'adapt-three_timescales__std-on__delay-dde_on__feat-r');
end

function testRejectIncludeInputTrue(testCase)
    cfg = mechanism_ablation_config('smoke');
    cfg.temporal_learning_gate.include_input = true;
    testCase.verifyError(@() evaluate_temporal_learning_gate(cfg), ...
        'evaluate_temporal_learning_gate:IncludeInputForbidden');
end

function testFingerprintSensitiveToGateFields(testCase)
    cfg = mechanism_ablation_config('publication');
    fp0 = cfg.protocol_fingerprint;

    cfg2 = cfg;
    cfg2.temporal_learning_gate.target_lag_steps = 11;
    cfg2.temporal_learning_gate.target_lag_time = 11 * cfg2.base.dt;
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg2));

    cfg3 = cfg;
    cfg3.temporal_learning_gate.train_samples = cfg3.temporal_learning_gate.train_samples + 1;
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg3));

    cfg4 = cfg;
    cfg4.temporal_learning_gate.model_seeds(1) = cfg4.temporal_learning_gate.model_seeds(1) + 1;
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg4));

    cfg5 = cfg;
    cfg5.temporal_learning_gate.thresholds.mesn_median_nrmse_max = 0.5;
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg5));

    cfg6 = cfg;
    cfg6.created_utc = '2099-01-01T00:00:00Z';
    testCase.verifyEqual(fp0, compute_protocol_fingerprint(cfg6));
end

function testSmokeNeverPublicationReadyEvenWithPassedGate(testCase)
    cfg = mechanism_ablation_config('smoke');
    fake_gate = synthetic_passed_gate(cfg);
    records = synthetic_ok_records(cfg);
    opts = struct( ...
        'temporal_learning_gate', fake_gate, ...
        'has_manifest', true, ...
        'has_commit_sha', true, ...
        'has_artifact_hashes', true);
    opts.cell_records = records;
    report = evaluate_publication_readiness(cfg, opts);
    testCase.verifyFalse(report.publication_ready);
end

function testMissingGateFailsReadiness(testCase)
    cfg = mechanism_ablation_config('publication');
    records = synthetic_ok_records(cfg);
    opts = struct( ...
        'has_manifest', true, ...
        'has_commit_sha', true, ...
        'has_artifact_hashes', true);
    opts.cell_records = records;
    report = evaluate_publication_readiness(cfg, opts);
    names = {report.checks.name};
    idx = find(strcmp(names, 'temporal_learning_gate_passed'), 1);
    testCase.verifyFalse(report.checks(idx).pass);
    testCase.verifyFalse(report.publication_ready);
end

%% D/E. Controls and ridge on synthetic fixtures
function testExactHistorySolvesNoiseFree(testCase)
    k = 5;
    n = 200;
    U = randn(n + k, 1);
    scored = (k + 1):(n + k);
    Y = U(scored - k);
    Xh = zeros(n, k + 1);
    for j = 0:k
        Xh(:, j + 1) = U(scored - j);
    end
    testCase.verifyEqual(Xh(:, end), Y, 'AbsTol', 0);
    warn_near = warning('error', 'MATLAB:nearlySingularMatrix');
    warn_sing = warning('error', 'MATLAB:singularMatrix');
    cleanup = onCleanup(@() restore_warn(warn_near, warn_sing)); %#ok<NASGU>
    model = fit_ridge_readout(Xh(1:120, :), Y(1:120), 1e-8);
    Y_hat = apply_ridge_readout(model, Xh(121:end, :));
    nrmse = sqrt(mean((Y_hat - Y(121:end)).^2)) / std(Y(121:end), 1);
    testCase.verifyLessThan(nrmse, 1e-6);
    testCase.verifyTrue(isfield(model, 'solver_method'));
    testCase.verifyTrue(isfield(model, 'numerical_rank'));
end

function testCurrentInputOnlyNearChanceOnIID(testCase)
    k = 10;
    n_tr = 500;
    n_te = 500;
    stream = RandStream('mt19937ar', 'Seed', 7);
    Utr = 2 * rand(stream, n_tr + k, 1) - 1;
    Ute = 2 * rand(stream, n_te + k, 1) - 1;
    idx_tr = (k + 1):(n_tr + k);
    idx_te = (k + 1):(n_te + k);
    Ytr = Utr(idx_tr - k);
    Yte = Ute(idx_te - k);
    Xtr = Utr(idx_tr);
    Xte = Ute(idx_te);
    sel = select_ridge_lambda(Xtr, Ytr, Xtr, Ytr, [0, 1e-2, 1]);
    Y_hat = apply_ridge_readout(sel.selected_model, Xte);
    nrmse = sqrt(mean((Y_hat - Yte).^2)) / std(Yte, 1);
    % Near chance for i.i.d. lag prediction from current input
    testCase.verifyGreaterThan(nrmse, 0.9);
end

function testChangingTestTargetDoesNotAlterModel(testCase)
% Fit once on train/validation; score frozen readouts on two test targets.
    cfg = mechanism_ablation_config('smoke');
    cfg.temporal_learning_gate.model_seeds = 1729;
    cfg.temporal_learning_gate.washout_steps = 25;
    cfg.temporal_learning_gate.train_samples = 120;
    cfg.temporal_learning_gate.validation_samples = 50;
    cfg.temporal_learning_gate.test_samples = 60;
    cfg.protocol_fingerprint = compute_protocol_fingerprint(cfg);

    dt = cfg.base.dt;
    lag_time = cfg.temporal_learning_gate.target_lag_steps * dt;
    bundle = fit_temporal_learning_gate_seed(cfg, 1729);
    scored_protocol = score_temporal_learning_gate_seed(bundle, ...
        bundle.Y_te_protocol, bundle.Y_te_shuffled_protocol, dt, lag_time);

    Y_alt = bundle.Y_te_protocol + 3.5;
    stream = RandStream('mt19937ar', 'Seed', cfg.temporal_learning_gate.shuffle_test_seed);
    Y_alt_shuf = Y_alt(randperm(stream, numel(Y_alt)));
    scored_alt = score_temporal_learning_gate_seed(bundle, Y_alt, Y_alt_shuf, dt, lag_time);

    p = scored_protocol.mesn;
    a = scored_alt.mesn;
    testCase.verifyEqual(p.selected_lambda, a.selected_lambda);
    testCase.verifyEqual(p.ridge.coefficients, a.ridge.coefficients);
    testCase.verifyEqual(p.ridge.intercept, a.ridge.intercept);
    testCase.verifyEqual(p.ridge.feature_mean, a.ridge.feature_mean);
    testCase.verifyEqual(p.ridge.feature_scale, a.ridge.feature_scale);
    testCase.verifyEqual(p.ridge.numerical_rank, a.ridge.numerical_rank);
    testCase.verifyTrue(isequaln(p.lambda_selection_table, a.lambda_selection_table));
    testCase.verifyNotEqual(p.metrics.nrmse, a.metrics.nrmse);
    testCase.verifyTrue(isfield(p, 'selected_at_grid_boundary'));
end

function testEvaluatorRejectsMutateTestTarget(testCase)
    cfg = mechanism_ablation_config('smoke');
    testCase.verifyError(@() evaluate_temporal_learning_gate(cfg, ...
        struct('mutate_test_target', @(y) y + 1)), ...
        'evaluate_temporal_learning_gate:MutateTestTargetForbidden');
end

function testProductionEvaluatorHasExecutedProvenance(testCase)
    [~, gate] = cached_smoke_gate(testCase);
    testCase.verifyTrue(isfield(gate, 'evaluation_provenance'));
    testCase.verifyEqual(gate.evaluation_provenance.mode, 'executed');
    testCase.verifyFalse(gate.evaluation_provenance.test_override_used);
    testCase.verifyFalse(gate.evaluation_provenance.test_target_mutated);
end

%% F. Gate logic with synthetic seed rows
function testGateLogicSyntheticPassAndFail(testCase)
    cfg = mechanism_ablation_config('smoke');
    thr = cfg.temporal_learning_gate.thresholds;

    pass_gate = synthetic_passed_gate(cfg);
    report = evaluate_publication_readiness(cfg, struct( ...
        'temporal_learning_gate', pass_gate));
    names = {report.checks.name};
    idx = find(strcmp(names, 'temporal_learning_gate_passed'), 1);
    % Smoke tier still blocks publication_ready, but the QA gate check itself passes
    testCase.verifyTrue(report.checks(idx).pass);

    fail_current = pass_gate;
    fail_current.passed = false;
    fail_current.failure_reasons = {'median_delta_vs_current_ok'};
    report2 = evaluate_publication_readiness(cfg, struct( ...
        'temporal_learning_gate', fail_current));
    idx2 = find(strcmp({report2.checks.name}, 'temporal_learning_gate_passed'), 1);
    testCase.verifyFalse(report2.checks(idx2).pass);

    missing_seed = pass_gate;
    missing_seed.seed_results = pass_gate.seed_results(1:2);
    report3 = evaluate_publication_readiness(cfg, struct( ...
        'temporal_learning_gate', missing_seed));
    idx3 = find(strcmp({report3.checks.name}, 'temporal_learning_gate_passed'), 1);
    testCase.verifyFalse(report3.checks(idx3).pass);

    %#ok<NASGU>
    thr = thr;
end

function testNonfiniteMetricFailsReadiness(testCase)
    cfg = mechanism_ablation_config('smoke');
    g = synthetic_passed_gate(cfg);
    g.seed_results(1).mesn.metrics.nrmse = NaN;
    report = evaluate_publication_readiness(cfg, struct('temporal_learning_gate', g));
    idx = find(strcmp({report.checks.name}, 'temporal_learning_gate_passed'), 1);
    testCase.verifyFalse(report.checks(idx).pass);
end

%% G. Independent validator + runner persistence (Phase 4B-R)
function testIndependentValidatorAcceptsHonestSmokeResult(testCase)
    [cfg, gate] = cached_smoke_gate(testCase);
    [ok, report] = validate_temporal_learning_gate_result(gate, cfg);
    testCase.verifyTrue(ok, strjoin(report.reasons, ','));
    testCase.verifyEqual(report.stored_passed, report.recomputed_passed);
end

function testFabricatedPassedFailsIndependentValidation(testCase)
    [cfg, gate] = cached_smoke_gate(testCase);
    gate.passed = true;
    [ok, report] = validate_temporal_learning_gate_result(gate, cfg);
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(report.reasons, ...
        'passed_flag_does_not_match_recomputed_conditions')));
end

function testWrongFingerprintFailsValidation(testCase)
    [cfg, gate] = cached_smoke_gate(testCase);
    gate.protocol_fingerprint = 'deadbeef';
    [ok, report] = validate_temporal_learning_gate_result(gate, cfg);
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(report.reasons, 'protocol_fingerprint_mismatch')));
end

function testWrongSeedIdentityFailsValidation(testCase)
    [cfg, gate] = cached_smoke_gate(testCase);
    gate.seed_results(2).model_seed = 99999;
    [ok, report] = validate_temporal_learning_gate_result(gate, cfg);
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(report.reasons, 'seed_identity_or_order_mismatch')));
end

function testChangedThresholdsFailValidation(testCase)
    [cfg, gate] = cached_smoke_gate(testCase);
    gate.thresholds.mesn_median_nrmse_max = 0.10;
    [ok, report] = validate_temporal_learning_gate_result(gate, cfg);
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(report.reasons, 'thresholds_mismatch')));
end

function testMissingControlDiagnosticsFailValidation(testCase)
    [cfg, gate] = cached_smoke_gate(testCase);
    gate.seed_results(1).current_input_only_control = rmfield( ...
        gate.seed_results(1).current_input_only_control, 'ridge');
    [ok, report] = validate_temporal_learning_gate_result(gate, cfg);
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(contains(report.reasons, 'diagnostics')));
end

function testRunnersPassGateIntoReadiness(testCase)
    tmp = tempname;
    mkdir(tmp);
    cleanup = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>

    opts = struct( ...
        'max_cells', 0, ...
        'max_seeds', 1, ...
        'save_results', false, ...
        'verbose', false, ...
        'revalidated_root_override', tmp, ...
        'do_rerun_check', false);

    [smoke_res, ~] = run_mechanism_ablation_smoke(opts);
    testCase.verifyTrue(isfield(smoke_res, 'temporal_learning_gate'));
    testCase.verifyEqual(smoke_res.temporal_learning_gate.evaluation_provenance.mode, 'executed');
    names = {smoke_res.readiness.checks.name};
    testCase.verifyTrue(any(strcmp(names, 'temporal_learning_gate_passed')));

    [pilot_res, ~] = run_mechanism_ablation_pilot(opts);
    testCase.verifyTrue(isfield(pilot_res, 'temporal_learning_gate'));
    testCase.verifyEqual(pilot_res.temporal_learning_gate.evaluation_provenance.mode, 'executed');

    full_opts = opts;
    full_opts.use_reduced_lengths = true;
    [full_res, ~] = run_mechanism_ablation_full(full_opts);
    testCase.verifyTrue(isfield(full_res, 'temporal_learning_gate'));
    testCase.verifyFalse(full_res.publication_ready);
end

function testPublicationRunnerRejectsTemporalGateOverride(testCase)
    cal_dir = make_synthetic_calibration_artifact();
    cleanup = onCleanup(@() rmdir(fileparts(cal_dir), 's')); %#ok<NASGU>
    opts = struct( ...
        'calibration_run_dir', cal_dir, ...
        'max_cells', 0, ...
        'max_seeds', 1, ...
        'save_results', false, ...
        'verbose', false, ...
        'temporal_learning_gate_override', struct('passed', true, 'status', 'complete'));
    testCase.verifyError(@() run_mechanism_ablation_full(opts), ...
        'run_mechanism_ablation_full:TemporalGateOverrideForbidden');
end

function testPublicationValidatorRejectsInjectedProvenance(testCase)
    pub = mechanism_ablation_config('publication');
    gate = testCase.TestData.smoke_gate_result;
    gate.protocol_tier = 'publication';
    gate.protocol_fingerprint = pub.protocol_fingerprint;
    gate.evaluation_provenance = struct( ...
        'mode', 'injected_test_fixture', ...
        'test_override_used', true, ...
        'test_target_mutated', false);
    [ok, report] = validate_temporal_learning_gate_result(gate, pub);
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(report.reasons, ...
        'evaluation_provenance_mode_not_executed')));
end

function testPublicationValidatorRejectsMutatedTargetProvenance(testCase)
    pub = mechanism_ablation_config('publication');
    gate = testCase.TestData.smoke_gate_result;
    gate.protocol_tier = 'publication';
    gate.protocol_fingerprint = pub.protocol_fingerprint;
    gate.evaluation_provenance = struct( ...
        'mode', 'executed', ...
        'test_override_used', false, ...
        'test_target_mutated', true);
    [ok, report] = validate_temporal_learning_gate_result(gate, pub);
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(report.reasons, ...
        'evaluation_provenance_test_target_mutated')));
end

function testInjectedFixtureNeverPublicationReady(testCase)
    [cfg, gate] = cached_smoke_gate(testCase);
    tmp = tempname;
    mkdir(tmp);
    cleanup = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>

    opts = struct( ...
        'max_cells', 0, ...
        'max_seeds', 1, ...
        'save_results', false, ...
        'verbose', false, ...
        'revalidated_root_override', tmp, ...
        'temporal_learning_gate_override', gate, ...
        'allow_injected_test_fixture', true);
    [res, ~] = run_mechanism_ablation_smoke(opts);
    testCase.verifyEqual(res.temporal_learning_gate.evaluation_provenance.mode, ...
        'injected_test_fixture');
    testCase.verifyTrue(res.temporal_learning_gate.evaluation_provenance.test_override_used);
    testCase.verifyFalse(res.publication_ready);
    %#ok<NASGU>
    cfg = cfg;
end

function testSavedRunRevalidatesAndMissingArtifactFailsClosed(testCase)
    tmp = tempname;
    mkdir(tmp);
    cleanup = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>

    opts = struct( ...
        'max_cells', 0, ...
        'max_seeds', 1, ...
        'save_results', true, ...
        'verbose', false, ...
        'revalidated_root_override', tmp);
    [~, run_dir] = run_mechanism_ablation_smoke(opts);
    art = fullfile(run_dir, 'validation', 'temporal_learning_gate.mat');
    testCase.verifyTrue(isfile(art));

    S = load(art);
    testCase.verifyEqual(S.temporal_learning_gate.evaluation_provenance.mode, 'executed');

    report = validate_publication_run(run_dir);
    names = {report.checks.name};
    idx = find(strcmp(names, 'temporal_learning_gate_independent_validation'), 1);
    testCase.verifyTrue(report.checks(idx).pass);
    testCase.verifyFalse(report.publication_ready);

    delete(art);
    report2 = validate_publication_run(run_dir);
    idx2 = find(strcmp({report2.checks.name}, 'temporal_learning_gate_artifact_present'), 1);
    testCase.verifyFalse(report2.checks(idx2).pass);
    testCase.verifyFalse(report2.publication_ready);
end

function testReducedViaFullUsesSmokeGateFeatureDimension(testCase)
    smoke = mechanism_ablation_config('smoke');
    pub = mechanism_ablation_config('publication');
    cfg = pub;
    cfg.lengths = smoke.lengths;
    cfg.base.n = smoke.base.n;
    cfg.secondary_enabled = false;
    cfg.temporal_learning_gate = smoke.temporal_learning_gate;
    cfg = force_smoke_protocol(cfg, 'test_reduced');
    cfg.frozen_operating_point = struct('input_scaling', 0.5, 'level_of_chaos', 0.8);
    cfg.protocol_fingerprint = compute_protocol_fingerprint(cfg);

    testCase.verifyEqual(cfg.temporal_learning_gate.feature_dimension, smoke.base.n);
    testCase.verifyEqual(numel(cfg.temporal_learning_gate.model_seeds), 3);
    testCase.verifyEqual(cfg.temporal_learning_gate.train_samples, ...
        smoke.temporal_learning_gate.train_samples);
    testCase.verifyEqual(cfg.protocol_tier, 'smoke');

    tmp = tempname;
    mkdir(tmp);
    cleanup = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>
    opts = struct( ...
        'max_cells', 0, ...
        'max_seeds', 1, ...
        'save_results', false, ...
        'verbose', false, ...
        'use_reduced_lengths', true);
    [result, ~] = run_mechanism_ablation_full(opts);
    testCase.verifyEqual(result.cfg.temporal_learning_gate.feature_dimension, 12);
    testCase.verifyEqual(result.cfg.protocol_tier, 'smoke');
    testCase.verifyEqual(result.temporal_learning_gate.evaluation_provenance.mode, 'executed');
    testCase.verifyFalse(result.publication_ready);
end

%% Helpers
function [cfg, gate] = cached_smoke_gate(testCase)
    cfg = testCase.TestData.smoke_gate_cfg;
    gate = testCase.TestData.smoke_gate_result;
end

function g = synthetic_passed_gate(cfg)
    seeds = cfg.temporal_learning_gate.model_seeds(:)';
    n = numel(seeds);
    seed_results = repmat(struct( ...
        'model_seed', NaN, ...
        'mesn', struct('metrics', struct('nrmse', 0.4, 'r2', 0.5)), ...
        'current_input_only_control', struct('metrics', struct('nrmse', 1.0, 'r2', 0)), ...
        'no_recurrent_coupling_control', struct('metrics', struct('nrmse', 0.7, 'r2', 0.1)), ...
        'shuffled_target_control', struct('metrics', struct('nrmse', 1.05, 'r2', -0.1)), ...
        'exact_history_control', struct('metrics', struct('nrmse', 1e-8, 'r2', 1.0))), n, 1);
    for i = 1:n
        seed_results(i).model_seed = seeds(i);
    end
    g = struct();
    g.protocol_version = 'temporal_learning_gate_v1';
    g.status = 'complete';
    g.passed = true;
    g.include_input = false;
    g.seed_results = seed_results;
    g.failure_reasons = {};
end

function records = synthetic_ok_records(cfg)
    cells = cfg.cells;
    seeds = cfg.seeds;
    records = {};
    for i = 1:numel(seeds)
        for j = 1:numel(cells)
            r = struct();
            r.base_seed = seeds(i);
            r.cell_key = cells{j}.cell_key;
            r.status = 'ok';
            r.dale_violations = 0;
            r.mode = cells{j}.mode;
            r.wall_time_seconds = 1;
            r.memory_capacity = struct('MC_total', 1);
            r.narma = struct('test_nrmse', 0.5);
            r.mackey_glass = struct('test_nrmse', 0.5);
            r.mackey_glass.rollout = synthetic_mg_rollout_for_gate(cfg, cells{j}.mode);
            r.empirical_convergence = struct('median_pair_slope', -0.1, ...
                'classification', 'converging');
            r.qa = struct('resource_in_unit_interval', true, ...
                'mean_rate', 0.4, 'saturation_fraction', 0.1, 'silent_fraction', 0.1);
            records{end+1} = r; %#ok<AGROW>
        end
    end
end

function rollout = synthetic_mg_rollout_for_gate(cfg, mode)
    rc = cfg.mg_autonomous_rollout;
    if strcmp(mode, 'DDE')
        rollout = struct( ...
            'status', 'unsupported_not_computed', ...
            'protocol_version', rc.protocol_version, ...
            'mode', 'DDE', ...
            'reason', 'DDE autonomous continuation is not implemented', ...
            'predictions', [], 'metrics', [], ...
            'evaluation_provenance', struct('mode', 'unsupported'));
        return;
    end
    H = rc.forecast_horizon_steps;
    n_o = rc.n_forecast_origins;
    origins = (100:(100+n_o-1))';
    po = repmat(struct('origin_global_index', 0, 'origin_test_relative_index', 0, ...
        'horizon', H, 'predictions', zeros(H,1), 'targets', zeros(H,1), ...
        'errors', zeros(H,1), 'normalized_absolute_errors', zeros(H,1), ...
        'full_horizon_nrmse', 0.1, 'rmse', 0.1, 'valid_horizon_steps', H, ...
        'first_threshold_exceedance_step', NaN, 'right_censored', true, ...
        'valid_error_threshold', 0.4), n_o, 1);
    for o = 1:n_o
        po(o).origin_global_index = origins(o);
        po(o).origin_test_relative_index = o;
    end
    rollout = struct( ...
        'status', 'computed', ...
        'protocol_version', rc.protocol_version, ...
        'role', rc.role, ...
        'mode', 'ODE', ...
        'origin_schedule', struct('n_forecast_origins', n_o, ...
            'origin_indices', origins, 'forecast_horizon_steps', H), ...
        'forecast_horizon_steps', H, ...
        'fixed_report_horizons', rc.fixed_report_horizons(:), ...
        'normalization_reference', rc.normalization_reference, ...
        'normalization_scale', 1.0, ...
        'per_origin', po, ...
        'metrics', struct( ...
            'pooled_nrmse_at_fixed_horizons', 0.1*ones(numel(rc.fixed_report_horizons),1), ...
            'pooled_nrmse_full_horizon', 0.1), ...
        'evaluation_provenance', struct( ...
            'mode', 'executed', ...
            'test_target_override_used', false, ...
            'origin_override_used', false, ...
            'model_refit_for_rollout', false, ...
            'lambda_reselected_for_rollout', false, ...
            'autonomous_performance_used_for_selection', false, ...
            'first_prediction_alignment_verified', true, ...
            'object_state_unchanged', true));
end

function restore_warn(a, b)
    warning(a);
    warning(b);
end
