function tests = test_mg_autonomous_baseline_alignment
% test_mg_autonomous_baseline_alignment  Readiness, fingerprint, one-step invariance.
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

function [records, bundle, cfg] = build_valid_control_records()
    cfg = tiny_cfg();
    cells = x_and_r_cells(cfg);
    seed = cfg.seeds(1);
    [bundle, ~] = prepare_seed_matched_baselines(cfg, seed, cells, '', false, struct());
    records = cell(1, 2);
    for i = 1:2
        cr = run_ablation_cell(cells{i}, seed, cfg, struct( ...
            'verbose', false, 'run_secondary', false, ...
            'shared_baseline_bundle', bundle));
        records{i} = local_cell_to_record(cr, cfg, cells{i});
    end
end

%% I. Readiness and fingerprint
function testReadinessRejectsMissingControls(testCase)
    cfg = mechanism_ablation_config('publication');
    records = local_publication_records(cfg);
    records(1).mackey_glass.rollout = rmfield(records(1).mackey_glass.rollout, 'controls');
    report = evaluate_publication_readiness(cfg, readiness_opts(cfg, records));
    testCase.verifyFalse(check_named(report, 'mg_autonomous_matched_controls_complete'));
    testCase.verifyFalse(report.publication_ready);
end

function testReadinessRejectsFailedControls(testCase)
    cfg = mechanism_ablation_config('publication');
    records = local_publication_records(cfg);
    records(1).mackey_glass.rollout.controls.status = 'failed_required_autonomous_baseline';
    report = evaluate_publication_readiness(cfg, readiness_opts(cfg, records));
    testCase.verifyFalse(check_named(report, 'mg_autonomous_matched_controls_complete'));
end

function testReadinessRejectsBundleIdMismatch(testCase)
    [records, bundle, cfg] = build_valid_control_records();
    records{1}.matched_baseline_bundle_id = bundle.bundle_id;
    records{1}.mackey_glass.rollout.controls.bundle_id = 'deadbeef';
    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', records, ...
        'has_manifest', true, 'has_commit_sha', true, 'has_artifact_hashes', true, ...
        'temporal_learning_gate', passing_gate(cfg)));
    testCase.verifyFalse(check_named(report, 'mg_autonomous_matched_controls_complete'));
end

function testReadinessRejectsAlteredComparisonArithmetic(testCase)
    [records, ~, cfg] = build_valid_control_records();
    records{1}.mackey_glass.rollout.controls.persistence.comparison.improvement_nrmse_full_horizon = ...
        records{1}.mackey_glass.rollout.controls.persistence.comparison.improvement_nrmse_full_horizon + 1;
    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', records, ...
        'has_manifest', true, 'has_commit_sha', true, 'has_artifact_hashes', true, ...
        'temporal_learning_gate', passing_gate(cfg)));
    testCase.verifyFalse(check_named(report, 'mg_autonomous_matched_controls_complete'));
end

function testReadinessPassesValidOdeRecords(testCase)
    [records, bundle, cfg] = build_valid_control_records();
    for i = 1:numel(records)
        testCase.verifyEqual(records{i}.matched_baseline_bundle_id, bundle.bundle_id);
        testCase.verifyEqual(records{i}.mackey_glass.rollout.controls.status, 'computed');
    end
    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', records, ...
        'has_manifest', true, 'has_commit_sha', true, 'has_artifact_hashes', true, ...
        'temporal_learning_gate', passing_gate(cfg)));
    testCase.verifyTrue(check_named(report, 'mg_autonomous_matched_controls_complete'));
end

function testSmokeNotPublicationReady(testCase)
    cfg = tiny_cfg();
    cells = x_and_r_cells(cfg);
    seed = cfg.seeds(1);
    [bundle, ~] = prepare_seed_matched_baselines(cfg, seed, cells, '', false, struct());
    records = cell(1, 2);
    for i = 1:2
        cr = run_ablation_cell(cells{i}, seed, cfg, struct( ...
            'verbose', false, 'run_secondary', false, ...
            'shared_baseline_bundle', bundle));
        records{i} = local_cell_to_record(cr, cfg, cells{i});
    end
    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', records, ...
        'has_manifest', true, 'has_commit_sha', true, 'has_artifact_hashes', true, ...
        'temporal_learning_gate', passing_gate(cfg)));
    testCase.verifyFalse(report.publication_ready);
    testCase.verifyNotEqual(cfg.protocol_tier, 'publication');
