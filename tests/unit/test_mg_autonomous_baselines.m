function tests = test_mg_autonomous_baselines
% test_mg_autonomous_baselines  Phase 4C-B2 matched MG autonomous controls.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'scripts')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
    testCase.TestData.repo_root = repo_root;
end

function cfg = tiny_cfg()
    cfg = mechanism_ablation_config('smoke');
    cfg.benchmark_baselines.conventional_leaky_esn.spectral_radius_candidates = 0.9;
    cfg.benchmark_baselines.conventional_leaky_esn.leak_rate_candidates = 1.0;
    cfg.benchmark_baselines.conventional_leaky_esn.input_scaling_candidates = 0.5;
    cfg.protocol_fingerprint = compute_protocol_fingerprint(cfg);
end

function cells = x_and_r_cells(cfg)
    keys = { ...
        'adapt-off__std-off__delay-ode_off__feat-x', ...
        'adapt-off__std-off__delay-ode_off__feat-r'};
    cells = {};
    for i = 1:numel(cfg.cells)
        if any(strcmp(cfg.cells{i}.cell_key, keys))
            cells{end+1} = cfg.cells{i}; %#ok<AGROW>
        end
    end
    assert(numel(cells) == 2);
end

function [task, baselines, rollout_cfg, schedule, cfg, seed] = mg_baseline_setup()
    cfg = tiny_cfg();
    seed = cfg.seeds(1);
    L = cfg.lengths;
    mg_seed = seed + 30;
    task = build_mackey_glass_onestep_task_dataset(struct( ...
        'T', L.mg_T, ...
        'discard', L.mg_discard, ...
        'washout_steps', L.mg_washout, ...
        'train_ratio', L.train_ratio, ...
        'val_ratio', L.val_ratio, ...
        'seed', mg_seed));
    [p, ~] = build_ablation_params(cfg.cells{1}, seed, cfg, struct());
    lambda_grid = resolve_baseline_lambda_grid(struct(), cfg);
    mg_opts = struct( ...
        'task', 'mackey_glass_onestep', ...
        'mesn_Win', p.W_in, ...
        'base_seed', seed, ...
        'seed', mg_seed, ...
        'feature_mode', 'x', ...
        'lambda_grid', lambda_grid, ...
        'ar_lags', local_get(L, 'mg_ar_lags', 10), ...
        'benchmark_baselines', cfg.benchmark_baselines, ...
        'skip_dale', true, ...
        'skip_comparisons', true, ...
        'task_data_hash', task.task_data_hash, ...
        'split_hash', task.split_hash);
    baselines = compute_matched_onestep_baselines( ...
        task.U, task.Y, task.split, task.washout_steps, mg_opts);
    rollout_cfg = cfg.mg_autonomous_rollout;
    schedule = build_mg_autonomous_origin_schedule(task.split, rollout_cfg);
end

%% A. B1 origin-schedule hardening
function testValidOriginSchedulePassesValidation(testCase)
    [task, ~, rollout_cfg, ~, cfg] = mg_baseline_setup();
    result = local_minimal_valid_ode_result(task.split, rollout_cfg, task.Y);
    [ok, rep] = validate_mg_autonomous_rollout_result(result, ...
        struct('mg_autonomous_rollout', rollout_cfg), 'ODE');
    testCase.verifyTrue(ok, strjoin(rep.reasons, ','));

    controls = compute_mg_autonomous_baseline_controls( ...
        task, baselines_from_task(task, cfg), rollout_cfg, cfg.seeds(1), ...
        'executed_shared_seed_bundle');
    exp = struct( ...
        'rollout_cfg', rollout_cfg, ...
        'require_production_provenance', true, ...
        'cell_mode', 'ODE', ...
        'one_step_baselines', baselines_from_task(task, cfg), ...
        'base_seed', cfg.seeds(1), ...
        'task_seed', task.seed, ...
        'task_data_hash', task.task_data_hash, ...
        'split_hash', task.split_hash);
    [cok, ~] = validate_mg_autonomous_baseline_controls(controls, exp);
    testCase.verifyTrue(cok);
end

function testTamperedOriginIndicesRejected(testCase)
    [task, ~, rollout_cfg] = mg_baseline_setup();
    result = local_minimal_valid_ode_result(task.split, rollout_cfg, task.Y);
    sch = result.origin_schedule;
    sch.origin_indices(1) = sch.origin_indices(1) + 1;
    result.origin_schedule = sch;
    result.per_origin(1).origin_global_index = sch.origin_indices(1);
    [ok, rep] = validate_mg_autonomous_rollout_result(result, ...
        struct('mg_autonomous_rollout', rollout_cfg), 'ODE');
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(rep.reasons, 'schedule_origin_indices_mismatch')));
end

function testChangedTestRelativeOriginRejected(testCase)
    [task, ~, rollout_cfg] = mg_baseline_setup();
    result = local_minimal_valid_ode_result(task.split, rollout_cfg, task.Y);
    sch = result.origin_schedule;
    sch.origin_test_relative_indices(1) = sch.origin_test_relative_indices(1) + 1;
    result.origin_schedule = sch;
    result.per_origin(1).origin_test_relative_index = sch.origin_test_relative_indices(1);
    [ok, rep] = validate_mg_autonomous_rollout_result(result, ...
        struct('mg_autonomous_rollout', rollout_cfg), 'ODE');
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(rep.reasons, 'schedule_origin_test_relative_indices_mismatch')));
end

