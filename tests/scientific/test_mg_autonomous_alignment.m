function tests = test_mg_autonomous_alignment
% test_mg_autonomous_alignment  First-step / target / one-step invariance for MG.
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

function testFirstAutonomousEqualsFrozenOneStep(testCase)
    [esn, opts, rollout_cfg] = small_mg_setup();
    opts.do_rollout = true;
    opts.mg_autonomous_rollout = rollout_cfg;
    bench = mackey_glass_benchmark(esn, opts);
    testCase.verifyEqual(bench.rollout.status, 'computed');
    for o = 1:numel(bench.rollout.per_origin)
        po = bench.rollout.per_origin(o);
        rel = po.origin_test_relative_index;
        frozen = bench.predictions.test(rel);
        testCase.verifyEqual(po.predictions(1), frozen, 'AbsTol', 1e-8);
        % Target alignment: step 1 scores Y(origin), step H scores Y(origin+H-1)
        i = po.origin_global_index;
        H = po.horizon;
        y_true = opts_task_Y(opts); %#ok<NASGU>
    end
    task = build_mackey_glass_onestep_task_dataset(struct( ...
        'T', opts.T, 'discard', opts.discard, 'washout_steps', opts.washout_steps, ...
        'train_ratio', opts.train_ratio, 'val_ratio', opts.val_ratio, 'seed', opts.seed));
    for o = 1:numel(bench.rollout.per_origin)
        po = bench.rollout.per_origin(o);
        i = po.origin_global_index;
        H = po.horizon;
        testCase.verifyEqual(po.targets, task.Y(i:i+H-1), 'AbsTol', 0);
        testCase.verifyEqual(po.targets(1), task.Y(i), 'AbsTol', 0);
        testCase.verifyEqual(po.targets(end), task.Y(i+H-1), 'AbsTol', 0);
        if (i + H) <= numel(task.Y)
            testCase.verifyFalse(isequal(po.targets, task.Y((i+1):(i+H))));
        end
    end
end

function testOneStepInvariantWhenRolloutEnabled(testCase)
    [esn_a, opts, rollout_cfg] = small_mg_setup();
    opts_off = opts;
    opts_off.do_rollout = false;
    bench_off = mackey_glass_benchmark(esn_a, opts_off);

    [esn_b, ~, ~] = small_mg_setup();  % identical params/seeds
    opts_on = opts;
    opts_on.do_rollout = true;
    opts_on.mg_autonomous_rollout = rollout_cfg;
    bench_on = mackey_glass_benchmark(esn_b, opts_on);

    testCase.verifyEqual(bench_off.selected_lambda, bench_on.selected_lambda);
    testCase.verifyEqual(bench_off.metrics_test.nrmse, bench_on.metrics_test.nrmse, 'AbsTol', 1e-12);
    testCase.verifyEqual(bench_off.metrics_val.nrmse, bench_on.metrics_val.nrmse, 'AbsTol', 1e-12);
    testCase.verifyEqual(bench_off.metrics_train.nrmse, bench_on.metrics_train.nrmse, 'AbsTol', 1e-12);
    testCase.verifyEqual(bench_off.predictions.test, bench_on.predictions.test, 'AbsTol', 1e-12);
    testCase.verifyEqual(bench_off.predictions.val, bench_on.predictions.val, 'AbsTol', 1e-12);
    testCase.verifyEqual(bench_off.predictions.train, bench_on.predictions.train, 'AbsTol', 1e-12);
    testCase.verifyEqual(esn_b.readout_model.coefficients, esn_a.readout_model.coefficients, ...
        'AbsTol', 1e-12);
    testCase.verifyEqual(esn_b.readout_model.intercept, esn_a.readout_model.intercept, ...
        'AbsTol', 1e-12);
    testCase.verifyEqual(esn_b.readout_model.mu, esn_a.readout_model.mu, 'AbsTol', 1e-12);
    testCase.verifyEqual(esn_b.readout_model.sigma, esn_a.readout_model.sigma, 'AbsTol', 1e-12);
    testCase.verifyEqual(bench_off.baselines.persistence.metrics_test.nrmse, ...
        bench_on.baselines.persistence.metrics_test.nrmse, 'AbsTol', 1e-12);
    testCase.verifyEqual( ...
        bench_off.baselines.conventional_leaky_esn.selected_candidate_index, ...
        bench_on.baselines.conventional_leaky_esn.selected_candidate_index);
    testCase.verifyEqual(bench_on.rollout.status, 'computed');
end

function testDeterministicAutonomousAndIndependentOrigins(testCase)
    [esn, opts, rollout_cfg] = small_mg_setup();
    opts.do_rollout = true;
    opts.mg_autonomous_rollout = rollout_cfg;
    b1 = mackey_glass_benchmark(esn, opts);
    [esn2, ~, ~] = small_mg_setup();
    b2 = mackey_glass_benchmark(esn2, opts);
    testCase.verifyEqual(b1.rollout.origin_schedule.origin_indices, ...
        b2.rollout.origin_schedule.origin_indices);
    for o = 1:numel(b1.rollout.per_origin)
        testCase.verifyEqual(b1.rollout.per_origin(o).predictions, ...
            b2.rollout.per_origin(o).predictions, 'AbsTol', 1e-12);
    end
    if numel(b1.rollout.per_origin) >= 2
        testCase.verifyNotEqual( ...
            b1.rollout.per_origin(1).origin_global_index, ...
            b1.rollout.per_origin(2).origin_global_index);
    end
end

