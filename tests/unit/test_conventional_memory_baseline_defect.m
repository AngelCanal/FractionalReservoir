function tests = test_conventional_memory_baseline_defect
% Phase 5D-B1-R: legacy defect fixture + single-reservoir production repair.
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

function testLegacyPerLagSelectionSwitchesCandidates(testCase)
% Fixture documenting the pre-repair defect: selecting inside the lag loop
% can assign different conventional candidate indices to different lags.
    fixture = synthetic_switching_fixture();
    selected = zeros(numel(fixture.lags), 1);
    for li = 1:numel(fixture.lags)
        scores = nan(fixture.n_cand, 1);
        for ic = 1:fixture.n_cand
            sel = select_ridge_lambda( ...
                fixture.cand{ic}.Htr, fixture.Ytr{li}, ...
                fixture.cand{ic}.Hva, fixture.Yva{li}, fixture.lambda_grid);
            scores(ic) = sel.selected_val_score;
        end
        best = min(scores);
        tied = abs(scores - best) <= 1e-12;
        selected(li) = find(tied, 1, 'first');
    end
    testCase.verifyGreaterThan(numel(unique(selected)), 1);
    testCase.verifyNotEqual(selected(1), selected(2));
    fprintf(['DEFECT RECORDED: MESN uses one reservoir for all lags; legacy ', ...
        'conventional selected candidates %s across lags %s; MC sums would ', ...
        'not belong to one reservoir. No real diagnostic outcomes inspected.\n'], ...
        mat2str(selected(:)'), mat2str(fixture.lags(:)'));
end

function testProductionSelectsOneCandidateAcrossLags(testCase)
    fixture = synthetic_switching_fixture();
    opts = struct();
    opts.conventional_config = fixture.ce;
    opts.inject_candidates = fixture.inject_candidates;
    opts.allow_test_fixture = true;
    opts.selection_lags = fixture.lags;
    bundle = fit_conventional_memory_curve( ...
        fixture.splits, fixture.Ytr, fixture.Yva, ...
        fixture.lags, fixture.lambda_grid, fixture.mesn_Win, 1729, opts);
    scored = score_conventional_memory_curve(bundle, fixture.Yte);
    idxs = [scored.per_lag.selected_candidate_index];
    testCase.verifyEqual(numel(unique(idxs)), 1);
    testCase.verifyTrue(scored.same_reservoir_for_all_lags);
    testCase.verifyEqual(scored.selected_candidate_index, idxs(1));
    for i = 1:numel(idxs)
        testCase.verifyEqual(scored.per_lag(i).selected_candidate_index, ...
            scored.selected_candidate_index);
        testCase.verifyEqual(scored.per_lag(i).hyperparameters.spectral_radius, ...
            scored.selected_hyperparameters.spectral_radius);
    end
end

function testAggregateMeanValidationNRMSESelection(testCase)
    fixture = synthetic_switching_fixture();
    opts = struct();
    opts.inject_candidates = fixture.inject_candidates;
    opts.allow_test_fixture = true;
    opts.selection_lags = fixture.lags;
    opts.conventional_config = fixture.ce;
    bundle = fit_conventional_memory_curve(fixture.splits, fixture.Ytr, ...
        fixture.Yva, fixture.lags, fixture.lambda_grid, fixture.mesn_Win, ...
        1729, opts);
    agg = bundle.aggregate_validation_nrmse;
    mat = bundle.per_candidate_per_lag_validation_nrmse;
    testCase.verifyEqual(agg, mean(mat, 2), 'AbsTol', 1e-15);
    testCase.verifyEqual(bundle.selection_metric, ...
        'mean_validation_nrmse_over_all_preregistered_lags');
end

function testEarliestCandidateTieBreak(testCase)
% Two identical candidates: earliest index must win at 1e-12.
    n = 30;
    lags = [1; 2];
    stream = RandStream('mt19937ar', 'Seed', 99);
    y = randn(stream, n, 1);
    H = [y, 0.01 * randn(stream, n, 1)];
    twin = struct('Htr', H, 'Hva', H, 'Hte', H, 'Wres', eye(2), 'Win', ones(2, 1));
    cand = {twin, twin};
    Y = {y; y};
    splits = dummy_splits(n, stream);
    opts = struct();
    opts.inject_candidates = cand;
    opts.allow_test_fixture = true;
    opts.selection_lags = lags;
    opts.tie_tolerance = 1e-12;
    bundle = fit_conventional_memory_curve(splits, Y, Y, lags, [0; 1], ...
        ones(2, 1), 1729, opts);
    testCase.verifyEqual(bundle.selected_candidate_index, 1);
    testCase.verifyEqual(abs(bundle.aggregate_validation_nrmse(1) - ...
        bundle.aggregate_validation_nrmse(2)) <= 1e-12, true);
