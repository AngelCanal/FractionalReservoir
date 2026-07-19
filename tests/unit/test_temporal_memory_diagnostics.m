function tests = test_temporal_memory_diagnostics
% Phase 5D-B1 leakage-safe temporal-memory diagnostic primitives.
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

%% Target indexing
function testTargetIndexingNoOffByOne(testCase)
    wash = 5;
    max_lag = 4;
    n = 10;
    U = (1:(wash + max_lag + n))';
    split = struct('U', U, 'scored_idx', ((wash + max_lag + 1):(wash + max_lag + n))', ...
        'washout_steps', wash, 'max_lag', max_lag);
    lags = (1:max_lag)';
    [Y, meta] = build_temporal_memory_targets(split, lags);
    for i = 1:numel(lags)
        k = lags(i);
        expected = U(split.scored_idx - k);
        testCase.verifyEqual(Y{i}, expected);
        % Explicit: first scored target at lag k is U(wash+max_lag+1-k)
        testCase.verifyEqual(Y{i}(1), U(wash + max_lag + 1 - k));
    end
    testCase.verifyEqual(meta.indexing, 'y_k(t)=U(scored_idx(t)-k)');
end

function testExactHistoryRecoversEveryLag(testCase)
    wash = 3;
    max_lag = 5;
    n = 20;
    stream = RandStream('mt19937ar', 'Seed', 11);
    U = 2 * rand(stream, wash + max_lag + n, 1) - 1;
    idx = ((wash + max_lag + 1):(wash + max_lag + n))';
    lags = (1:max_lag)';
    Xh = zeros(n, max_lag + 1);
    for j = 0:max_lag
        Xh(:, j + 1) = U(idx - j);
    end
    for i = 1:numel(lags)
        k = lags(i);
        y = U(idx - k);
        % Column j=k (1-based index k+1) is u(t-k)
        testCase.verifyEqual(Xh(:, k + 1), y);
    end
end

function testSyntheticShiftRegisterRecoversKnownLags(testCase)
% Features are exact delayed inputs; ridge must recover each lag.
    n = 200;
    max_lag = 6;
    lags = (1:max_lag)';
    stream = RandStream('mt19937ar', 'Seed', 21);
    U = 2 * rand(stream, n + max_lag, 1) - 1;
    idx = ((max_lag + 1):(n + max_lag))';
    X = zeros(n, max_lag + 1);
    for j = 0:max_lag
        X(:, j + 1) = U(idx - j);
    end
    Ytr = cell(max_lag, 1);
    Yva = cell(max_lag, 1);
    Yte = cell(max_lag, 1);
    n_tr = 100; n_va = 50; n_te = 50;
    Xtr = X(1:n_tr, :); Xva = X(n_tr+(1:n_va), :); Xte = X(n_tr+n_va+(1:n_te), :);
    for i = 1:max_lag
        y = U(idx - lags(i));
        Ytr{i} = y(1:n_tr);
        Yva{i} = y(n_tr+(1:n_va));
        Yte{i} = y(n_tr+n_va+(1:n_te));
    end
    bundle = fit_temporal_memory_curve(Xtr, Xva, Ytr, Yva, lags, [0, 1e-8, 1e-4], ...
        struct('X_test', Xte));
    scored = score_temporal_memory_curve(bundle, Yte);
    for i = 1:max_lag
        testCase.verifyLessThan(scored.per_lag(i).metrics.rmse, 1e-8);
        testCase.verifyGreaterThan(scored.per_lag(i).metrics.memory_coefficient, 0.999);
    end
end

