function tests = test_matched_task_baselines
% Phase 4C-A matched one-step NARMA/MG baselines.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'scripts')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function params = tiny_params()
    params = make_test_params(struct( ...
        'n', 8, ...
        'fraction_E', 0.5, ...
        'n_a_E', 1, ...
        'n_a_I', 0, ...
        'n_b_E', 0, ...
        'n_b_I', 0, ...
        'lags', [], ...
        'level_of_chaos', 0.9, ...
        'input_sparsity', 0.5, ...
        'input_mask_mode', 'fixed_count'));
end

function opts = smoke_opts(extra)
    bb = build_matched_task_baselines_config(struct('base', struct('n', 8)));
    % Keep production candidate order; shrink grids for suite runtime only.
    bb.conventional_leaky_esn.spectral_radius_candidates = [0.5, 0.9];
    bb.conventional_leaky_esn.leak_rate_candidates = [0.3, 1.0];
    bb.conventional_leaky_esn.input_scaling_candidates = [0.5, 1.0];
    opts = struct( ...
        'train_ratio', 0.5, ...
        'val_ratio', 0.25, ...
        'washout_steps', 10, ...
        'seed', 1729, ...
        'base_seed', 1700, ...
        'lambda_grid', [0, 1e-4, 1e-2], ...
        'benchmark_baselines', bb);
    if nargin >= 1 && ~isempty(extra)
        f = fieldnames(extra);
        for i = 1:numel(f)
            opts.(f{i}) = extra.(f{i});
        end
    end
end

function testNarmaBaselinesSchemaAndPhase4A(testCase)
    esn = SRNN_ESN(tiny_params());
    bench = narma_benchmark(esn, smoke_opts(struct('order', 10, 'T', 140)));
    b = bench.baselines;
    testCase.verifyTrue(isfield(b, 'training_target_mean'));
    testCase.verifyTrue(isfield(b, 'linear_input_history'));
    testCase.verifyTrue(isfield(b, 'conventional_leaky_esn'));
    testCase.verifyTrue(isfield(b, 'dale_mesn_control'));
    testCase.verifyEqual(b.conventional_leaky_esn.status, 'computed');
    testCase.verifyEqual(b.dale_mesn_control.status, 'pending_paired_aggregation');
    testCase.verifyEqual(b.dale_mesn_control.dale_mesn_control_reference, ...
        'adapt-off__std-off__delay-ode_off__feat-x');
    testCase.verifyFalse(strcmp(b.dale_mesn_control.model_family, 'conventional_leaky_esn'));
    testCase.verifyTrue(isfinite(b.training_target_mean.metrics_test.nrmse));
    testCase.verifyTrue(isfinite(b.linear_input_history.metrics_test.nrmse));
    testCase.verifyTrue(isfield(b.linear_input_history, 'ridge_diagnostics'));
    testCase.verifyTrue(isfield(b.linear_input_history, 'lambda_selection_table'));
    testCase.verifyTrue(isfield(b.conventional_leaky_esn, 'candidate_selection_table'));
    testCase.verifyTrue(isfield(b.conventional_leaky_esn, 'selected_at_candidate_boundary'));
    testCase.verifyEqual(b.conventional_leaky_esn.include_input, false);
    cmp = b.conventional_leaky_esn.comparison;
    testCase.verifyEqual(cmp.improvement_nrmse, ...
        cmp.baseline_nrmse - cmp.model_nrmse, 'AbsTol', 1e-14);
end

function testMackeyGlassBaselinesSchema(testCase)
    esn = SRNN_ESN(tiny_params());
    bench = mackey_glass_benchmark(esn, smoke_opts(struct( ...
        'T', 160, 'discard', 40, 'do_rollout', false, 'ar_lags', 5, ...
        'feature_mode', 'r')));
    b = bench.baselines;
    testCase.verifyEqual(b.persistence.status, 'computed');
    % Persistence equals u on scored rows
    testCase.verifyTrue(isfinite(b.persistence.metrics_test.nrmse));
    testCase.verifyTrue(isfield(b, 'linear_autoregression'));
    testCase.verifyTrue(isfield(b.linear_autoregression, 'ridge_diagnostics'));
    testCase.verifyEqual(b.dale_mesn_control.dale_mesn_control_reference, ...
        'adapt-off__std-off__delay-ode_off__feat-r');
    testCase.verifyEqual(b.conventional_leaky_esn.status, 'computed');