function testChangedFirstOrLastOriginRejected(testCase)
    [task, ~, rollout_cfg] = mg_baseline_setup();
    result = local_minimal_valid_ode_result(task.split, rollout_cfg, task.Y);
    bad_first = result;
    sch = bad_first.origin_schedule;
    sch.first_origin = sch.first_origin + 1;
    bad_first.origin_schedule = sch;
    [ok1, rep1] = validate_mg_autonomous_rollout_result(bad_first, ...
        struct('mg_autonomous_rollout', rollout_cfg), 'ODE');
    testCase.verifyFalse(ok1);
    testCase.verifyTrue(any(strcmp(rep1.reasons, 'schedule_first_origin_mismatch')));

    bad_last = result;
    sch2 = bad_last.origin_schedule;
    sch2.last_origin = sch2.last_origin - 1;
    bad_last.origin_schedule = sch2;
    [ok2, rep2] = validate_mg_autonomous_rollout_result(bad_last, ...
        struct('mg_autonomous_rollout', rollout_cfg), 'ODE');
    testCase.verifyFalse(ok2);
    testCase.verifyTrue(any(strcmp(rep2.reasons, 'schedule_last_origin_mismatch')));
end

function testScorerRejectsTargetBeyondTestEnd(testCase)
    cfg = build_mg_autonomous_rollout_config('smoke');
    cfg.forecast_horizon_steps = 5;
    cfg.n_forecast_origins = 1;
    cfg.fixed_report_horizons = [1, 5];
    split = struct( ...
        'train_idx', (1:20)', 'val_idx', (21:30)', 'test_idx', (31:40)', ...
        'washout_steps', 2);
    Y = (1:50)';
    origin = split.test_idx(end) - 2;  % i+H-1 > test_idx(end)
    testCase.verifyError(@() score_mg_autonomous_forecasts( ...
        {ones(5, 1)}, Y, origin, split, cfg), ...
        'score_mg_autonomous_forecasts:TargetBeyondTestEnd');
    % Gap in test block also triggers TargetOutsideTest
    split_gap = split;
    split_gap.test_idx = [31:35, 37:40]';
    testCase.verifyError(@() score_mg_autonomous_forecasts( ...
        {ones(5, 1)}, Y, 33, split_gap, cfg), ...
        'score_mg_autonomous_forecasts:TargetOutsideTest');
end

function testPerOriginCountMismatchRejected(testCase)
    [task, ~, rollout_cfg] = mg_baseline_setup();
    result = local_minimal_valid_ode_result(task.split, rollout_cfg, task.Y);
    result.per_origin = result.per_origin(1);
    [ok, rep] = validate_mg_autonomous_rollout_result(result, ...
        struct('mg_autonomous_rollout', rollout_cfg), 'ODE');
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(rep.reasons, 'per_origin_count_mismatch')));
end

%% B. Persistence
function testPersistenceConstantAtOrigin(testCase)
    [task, ~, rollout_cfg, schedule] = mg_baseline_setup();
    res = rollout_mg_autonomous_persistence(task.U, task.Y, task.split, schedule, rollout_cfg);
    H = schedule.forecast_horizon_steps;
    for o = 1:numel(schedule.origin_indices)
        i = schedule.origin_indices(o);
        pred = res.predictions{o};
        testCase.verifyEqual(pred, repmat(task.U(i), H, 1), 'AbsTol', 0);
    end
end

function testPersistenceNeverUsesFutureU(testCase)
    [task, ~, rollout_cfg, schedule] = mg_baseline_setup();
    res = rollout_mg_autonomous_persistence(task.U, task.Y, task.split, schedule, rollout_cfg);
    H = schedule.forecast_horizon_steps;
    for o = 1:numel(schedule.origin_indices)
        i = schedule.origin_indices(o);
        pred = res.predictions{o};
        for k = 2:H
            if abs(task.U(i + k - 1) - task.U(i)) > 1e-12
                testCase.verifyEqual(pred(k), task.U(i), 'AbsTol', 0);
                testCase.verifyFalse(abs(pred(k) - task.U(i + k - 1)) <= 1e-12);
            end
        end
    end
end

function testPersistenceStep1EqualsUOrigin(testCase)
    [task, ~, rollout_cfg, schedule] = mg_baseline_setup();
    res = rollout_mg_autonomous_persistence(task.U, task.Y, task.split, schedule, rollout_cfg);
    for o = 1:numel(schedule.origin_indices)
        i = schedule.origin_indices(o);
        testCase.verifyEqual(res.predictions{o}(1), task.U(i), 'AbsTol', 0);
    end
    testCase.verifyTrue(res.first_step_alignment.verified);
end

function testPersistenceMetricsHandCalc(testCase)
    [task, ~, rollout_cfg, schedule] = mg_baseline_setup();
    res = rollout_mg_autonomous_persistence(task.U, task.Y, task.split, schedule, rollout_cfg);
    preds = res.predictions;
    scored = score_mg_autonomous_forecasts(preds, task.Y, schedule.origin_indices, ...
        task.split, rollout_cfg);
    testCase.verifyEqual(res.metrics.pooled_nrmse_full_horizon, ...
        scored.metrics.pooled_nrmse_full_horizon, 'AbsTol', 1e-12);
    testCase.verifyEqual(res.metrics.pooled_nrmse_at_fixed_horizons, ...
        scored.metrics.pooled_nrmse_at_fixed_horizons, 'AbsTol', 1e-12);
    testCase.verifyEqual(res.normalization_scale, scored.normalization_scale, 'AbsTol', 1e-12);
end