%% Controls
function testCurrentInputCannotAccessDelayedInputs(testCase)
    n = 400;
    k = 5;
    stream = RandStream('mt19937ar', 'Seed', 31);
    U = 2 * rand(stream, n + k, 1) - 1;
    idx = ((k + 1):(n + k))';
    y = U(idx - k);
    x = U(idx);
    n_tr = 200; n_va = 100; n_te = 100;
    Xtr = x(1:n_tr); Xva = x(n_tr+(1:n_va)); Xte = x(n_tr+n_va+(1:n_te));
    Ytr = {y(1:n_tr)}; Yva = {y(n_tr+(1:n_va))}; Yte = {y(n_tr+n_va+(1:n_te))};
    bundle = fit_temporal_memory_curve(Xtr, Xva, Ytr, Yva, 5, [0, 1e-2, 1], ...
        struct('X_test', Xte));
    scored = score_temporal_memory_curve(bundle, Yte);
    testCase.verifyGreaterThan(scored.per_lag(1).metrics.nrmse, 0.9);
    testCase.verifyLessThan(scored.per_lag(1).metrics.memory_coefficient, 0.05);
end

function testNoRecurrentRebuildZeroWAndOriginalUnchanged(testCase)
    cfg = testCase.TestData.cfg;
    cell_spec = cfg.diagnostic_cells.reference_r;
    [params, ~] = build_ablation_params(cell_spec, 1729, cfg);
    params.include_input = false;
    esn = SRNN_ESN(params);
    W_before = esn.W;
    [esn_nr, ~] = rebuild_mesn_no_recurrent(esn);
    testCase.verifyTrue(all(esn_nr.W(:) == 0));
    testCase.verifyEqual(esn.W, W_before);
    testCase.verifyFalse(isequal(esn.W, esn_nr.W));
end

%% Fit / score isolation and simulation reuse
function testOneSimulationPerSplitNotPerLag(testCase)
    cfg = testCase.TestData.cfg;
    cell_spec = cfg.diagnostic_cells.reference_r;
    opts = struct( ...
        'washout_steps', 20, ...
        'train_samples', 40, ...
        'validation_samples', 20, ...
        'test_samples', 20, ...
        'lags', (1:5)', ...
        'lambda_grid', [0; 1e-4; 1], ...
        'allow_test_fixture', true);
    bundle = fit_temporal_memory_seed(cfg, cell_spec, 1729, opts);
    testCase.verifyEqual(bundle.n_reservoir_simulations, 3);
    testCase.verifyEqual(bundle.simulations_per_split, 1);
    testCase.verifyEqual(numel(bundle.curve.per_lag), 5);
end

function testOutputRowCountsForFiftyLags(testCase)
    n = 30;
    lags = (1:50)';
    Xtr = randn(n, 4); Xva = randn(n, 4); Xte = randn(n, 4);
    Ytr = cell(50, 1); Yva = cell(50, 1); Yte = cell(50, 1);
    for i = 1:50
        Ytr{i} = randn(n, 1);
        Yva{i} = randn(n, 1);
        Yte{i} = randn(n, 1);
    end
    bundle = fit_temporal_memory_curve(Xtr, Xva, Ytr, Yva, lags, [0; 1], ...
        struct('X_test', Xte));
    scored = score_temporal_memory_curve(bundle, Yte);
    testCase.verifyEqual(numel(scored.per_lag), 50);
    testCase.verifyEqual(numel(scored.memory_coefficients), 50);
    testCase.verifyEqual(scored.n_lags, 50);
end

function testDeterministicLocalRNGAndCallerGlobalUnchanged(testCase)
    cfg = testCase.TestData.cfg;
    stream = RandStream.getGlobalStream();
    stream.State = stream.State; %#ok<NASGU>
    before = RandStream.getGlobalStream().State;
    opts = struct( ...
        'washout_steps', 10, ...
        'train_samples', 15, ...
        'validation_samples', 10, ...
        'test_samples', 10, ...
        'max_lag', 5);
    s1 = build_temporal_memory_development_splits(cfg, opts);
    mid = RandStream.getGlobalStream().State;
    s2 = build_temporal_memory_development_splits(cfg, opts);
    after = RandStream.getGlobalStream().State;
    testCase.verifyEqual(before, mid);
    testCase.verifyEqual(mid, after);
    testCase.verifyEqual(s1.train.U, s2.train.U);
    testCase.verifyEqual(s1.validation.U, s2.validation.U);
    testCase.verifyEqual(s1.test.U, s2.test.U);
    testCase.verifyTrue(s1.global_rng_unchanged);