end

function testTrainingMeanUsesTrainOnly(testCase)
    U = randn(100, 1);
    Y = randn(100, 1);
    wash = 5;
    split = struct('train_idx', (1:50)', 'val_idx', (51:70)', ...
        'test_idx', (71:100)', 'washout_steps', wash);
    Win = ones(4, 1);
    Y_mut = Y;
    Y_mut(split.test_idx) = Y_mut(split.test_idx) + 10;
    Y_mut(split.val_idx) = Y_mut(split.val_idx) - 7;
    opts = struct('task', 'narma', 'mesn_Win', Win, 'base_seed', 1, ...
        'feature_mode', 'x', 'lambda_grid', [1e-2, 1], 'narma_order', 3, ...
        'model_test_nrmse', 1, ...
        'benchmark_baselines', build_matched_task_baselines_config(struct('base', struct('n', 4))));
    % Shrink conventional search for speed
    opts.benchmark_baselines.conventional_leaky_esn.spectral_radius_candidates = 0.5;
    opts.benchmark_baselines.conventional_leaky_esn.leak_rate_candidates = 1.0;
    opts.benchmark_baselines.conventional_leaky_esn.input_scaling_candidates = 0.5;
    b1 = compute_matched_onestep_baselines(U, Y, split, wash, opts);
    b2 = compute_matched_onestep_baselines(U, Y_mut, split, wash, opts);
    testCase.verifyEqual(b1.training_target_mean.hyperparameters.mean, ...
        b2.training_target_mean.hyperparameters.mean, 'AbsTol', 0);
    testCase.verifyNotEqual(b1.training_target_mean.metrics_test.nrmse, ...
        b2.training_target_mean.metrics_test.nrmse);
end

function testPersistenceEqualsInput(testCase)
    U = (1:30)';
    Y = U; % persistence is exact when target equals current input
    wash = 2;
    split = struct('train_idx', (1:12)', 'val_idx', (13:18)', ...
        'test_idx', (19:30)', 'washout_steps', wash);
    opts = struct('task', 'mackey_glass_onestep', 'mesn_Win', ones(3, 1), ...
        'base_seed', 2, 'feature_mode', 'x', 'lambda_grid', 1e-2, ...
        'ar_lags', 2, 'model_test_nrmse', 0.1, ...
        'benchmark_baselines', build_matched_task_baselines_config(struct('base', struct('n', 3))));
    opts.benchmark_baselines.conventional_leaky_esn.spectral_radius_candidates = 0.5;
    opts.benchmark_baselines.conventional_leaky_esn.leak_rate_candidates = 1;
    opts.benchmark_baselines.conventional_leaky_esn.input_scaling_candidates = 0.5;
    b = compute_matched_onestep_baselines(U, Y, split, wash, opts);
    testCase.verifyEqual(b.persistence.metrics_test.nrmse, 0, 'AbsTol', 1e-14);
    % Prediction equals u(t) on test indices
    testCase.verifyEqual(b.persistence.metrics_test.rmse, 0, 'AbsTol', 1e-14);
end

function testLinearHistoryLearnsSynthetic(testCase)
    % y(t) = 0.5*u(t) - 0.25*u(t-1) + noise tiny
    T = 200;
    stream = RandStream('mt19937ar', 'Seed', 9);
    U = 2 * rand(stream, T, 1) - 1;
    Y = zeros(T, 1);
    for t = 2:T
        Y(t) = 0.5 * U(t) - 0.25 * U(t-1);
    end
    wash = 5;
    split = struct('train_idx', (1:100)', 'val_idx', (101:140)', ...
        'test_idx', (141:T)', 'washout_steps', wash);
    lin = fit_phase4a_lag_baseline(U, Y, split, wash, 2, [0, 1e-8, 1e-4], ...
        struct('name', 'linear_input_history', 'model_family', 'linear_input_history'));
    testCase.verifyEqual(lin.status, 'computed');
    testCase.verifyLessThan(lin.metrics_test.nrmse, 1e-6);
    testCase.verifyTrue(isfield(lin.ridge_diagnostics, 'solver_method'));
end

function testLagBaselineHandlesCollinearNoSingularWarning(testCase)
    T = 80;
    U = ones(T, 1); % constant -> zero-variance lag columns after std
    Y = 0.1 * randn(T, 1);
    wash = 3;
    split = struct('train_idx', (1:40)', 'val_idx', (41:55)', ...
        'test_idx', (56:T)', 'washout_steps', wash);
    warn_near = warning('error', 'MATLAB:nearlySingularMatrix');
    warn_sing = warning('error', 'MATLAB:singularMatrix');
    cleanup = onCleanup(@() restore_warn(warn_near, warn_sing)); %#ok<NASGU>
    lin = fit_phase4a_lag_baseline(U, Y, split, wash, 3, [1e-4, 1e-2, 1], ...
        struct('name', 'linear_autoregression'));
    testCase.verifyEqual(lin.status, 'computed');
    testCase.verifyTrue(isfinite(lin.metrics_test.nrmse));
end

function testCompactBenchPreservesBaselines(testCase)
    cfg = mechanism_ablation_config('smoke');
    % Shrink conventional grid for pipeline schema check only.
    cfg.benchmark_baselines.conventional_leaky_esn.spectral_radius_candidates = 0.9;
    cfg.benchmark_baselines.conventional_leaky_esn.leak_rate_candidates = 1.0;
    cfg.benchmark_baselines.conventional_leaky_esn.input_scaling_candidates = 0.5;
    cfg.protocol_fingerprint = compute_protocol_fingerprint(cfg);
    cell_spec = cfg.cells{1};
    cr = run_ablation_cell(cell_spec, 1729, cfg, struct( ...
        'verbose', false, 'run_secondary', false));
    testCase.verifyTrue(isfield(cr.narma, 'baselines'));
    testCase.verifyTrue(isfield(cr.narma.baselines, 'conventional_leaky_esn'));
    testCase.verifyTrue(isfield(cr.narma.baselines.conventional_leaky_esn, ...
        'candidate_selection_table'));
    testCase.verifyTrue(isfield(cr.narma.baselines.conventional_leaky_esn, ...
        'ridge_diagnostics'));
    testCase.verifyTrue(isfield(cr.narma.baselines, 'dale_mesn_control'));
    testCase.verifyEqual(cr.narma.baselines.dale_mesn_control.status, ...
        'pending_paired_aggregation');
    testCase.verifyTrue(isfield(cr.mackey_glass.baselines, 'conventional_leaky_esn'));
    testCase.verifyTrue(cfg.pilot_not_for_publication);
end

function testFingerprintSensitiveToBaselineConfig(testCase)
    cfg = mechanism_ablation_config('publication');
    fp0 = cfg.protocol_fingerprint;
    cfg2 = cfg;
    cfg2.benchmark_baselines.conventional_leaky_esn.spectral_radius_candidates = [0.5, 1.0];
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg2));
    cfg3 = cfg;
    cfg3.benchmark_baselines.conventional_leaky_esn.leak_rate_candidates = [0.2, 0.5];
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg3));
    cfg4 = cfg;
    cfg4.benchmark_baselines.conventional_leaky_esn.input_scaling_candidates = [0.1, 1.0];
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg4));
    cfg5 = cfg;
    cfg5.benchmark_baselines.conventional_leaky_esn.reservoir_seed_offset = 2001;
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg5));
    cfg6 = cfg;
    cfg6.benchmark_baselines.validation_tie_tolerance = 1e-10;
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg6));
    cfg7 = cfg;
    cfg7.benchmark_baselines.conventional_leaky_esn.activation = 'relu';
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg7));
    cfg8 = cfg;
    cfg8.benchmark_baselines.protocol_version = 'matched_task_baselines_v0';
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg8));
    cfg9 = cfg;
    cfg9.lengths.lambda_grid = [0, 1e-3, 1];
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg9));
end

function testResolvedLambdaGridRecorded(testCase)
    cfg = mechanism_ablation_config('publication');
    lam = resolve_baseline_lambda_grid(struct(), cfg);
    testCase.verifyEqual(lam(:), [0; logspace(-12, 2, 15)']);
    smoke = mechanism_ablation_config('smoke');
    lam_s = resolve_baseline_lambda_grid(struct(), smoke);
    testCase.verifyEqual(lam_s(:), smoke.lengths.lambda_grid(:));
end

function restore_warn(a, b)
    warning(a);
    warning(b);
end