%% C. Linear AR
function testLinearArStep1EqualsFrozenOneStep(testCase)
    [task, baselines, rollout_cfg, schedule] = mg_baseline_setup();
    lar = baselines.linear_autoregression;
    res = rollout_mg_autonomous_linear_ar(task.U, task.Y, task.split, schedule, ...
        rollout_cfg, lar);
    L = lar.lag_count;
    for o = 1:numel(schedule.origin_indices)
        i = schedule.origin_indices(o);
        frozen = apply_ridge_readout(lar.fitted_model, task.U(i:-1:(i - L + 1)).');
        testCase.verifyEqual(res.predictions{o}(1), frozen, 'AbsTol', 1e-10);
    end
    testCase.verifyTrue(res.first_step_alignment.verified);
end

function testLinearArStep2UsesPredictionNotTrueU(testCase)
    [task, baselines, rollout_cfg, schedule] = mg_baseline_setup();
    lar = baselines.linear_autoregression;
    res = rollout_mg_autonomous_linear_ar(task.U, task.Y, task.split, schedule, ...
        rollout_cfg, lar);
    L = lar.lag_count;
    i = schedule.origin_indices(1);
    history_true = task.U(i:-1:(i - L + 1)).';
    pred1 = apply_ridge_readout(lar.fitted_model, history_true);
    history_pred = [pred1, history_true(1:end-1)];
    teacher_step2 = apply_ridge_readout(lar.fitted_model, history_pred);
    autonomous_step2 = res.predictions{1}(2);
    testCase.verifyEqual(autonomous_step2, teacher_step2, 'AbsTol', 1e-10);
    history_true_step2 = [task.U(i + 1), history_true(1:end-1)];
    oracle_with_true = apply_ridge_readout(lar.fitted_model, history_true_step2);
    if abs(oracle_with_true - autonomous_step2) > 1e-8
        testCase.verifyFalse(abs(autonomous_step2 - oracle_with_true) <= 1e-8);
    end
end

function testLinearArLambdaUnchanged(testCase)
    [task, baselines, rollout_cfg, schedule] = mg_baseline_setup();
    lar = baselines.linear_autoregression;
    res = rollout_mg_autonomous_linear_ar(task.U, task.Y, task.split, schedule, ...
        rollout_cfg, lar);
    testCase.verifyEqual(res.selected_lambda, lar.selected_lambda, 'AbsTol', 0);
    testCase.verifyFalse(res.provenance.lambda_reselected);
end

function testLinearArModelHashMismatchRejected(testCase)
    [task, baselines, rollout_cfg, schedule] = mg_baseline_setup();
    lar = baselines.linear_autoregression;
    bad = lar;
    bad.fitted_model_hash = 'deadbeef';
    testCase.verifyError(@() rollout_mg_autonomous_linear_ar(task.U, task.Y, ...
        task.split, schedule, rollout_cfg, bad), ...
        'rollout_mg_autonomous_linear_ar:ModelHashMismatch');
end

function testLinearArTestPredictionHashMatches(testCase)
    [task, baselines, rollout_cfg, schedule] = mg_baseline_setup();
    lar = baselines.linear_autoregression;
    res = rollout_mg_autonomous_linear_ar(task.U, task.Y, task.split, schedule, ...
        rollout_cfg, lar);
    testCase.verifyEqual(res.status, 'computed');
    testCase.verifyEqual(res.test_prediction_hash, lar.test_prediction_hash);
    testCase.verifyTrue(res.first_step_alignment.test_prediction_hash_verified);
end

%% D. Conventional ESN
function testConventionalEsnStep1Alignment(testCase)
    [task, baselines, rollout_cfg, schedule] = mg_baseline_setup();
    ce = baselines.conventional_leaky_esn;
    res = rollout_mg_autonomous_conventional_esn(task.U, task.Y, task.split, ...
        schedule, rollout_cfg, ce);
    fitted = ce.fitted_model;
    [H_tf, ~] = run_conventional_leaky_esn(task.U, fitted.W_res, fitted.W_in, ...
        fitted.leak_rate, struct('initial_state', fitted.zero_initial_state));
    for o = 1:numel(schedule.origin_indices)
        i = schedule.origin_indices(o);
        frozen = apply_ridge_readout(fitted.readout_model, H_tf(i, :));
        testCase.verifyEqual(res.predictions{o}(1), frozen, 'AbsTol', 1e-8);
    end
    testCase.verifyTrue(res.first_step_alignment.verified);
end

function testConventionalEsnStep2UsesPredictionInput(testCase)
    [task, baselines, rollout_cfg, schedule] = mg_baseline_setup();
    ce = baselines.conventional_leaky_esn;
    res = rollout_mg_autonomous_conventional_esn(task.U, task.Y, task.split, ...
        schedule, rollout_cfg, ce);
    fitted = ce.fitted_model;
    [H_tf, ~] = run_conventional_leaky_esn(task.U, fitted.W_res, fitted.W_in, ...
        fitted.leak_rate, struct('initial_state', fitted.zero_initial_state));
    i = schedule.origin_indices(1);
    h = H_tf(i, :).';
    pred1 = apply_ridge_readout(fitted.readout_model, h.');
    pre = fitted.W_res * h + fitted.W_in * pred1;
    h2 = (1 - fitted.leak_rate) * h + fitted.leak_rate * tanh(pre);
    teacher_step2 = apply_ridge_readout(fitted.readout_model, h2.');
    testCase.verifyEqual(res.predictions{1}(2), teacher_step2, 'AbsTol', 1e-8);
    true_input = task.U(i + 1);
    pre_true = fitted.W_res * h + fitted.W_in * true_input;
    h2_true = (1 - fitted.leak_rate) * h + fitted.leak_rate * tanh(pre_true);
    oracle_true = apply_ridge_readout(fitted.readout_model, h2_true.');
    if abs(oracle_true - teacher_step2) > 1e-6
        testCase.verifyFalse(abs(res.predictions{1}(2) - oracle_true) <= 1e-6);
    end
end

function testConventionalEsnHyperparamsUnchanged(testCase)
    [task, baselines, rollout_cfg, schedule] = mg_baseline_setup();
    ce = baselines.conventional_leaky_esn;
    res = rollout_mg_autonomous_conventional_esn(task.U, task.Y, task.split, ...
        schedule, rollout_cfg, ce);
    fitted = ce.fitted_model;
    testCase.verifyEqual(res.selected_lambda, ce.selected_lambda, 'AbsTol', 0);
    testCase.verifyEqual(res.selected_candidate_index, fitted.selected_candidate_index);
    testCase.verifyEqual(res.spectral_radius, fitted.spectral_radius, 'AbsTol', 0);
    testCase.verifyEqual(res.leak_rate, fitted.leak_rate, 'AbsTol', 0);
    testCase.verifyEqual(res.input_scaling, fitted.input_scaling, 'AbsTol', 0);
    testCase.verifyEqual(res.reservoir_seed, fitted.reservoir_seed);
    testCase.verifyFalse(res.provenance.lambda_reselected);
    testCase.verifyFalse(res.provenance.candidate_reselected);
end

function testConventionalEsnMutatedWresRejected(testCase)
    [task, baselines, rollout_cfg, schedule] = mg_baseline_setup();
    ce = baselines.conventional_leaky_esn;
    bad = ce;
    bad.fitted_model = ce.fitted_model;
    bad.fitted_model.W_res(1) = bad.fitted_model.W_res(1) + 0.01;
    testCase.verifyError(@() rollout_mg_autonomous_conventional_esn(task.U, task.Y, ...
        task.split, schedule, rollout_cfg, bad), ...
        'rollout_mg_autonomous_conventional_esn:ModelHashMismatch');
end

function testConventionalEsnMutatedWinRejected(testCase)
    [task, baselines, rollout_cfg, schedule] = mg_baseline_setup();
    ce = baselines.conventional_leaky_esn;
    bad = ce;
    bad.fitted_model = ce.fitted_model;
    bad.fitted_model.W_in(1) = bad.fitted_model.W_in(1) + 0.01;
    testCase.verifyError(@() rollout_mg_autonomous_conventional_esn(task.U, task.Y, ...
        task.split, schedule, rollout_cfg, bad), ...
        'rollout_mg_autonomous_conventional_esn:ModelHashMismatch');
end

function testConventionalEsnMutatedReadoutRejected(testCase)
    [task, baselines, rollout_cfg, schedule] = mg_baseline_setup();
    ce = baselines.conventional_leaky_esn;
    bad = ce;
    bad.fitted_model = ce.fitted_model;
    bad.fitted_model.readout_model = ce.fitted_model.readout_model;
    bad.fitted_model.readout_model.coefficients(1) = ...
        bad.fitted_model.readout_model.coefficients(1) + 0.01;
    testCase.verifyError(@() rollout_mg_autonomous_conventional_esn(task.U, task.Y, ...
        task.split, schedule, rollout_cfg, bad), ...
        'rollout_mg_autonomous_conventional_esn:ModelHashMismatch');
end

%% E. Shared execution
function testSharedControlsOncePerSeed(testCase)
    cfg = tiny_cfg();
    cells = x_and_r_cells(cfg);
    seed = cfg.seeds(1);
    root = tempname;
    mkdir(root);
    run_dir = fullfile(root, 'run');
    mkdir(run_dir);
    cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
    [bundle, art] = prepare_seed_matched_baselines(cfg, seed, cells, run_dir, true, struct());
    testCase.verifyTrue(exist(art, 'file') == 2);
    testCase.verifyEqual(bundle.mackey_glass_autonomous.status, 'computed');
    d = dir(fullfile(run_dir, 'baselines', 'seed_*_matched_task_baselines.mat'));
    testCase.verifyEqual(numel(d), 1);
end

function testSharedContentHashAcrossOdeCells(testCase)
    cfg = tiny_cfg();
    cells = x_and_r_cells(cfg);
    seed = cfg.seeds(1);
    [bundle, ~] = prepare_seed_matched_baselines(cfg, seed, cells, '', false, struct());
    attached = cell(1, 2);
    model_rollout = struct('mode', 'ODE', 'metrics', struct( ...
        'pooled_nrmse_full_horizon', 0.5, ...
        'pooled_nrmse_at_fixed_horizons', 0.5*ones(numel(cfg.mg_autonomous_rollout.fixed_report_horizons), 1), ...
        'median_valid_horizon', 10, 'fraction_right_censored', 0));
    for i = 1:2
        attached{i} = attach_shared_mg_autonomous_controls_for_cell( ...
            bundle.mackey_glass_autonomous, model_rollout, cells{i}.which_states, ...
            bundle.bundle_id, cfg.mg_autonomous_rollout, cfg.benchmark_baselines);
    end
    testCase.verifyEqual(attached{1}.content_hash, attached{2}.content_hash);
    testCase.verifyEqual(attached{1}.origin_schedule_hash, attached{2}.origin_schedule_hash);
end

function testSharedControlsDifferentCellComparisons(testCase)
    cfg = tiny_cfg();
    cells = x_and_r_cells(cfg);
    seed = cfg.seeds(1);
    [bundle, ~] = prepare_seed_matched_baselines(cfg, seed, cells, '', false, struct());
    m1 = struct('pooled_nrmse_full_horizon', 0.4, ...
        'pooled_nrmse_at_fixed_horizons', 0.4*ones(4,1), ...
        'median_valid_horizon', 8, 'fraction_right_censored', 0.5);
    m2 = struct('pooled_nrmse_full_horizon', 0.6, ...
        'pooled_nrmse_at_fixed_horizons', 0.6*ones(4,1), ...
        'median_valid_horizon', 12, 'fraction_right_censored', 0);
    a1 = attach_shared_mg_autonomous_controls_for_cell(bundle.mackey_glass_autonomous, ...
        struct('mode', 'ODE', 'metrics', m1), 'x', bundle.bundle_id, ...
        cfg.mg_autonomous_rollout, cfg.benchmark_baselines);
    a2 = attach_shared_mg_autonomous_controls_for_cell(bundle.mackey_glass_autonomous, ...
        struct('mode', 'ODE', 'metrics', m2), 'r', bundle.bundle_id, ...
        cfg.mg_autonomous_rollout, cfg.benchmark_baselines);
    testCase.verifyNotEqual(a1.persistence.comparison.improvement_nrmse_full_horizon, ...
        a2.persistence.comparison.improvement_nrmse_full_horizon);
    testCase.verifyEqual(a1.persistence.comparison.model_nrmse_full_horizon, 0.4, 'AbsTol', 0);
    testCase.verifyEqual(a2.persistence.comparison.model_nrmse_full_horizon, 0.6, 'AbsTol', 0);
end

function testCompactControlsOmitFullArrays(testCase)
    cfg = tiny_cfg();
    [bundle, ~] = prepare_seed_matched_baselines(cfg, cfg.seeds(1), x_and_r_cells(cfg), '', false, struct());
    attached = attach_shared_mg_autonomous_controls_for_cell(bundle.mackey_glass_autonomous, ...
        struct('mode', 'ODE', 'metrics', bundle.mackey_glass_autonomous.persistence.metrics), ...
        'x', bundle.bundle_id, cfg.mg_autonomous_rollout, cfg.benchmark_baselines);
    for nm = {'persistence', 'linear_autoregression', 'conventional_leaky_esn'}
        slim = attached.(nm{1});
        testCase.verifyFalse(isfield(slim, 'predictions'));
        testCase.verifyFalse(isfield(slim, 'per_origin'));
        testCase.verifyFalse(isfield(slim, 'fitted_model'));
    end
end

function testBundleStoresFittedModels(testCase)
    cfg = tiny_cfg();
    [bundle, ~] = prepare_seed_matched_baselines(cfg, cfg.seeds(1), x_and_r_cells(cfg), '', false, struct());
    mg = bundle.mackey_glass_onestep.baselines;
    testCase.verifyTrue(isfield(mg.linear_autoregression, 'fitted_model'));
    testCase.verifyTrue(isfield(mg.conventional_leaky_esn, 'fitted_model'));
    testCase.verifyTrue(isfield(bundle.mackey_glass_autonomous.persistence, 'predictions'));
end

function testSharedThreeControlsComputed(testCase)
    cfg = tiny_cfg();
    [bundle, ~] = prepare_seed_matched_baselines(cfg, cfg.seeds(1), x_and_r_cells(cfg), '', false, struct());
    auto = bundle.mackey_glass_autonomous;
    for nm = {'persistence', 'linear_autoregression', 'conventional_leaky_esn'}
        testCase.verifyEqual(auto.(nm{1}).status, 'computed');
        testCase.verifyTrue(isfinite(auto.(nm{1}).metrics.pooled_nrmse_full_horizon));
    end
end

function testDistinctDaleKeysPerFeatureMode(testCase)
    cfg = tiny_cfg();
    [bundle, ~] = prepare_seed_matched_baselines(cfg, cfg.seeds(1), x_and_r_cells(cfg), '', false, struct());
    ax = attach_shared_mg_autonomous_controls_for_cell(bundle.mackey_glass_autonomous, ...
        struct('mode', 'ODE', 'metrics', struct('pooled_nrmse_full_horizon', 0.5)), ...
        'x', bundle.bundle_id, cfg.mg_autonomous_rollout, cfg.benchmark_baselines);
    ar = attach_shared_mg_autonomous_controls_for_cell(bundle.mackey_glass_autonomous, ...
        struct('mode', 'ODE', 'metrics', struct('pooled_nrmse_full_horizon', 0.6)), ...
        'r', bundle.bundle_id, cfg.mg_autonomous_rollout, cfg.benchmark_baselines);
    testCase.verifyEqual(ax.dale_mesn_control.dale_mesn_control_reference, ...
        dale_mesn_control_reference_key('x', cfg.benchmark_baselines.dale_mesn_control_keys));
    testCase.verifyEqual(ar.dale_mesn_control.dale_mesn_control_reference, ...
        dale_mesn_control_reference_key('r', cfg.benchmark_baselines.dale_mesn_control_keys));
    testCase.verifyNotEqual(ax.dale_mesn_control.dale_mesn_control_reference, ...
        ar.dale_mesn_control.dale_mesn_control_reference);
end

%% F. Comparisons
function testComparisonImprovementArithmetic(testCase)
    model_m = struct('pooled_nrmse_full_horizon', 0.3, ...
        'pooled_nrmse_at_fixed_horizons', [0.2; 0.3], ...
        'median_valid_horizon', 5, 'fraction_right_censored', 0.5);
    base_m = struct('pooled_nrmse_full_horizon', 0.5, ...
        'pooled_nrmse_at_fixed_horizons', [0.4; 0.5], ...
        'median_valid_horizon', 8, 'fraction_right_censored', 0.25);
    cmp = mg_autonomous_control_comparison(model_m, base_m);
    testCase.verifyEqual(cmp.improvement_nrmse_full_horizon, 0.2, 'AbsTol', 1e-14);
    testCase.verifyEqual(cmp.improvement_nrmse_at_fixed_horizons(1), 0.2, 'AbsTol', 1e-14);
end

function testComparisonRatioArithmetic(testCase)
    model_m = struct('pooled_nrmse_full_horizon', 0.4);
    base_m = struct('pooled_nrmse_full_horizon', 0.8);
    cmp = mg_autonomous_control_comparison(model_m, base_m);
    testCase.verifyEqual(cmp.ratio_nrmse_full_horizon, 0.5, 'AbsTol', 1e-14);
    testCase.verifyEqual(cmp.ratio_status_full_horizon, 'defined');
end

function testComparisonZeroDenomRatioUndefined(testCase)
    model_m = struct('pooled_nrmse_full_horizon', 0.4);
    base_m = struct('pooled_nrmse_full_horizon', 0);
    cmp = mg_autonomous_control_comparison(model_m, base_m);
    testCase.verifyTrue(isnan(cmp.ratio_nrmse_full_horizon));
    testCase.verifyEqual(cmp.ratio_status_full_horizon, 'undefined_nonfinite_denominator');
end

function testComparisonRestrictedValidHorizon(testCase)
    model_m = struct('pooled_nrmse_full_horizon', 0.3, 'median_valid_horizon', 6);
    base_m = struct('pooled_nrmse_full_horizon', 0.5, 'median_valid_horizon', 10);
    cmp = mg_autonomous_control_comparison(model_m, base_m);
    testCase.verifyEqual(cmp.difference_restricted_valid_horizon, -4, 'AbsTol', 0);
end

function testComparisonCensoringFields(testCase)
    model_m = struct('pooled_nrmse_full_horizon', 0.3, 'fraction_right_censored', 0.5);
    base_m = struct('pooled_nrmse_full_horizon', 0.5, 'fraction_right_censored', 1.0);
    cmp = mg_autonomous_control_comparison(model_m, base_m);
    testCase.verifyEqual(cmp.model_fraction_right_censored, 0.5, 'AbsTol', 0);
    testCase.verifyEqual(cmp.baseline_fraction_right_censored, 1.0, 'AbsTol', 0);
end

function testDaleNoNumericalSuperiority(testCase)
    cfg = tiny_cfg();
    [task, ~, rollout_cfg] = mg_baseline_setup();
    controls = compute_mg_autonomous_baseline_controls( ...
        task, baselines_from_task(task, cfg), rollout_cfg, cfg.seeds(1), ...
        'executed_shared_seed_bundle');
    attached = attach_shared_mg_autonomous_controls_for_cell(controls, ...
        struct('mode', 'ODE', 'metrics', struct('pooled_nrmse_full_horizon', 0.5)), ...
        'x', 'bundle', rollout_cfg, cfg.benchmark_baselines);
    dale = attached.dale_mesn_control;
    testCase.verifyEqual(dale.status, 'pending_paired_aggregation');
    testCase.verifyFalse(dale.comparison.numerical_superiority_claim);
    testCase.verifyFalse(isfield(dale.comparison, 'improvement_nrmse_full_horizon'));
    bad = attached;
    bad.dale_mesn_control.comparison.improvement_nrmse = 0.1;
    [ok, rep] = validate_mg_autonomous_baseline_controls(bad, struct( ...
        'cell_mode', 'ODE', 'require_production_provenance', false, ...
        'feature_mode', 'x', 'dale_keys', cfg.benchmark_baselines.dale_mesn_control_keys));
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(rep.reasons, 'dale_has_numerical_superiority_metrics')));
end

%% G. Leakage / provenance
function testScoringOverrideChangesMetricsNotPreds(testCase)
    [task, ~, rollout_cfg, schedule] = mg_baseline_setup();
    res = rollout_mg_autonomous_persistence(task.U, task.Y, task.split, schedule, rollout_cfg);
    Y2 = task.Y;
    Y2(schedule.origin_indices(1):(schedule.origin_indices(1) + rollout_cfg.forecast_horizon_steps - 1)) = 99;
    scored2 = score_mg_autonomous_forecasts(res.predictions, task.Y, schedule.origin_indices, ...
        task.split, rollout_cfg, struct('Y_scoring_override', Y2));
    testCase.verifyEqual(res.per_origin(1).predictions, scored2.per_origin(1).predictions);
    testCase.verifyNotEqual(res.metrics.pooled_nrmse_full_horizon, ...
        scored2.metrics.pooled_nrmse_full_horizon);
end

function testScoringOverrideDoesNotChangeLambda(testCase)
    [task, baselines, rollout_cfg, schedule] = mg_baseline_setup();
    lar = baselines.linear_autoregression;
    res = rollout_mg_autonomous_linear_ar(task.U, task.Y, task.split, schedule, rollout_cfg, lar);
    Y2 = task.Y + 10;
    scored2 = score_mg_autonomous_forecasts(res.predictions, task.Y, schedule.origin_indices, ...
        task.split, rollout_cfg, struct('Y_scoring_override', Y2));
    testCase.verifyEqual(res.selected_lambda, lar.selected_lambda, 'AbsTol', 0);
    testCase.verifyEqual(scored2.per_origin(1).predictions, res.per_origin(1).predictions);
end

function testScoringOverrideDoesNotChangeCandidate(testCase)
    [task, baselines, rollout_cfg, schedule] = mg_baseline_setup();
    ce = baselines.conventional_leaky_esn;
    res = rollout_mg_autonomous_conventional_esn(task.U, task.Y, task.split, schedule, rollout_cfg, ce);
    Y2 = task.Y * 2;
    scored2 = score_mg_autonomous_forecasts(res.predictions, task.Y, schedule.origin_indices, ...
        task.split, rollout_cfg, struct('Y_scoring_override', Y2));
    testCase.verifyEqual(res.selected_candidate_index, ce.selected_candidate_index);
    testCase.verifyEqual(scored2.per_origin(1).predictions, res.per_origin(1).predictions);
end

function testScoringOverrideDoesNotChangeHashes(testCase)
    [task, baselines, rollout_cfg, schedule] = mg_baseline_setup();
    lar = baselines.linear_autoregression;
    res = rollout_mg_autonomous_linear_ar(task.U, task.Y, task.split, schedule, rollout_cfg, lar);
    Y2 = task.Y + 5;
    scored2 = score_mg_autonomous_forecasts(res.predictions, task.Y, schedule.origin_indices, ...
        task.split, rollout_cfg, struct('Y_scoring_override', Y2));
    testCase.verifyEqual(res.fitted_model_hash, lar.fitted_model_hash);
    testCase.verifyEqual(res.test_prediction_hash, lar.test_prediction_hash);
    testCase.verifyNotEqual(res.metrics.pooled_nrmse_full_horizon, ...
        scored2.metrics.pooled_nrmse_full_horizon);
end

function testScoringOverrideDoesNotChangeOrigins(testCase)
    [task, ~, rollout_cfg, schedule] = mg_baseline_setup();
    res = rollout_mg_autonomous_persistence(task.U, task.Y, task.split, schedule, rollout_cfg);
    Y2 = task.Y;
    Y2(end) = -1;
    scored2 = score_mg_autonomous_forecasts(res.predictions, task.Y, schedule.origin_indices, ...
        task.split, rollout_cfg, struct('Y_scoring_override', Y2));
    for o = 1:numel(schedule.origin_indices)
        testCase.verifyEqual(scored2.per_origin(o).origin_global_index, ...
            res.per_origin(o).origin_global_index);
        testCase.verifyEqual(scored2.per_origin(o).origin_test_relative_index, ...
            res.per_origin(o).origin_test_relative_index);
    end
end

function testRejectInjectedProvenance(testCase)
    cfg = tiny_cfg();
    [task, ~, rollout_cfg] = mg_baseline_setup();
    controls = compute_mg_autonomous_baseline_controls( ...
        task, baselines_from_task(task, cfg), rollout_cfg, cfg.seeds(1), ...
        'injected_test_fixture');
    [ok, rep] = validate_mg_autonomous_baseline_controls(controls, struct( ...
        'cell_mode', 'ODE', 'require_production_provenance', true, ...
        'rollout_cfg', rollout_cfg, ...
        'one_step_baselines', baselines_from_task(task, cfg)));
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(rep.reasons, 'provenance_not_shared_seed_bundle')));
end