end

function testTrainValidationTestIndependence(testCase)
    cfg = testCase.TestData.cfg;
    opts = struct('washout_steps', 8, 'train_samples', 12, ...
        'validation_samples', 11, 'test_samples', 13, 'max_lag', 4);
    splits = build_temporal_memory_development_splits(cfg, opts);
    seeds = [splits.train.seed, splits.validation.seed, splits.test.seed];
    testCase.verifyEqual(numel(unique(seeds)), 3);
    testCase.verifyFalse(isequal(splits.train.U, splits.validation.U));
    testCase.verifyFalse(isequal(splits.train.U, splits.test.U));
    testCase.verifyFalse(isequal(splits.validation.U, splits.test.U));
    testCase.verifyEqual(splits.train.n_samples_used, 12);
    testCase.verifyEqual(splits.validation.n_samples_used, 11);
    testCase.verifyEqual(splits.test.n_samples_used, 13);
end

function testTestTargetIsolation(testCase)
    n = 40;
    lags = [1; 3; 5];
    Xtr = randn(n, 3); Xva = randn(n, 3); Xte = randn(n, 3);
    Ytr = cell(3, 1); Yva = cell(3, 1); Yte = cell(3, 1);
    for i = 1:3
        Ytr{i} = randn(n, 1);
        Yva{i} = randn(n, 1);
        Yte{i} = randn(n, 1);
    end
    bundle = fit_temporal_memory_curve(Xtr, Xva, Ytr, Yva, lags, [0; 1e-3; 1], ...
        struct('X_test', Xte));
    scored1 = score_temporal_memory_curve(bundle, Yte);
    Yte2 = Yte;
    for i = 1:3
        Yte2{i} = Yte{i} + 2.5;
    end
    scored2 = score_temporal_memory_curve(bundle, Yte2);

    for i = 1:3
        p = scored1.per_lag(i);
        a = scored2.per_lag(i);
        testCase.verifyEqual(p.selected_lambda, a.selected_lambda);
        testCase.verifyEqual(p.coefficients, a.coefficients);
        testCase.verifyEqual(p.intercept, a.intercept);
        testCase.verifyEqual(p.feature_mean, a.feature_mean);
        testCase.verifyEqual(p.feature_scale, a.feature_scale);
        testCase.verifyEqual(p.numerical_rank, a.numerical_rank);
        testCase.verifyTrue(isequaln(p.lambda_selection_table, a.lambda_selection_table));
        testCase.verifyNotEqual(p.metrics.nrmse, a.metrics.nrmse);
    end
end

function testConstantPredictionHandling(testCase)
    y = randn(50, 1);
    y_hat = ones(50, 1) * 0.3;
    m = compute_temporal_memory_metrics(y_hat, y);
    testCase.verifyEqual(m.pearson, 0);
    testCase.verifyEqual(m.memory_coefficient, 0);
    testCase.verifyTrue(m.constant_prediction);
    testCase.verifyTrue(isfinite(m.r2));
end

%% Feature diagnostics
function testFullRankAndRankDeficientFixtures(testCase)
    stream = RandStream('mt19937ar', 'Seed', 41);
    X_full = randn(stream, 80, 5);
    d_full = compute_temporal_feature_diagnostics(X_full, struct( ...
        'mean_rate', 0.2, 'saturation_fraction', 0.01, 'silence_fraction', 0.02, ...
        'n_neurons', 40, 'packed_state_dimension', 120, ...
        'rates_are_neuronal', true, 'packed_states_counted_as_neurons', false));
    testCase.verifyEqual(d_full.numerical_rank, 5);
    testCase.verifyGreaterThan(d_full.participation_ratio, 1);

    X_def = [X_full(:, 1:3), X_full(:, 1), 2 * X_full(:, 2)];
    d_def = compute_temporal_feature_diagnostics(X_def);
    testCase.verifyEqual(d_def.numerical_rank, 3);
    testCase.verifyLessThanOrEqual(d_def.numerical_rank, 3);
end