end

function testConventionalTestTargetIsolation(testCase)
    fixture = synthetic_switching_fixture();
    opts = struct();
    opts.inject_candidates = fixture.inject_candidates;
    opts.allow_test_fixture = true;
    opts.selection_lags = fixture.lags;
    opts.conventional_config = fixture.ce;
    bundle = fit_conventional_memory_curve(fixture.splits, fixture.Ytr, ...
        fixture.Yva, fixture.lags, fixture.lambda_grid, fixture.mesn_Win, ...
        1729, opts);
    s1 = score_conventional_memory_curve(bundle, fixture.Yte);
    Yalt = fixture.Yte;
    for i = 1:numel(Yalt); Yalt{i} = Yalt{i} + 3; end
    s2 = score_conventional_memory_curve(bundle, Yalt);
    testCase.verifyEqual(s1.selected_candidate_index, s2.selected_candidate_index);
    testCase.verifyEqual(s1.selected_hyperparameters.spectral_radius, ...
        s2.selected_hyperparameters.spectral_radius);
    testCase.verifyEqual(s1.selected_hyperparameters.leak_rate, ...
        s2.selected_hyperparameters.leak_rate);
    testCase.verifyEqual(s1.selected_hyperparameters.input_scaling, ...
        s2.selected_hyperparameters.input_scaling);
    testCase.verifyEqual(s1.Wres, s2.Wres);
    testCase.verifyEqual(s1.Win, s2.Win);
    testCase.verifyEqual(s1.selected_candidate_content_hash, ...
        s2.selected_candidate_content_hash);
    testCase.verifyTrue(isequaln(s1.candidate_selection_table, ...
        s2.candidate_selection_table));
    testCase.verifyEqual(s1.aggregate_validation_nrmse, s2.aggregate_validation_nrmse);
    for i = 1:numel(fixture.lags)
        testCase.verifyEqual(s1.per_lag(i).selected_lambda, s2.per_lag(i).selected_lambda);
        testCase.verifyEqual(s1.per_lag(i).coefficients, s2.per_lag(i).coefficients);
        testCase.verifyEqual(s1.per_lag(i).intercept, s2.per_lag(i).intercept);
        testCase.verifyEqual(s1.per_lag(i).feature_mean, s2.per_lag(i).feature_mean);
        testCase.verifyEqual(s1.per_lag(i).feature_scale, s2.per_lag(i).feature_scale);
        testCase.verifyNotEqual(s1.per_lag(i).metrics.nrmse, s2.per_lag(i).metrics.nrmse);
    end
end

function testCandidateGridCount27AndEngineFlags(testCase)
    cfg = testCase.TestData.cfg;
    testCase.verifyEqual(cfg.conventional_memory_baseline.candidate_count, 27);
    testCase.verifyEqual(cfg.conventional_memory_baseline.engine, ...
        'run_conventional_leaky_esn');
    testCase.verifyEqual(cfg.conventional_memory_baseline.candidate_grid_source, ...
        'build_matched_task_baselines_config');
    bb = build_matched_task_baselines_config(cfg);
    ce = bb.conventional_leaky_esn;
    n = numel(ce.spectral_radius_candidates) * numel(ce.leak_rate_candidates) * ...
        numel(ce.input_scaling_candidates);
    testCase.verifyEqual(n, 27);
end