function testRejectCellLocalProvenance(testCase)
    cfg = tiny_cfg();
    [task, ~, rollout_cfg] = mg_baseline_setup();
    controls = compute_mg_autonomous_baseline_controls( ...
        task, baselines_from_task(task, cfg), rollout_cfg, cfg.seeds(1), ...
        'executed_cell_local');
    attached = attach_shared_mg_autonomous_controls_for_cell(controls, ...
        struct('mode', 'ODE', 'metrics', struct('pooled_nrmse_full_horizon', 0.5)), ...
        'x', '', rollout_cfg, cfg.benchmark_baselines);
    attached.evaluation_provenance.mode = 'executed_cell_local';
    attached.origin_schedule = controls.origin_schedule;
    [ok, rep] = validate_mg_autonomous_baseline_controls(attached, struct( ...
        'cell_mode', 'ODE', 'require_production_provenance', true, ...
        'rollout_cfg', rollout_cfg, ...
        'model_metrics', struct('pooled_nrmse_full_horizon', 0.5), ...
        'feature_mode', 'x', 'dale_keys', cfg.benchmark_baselines.dale_mesn_control_keys, ...
        'bundle_id', 'test', 'require_bundle_id', true));
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(rep.reasons, 'provenance_not_shared_seed_bundle')));
end