end

function testFingerprintChangesWithAutonomousConfig(testCase)
    cfg_a = tiny_cfg();
    cfg_b = cfg_a;
    cfg_b.mg_autonomous_rollout.forecast_horizon_steps = ...
        cfg_b.mg_autonomous_rollout.forecast_horizon_steps + 1;
    fp_a = compute_protocol_fingerprint(cfg_a);
    fp_b = compute_protocol_fingerprint(cfg_b);
    testCase.verifyNotEqual(fp_a, fp_b);
end

function testFingerprintIgnoresPathsAndTimestamps(testCase)
    cfg_a = tiny_cfg();
    cfg_b = cfg_a;
    cfg_b.created_utc = '2099-01-01T00:00:00Z';
    cfg_b.run_dir = 'C:\tmp\autonomous_controls_smoke';
    testCase.verifyEqual(compute_protocol_fingerprint(cfg_a), ...
        compute_protocol_fingerprint(cfg_b));
end

function testOneStepMetricsUnchangedByAutonomousControls(testCase)
    cfg = tiny_cfg();
    cells = x_and_r_cells(cfg);
    seed = cfg.seeds(1);
    [bundle, ~] = prepare_seed_matched_baselines(cfg, seed, cells, '', false, struct());
    cr_shared = run_ablation_cell(cells{1}, seed, cfg, struct( ...
        'verbose', false, 'run_secondary', false, ...
        'shared_baseline_bundle', bundle));
    cr_local = run_ablation_cell(cells{1}, seed, cfg, struct( ...
        'verbose', false, 'run_secondary', false));
    testCase.verifyEqual(cr_shared.mackey_glass.test_nrmse, ...
        cr_local.mackey_glass.test_nrmse, 'AbsTol', 1e-12);
    testCase.verifyEqual(cr_shared.mackey_glass.baselines.persistence.metrics_test.nrmse, ...
        cr_local.mackey_glass.baselines.persistence.metrics_test.nrmse, 'AbsTol', 1e-12);
    testCase.verifyEqual( ...
        cr_shared.mackey_glass.baselines.conventional_leaky_esn.selected_candidate_index, ...
        cr_local.mackey_glass.baselines.conventional_leaky_esn.selected_candidate_index);
    testCase.verifyEqual(cr_shared.mackey_glass.baselines.linear_autoregression.selected_lambda, ...
        cr_local.mackey_glass.baselines.linear_autoregression.selected_lambda, 'AbsTol', 0);
    testCase.verifyTrue(isfield(cr_shared.mackey_glass.rollout, 'controls'));
    testCase.verifyEqual(cr_shared.mackey_glass.rollout.controls.content_hash, ...
        bundle.mackey_glass_autonomous.content_hash);
end

function testBundleIdentityValidationPasses(testCase)
    cfg = tiny_cfg();
    cells = x_and_r_cells(cfg);
    seed = cfg.seeds(1);
    [bundle, ~] = prepare_seed_matched_baselines(cfg, seed, cells, '', false, struct());
    [p, ~] = build_ablation_params(cells{1}, seed, cfg, struct());
    [ok, ~] = validate_seed_matched_baseline_bundle(bundle, cfg, seed, p.W_in);
    testCase.verifyTrue(ok);
    testCase.verifyEqual(bundle.autonomous_control_content_hash, ...
        bundle.mackey_glass_autonomous.content_hash);
end

