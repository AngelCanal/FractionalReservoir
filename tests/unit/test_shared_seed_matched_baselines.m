function tests = test_shared_seed_matched_baselines
% Phase 4C-A-R shared seed baselines: identity, fail-closed, runner sharing.
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

function cfg = tiny_shared_cfg()
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

%% A. Shared execution
function testSharedBundleIdAcrossCellsAndOneArtifact(testCase)
    cfg = tiny_shared_cfg();
    cells = x_and_r_cells(cfg);
    seed = 1729;
    root = tempname;
    mkdir(root);
    run_dir = fullfile(root, 'run');
    mkdir(run_dir);
    mkdir(fullfile(run_dir, 'cells'));
    cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>

    [bundle, art] = prepare_seed_matched_baselines( ...
        cfg, seed, cells, run_dir, true, struct());
    testCase.verifyTrue(exist(art, 'file') == 2);
    S = load(art);
    B = S.matched_task_baselines;
    testCase.verifyEqual(B.bundle_id, bundle.bundle_id);
    testCase.verifyTrue(isfield(B, 'narma'));
    testCase.verifyTrue(isfield(B, 'mackey_glass_onestep'));
    testCase.verifyTrue(isfield(B.narma.baselines.conventional_leaky_esn, ...
        'candidate_selection_table'));

    cr = cell(1, 2);
    for i = 1:2
        cr{i} = run_ablation_cell(cells{i}, seed, cfg, struct( ...
            'verbose', false, 'run_secondary', false, ...
            'shared_baseline_bundle', bundle));
        atomic_save_results(fullfile(run_dir, 'cells', ...
            sprintf('seed_%d__%s.mat', seed, cells{i}.cell_key)), ...
            struct('cell_result', cr{i}));
        testCase.verifyEqual(cr{i}.matched_baseline_bundle_id, bundle.bundle_id);
        testCase.verifyEqual(cr{i}.narma.baselines.bundle_id, bundle.bundle_id);
        testCase.verifyEqual(cr{i}.mackey_glass.baselines.bundle_id, bundle.bundle_id);
        testCase.verifyFalse(isfield(cr{i}.narma.baselines.conventional_leaky_esn, ...
            'candidate_selection_table'));
        testCase.verifyEqual(cr{i}.narma.baselines.evaluation_provenance.mode, ...
            'executed_shared_seed_bundle');
    end
    c1 = cr{1}.narma.baselines.conventional_leaky_esn.comparison;
    c2 = cr{2}.narma.baselines.conventional_leaky_esn.comparison;
    testCase.verifyEqual(c1.model_nrmse, cr{1}.narma.test_nrmse, 'AbsTol', 1e-14);
    testCase.verifyEqual(c2.model_nrmse, cr{2}.narma.test_nrmse, 'AbsTol', 1e-14);
    testCase.verifyEqual(c1.improvement_nrmse, c1.baseline_nrmse - c1.model_nrmse, ...
        'AbsTol', 1e-14);
    testCase.verifyEqual(c1.ratio_nrmse, c1.model_nrmse / c1.baseline_nrmse, ...
        'AbsTol', 1e-14);
    % Only one seed baseline artifact
    d = dir(fullfile(run_dir, 'baselines', 'seed_*_matched_task_baselines.mat'));
    testCase.verifyEqual(numel(d), 1);
end