function testActivityUsesNeuronalRateDimension40(testCase)
    cfg = testCase.TestData.cfg;
    cell_spec = cfg.diagnostic_cells.reference_r;
    opts = struct( ...
        'washout_steps', 15, ...
        'train_samples', 25, ...
        'validation_samples', 15, ...
        'test_samples', 15, ...
        'lags', (1:3)', ...
        'lambda_grid', [0; 1], ...
        'allow_test_fixture', true);
    bundle = fit_temporal_memory_seed(cfg, cell_spec, 1729, opts);
    fd = bundle.feature_diagnostics;
    testCase.verifyEqual(fd.n_neurons, 40);
    testCase.verifyTrue(fd.activity_from_neuronal_rates);
    testCase.verifyFalse(fd.packed_states_counted_as_neurons);
    testCase.verifyGreaterThan(fd.packed_state_dimension, 40);
    scored = score_temporal_memory_seed(bundle, bundle.Y_test_protocol);
    testCase.verifyTrue(scored.synthetic_provenance);
    testCase.verifyError(@() validate_temporal_memory_seed_result(scored, cfg), ...
        'validate_temporal_memory_seed_result:Failed');
end

%% Seed rejection
function testReservedFutureSeedsRejected(testCase)
    cfg = testCase.TestData.cfg;
    cell_spec = cfg.diagnostic_cells.reference_r;
    opts = struct('washout_steps', 5, 'train_samples', 8, ...
        'validation_samples', 8, 'test_samples', 8, 'lags', 1, ...
        'lambda_grid', 0);
    testCase.verifyError(@() fit_temporal_memory_seed(cfg, cell_spec, 11003, opts), ...
        'fit_temporal_memory_seed:ModelSeedNotExecutable');

    bad_task = cfg.task_seeds;
    bad_task.test = 13007;
    opts.task_seeds = bad_task;
    testCase.verifyError(@() build_temporal_memory_development_splits(cfg, opts), ...
        'build_temporal_memory_development_splits:ForbiddenSeed');
end

function testArbitraryUnregisteredModelSeedRejected(testCase)
    cfg = testCase.TestData.cfg;
    cell_spec = cfg.diagnostic_cells.reference_r;
    opts = struct('washout_steps', 5, 'train_samples', 8, ...
        'validation_samples', 8, 'test_samples', 8, 'lags', 1, ...
        'lambda_grid', 0);
    testCase.verifyError(@() fit_temporal_memory_seed(cfg, cell_spec, 424242, opts), ...
        'fit_temporal_memory_seed:ModelSeedNotExecutable');
    testCase.verifyError(@() fit_temporal_memory_seed(cfg, cell_spec, 10037, opts), ...
        'fit_temporal_memory_seed:ModelSeedNotExecutable');
end

function testV1TestSeed9003Rejected(testCase)
    cfg = testCase.TestData.cfg;
    opts = struct('washout_steps', 5, 'train_samples', 8, ...
        'validation_samples', 8, 'test_samples', 8, 'max_lag', 2);
    bad = cfg.task_seeds;
    bad.test = 9003;
    opts.task_seeds = bad;
    testCase.verifyError(@() build_temporal_memory_development_splits(cfg, opts), ...
        'build_temporal_memory_development_splits:ForbiddenSeed9003');

    result = struct( ...
        'model_seed', 9003, ...
        'lags', 1:50, ...
        'per_lag', repmat(struct('lag', 1), 50, 1), ...
        'include_input', false, ...
        'simulations_per_split', 1, ...
        'summary', struct('MC_1_50', 1), ...
        'feature_diagnostics', struct('n_neurons', 40, ...
            'packed_states_counted_as_neurons', false, ...
            'activity_from_neuronal_rates', true));
    testCase.verifyError(@() validate_temporal_memory_seed_result(result, cfg), ...
        'validate_temporal_memory_seed_result:Failed');
end