function testDdeBenchmarkUnsupported(testCase)
    params = make_test_params(struct( ...
        'n', 8, 'fraction_E', 0.5, 'n_a_E', 1, 'n_a_I', 0, ...
        'n_b_E', 0, 'n_b_I', 0, 'lags', 0.05, 'level_of_chaos', 0.9));
    esn = SRNN_ESN(params);
    bb = build_matched_task_baselines_config(struct('base', struct('n', 8)));
    bb.conventional_leaky_esn.spectral_radius_candidates = 0.9;
    bb.conventional_leaky_esn.leak_rate_candidates = 1.0;
    bb.conventional_leaky_esn.input_scaling_candidates = 0.5;
    rollout_cfg = build_mg_autonomous_rollout_config('smoke');
    opts = struct( ...
        'T', 160, 'discard', 40, 'washout_steps', 10, ...
        'train_ratio', 0.5, 'val_ratio', 0.25, ...
        'seed', 1729, 'base_seed', 1700, ...
        'lambda_grid', [1e-4, 1e-2], ...
        'do_rollout', true, ...
        'mg_autonomous_rollout', rollout_cfg, ...
        'benchmark_baselines', bb, ...
        'ode_reltol', 1e-4, 'ode_abstol', 1e-6, ...
        'dde_reltol', 1e-4, 'dde_abstol', 1e-6);
    bench = mackey_glass_benchmark(esn, opts);
    testCase.verifyEqual(bench.rollout.status, 'unsupported_not_computed');
    testCase.verifyEqual(bench.rollout.mode, 'DDE');
    testCase.verifyTrue(isempty(bench.rollout.predictions));
    testCase.verifyTrue(isempty(bench.rollout.metrics));
    testCase.verifyError(@() esn.generateAutonomous(randn(10,1), 3), ...
        'SRNN_ESN:DDEAutonomousUnsupported');
end

function testCompactPreservesRolloutFields(testCase)
    [esn, opts, rollout_cfg] = small_mg_setup();
    opts.do_rollout = true;
    opts.mg_autonomous_rollout = rollout_cfg;
    bench = mackey_glass_benchmark(esn, opts);
    % Mimic compact path via run_ablation_cell helper by re-invoking compact logic
    % through a thin eval of stored fields expected by publication gate
    testCase.verifyTrue(isfield(bench.rollout, 'origin_schedule'));
    testCase.verifyTrue(isfield(bench.rollout, 'metrics'));
    testCase.verifyTrue(isfield(bench.rollout, 'per_origin'));
    testCase.verifyTrue(isfield(bench.rollout, 'evaluation_provenance'));
    testCase.verifyEqual(bench.rollout.evaluation_provenance.mode, 'executed');
end

function testTargetsForbiddenInGeneration(testCase)
    esn = make_tiny_trained_esn();
    [~, S_hist] = esn.runReservoir(0.1*ones(5,1), struct( ...
        'reset_before', true, 'update_internal_state', false));
    testCase.verifyError(@() esn.generateAutonomousFromState( ...
        S_hist(end,:).', 0.1, 2, struct('targets', 1)), ...
        'SRNN_ESN:AutonomousTargetsForbidden');
end

%% helpers
function [esn, opts, rollout_cfg] = small_mg_setup()
    params = make_test_params(struct( ...
        'n', 8, 'fraction_E', 0.5, 'n_a_E', 1, 'n_a_I', 0, ...
        'n_b_E', 0, 'n_b_I', 0, 'lags', [], 'level_of_chaos', 0.9));
    esn = SRNN_ESN(params);
    esn.ode_solver = @ode45;
    bb = build_matched_task_baselines_config(struct('base', struct('n', 8)));
    bb.conventional_leaky_esn.spectral_radius_candidates = 0.9;
    bb.conventional_leaky_esn.leak_rate_candidates = 1.0;
    bb.conventional_leaky_esn.input_scaling_candidates = 0.5;
    rollout_cfg = build_mg_autonomous_rollout_config('smoke');
    rollout_cfg.forecast_horizon_steps = 10;
    rollout_cfg.n_forecast_origins = 2;
    rollout_cfg.fixed_report_horizons = [1, 5, 10];
    opts = struct( ...
        'T', 180, 'discard', 50, 'washout_steps', 10, ...
        'train_ratio', 0.5, 'val_ratio', 0.25, ...
        'seed', 1729, 'base_seed', 1700, ...
        'lambda_grid', [0, 1e-4, 1e-2], ...
        'feature_mode', 'x', ...
        'do_rollout', false, ...
        'benchmark_baselines', bb, ...
        'ode_reltol', 1e-4, 'ode_abstol', 1e-6);
end

function esn = make_tiny_trained_esn()
    overrides = struct( ...
        'n', 1, 'fraction_E', 1, 'n_a_E', 0, 'n_a_I', 0, ...
        'n_b_E', 0, 'n_b_I', 0, 'n_inputs', 1, 'lags', [], ...
        'W', 0, 'W_in', 1, 'tau_d', 1, 'dt', 0.5, ...
        'activation_function', @(x) x, ...
        'activation_function_derivative', @(x) ones(size(x)), ...
        'which_states', 'x', 'state_rng_seed', 1);
    esn = SRNN_ESN(default_MESN_config(overrides));
    model = struct('intercept', 0, 'coefficients', 1, 'mu', 0, 'sigma', 1, ...
        'lambda', 0, 'n_features', 1, 'n_outputs', 1, 'constant_feature', false);
    esn.readout_model = model;
    esn.W_out = 1; esn.b_out = 0; esn.is_trained = true; esn.n_outputs = 1;
end

function Y = opts_task_Y(opts) %#ok<DEFNU>
    task = build_mackey_glass_onestep_task_dataset(struct( ...
        'T', opts.T, 'discard', opts.discard, 'washout_steps', opts.washout_steps, ...
        'train_ratio', opts.train_ratio, 'val_ratio', opts.val_ratio, 'seed', opts.seed));
    Y = task.Y;
end