%% B. Identity validation
function testIdentityPassAndRejections(testCase)
    cfg = tiny_shared_cfg();
    cells = x_and_r_cells(cfg);
    seed = 1729;
    [bundle, ~] = prepare_seed_matched_baselines(cfg, seed, cells, '', false, struct());
    [p, ~] = build_ablation_params(cells{1}, seed, cfg, struct());
    [ok, ~] = validate_seed_matched_baseline_bundle(bundle, cfg, seed, p.W_in);
    testCase.verifyTrue(ok);

    bad = bundle; bad.base_seed = seed + 1;
    [ok2, r2] = validate_seed_matched_baseline_bundle(bad, cfg, seed, p.W_in);
    testCase.verifyFalse(ok2);
    testCase.verifyTrue(any(strcmp(r2.reasons, 'base_seed_mismatch')));

    bad = bundle; bad.protocol_fingerprint = 'deadbeef';
    [ok3, r3] = validate_seed_matched_baseline_bundle(bad, cfg, seed, p.W_in);
    testCase.verifyFalse(ok3);
    testCase.verifyTrue(any(strcmp(r3.reasons, 'protocol_fingerprint_mismatch')));

    Wbad = p.W_in; Wbad(1) = Wbad(1) + 0.1;
    [ok4, r4] = validate_seed_matched_baseline_bundle(bundle, cfg, seed, Wbad);
    testCase.verifyFalse(ok4);
    testCase.verifyTrue(any(strcmp(r4.reasons, 'W_in_hash_mismatch')));

    bad = bundle; bad.narma_task_seed = seed + 99;
    [ok5, r5] = validate_seed_matched_baseline_bundle(bad, cfg, seed, p.W_in);
    testCase.verifyFalse(ok5);
    testCase.verifyTrue(any(strcmp(r5.reasons, 'narma_task_seed_mismatch')));

    bad = bundle; bad.narma_task_data_hash = 'abc';
    [ok6, r6] = validate_seed_matched_baseline_bundle(bad, cfg, seed, p.W_in);
    testCase.verifyFalse(ok6);
    testCase.verifyTrue(any(contains(r6.reasons, 'task_data_hash_mismatch')) || ...
        any(strcmp(r6.reasons, 'bundle_id_mismatch')));

    bad = bundle; bad.narma_split_hash = 'def';
    [ok7, r7] = validate_seed_matched_baseline_bundle(bad, cfg, seed, p.W_in);
    testCase.verifyFalse(ok7);

    bad = bundle;
    bad.evaluation_provenance.mode = 'injected_test_fixture';
    [ok8, r8] = validate_seed_matched_baseline_bundle(bad, cfg, seed, p.W_in);
    testCase.verifyFalse(ok8);
    testCase.verifyTrue(any(contains(r8.reasons, 'provenance_rejected')));
end

%% C. Fail-closed required baselines
function testFailClosedSimpleAndConventional(testCase)
    cfg = tiny_shared_cfg();
    cells = x_and_r_cells(cfg);
    seed = 1729;
    [bundle, ~] = prepare_seed_matched_baselines(cfg, seed, cells, '', false, struct());

    bl = bundle.narma.baselines;
    bl.linear_input_history.status = 'failed';
    [ok1, r1] = validate_matched_task_baselines(bl, 'narma', struct( ...
        'lambda_grid', bundle.ridge_lambda_grid, ...
        'require_dale', false, 'require_comparisons', false));
    testCase.verifyFalse(ok1);
    testCase.verifyTrue(any(contains(r1.reasons, 'linear_input_history')));

    bl = bundle.narma.baselines;
    bl.training_target_mean.metrics_test.nrmse = Inf;
    [ok2, r2] = validate_matched_task_baselines(bl, 'narma', struct( ...
        'lambda_grid', bundle.ridge_lambda_grid, ...
        'require_dale', false, 'require_comparisons', false));
    testCase.verifyFalse(ok2);
    testCase.verifyTrue(any(contains(r2.reasons, 'training_target_mean_test_nrmse_nonfinite')));

    bl = bundle.mackey_glass_onestep.baselines;
    bl.linear_autoregression.status = 'failed';
    [ok3, ~] = validate_matched_task_baselines(bl, 'mackey_glass_onestep', struct( ...
        'lambda_grid', bundle.ridge_lambda_grid, ...
        'require_dale', false, 'require_comparisons', false));
    testCase.verifyFalse(ok3);

    bl = bundle.mackey_glass_onestep.baselines;
    bl.persistence.metrics_test.nrmse = NaN;
    [ok4, ~] = validate_matched_task_baselines(bl, 'mackey_glass_onestep', struct( ...
        'lambda_grid', bundle.ridge_lambda_grid, ...
        'require_dale', false, 'require_comparisons', false));
    testCase.verifyFalse(ok4);

    bl = bundle.narma.baselines;
    bl.conventional_leaky_esn.status = 'failed';
    [ok5, ~] = validate_matched_task_baselines(bl, 'narma', struct( ...
        'lambda_grid', bundle.ridge_lambda_grid, ...
        'require_dale', false, 'require_comparisons', false));
    testCase.verifyFalse(ok5);
    blm = bundle.mackey_glass_onestep.baselines;
    blm.conventional_leaky_esn.status = 'failed';
    [ok5b, ~] = validate_matched_task_baselines(blm, 'mackey_glass_onestep', struct( ...
        'lambda_grid', bundle.ridge_lambda_grid, ...
        'require_dale', false, 'require_comparisons', false));
    testCase.verifyFalse(ok5b);

    bl = bundle.narma.baselines;
    bl.linear_input_history.ridge_diagnostics = struct();
    [ok6, r6] = validate_matched_task_baselines(bl, 'narma', struct( ...
        'lambda_grid', bundle.ridge_lambda_grid, ...
        'require_dale', false, 'require_comparisons', false));
    testCase.verifyFalse(ok6);
    testCase.verifyTrue(any(contains(r6.reasons, 'missing_ridge_diagnostics')));

    % Pending Dale allowed; cannot produce superiority claim
    attached = attach_shared_baselines_for_cell(bundle.narma, 0.5, 'x', ...
        cfg.benchmark_baselines, bundle.bundle_id);
    testCase.verifyEqual(attached.dale_mesn_control.status, 'pending_paired_aggregation');
    [ok7, ~] = validate_matched_task_baselines(attached, 'narma', struct( ...
        'lambda_grid', bundle.ridge_lambda_grid, ...
        'feature_mode', 'x', ...
        'dale_mesn_control_keys', cfg.benchmark_baselines.dale_mesn_control_keys, ...
        'require_dale', true, 'require_comparisons', true, ...
        'require_candidate_table', false));
    testCase.verifyTrue(ok7);
    attached.dale_mesn_control.comparison.improvement_nrmse = 0.1;
    [ok8, r8] = validate_matched_task_baselines(attached, 'narma', struct( ...
        'lambda_grid', bundle.ridge_lambda_grid, ...
        'feature_mode', 'x', ...
        'dale_mesn_control_keys', cfg.benchmark_baselines.dale_mesn_control_keys, ...
        'require_dale', true, 'require_comparisons', true, ...
        'require_candidate_table', false));
    testCase.verifyFalse(ok8);
    testCase.verifyTrue(any(strcmp(r8.reasons, 'dale_pending_produced_superiority_claim')));