function testBundleIdentityRejectsAlteredArithmetic(testCase)
    cfg = tiny_cfg();
    cells = x_and_r_cells(cfg);
    seed = cfg.seeds(1);
    [bundle, ~] = prepare_seed_matched_baselines(cfg, seed, cells, '', false, struct());
    [p, ~] = build_ablation_params(cells{1}, seed, cfg, struct());
    bad = bundle;
    bad.mackey_glass_autonomous.content_hash = 'deadbeef';
    [ok, rep] = validate_seed_matched_baseline_bundle(bad, cfg, seed, p.W_in);
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(rep.reasons, 'autonomous_content_hash_mismatch')) || ...
        any(strcmp(rep.reasons, 'bundle_autonomous_content_hash_mismatch')));
end

%% helpers
function r = local_cell_to_record(cr, cfg, cell_spec)
    r = struct();
    r.cell_key = cr.cell_key;
    r.cell_id = cr.cell_id;
    r.base_seed = cr.base_seed;
    r.mode = cr.mode;
    r.status = cr.status;
    r.which_states = cell_spec.which_states;
    r.dale_violations = cr.dale_violations;
    r.wall_time_seconds = cr.wall_time_seconds;
    r.memory_capacity = cr.memory_capacity;
    r.narma = cr.narma;
    r.mackey_glass = cr.mackey_glass;
    r.empirical_convergence = cr.empirical_convergence;
    r.qa = cr.qa;
    r.matched_baseline_bundle_id = cr.matched_baseline_bundle_id;
    if ~isfield(r.mackey_glass, 'rollout') || isempty(r.mackey_glass.rollout)
        r.mackey_glass.rollout = struct('status', 'skipped');
    end
    if strcmp(r.mode, 'DDE') && ~isfield(r.mackey_glass.rollout, 'controls')
        r.mackey_glass.rollout.controls = attach_shared_mg_autonomous_controls_for_cell( ...
            struct('status', 'computed'), ...
            struct('mode', 'DDE', 'status', 'unsupported_not_computed'), ...
            r.which_states, cr.matched_baseline_bundle_id, ...
            cfg.mg_autonomous_rollout, cfg.benchmark_baselines);
    end
end

function records = local_publication_records(cfg)
    ode_cell = [];
    for i = 1:numel(cfg.cells)
        if strcmp(cfg.cells{i}.mode, 'ODE') && isempty(ode_cell)
            ode_cell = cfg.cells{i};
            break;
        end
    end
    records = make_publication_record(cfg, ode_cell, cfg.seeds(1));
    records = [records; make_publication_record(cfg, ode_cell, cfg.seeds(2))];
end

