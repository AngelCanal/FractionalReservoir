function tests = test_mg_autonomous_rollout
% test_mg_autonomous_rollout  Protocol, scoring, validation, readiness for MG autonomous.
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

function testPublicationOriginSchedule(testCase)
    cfg = build_mg_autonomous_rollout_config('publication');
    testCase.verifyEqual(cfg.forecast_horizon_steps, 100);
    testCase.verifyEqual(cfg.n_forecast_origins, 5);
    split = build_contiguous_ratio_split(2999, 0.6, 0.2, 100);
    % Reproduce publication MG U length T-1=2999; test ~601
    testCase.verifyGreaterThanOrEqual(numel(split.test_idx), 100);
    sch = build_mg_autonomous_origin_schedule(split, cfg);
    testCase.verifyEqual(numel(sch.origin_indices), 5);
    testCase.verifyEqual(sch.forecast_horizon_steps, 100);
    for o = 1:5
        i = sch.origin_indices(o);
        testCase.verifyGreaterThanOrEqual(i, split.test_idx(1));
        testCase.verifyLessThanOrEqual(i + 99, split.test_idx(end));
    end
    testCase.verifyTrue(issorted(sch.origin_indices) && ...
        numel(unique(sch.origin_indices)) == 5);
end

function testValidationRejectsTamperedOriginIndices(testCase)
    cfg = build_mg_autonomous_rollout_config('smoke');
    split = build_contiguous_ratio_split(279, 0.6, 0.2, 15);
    Y = (1:300)';
    result = local_minimal_valid_ode_result(split, cfg, Y);
    sch = result.origin_schedule;
    sch.origin_indices(1) = sch.origin_indices(1) + 1;
    result.origin_schedule = sch;
    result.per_origin(1).origin_global_index = sch.origin_indices(1);
    [ok, rep] = validate_mg_autonomous_rollout_result(result, ...
        struct('mg_autonomous_rollout', cfg), 'ODE');
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(rep.reasons, 'schedule_origin_indices_mismatch')));
end

function testValidationRejectsChangedTestRelativeOrigin(testCase)
    cfg = build_mg_autonomous_rollout_config('smoke');
    split = build_contiguous_ratio_split(279, 0.6, 0.2, 15);
    Y = (1:300)';
    result = local_minimal_valid_ode_result(split, cfg, Y);
    sch = result.origin_schedule;
    sch.origin_test_relative_indices(1) = sch.origin_test_relative_indices(1) + 1;
    result.origin_schedule = sch;
    result.per_origin(1).origin_test_relative_index = sch.origin_test_relative_indices(1);
    [ok, rep] = validate_mg_autonomous_rollout_result(result, ...
        struct('mg_autonomous_rollout', cfg), 'ODE');
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(rep.reasons, 'schedule_origin_test_relative_indices_mismatch')));
end

function testValidationRejectsChangedFirstOrLastOrigin(testCase)
    cfg = build_mg_autonomous_rollout_config('smoke');
    split = build_contiguous_ratio_split(279, 0.6, 0.2, 15);
    Y = (1:300)';
    result = local_minimal_valid_ode_result(split, cfg, Y);
    bad = result;
    sch = bad.origin_schedule;
    sch.first_origin = sch.first_origin + 1;
    bad.origin_schedule = sch;
    [ok1, rep1] = validate_mg_autonomous_rollout_result(bad, ...
        struct('mg_autonomous_rollout', cfg), 'ODE');
    testCase.verifyFalse(ok1);
    testCase.verifyTrue(any(strcmp(rep1.reasons, 'schedule_first_origin_mismatch')));

    bad2 = result;
    sch2 = bad2.origin_schedule;
    sch2.last_origin = sch2.last_origin - 1;
    bad2.origin_schedule = sch2;
    [ok2, rep2] = validate_mg_autonomous_rollout_result(bad2, ...
        struct('mg_autonomous_rollout', cfg), 'ODE');
    testCase.verifyFalse(ok2);
    testCase.verifyTrue(any(strcmp(rep2.reasons, 'schedule_last_origin_mismatch')));
end

function testScorerRejectsOriginNearTestEnd(testCase)
    cfg = build_mg_autonomous_rollout_config('smoke');
    cfg.forecast_horizon_steps = 5;
    cfg.n_forecast_origins = 1;
    cfg.fixed_report_horizons = [1, 5];
    split = struct( ...
        'train_idx', (1:20)', 'val_idx', (21:30)', 'test_idx', (31:40)', ...
        'washout_steps', 2);
    Y = (1:50)';
    origin = split.test_idx(end) - 2;
    testCase.verifyError(@() score_mg_autonomous_forecasts( ...
        {ones(5, 1)}, Y, origin, split, cfg), ...
        'score_mg_autonomous_forecasts:TargetBeyondTestEnd');