function testReusableSharedBaselineAcrossCells(testCase)
    fixture = synthetic_switching_fixture();
    opts = struct();
    opts.inject_candidates = fixture.inject_candidates;
    opts.allow_test_fixture = true;
    opts.selection_lags = fixture.lags;
    bundle = fit_conventional_memory_curve(fixture.splits, fixture.Ytr, ...
        fixture.Yva, fixture.lags, fixture.lambda_grid, fixture.mesn_Win, ...
        1729, opts);
    testCase.verifyTrue(bundle.reusable_across_cells);
    payload = struct();
    payload.splits = fixture.splits;
    payload.lags = fixture.lags;
    payload.lambda_grid = fixture.lambda_grid;
    payload.mesn_features = struct( ...
        'train', struct('X', randn(40, 3)), ...
        'validation', struct('X', randn(40, 3)), ...
        'test', struct('X', randn(40, 3)));
    payload.Y_train = fixture.Ytr;
    payload.Y_val = fixture.Yva;
    payload.Y_test = fixture.Yte;
    payload.cell_name = 'delay_removed_r';
    payload.model_seed = 1729;
    payload.conventional_precomputed = bundle;
    cfg = testCase.TestData.cfg;
    c1 = compute_temporal_memory_controls(payload, cfg, struct());
    c2 = compute_temporal_memory_controls(payload, cfg, struct());
    testCase.verifyTrue(c1.conventional_leaky_esn.reused_shared_baseline);
    testCase.verifyEqual(c1.conventional_leaky_esn.selected_candidate_index, ...
        c2.conventional_leaky_esn.selected_candidate_index);
    testCase.verifyFalse(c1.conventional_leaky_esn.used_narma_orchestrator);
    testCase.verifyFalse(c1.conventional_leaky_esn.used_mackey_glass_orchestrator);
end

function fixture = synthetic_switching_fixture()
    n = 40;
    lags = [1; 2];
    lambda_grid = [0; 1e-4; 1];
    stream = RandStream('mt19937ar', 'Seed', 77);
    noise = @(m, k) 0.05 * randn(stream, m, k);
    u_tr = randn(stream, n, 1);
    u_va = randn(stream, n, 1);
    u_te = randn(stream, n, 1);
    y1_tr = u_tr + noise(n, 1);
    y1_va = u_va + noise(n, 1);
    y1_te = u_te + noise(n, 1);
    z_tr = randn(stream, n, 1);
    z_va = randn(stream, n, 1);
    z_te = randn(stream, n, 1);
    y2_tr = z_tr + noise(n, 1);
    y2_va = z_va + noise(n, 1);
    y2_te = z_te + noise(n, 1);
    cand = cell(2, 1);
    cand{1} = struct('Htr', [y1_tr, noise(n, 1)], 'Hva', [y1_va, noise(n, 1)], ...
        'Hte', [y1_te, noise(n, 1)], 'Wres', eye(2), 'Win', ones(2, 1));
    cand{2} = struct('Htr', [y2_tr, noise(n, 1)], 'Hva', [y2_va, noise(n, 1)], ...
        'Hte', [y2_te, noise(n, 1)], 'Wres', 2 * eye(2), 'Win', 2 * ones(2, 1));
    fixture = struct();
    fixture.n_cand = 2;
    fixture.cand = cand;
    fixture.inject_candidates = cand;
    fixture.Ytr = {y1_tr; y2_tr};
    fixture.Yva = {y1_va; y2_va};
    fixture.Yte = {y1_te; y2_te};
    fixture.lags = lags;
    fixture.lambda_grid = lambda_grid;
    fixture.splits = dummy_splits(n, stream);
    fixture.mesn_Win = ones(2, 1);
    fixture.ce = struct('spectral_radius_candidates', [0.5, 0.9], ...
        'leak_rate_candidates', 1.0, 'input_scaling_candidates', 1.0, ...
        'reservoir_seed_offset', 2000);
end

function splits = dummy_splits(n, stream)
    wash = 5;
    max_lag = 2;
    L = wash + max_lag + n;
    mk = @(seed) local_mk(stream, seed, wash, max_lag, n, L);
    splits = struct('train', mk(1), 'validation', mk(2), 'test', mk(3));
end

function split = local_mk(stream, seed, wash, max_lag, n, L)
    split = struct();
    split.U = randn(stream, L, 1);
    split.scored_idx = ((wash + max_lag + 1):L)';
    split.U_scored = split.U(split.scored_idx);
    split.washout_steps = wash;
    split.max_lag = max_lag;
    split.seed = seed;
    split.n_samples_used = n;
    split.total_length = L;
end