%% Exact-history control integration
function testExactHistoryControlViaComputeControls(testCase)
    wash = 4; max_lag = 4; n = 60;
    s_tr = RandStream('mt19937ar', 'Seed', 51);
    s_va = RandStream('mt19937ar', 'Seed', 52);
    s_te = RandStream('mt19937ar', 'Seed', 53);
    mk = @(s) local_split(s, wash, max_lag, n);
    splits = struct('train', mk(s_tr), 'validation', mk(s_va), 'test', mk(s_te));
    lags = (1:max_lag)';
    [Ytr, ~] = build_temporal_memory_targets(splits.train, lags);
    [Yva, ~] = build_temporal_memory_targets(splits.validation, lags);
    [Yte, ~] = build_temporal_memory_targets(splits.test, lags);
    dummy_X = @(ns) randn(ns, 3);
    payload = struct();
    payload.splits = splits;
    payload.lags = lags;
    payload.lambda_grid = [0; 1e-8];
    payload.mesn_features = struct( ...
        'train', struct('X', dummy_X(n)), ...
        'validation', struct('X', dummy_X(n)), ...
        'test', struct('X', dummy_X(n)));
    payload.Y_train = Ytr;
    payload.Y_val = Yva;
    payload.Y_test = Yte;
    payload.cell_name = 'delay_removed_r';
    payload.model_seed = 1729;
    cfg = testCase.TestData.cfg;
    controls = compute_temporal_memory_controls(payload, cfg, struct());
    for i = 1:numel(lags)
        testCase.verifyLessThan(controls.exact_history.per_lag(i).metrics.rmse, 1e-6);
        testCase.verifyGreaterThan( ...
            controls.exact_history.per_lag(i).metrics.memory_coefficient, 0.999);
    end
end

function split = local_split(stream, wash, max_lag, n)
    L = wash + max_lag + n;
    U = 2 * rand(stream, L, 1) - 1;
    split = struct();
    split.U = U;
    split.scored_idx = ((wash + max_lag + 1):L)';
    split.U_scored = U(split.scored_idx);
    split.washout_steps = wash;
    split.max_lag = max_lag;
    split.n_samples_used = n;
    split.total_length = L;
    split.seed = stream.Seed;
end

function testNegativeR2Retained(testCase)
    y = randn(40, 1);
    y_hat = -2 * y + 10;
    m = compute_temporal_memory_metrics(y_hat, y);
    % Can be negative for poor fits; ensure not clipped
    testCase.verifyTrue(isfield(m, 'r2'));
    testCase.verifyFalse(isnan(m.r2));
end

function testSummariesMCSums(testCase)
    lags = (1:50)';
    mc = zeros(50, 1);
    mc(1:10) = 0.5;
    mc(11:25) = 0.2;
    mc(26:50) = 0.05;
    metrics = repmat(struct('nrmse', 1, 'r2', 0, 'rmse', 1, ...
        'pearson', 0, 'memory_coefficient', 0), 50, 1);
    for i = 1:50
        metrics(i).memory_coefficient = mc(i);
        metrics(i).pearson = sqrt(mc(i));
    end
    metrics(10).nrmse = 0.4;
    metrics(10).r2 = 0.3;
    s = summarize_temporal_memory_curve(lags, mc, metrics);
    testCase.verifyEqual(s.MC_1_10, 5.0, 'AbsTol', 1e-12);
    testCase.verifyEqual(s.MC_1_25, 5.0 + 15 * 0.2, 'AbsTol', 1e-12);
    testCase.verifyEqual(s.MC_1_50, s.MC_1_25 + 25 * 0.05, 'AbsTol', 1e-12);
    testCase.verifyEqual(s.first_lag_memory_below_0_1, 26);
    testCase.verifyFalse(s.memory_crossing_right_censored_at_50);
    testCase.verifyEqual(s.lag10_nrmse, 0.4);
end