end

function testValidationRejectsPerOriginCountMismatch(testCase)
    cfg = build_mg_autonomous_rollout_config('smoke');
    split = build_contiguous_ratio_split(279, 0.6, 0.2, 15);
    Y = (1:300)';
    result = local_minimal_valid_ode_result(split, cfg, Y);
    result.per_origin = result.per_origin(1);
    [ok, rep] = validate_mg_autonomous_rollout_result(result, ...
        struct('mg_autonomous_rollout', cfg), 'ODE');
    testCase.verifyFalse(ok);
    testCase.verifyTrue(any(strcmp(rep.reasons, 'per_origin_count_mismatch')));
end

function testSmokePilotOriginSchedule(testCase)
    for tier = {'smoke', 'pilot'}
        cfg = build_mg_autonomous_rollout_config(tier{1});
        testCase.verifyEqual(cfg.forecast_horizon_steps, 20);
        testCase.verifyEqual(cfg.n_forecast_origins, 2);
        testCase.verifyEqual(cfg.fixed_report_horizons(:), [1;5;10;20]);
        split = build_contiguous_ratio_split(279, 0.6, 0.2, 15);
        sch = build_mg_autonomous_origin_schedule(split, cfg);
        testCase.verifyEqual(numel(sch.origin_indices), 2);
    end
end

function testInsufficientLengthErrors(testCase)
    cfg = build_mg_autonomous_rollout_config('publication');
    split = build_contiguous_ratio_split(200, 0.6, 0.2, 10);  % test << 100
    testCase.verifyError(@() build_mg_autonomous_origin_schedule(split, cfg), ...
        'build_mg_autonomous_origin_schedule:InsufficientTestLength');
end

function testOldPublicationAllocationWouldSkip(testCase)
    % Document prior defect: init_len=200 + rollout 500 > test ~601
    split = build_contiguous_ratio_split(2999, 0.6, 0.2, 100);
    n_test = numel(split.test_idx);
    init_len = max(2*100, 200);
    rollout_steps = 500;
    testCase.verifyTrue(init_len + rollout_steps > n_test);
    % New protocol allocates without that skip condition
    cfg = build_mg_autonomous_rollout_config('publication');
    sch = build_mg_autonomous_origin_schedule(split, cfg);
    testCase.verifyEqual(numel(sch.origin_indices), 5);
end

function testValidHorizonCrossingAndCensoring(testCase)
    cfg = build_mg_autonomous_rollout_config('smoke');
    cfg.forecast_horizon_steps = 5;
    cfg.n_forecast_origins = 1;
    cfg.fixed_report_horizons = [1, 5];
    split = struct( ...
        'train_idx', (1:20)', 'val_idx', (21:30)', 'test_idx', (31:40)', ...
        'washout_steps', 2);
    Y = (1:50)';
    % Perfect until step 3 then large error
    pred = Y(31:35);
    pred(3) = pred(3) + 10;
    scored = score_mg_autonomous_forecasts({pred}, Y, 31, split, cfg);
    sigma = scored.normalization_scale;
    nabs = abs(pred - Y(31:35)) / sigma;
    k = find(nabs > 0.4, 1, 'first');
    testCase.verifyEqual(scored.per_origin(1).valid_horizon_steps, k-1);
    testCase.verifyFalse(scored.per_origin(1).right_censored);

    pred2 = Y(31:35);
    scored2 = score_mg_autonomous_forecasts({pred2}, Y, 31, split, cfg);
    testCase.verifyEqual(scored2.per_origin(1).valid_horizon_steps, 5);
    testCase.verifyTrue(scored2.per_origin(1).right_censored);
end