function r = make_publication_record(cfg, cell_spec, seed)
    r = struct();
    r.cell_key = cell_spec.cell_key;
    r.cell_id = cell_spec.cell_id;
    r.base_seed = seed;
    r.mode = cell_spec.mode;
    r.which_states = cell_spec.which_states;
    r.status = 'ok';
    r.dale_violations = 0;
    r.wall_time_seconds = 1;
    r.matched_baseline_bundle_id = 'bundle_test';
    r.memory_capacity = struct('MC_total', 1);
    r.narma = struct('test_nrmse', 0.1);
    r.mackey_glass = struct('test_nrmse', 0.2);
    r.empirical_convergence = struct( ...
        'classification', 'empirically_contracting_on_test_set', ...
        'median_pair_slope', -0.1);
    r.qa = struct('mean_rate', 0.4, 'saturation_fraction', 0.1, ...
        'silent_fraction', 0.1, 'resource_in_unit_interval', true);
    rc = cfg.mg_autonomous_rollout;
    H = rc.forecast_horizon_steps;
    n_o = rc.n_forecast_origins;
    split = struct('test_idx', (100:700)');
    sch = build_mg_autonomous_origin_schedule(split, rc);
    origins = sch.origin_indices(:);
    po = repmat(struct('origin_global_index', 0, 'origin_test_relative_index', 0, ...
        'horizon', H, 'predictions', zeros(H, 1), 'targets', zeros(H, 1), ...
        'errors', zeros(H, 1), 'normalized_absolute_errors', zeros(H, 1), ...
        'full_horizon_nrmse', 0.1, 'rmse', 0.1, 'valid_horizon_steps', H, ...
        'first_threshold_exceedance_step', NaN, 'right_censored', true, ...
        'valid_error_threshold', 0.4), n_o, 1);
    for o = 1:n_o
        po(o).origin_global_index = origins(o);
        po(o).origin_test_relative_index = sch.origin_test_relative_indices(o);
    end
    model_metrics = struct( ...
        'pooled_nrmse_full_horizon', 0.2, ...
        'pooled_nrmse_at_fixed_horizons', 0.2 * ones(numel(rc.fixed_report_horizons), 1), ...
        'fixed_report_horizons', rc.fixed_report_horizons(:), ...
        'median_valid_horizon', H, 'fraction_right_censored', 1);
    base_metrics = struct( ...
        'pooled_nrmse_full_horizon', 0.35, ...
        'pooled_nrmse_at_fixed_horizons', 0.35 * ones(numel(rc.fixed_report_horizons), 1), ...
        'median_valid_horizon', H - 2, 'fraction_right_censored', 0.5);
    controls = struct();
    controls.protocol_version = 'matched_mg_autonomous_controls_v1';
    controls.status = 'computed';
    controls.bundle_id = 'bundle_test';
    controls.content_hash = 'content';
    controls.origin_schedule_hash = 'schedule';
    controls.normalization_scale = 1.0;
    controls.normalization_reference = rc.normalization_reference;
    controls.comparisons_attached = true;
    controls.evaluation_provenance = struct( ...
        'mode', 'executed_shared_seed_bundle', ...
        'model_refit_for_rollout', false, ...
        'lambda_reselected_for_rollout', false, ...
        'candidate_reselected_for_rollout', false, ...
        'autonomous_performance_used_for_selection', false, ...
        'publication_shared_bundle', true);
    for nm = {'persistence', 'linear_autoregression', 'conventional_leaky_esn'}
        c = struct();
        c.status = 'computed';
        c.metrics = base_metrics;
        c.first_step_alignment = struct('verified', true);
        c.fitted_model_hash = 'hash';
        c.comparison = mg_autonomous_control_comparison(model_metrics, base_metrics);
        controls.(nm{1}) = c;
    end
    controls.dale_mesn_control = struct( ...
        'status', 'pending_paired_aggregation', ...
        'dale_mesn_control_reference', dale_mesn_control_reference_key( ...
            cell_spec.which_states, cfg.benchmark_baselines.dale_mesn_control_keys), ...
        'comparison', struct('numerical_superiority_claim', false, ...
            'status', 'pending_paired_aggregation'));
    controls.origin_schedule = sch;
    r.mackey_glass.rollout = struct( ...
        'status', 'computed', ...
        'protocol_version', rc.protocol_version, ...
        'role', rc.role, ...
        'mode', 'ODE', ...
        'origin_schedule', sch, ...
        'forecast_horizon_steps', H, ...
        'fixed_report_horizons', rc.fixed_report_horizons(:), ...
        'normalization_scale', 1.0, ...
        'normalization_reference', rc.normalization_reference, ...
        'per_origin', po, ...
        'metrics', model_metrics, ...
        'controls', controls, ...
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

function opts = readiness_opts(cfg, records)
    opts = struct( ...
        'cell_records', records, ...
        'has_manifest', true, 'has_commit_sha', true, 'has_artifact_hashes', true, ...
        'temporal_learning_gate', passing_gate(cfg));
end

function g = passing_gate(cfg)
    tg = cfg.temporal_learning_gate;
    n = numel(tg.model_seeds);
    seed_results = repmat(struct( ...
        'mesn', struct('metrics', struct('nrmse', 0.5, 'r2', 0.5)), ...
        'current_input_only_control', struct(), ...
        'no_recurrent_coupling_control', struct(), ...
        'shuffled_target_control', struct(), ...
        'exact_history_control', struct()), n, 1);
    g = struct( ...
        'status', 'complete', ...
        'passed', true, ...
        'include_input', false, ...
        'protocol_version', tg.protocol_version, ...
        'seed_results', seed_results);
end

function tf = check_named(report, name)
    names = {report.checks.name};
    idx = find(strcmp(names, name), 1);
    tf = ~isempty(idx) && report.checks(idx).pass;
end
