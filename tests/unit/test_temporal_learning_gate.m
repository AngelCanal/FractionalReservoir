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
    rng(11);
    Xtr = randn(80, 4);
    Ytr = Xtr * [1; -1; 0.2; 0] + 0.01 * randn(80, 1);
    Xva = randn(40, 4);
    Yva = Xva * [1; -1; 0.2; 0] + 0.01 * randn(40, 1);
    sel1 = select_ridge_lambda(Xtr, Ytr, Xva, Yva, [1e-4, 1e-2, 1]);
    m1 = sel1.selected_model;
    % Mutating a held-out test target variable cannot affect selection
    Yte = randn(40, 1); %#ok<NASGU>
    Yte = Yte + 100; %#ok<NASGU>
    sel2 = select_ridge_lambda(Xtr, Ytr, Xva, Yva, [1e-4, 1e-2, 1]);
    testCase.verifyEqual(sel1.selected_lambda, sel2.selected_lambda);
    testCase.verifyEqual(m1.coefficients, sel2.selected_model.coefficients);
    testCase.verifyEqual(m1.feature_mean, sel2.selected_model.feature_mean);
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

%% Helpers
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
            r.empirical_convergence = struct('median_pair_slope', -0.1, ...
                'classification', 'converging');
            r.qa = struct('resource_in_unit_interval', true, ...
                'mean_rate', 0.4, 'saturation_fraction', 0.1, 'silent_fraction', 0.1);
            records{end+1} = r; %#ok<AGROW>
        end
    end
end

function restore_warn(a, b)
    warning(a);
    warning(b);
end