function testPooledNrmseHandExample(testCase)
    cfg = build_mg_autonomous_rollout_config('smoke');
    cfg.forecast_horizon_steps = 2;
    cfg.n_forecast_origins = 2;
    cfg.fixed_report_horizons = [1, 2];
    split = struct( ...
        'train_idx', (1:10)', 'val_idx', (11:15)', 'test_idx', (16:20)', ...
        'washout_steps', 1);
    Y = ones(20, 1);
    Y(1:15) = [zeros(5,1); ones(10,1)];  % ensure nonzero train/val std
    Y_fit = [Y(2:10); Y(11:15)];
    sigma = std(Y_fit, 1);
    preds = {[1; 2], [3; 4]};
    origins = [16; 17];
    % targets for origin 16: Y(16:17)=[1;1]; origin 17: Y(17:18)=[1;1]
    scored = score_mg_autonomous_forecasts(preds, Y, origins, split, cfg);
    e = [1-1, 2-1; 3-1, 4-1];
    expect_h1 = sqrt(mean(e(:,1).^2)) / sigma;
    expect_h2 = sqrt(mean(e(:).^2)) / sigma;
    testCase.verifyEqual(scored.metrics.pooled_nrmse_at_fixed_horizons(1), expect_h1, 'AbsTol', 1e-12);
    testCase.verifyEqual(scored.metrics.pooled_nrmse_at_fixed_horizons(2), expect_h2, 'AbsTol', 1e-12);
end

function testDegenerateScaleFails(testCase)
    cfg = build_mg_autonomous_rollout_config('smoke');
    cfg.forecast_horizon_steps = 2;
    cfg.n_forecast_origins = 1;
    cfg.fixed_report_horizons = [1, 2];
    split = struct( ...
        'train_idx', (1:10)', 'val_idx', (11:15)', 'test_idx', (16:20)', ...
        'washout_steps', 1);
    Y = ones(20, 1);  % zero std after washout train+val
    testCase.verifyError(@() score_mg_autonomous_forecasts({[1;1]}, Y, 16, split, cfg), ...
        'score_mg_autonomous_forecasts:DegenerateScale');
end

function testNonfinitePredictionsFail(testCase)
    cfg = build_mg_autonomous_rollout_config('smoke');
    cfg.forecast_horizon_steps = 2;
    cfg.n_forecast_origins = 1;
    cfg.fixed_report_horizons = [1, 2];
    split = struct( ...
        'train_idx', (1:10)', 'val_idx', (11:15)', 'test_idx', (16:20)', ...
        'washout_steps', 1);
    Y = (1:20)';
    testCase.verifyError(@() score_mg_autonomous_forecasts({[NaN;1]}, Y, 16, split, cfg), ...
        'score_mg_autonomous_forecasts:NonfinitePredictions');
end

function testScoringOverrideChangesMetricsNotCalledGeneration(testCase)
    cfg = build_mg_autonomous_rollout_config('smoke');
    cfg.forecast_horizon_steps = 2;
    cfg.n_forecast_origins = 1;
    cfg.fixed_report_horizons = [1, 2];
    split = struct( ...
        'train_idx', (1:10)', 'val_idx', (11:15)', 'test_idx', (16:20)', ...
        'washout_steps', 1);
    Y = (1:20)';
    pred = [1; 2];
    s1 = score_mg_autonomous_forecasts({pred}, Y, 16, split, cfg);
    Y2 = Y;
    Y2(16:17) = [10; 20];
    s2 = score_mg_autonomous_forecasts({pred}, Y, 16, split, cfg, ...
        struct('Y_scoring_override', Y2));
    testCase.verifyEqual(s1.per_origin(1).predictions, s2.per_origin(1).predictions);
    testCase.verifyNotEqual(s1.metrics.pooled_nrmse_full_horizon, ...
        s2.metrics.pooled_nrmse_full_horizon);
    testCase.verifyTrue(s2.Y_scoring_override_used);
end

function testDdeValidation(testCase)
    cfg = mechanism_ablation_config('smoke');
    r = struct( ...
        'status', 'unsupported_not_computed', ...
        'protocol_version', cfg.mg_autonomous_rollout.protocol_version, ...
        'mode', 'DDE', ...
        'reason', 'DDE autonomous continuation is not implemented', ...
        'predictions', [], ...
        'metrics', [], ...
        'evaluation_provenance', struct('mode', 'unsupported'));
    [ok, rep] = validate_mg_autonomous_rollout_result(r, cfg, 'DDE');
    testCase.verifyTrue(ok, strjoin(rep.reasons, ','));
end