%% H. DDE
function testDdeControlsUnsupported(testCase)
    cfg = tiny_cfg();
    [bundle, ~] = prepare_seed_matched_baselines(cfg, cfg.seeds(1), x_and_r_cells(cfg), '', false, struct());
    dde_rollout = struct('status', 'unsupported_not_computed', 'mode', 'DDE', ...
        'metrics', [], 'predictions', []);
    ctrl = attach_shared_mg_autonomous_controls_for_cell(bundle.mackey_glass_autonomous, ...
        dde_rollout, 'x', bundle.bundle_id, cfg.mg_autonomous_rollout, cfg.benchmark_baselines);
    [ok, ~] = validate_mg_autonomous_baseline_controls(ctrl, struct('cell_mode', 'DDE', ...
        'require_production_provenance', false));
    testCase.verifyTrue(ok);
    testCase.verifyEqual(ctrl.persistence.status, 'not_applicable_dde_model_rollout_unsupported');
end

function testDdeNoModelComparison(testCase)
    cfg = tiny_cfg();
    [bundle, ~] = prepare_seed_matched_baselines(cfg, cfg.seeds(1), x_and_r_cells(cfg), '', false, struct());
    ctrl = attach_shared_mg_autonomous_controls_for_cell(bundle.mackey_glass_autonomous, ...
        struct('status', 'unsupported_not_computed', 'mode', 'DDE'), ...
        'x', bundle.bundle_id, cfg.mg_autonomous_rollout, cfg.benchmark_baselines);
    testCase.verifyFalse(ctrl.comparisons_attached);
    testCase.verifyTrue(isempty(fieldnames(ctrl.persistence.comparison)));