%% Hardened production validator
function testValidatorRejectsBadCellAndLags(testCase)
    cfg = testCase.TestData.cfg;
    r = synthetic_production_result(cfg);
    r.cell_name = 'not_a_real_cell';
    testCase.verifyError(@() validate_temporal_memory_seed_result(r, cfg), ...
        'validate_temporal_memory_seed_result:Failed');

    r = synthetic_production_result(cfg);
    r.lags = 50:-1:1;
    for i = 1:50; r.per_lag(i).lag = r.lags(i); end
    testCase.verifyError(@() validate_temporal_memory_seed_result(r, cfg), ...
        'validate_temporal_memory_seed_result:Failed');

    r = synthetic_production_result(cfg);
    r.lags = 1:49;
    r.per_lag = r.per_lag(1:49);
    testCase.verifyError(@() validate_temporal_memory_seed_result(r, cfg), ...
        'validate_temporal_memory_seed_result:Failed');
end

function testValidatorRejectsMissingDuplicateNonfiniteAndMC(testCase)
    cfg = testCase.TestData.cfg;
    r = synthetic_production_result(cfg);
    r.per_lag(5).lag = 4; % duplicate 4, missing 5
    testCase.verifyError(@() validate_temporal_memory_seed_result(r, cfg), ...
        'validate_temporal_memory_seed_result:Failed');

    r = synthetic_production_result(cfg);
    r.per_lag(3).metrics.nrmse = Inf;
    testCase.verifyError(@() validate_temporal_memory_seed_result(r, cfg), ...
        'validate_temporal_memory_seed_result:Failed');

    r = synthetic_production_result(cfg);
    r.summary.MC_1_10 = r.summary.MC_1_10 + 1;
    testCase.verifyError(@() validate_temporal_memory_seed_result(r, cfg), ...
        'validate_temporal_memory_seed_result:Failed');

    r = synthetic_production_result(cfg);
    r.summary.lag10_nrmse = r.summary.lag10_nrmse + 0.5;
    testCase.verifyError(@() validate_temporal_memory_seed_result(r, cfg), ...
        'validate_temporal_memory_seed_result:Failed');
end

function testValidatorRejectsActivityAndRNG(testCase)
    cfg = testCase.TestData.cfg;
    r = synthetic_production_result(cfg);
    r.feature_diagnostics.n_neurons = 80;
    testCase.verifyError(@() validate_temporal_memory_seed_result(r, cfg), ...
        'validate_temporal_memory_seed_result:Failed');

    r = synthetic_production_result(cfg);
    r.global_rng_unchanged = false;
    testCase.verifyError(@() validate_temporal_memory_seed_result(r, cfg), ...
        'validate_temporal_memory_seed_result:Failed');
end

function testValidatorAcceptsSyntheticProductionShapedResult(testCase)
    cfg = testCase.TestData.cfg;
    r = synthetic_production_result(cfg);
    report = validate_temporal_memory_seed_result(r, cfg);
    testCase.verifyTrue(report.ok);
end

function r = synthetic_production_result(cfg)
    r = struct();
    r.model_seed = 1729;
    r.cell_name = 'reference_r';
    r.cell_key = cfg.diagnostic_cells.reference_r.cell_key;
    r.lags = (1:50)';
    r.include_input = false;
    r.simulations_per_split = 1;
    r.n_reservoir_simulations = 3;
    r.global_rng_unchanged = true;
    r.feature_dimension = 40;
    r.is_test_fixture = false;
    r.synthetic_provenance = false;
    blank = struct('lag', NaN, 'selected_lambda', 0, 'numerical_rank', 5, ...
        'coefficient_norm', 1, 'metrics', struct('rmse', 0.5, 'nrmse', 0.5, ...
        'r2', 0.2, 'pearson', 0.4, 'memory_coefficient', 0.16));
    r.per_lag = repmat(blank, 50, 1);
    mc = zeros(50, 1);
    for i = 1:50
        r.per_lag(i).lag = i;
        r.per_lag(i).metrics.memory_coefficient = 0.16;
        r.per_lag(i).metrics.pearson = 0.4;
        mc(i) = 0.16;
    end
    r.summary = summarize_temporal_memory_curve(r.lags, mc, [r.per_lag.metrics]);
    r.feature_diagnostics = struct('n_neurons', 40, ...
        'activity_from_neuronal_rates', true, ...
        'packed_states_counted_as_neurons', false, ...
        'packed_state_dimension', 120);
end