function testPublicationReadinessRejectsMissingAndSkipped(testCase)
    cfg = mechanism_ablation_config('publication');
    records = local_two_cell_records(cfg);
    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', records, ...
        'has_manifest', true, 'has_commit_sha', true, 'has_artifact_hashes', true, ...
        'temporal_learning_gate', passing_gate(cfg)));
    testCase.verifyTrue(check_named(report, 'mg_autonomous_protocol_complete'));

    records(1).mackey_glass = rmfield(records(1).mackey_glass, 'rollout');
    report2 = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', records, ...
        'has_manifest', true, 'has_commit_sha', true, 'has_artifact_hashes', true, ...
        'temporal_learning_gate', passing_gate(cfg)));
    testCase.verifyFalse(check_named(report2, 'mg_autonomous_protocol_complete'));
    testCase.verifyFalse(report2.all_required_secondary_endpoints_complete);
    testCase.verifyFalse(report2.publication_ready);

    records = local_two_cell_records(cfg);
    records(1).mackey_glass.rollout.status = 'skipped';
    report3 = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', records, ...
        'has_manifest', true, 'has_commit_sha', true, 'has_artifact_hashes', true, ...
        'temporal_learning_gate', passing_gate(cfg)));
    testCase.verifyFalse(check_named(report3, 'mg_autonomous_protocol_complete'));
end

function testPublicationReadinessRejectsInvalidDdeComputed(testCase)
    cfg = mechanism_ablation_config('publication');
    records = local_two_cell_records(cfg);
    records(2).mackey_glass.rollout.status = 'computed';
    records(2).mackey_glass.rollout.mode = 'DDE';
    records(2).mackey_glass.rollout.metrics = struct('nrmse', 0.1);
    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', records, ...
        'has_manifest', true, 'has_commit_sha', true, 'has_artifact_hashes', true, ...
        'temporal_learning_gate', passing_gate(cfg)));
    testCase.verifyFalse(check_named(report, 'mg_autonomous_protocol_complete'));
end

function testFingerprintIgnoresRuntimePath(testCase)
    cfg_a = mechanism_ablation_config('smoke');
    cfg_b = cfg_a;
    cfg_b.created_utc = '2099-01-01T00:00:00Z';
    cfg_b.run_dir = 'C:\tmp\whatever';
    testCase.verifyEqual(compute_protocol_fingerprint(cfg_a), ...
        compute_protocol_fingerprint(cfg_b));
end

function testConfigPresentOnAllTiers(testCase)
    for tier = {'smoke', 'pilot', 'publication'}
        cfg = mechanism_ablation_config(tier{1});
        testCase.verifyTrue(isfield(cfg, 'mg_autonomous_rollout'));
        testCase.verifyEqual(cfg.mg_autonomous_rollout.protocol_version, ...
            'mackey_glass_autonomous_rollout_v1');
        testCase.verifyTrue(cfg.lengths.mg_do_rollout);
    end
end

%% helpers
function records = local_two_cell_records(cfg)
    ode_cell = [];
    dde_cell = [];
    for i = 1:numel(cfg.cells)
        if strcmp(cfg.cells{i}.mode, 'ODE') && isempty(ode_cell)
            ode_cell = cfg.cells{i};
        elseif strcmp(cfg.cells{i}.mode, 'DDE') && isempty(dde_cell)
            dde_cell = cfg.cells{i};
        end
    end
    records = [make_record(cfg, ode_cell, cfg.seeds(1)); ...
               make_record(cfg, dde_cell, cfg.seeds(1))];
end

function r = make_record(cfg, cell_spec, seed)
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
    if strcmp(cell_spec.mode, 'DDE')
        r.mackey_glass.rollout = struct( ...
            'status', 'unsupported_not_computed', ...
            'protocol_version', rc.protocol_version, ...
            'mode', 'DDE', ...
            'reason', 'DDE autonomous continuation is not implemented', ...
            'predictions', [], 'metrics', [], ...
            'evaluation_provenance', struct('mode', 'unsupported'));
    else
        H = rc.forecast_horizon_steps;
        n_o = rc.n_forecast_origins;
        split = struct('test_idx', (100:700)');
        sch = build_mg_autonomous_origin_schedule(split, rc);
        origins = sch.origin_indices(:);
        po = repmat(struct('origin_global_index', 0, 'origin_test_relative_index', 0, ...
            'horizon', H, 'predictions', zeros(H,1), 'targets', zeros(H,1), ...
            'errors', zeros(H,1), 'normalized_absolute_errors', zeros(H,1), ...
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
            c = struct('status', 'computed', 'metrics', base_metrics, ...
                'first_step_alignment', struct('verified', true), ...
                'fitted_model_hash', 'hash');
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
            'normalization_reference', rc.normalization_reference, ...
            'normalization_scale', 1.0, ...
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