end

function testDdeExplicitApplicability(testCase)
    cfg = tiny_cfg();
    [bundle, ~] = prepare_seed_matched_baselines(cfg, cfg.seeds(1), x_and_r_cells(cfg), '', false, struct());
    ctrl = attach_shared_mg_autonomous_controls_for_cell(bundle.mackey_glass_autonomous, ...
        struct('mode', 'DDE', 'status', 'unsupported_not_computed'), ...
        'r', bundle.bundle_id, cfg.mg_autonomous_rollout, cfg.benchmark_baselines);
    testCase.verifyEqual(ctrl.applicability, 'not_applicable_dde_model_rollout_unsupported');
end

function testRejectInvalidDdeComparison(testCase)
    cfg = tiny_cfg();
    [bundle, ~] = prepare_seed_matched_baselines(cfg, cfg.seeds(1), x_and_r_cells(cfg), '', false, struct());
    ctrl = attach_shared_mg_autonomous_controls_for_cell(bundle.mackey_glass_autonomous, ...
        struct('mode', 'DDE', 'status', 'unsupported_not_computed'), ...
        'x', bundle.bundle_id, cfg.mg_autonomous_rollout, cfg.benchmark_baselines);
    bad = ctrl;
    bad.persistence.comparison.improvement_nrmse_full_horizon = 0.1;
    [ok, rep] = validate_mg_autonomous_baseline_controls(bad, struct('cell_mode', 'DDE', ...
        'require_production_provenance', false));
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(contains(rep.reasons, 'dde_has_computed_comparison')));
end