end

%% D. Matching and comparisons
function testFeatureModesShareConventionalButKeepDaleKeys(testCase)
    cfg = tiny_shared_cfg();
    cells = x_and_r_cells(cfg);
    seed = 1729;
    [bundle, ~] = prepare_seed_matched_baselines(cfg, seed, cells, '', false, struct());
    ax = attach_shared_baselines_for_cell(bundle.narma, 0.4, 'x', ...
        cfg.benchmark_baselines, bundle.bundle_id);
    ar = attach_shared_baselines_for_cell(bundle.narma, 0.6, 'r', ...
        cfg.benchmark_baselines, bundle.bundle_id);
    testCase.verifyEqual(ax.conventional_leaky_esn.selected_candidate_index, ...
        ar.conventional_leaky_esn.selected_candidate_index);
    testCase.verifyEqual(ax.conventional_leaky_esn.metrics_test.nrmse, ...
        ar.conventional_leaky_esn.metrics_test.nrmse, 'AbsTol', 0);
    testCase.verifyEqual(ax.dale_mesn_control.dale_mesn_control_reference, ...
        'adapt-off__std-off__delay-ode_off__feat-x');
    testCase.verifyEqual(ar.dale_mesn_control.dale_mesn_control_reference, ...
        'adapt-off__std-off__delay-ode_off__feat-r');
    testCase.verifyEqual(ax.conventional_leaky_esn.comparison.model_nrmse, 0.4);
    testCase.verifyEqual(ar.conventional_leaky_esn.comparison.model_nrmse, 0.6);
end

function testMutatingTestTargetDoesNotAlterSelection(testCase)
    U = randn(120, 1);
    Y = randn(120, 1);
    wash = 5;
    split = build_contiguous_ratio_split(120, 0.5, 0.25, wash);
    Win = ones(4, 1);
    opts = struct('task', 'narma', 'mesn_Win', Win, 'base_seed', 1, ...
        'feature_mode', 'x', 'lambda_grid', [1e-2, 1], 'narma_order', 3, ...
        'model_test_nrmse', 1, 'skip_dale', true, ...
        'benchmark_baselines', build_matched_task_baselines_config(struct('base', struct('n', 4))));
    opts.benchmark_baselines.conventional_leaky_esn.spectral_radius_candidates = 0.5;
    opts.benchmark_baselines.conventional_leaky_esn.leak_rate_candidates = 1.0;
    opts.benchmark_baselines.conventional_leaky_esn.input_scaling_candidates = 0.5;
    b1 = compute_matched_onestep_baselines(U, Y, split, wash, opts);
    Y2 = Y; Y2(split.test_idx) = Y2(split.test_idx) + 5;
    b2 = compute_matched_onestep_baselines(U, Y2, split, wash, opts);
    testCase.verifyEqual(b1.linear_input_history.selected_lambda, ...
        b2.linear_input_history.selected_lambda);
    testCase.verifyEqual(b1.conventional_leaky_esn.selected_lambda, ...
        b2.conventional_leaky_esn.selected_lambda);
    testCase.verifyEqual(b1.conventional_leaky_esn.selected_candidate_index, ...
        b2.conventional_leaky_esn.selected_candidate_index);
    testCase.verifyEqual(b1.linear_input_history.ridge_diagnostics.numerical_rank, ...
        b2.linear_input_history.ridge_diagnostics.numerical_rank);
    testCase.verifyEqual(b1.linear_input_history.ridge_diagnostics.intercept, ...
        b2.linear_input_history.ridge_diagnostics.intercept, 'AbsTol', 0);