%% helpers
function baselines = baselines_from_task(task, cfg)
    seed = cfg.seeds(1);
    L = cfg.lengths;
    [p, ~] = build_ablation_params(cfg.cells{1}, seed, cfg, struct());
    mg_opts = struct( ...
        'task', 'mackey_glass_onestep', ...
        'mesn_Win', p.W_in, ...
        'base_seed', seed, ...
        'seed', task.seed, ...
        'feature_mode', 'x', ...
        'lambda_grid', resolve_baseline_lambda_grid(struct(), cfg), ...
        'ar_lags', local_get(L, 'mg_ar_lags', 10), ...
        'benchmark_baselines', cfg.benchmark_baselines, ...
        'skip_dale', true, ...
        'skip_comparisons', true, ...
        'task_data_hash', task.task_data_hash, ...
        'split_hash', task.split_hash);
    baselines = compute_matched_onestep_baselines( ...
        task.U, task.Y, task.split, task.washout_steps, mg_opts);
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end

function result = local_minimal_valid_ode_result(split, rollout_cfg, Y)
    sch = build_mg_autonomous_origin_schedule(split, rollout_cfg);
    H = rollout_cfg.forecast_horizon_steps;
    n_o = numel(sch.origin_indices);
    preds = cell(n_o, 1);
    for o = 1:n_o
        preds{o} = ones(H, 1);
    end
    scored = score_mg_autonomous_forecasts(preds, Y, sch.origin_indices, split, rollout_cfg);
    po = repmat(struct( ...
        'origin_global_index', 0, ...
        'origin_test_relative_index', 0, ...
        'horizon', H, ...
        'predictions', zeros(H, 1), ...
        'targets', zeros(H, 1), ...
        'errors', zeros(H, 1), ...
        'normalized_absolute_errors', zeros(H, 1), ...
        'full_horizon_nrmse', 0.1, ...
        'rmse', 0.1, ...
        'valid_horizon_steps', H, ...
        'first_threshold_exceedance_step', NaN, ...
        'right_censored', true, ...
        'valid_error_threshold', rollout_cfg.primary_threshold), n_o, 1);
    for o = 1:n_o
        spo = scored.per_origin(o);
        po(o).origin_global_index = spo.origin_global_index;
        po(o).origin_test_relative_index = spo.origin_test_relative_index;
        po(o).predictions = spo.predictions;
        po(o).targets = spo.targets;
        po(o).valid_horizon_steps = spo.valid_horizon_steps;
        po(o).right_censored = spo.right_censored;
    end
    result = struct( ...
        'status', 'computed', ...
        'protocol_version', rollout_cfg.protocol_version, ...
        'role', rollout_cfg.role, ...
        'mode', 'ODE', ...
        'forecast_horizon_steps', H, ...
        'origin_schedule', sch, ...
        'fixed_report_horizons', rollout_cfg.fixed_report_horizons(:), ...
        'normalization_scale', scored.normalization_scale, ...
        'normalization_reference', rollout_cfg.normalization_reference, ...
        'per_origin', po, ...
        'metrics', scored.metrics, ...
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