end

%% E. Runner behavior
function testFullRejectsBaselineOverrides(testCase)
    opts = struct( ...
        'baseline_bundle_override', struct('x', 1), ...
        'use_reduced_lengths', true, 'max_seeds', 1, 'max_cells', 1, ...
        'save_results', false, 'verbose', false);
    testCase.verifyError(@() run_mechanism_ablation_full(opts), ...
        'run_mechanism_ablation_full:BaselineOverrideForbidden');
end

function testSmokeAndPilotConstructBundlesInternally(testCase)
    root = tempname;
    mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
    % Production smoke path (full preregistered conventional grid would be slow;
    % assert the prepare hook runs by mocking via existing prepare with shrunk cfg
    % and separately checking the smoke/pilot runner source calls prepare).
    cfg = tiny_shared_cfg();
    cells = cfg.cells(1);
    [bundle, art] = prepare_seed_matched_baselines(cfg, 1729, cells, root, true, struct());
    testCase.verifyEqual(bundle.evaluation_provenance.mode, 'executed_shared_seed_bundle');
    testCase.verifyTrue(exist(art, 'file') == 2);
    smoke_src = fileread(fullfile(testCase.TestData.repo_root, ...
        'experiments', 'revalidated', 'run_mechanism_ablation_smoke.m'));
    pilot_src = fileread(fullfile(testCase.TestData.repo_root, ...
        'experiments', 'revalidated', 'run_mechanism_ablation_pilot.m'));
    full_src = fileread(fullfile(testCase.TestData.repo_root, ...
        'experiments', 'revalidated', 'run_mechanism_ablation_full.m'));
    testCase.verifyTrue(contains(smoke_src, 'prepare_seed_matched_baselines'));
    testCase.verifyTrue(contains(pilot_src, 'prepare_seed_matched_baselines'));
    testCase.verifyTrue(contains(full_src, 'prepare_seed_matched_baselines'));
    testCase.verifyTrue(contains(full_src, 'reject_baseline_overrides'));
end

function testStandaloneLocalProvenance(testCase)
    cfg = tiny_shared_cfg();
    cr = run_ablation_cell(cfg.cells{1}, 1729, cfg, struct( ...
        'verbose', false, 'run_secondary', false));
    testCase.verifyEqual(cr.narma.baselines.evaluation_provenance.mode, ...
        'executed_cell_local');
    testCase.verifyEqual(cr.matched_baseline_bundle_id, '');
end

function testNegativeR2Allowed(testCase)
    b = struct();
    b.persistence = struct('status', 'computed', ...
        'metrics_test', struct('nrmse', 1.2, 'r2', -0.5));
    b.linear_autoregression = struct('status', 'computed', ...
        'selected_lambda', 1e-2, ...
        'metrics_test', struct('nrmse', 1.1, 'r2', -1), ...
        'ridge_diagnostics', struct('lambda', 1e-2));
    b.conventional_leaky_esn = struct('status', 'computed', ...
        'selected_lambda', 1e-2, 'selected_candidate_index', 1, ...
        'metrics_test', struct('nrmse', 1.0, 'r2', -2), ...
        'ridge_diagnostics', struct('lambda', 1e-2), ...
        'candidate_selection_table', struct('x', 1));
    [ok, ~] = validate_matched_task_baselines(b, 'mackey_glass_onestep', struct( ...
        'lambda_grid', [1e-2; 1], ...
        'require_dale', false, 'require_comparisons', false, ...
        'require_candidate_table', true));
    testCase.verifyTrue(ok);
end
