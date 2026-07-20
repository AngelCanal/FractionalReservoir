function tests = test_temporal_memory_development_runner
% Phase 5D-B2 resumable temporal-memory development diagnostic runner.
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

function opts = small_fixture_opts(run_root, run_id)
    opts = struct();
    opts.allow_test_fixture = true;
    opts.development_root_override = run_root;
    opts.run_id = run_id;
    opts.fixture = struct( ...
        'washout_steps', 8, ...
        'train_samples', 12, ...
        'validation_samples', 8, ...
        'test_samples', 8, ...
        'lags', (1:3)', ...
        'lambda_grid', [0; 1e-4; 1], ...
        'model_seeds', [101; 102], ...
        'cell_names', {{'reference_r'; 'reference_x'; 'delay_removed_r'; ...
            'std_removed_r'; 'std_and_delay_removed_r'; ...
            'single_moment_matched_r'; 'adaptation_removed_r'; ...
            'mechanisms_off_r'}}, ...
        'use_synthetic_metrics', true, ...
        'n_candidates', 3);
end

function testFreshCompleteRunFixture(testCase)
    root = tempname;
    mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
    opts = small_fixture_opts(root, 'tm_fresh');
    [result, run_dir] = run_temporal_memory_development_diagnostics(opts);
    testCase.verifyEqual(result.status, 'complete');
    testCase.verifyTrue(result.global_rng_restored);
    testCase.verifyFalse(result.publication_evidence);
    testCase.verifyFalse(result.publication_ready);
    testCase.verifyEqual(result.n_long_rows, 8 * 2 * 3);
    testCase.verifyEqual(result.n_summary_rows, 8 * 2);
    testCase.verifyEqual(result.n_control_long_rows, 2 * 3 + 3 * 2 * 3);
    testCase.verifyTrue(isfile(fullfile(run_dir, 'diagnostic_checkpoint.mat')));
    testCase.verifyTrue(isfile(fullfile(run_dir, 'temporal_memory_control_long_table.csv')));
    S = load(fullfile(run_dir, 'diagnostic_checkpoint.mat'), 'diagnostic_checkpoint');
    testCase.verifyEqual(S.diagnostic_checkpoint.status, 'complete');
    testCase.verifyEqual(numel(S.diagnostic_checkpoint.completed_cell_seed_keys), 16);
    testCase.verifyEqual(numel(S.diagnostic_checkpoint.completed_conventional_keys), 2);
    testCase.verifyTrue(S.diagnostic_checkpoint.completed_shared_task_controls);
end

function testInterruptedRunAndResume(testCase)
    root = tempname;
    mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
    opts = small_fixture_opts(root, 'tm_resume');
    [~, run_dir] = run_temporal_memory_development_diagnostics(opts);

    % Downgrade checkpoint to running and drop one cell key to simulate interrupt
    S = load(fullfile(run_dir, 'diagnostic_checkpoint.mat'), 'diagnostic_checkpoint');
    cp = S.diagnostic_checkpoint;
    drop_key = cp.completed_cell_seed_keys{end};
    cp.completed_keys = cp.completed_keys(~strcmp(cp.completed_keys, drop_key));
    cp.completed_cell_seed_keys = cp.completed_cell_seed_keys( ...
        ~strcmp(cp.completed_cell_seed_keys, drop_key));
    field = regexprep(drop_key, '[^A-Za-z0-9]', '_');
    if isfield(cp.result_hashes, field)
        cp.result_hashes = rmfield(cp.result_hashes, field);
    end
    cp.status = 'running';
    write_temporal_memory_development_checkpoint(run_dir, cp);
    delete(fullfile(run_dir, 'seed_cell_results', cell_file_from_key(drop_key)));
    % Remove final artifacts so resume rewrites them
    arts = {'diagnostic_result.mat', 'diagnostic_manifest.mat', ...
        'diagnostic_manifest.json', 'temporal_memory_long_table.mat', ...
        'temporal_memory_long_table.csv', 'temporal_memory_summary_table.mat', ...
        'temporal_memory_summary_table.csv', 'temporal_memory_contrast_table.mat', ...
        'temporal_memory_contrast_table.csv', ...
        'temporal_memory_control_long_table.mat', ...
        'temporal_memory_control_long_table.csv', 'control_summary.mat'};
    for i = 1:numel(arts)
        p = fullfile(run_dir, arts{i});
        if isfile(p); delete(p); end
    end

    opts2 = opts;
    opts2.resume_run_dir = run_dir;
    opts2 = rmfield(opts2, 'run_id');
    [result2, run_dir2] = run_temporal_memory_development_diagnostics(opts2);
    testCase.verifyEqual(run_dir2, run_dir);
    testCase.verifyEqual(result2.status, 'complete');
    testCase.verifyEqual(result2.n_long_rows, 48);
    S2 = load(fullfile(run_dir, 'diagnostic_checkpoint.mat'), 'diagnostic_checkpoint');
    testCase.verifyEqual(numel(S2.diagnostic_checkpoint.completed_cell_seed_keys), 16);
end

function testDuplicateCheckpointKeyRejection(testCase)
    root = tempname;
    mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
    opts = small_fixture_opts(root, 'tm_dup');
    [~, run_dir] = run_temporal_memory_development_diagnostics(opts);
    S = load(fullfile(run_dir, 'diagnostic_checkpoint.mat'), 'diagnostic_checkpoint');
    cp = S.diagnostic_checkpoint;
    cp.completed_keys{end+1} = cp.completed_keys{1}; %#ok<AGROW>
    write_temporal_memory_development_checkpoint(run_dir, cp);
    cfg = load_effective_cfg_from_run(run_dir);
    testCase.verifyError(@() load_and_validate_temporal_memory_development_checkpoint( ...
        run_dir, cfg, git_head_sha_for_tests()), ...
        'load_and_validate_temporal_memory_development_checkpoint:DuplicateKey');
end

function testMissingRowRejection(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct('missing_row', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testProtocolMismatchRejection(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct( ...
        'protocol_mismatch', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testCommitMismatchRejection(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct( ...
        'commit_mismatch', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testReservedSeedRejection(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct( ...
        'reserved_seed', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testLongTableRowCountsSyntheticProductionShaped(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    Sl = load(fullfile(run_dir, 'temporal_memory_long_table.mat'), ...
        'temporal_memory_long_table');
    Ss = load(fullfile(run_dir, 'temporal_memory_summary_table.mat'), ...
        'temporal_memory_summary_table');
    Sc = load(fullfile(run_dir, 'temporal_memory_control_long_table.mat'), ...
        'temporal_memory_control_long_table');
    testCase.verifyEqual(height(Sl.temporal_memory_long_table), 1200);
    testCase.verifyEqual(height(Ss.temporal_memory_summary_table), 24);
    testCase.verifyEqual(height(Sc.temporal_memory_control_long_table), 550);
end

function testContrastSignArithmetic(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    Sct = load(fullfile(run_dir, 'temporal_memory_contrast_table.mat'), ...
        'temporal_memory_contrast_table');
    Ss = load(fullfile(run_dir, 'temporal_memory_summary_table.mat'), ...
        'temporal_memory_summary_table');
    T = Sct.temporal_memory_contrast_table;
    S = Ss.temporal_memory_summary_table;
    for i = 1:height(T)
        ref = S(strcmp(string(S.cell_name), string(T.reference_cell(i))) & ...
            S.model_seed == T.model_seed(i), :);
        ctrl = S(strcmp(string(S.cell_name), string(T.control_cell(i))) & ...
            S.model_seed == T.model_seed(i), :);
        testCase.verifyEqual(T.improvement_nrmse(i), ...
            ctrl.lag10_nrmse - ref.lag10_nrmse, 'AbsTol', 1e-12);
        testCase.verifyEqual(T.improvement_r2(i), ...
            ref.lag10_r2 - ctrl.lag10_r2, 'AbsTol', 1e-12);
        testCase.verifyEqual(T.improvement_MC_1_50(i), ...
            ref.memory_capacity_sum_lags_1_50 - ctrl.memory_capacity_sum_lags_1_50, ...
            'AbsTol', 1e-12);
        testCase.verifyEqual(T.improvement_MC_1_10(i), ...
            ref.memory_capacity_sum_lags_1_10 - ctrl.memory_capacity_sum_lags_1_10, ...
            'AbsTol', 1e-12);
        testCase.verifyEqual(T.improvement_MC_1_25(i), ...
            ref.memory_capacity_sum_lags_1_25 - ctrl.memory_capacity_sum_lags_1_25, ...
            'AbsTol', 1e-12);
    end
end

function testMatCsvAgreement(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_temporal_memory_development_diagnostics(run_dir, ...
        struct('throw_on_fail', false));
    names = cellfun(@(c) c.name, report.checks, 'UniformOutput', false);
    idx = find(strcmp(names, 'mat_csv_agreement'), 1);
    testCase.verifyFalse(isempty(idx));
    testCase.verifyTrue(report.checks{idx}.pass);
    testCase.verifyTrue(report.ok);
end

function testHashTamperingRejection(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct( ...
        'corrupt_hash', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testRngRestoration(testCase)
    root = tempname;
    mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
    opts = small_fixture_opts(root, 'tm_rng');
    rng(12345);
    entry_gs = RandStream.getGlobalStream();
    entry = entry_gs.State;
    [result, ~] = run_temporal_memory_development_diagnostics(opts);
    after_gs = RandStream.getGlobalStream();
    after = after_gs.State;
    testCase.verifyTrue(result.global_rng_restored);
    testCase.verifyEqual(after, entry);
end

function testScientificOverrideRejection(testCase)
    opts = struct('lags', 1:10);
    testCase.verifyError(@() run_temporal_memory_development_diagnostics(opts), ...
        'run_temporal_memory_development_diagnostics:ScientificOverrideForbidden');
    opts2 = struct('fixture', struct('lags', 1:3));
    testCase.verifyError(@() run_temporal_memory_development_diagnostics(opts2), ...
        'run_temporal_memory_development_diagnostics:ScientificOverrideForbidden');
    opts3 = struct('conventional_config', struct('x', 1));
    testCase.verifyError(@() run_temporal_memory_development_diagnostics(opts3), ...
        'run_temporal_memory_development_diagnostics:ScientificOverrideForbidden');
end

function testValidatorIndependence(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    % Mutate a local cfg copy; validator must ignore it and load frozen cfg
    cfg = temporal_memory_development_config();
    cfg.protocol_fingerprint = 'tampered';
    cfg.model_seeds = [1, 2, 3]; %#ok<NASGU>
    report = validate_temporal_memory_development_diagnostics(run_dir, ...
        struct('throw_on_fail', false));
    testCase.verifyTrue(report.ok);
    names = cellfun(@(c) c.name, report.checks, 'UniformOutput', false);
    fp_check = find(strcmp(names, 'protocol_fingerprint_match'), 1);
    testCase.verifyTrue(report.checks{fp_check}.pass);
end

function testPublicationReadinessCannotPass(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct( ...
        'publication_ready_true', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_temporal_memory_development_diagnostics(run_dir, ...
        struct('throw_on_fail', false));
    testCase.verifyFalse(report.ok);
    testCase.verifyFalse(report.publication_ready);
    testCase.verifyFalse(report.can_authorize_publication);
    testCase.verifyTrue(any(strcmp(report.failure_reasons, 'publication_ready_true')));
end

function testFixtureRejectedByProductionValidator(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct( ...
        'fixture_flag_true', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_temporal_memory_development_diagnostics(run_dir, ...
        struct('throw_on_fail', false));
    testCase.verifyFalse(report.ok);
    testCase.verifyTrue(any(strcmp(report.failure_reasons, ...
        'fixture_or_synthetic_provenance')));
end

function testCellSemanticHashBindsUnboundFields(testCase)
    % DEFECT 1 regression: R2, lambda, rank, norm, MC_1_25, PR, rate, Win must bind.
    cfg = testCase.TestData.cfg;
    cell_spec = cfg.diagnostic_cells.reference_r;
    base = synthesize_minimal_cell(cfg, cell_spec, 1729);
    h0 = temporal_memory_seed_result_content_hash(base);
    cases = { ...
        'r2', @mutate_r2; ...
        'lambda', @mutate_lambda; ...
        'rank', @mutate_rank; ...
        'cnorm', @mutate_cnorm; ...
        'mc125', @mutate_mc125; ...
        'pr', @mutate_pr; ...
        'rate', @mutate_rate; ...
        'win', @mutate_win; ...
        'whash', @mutate_w_hash};
    for i = 1:size(cases, 1)
        mut = cases{i, 2};
        h1 = temporal_memory_seed_result_content_hash(mut(base));
        testCase.verifyNotEqual(h0, h1, cases{i, 1});
    end
end

function testWinInHashConsistencyRequired(testCase)
    cfg = testCase.TestData.cfg;
    base = synthesize_minimal_cell(cfg, cfg.diagnostic_cells.reference_r, 1729);
    base.W_in = rand(4, 1);
    base.W_in_hash = canonical_sha256(base.W_in);
    temporal_memory_seed_result_content_hash(base);
    bad = base;
    bad.W_in = bad.W_in + 1;
    testCase.verifyError(@() temporal_memory_seed_result_content_hash(bad), ...
        'temporal_memory_seed_result_content_hash:WinHashMismatch');
end

function testWHashConsistencyRequired(testCase)
    cfg = testCase.TestData.cfg;
    base = synthesize_minimal_cell(cfg, cfg.diagnostic_cells.reference_r, 1729);
    base.W = eye(4);
    base.W_hash = canonical_sha256(base.W);
    temporal_memory_seed_result_content_hash(base);
    bad = base;
    bad.W = bad.W * 2;
    testCase.verifyError(@() temporal_memory_seed_result_content_hash(bad), ...
        'temporal_memory_seed_result_content_hash:WHashMismatch');
end

function testConventionalSemanticHashBindsUnboundFields(testCase)
    cfg = testCase.TestData.cfg;
    b0 = synthesize_minimal_conventional(cfg, 1729);
    h0 = temporal_memory_conventional_bundle_content_hash(b0);
    b = b0; b.per_lag(1).selected_lambda = 1;
    testCase.verifyNotEqual(h0, temporal_memory_conventional_bundle_content_hash(b));
    b = b0; b.candidate_selection_table(1).aggregate_validation_nrmse = 9;
    testCase.verifyNotEqual(h0, temporal_memory_conventional_bundle_content_hash(b));
    b = b0; b.Wres = 2 * eye(size(b0.Wres));
    testCase.verifyNotEqual(h0, temporal_memory_conventional_bundle_content_hash(b));
end

function testTamperCellR2Rejected(testCase)
    assert_cell_field_tamper_rejected(@mutate_r2, testCase);
end

function testTamperCellSelectedLambdaRejected(testCase)
    assert_cell_field_tamper_rejected(@mutate_lambda, testCase);
end

function testTamperFeatureParticipationRatioRejected(testCase)
    assert_cell_field_tamper_rejected(@mutate_pr, testCase);
end

function testTamperActivityMeanRateRejected(testCase)
    assert_cell_field_tamper_rejected(@mutate_rate, testCase);
end

function testTamperWinHashRejected(testCase)
    assert_cell_field_tamper_rejected(@mutate_win, testCase);
end

function testTamperConventionalSelectedLambdaRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    seed = testCase.TestData.cfg.model_seeds(1);
    path = fullfile(run_dir, 'shared', 'conventional', sprintf('seed_%d_conventional.mat', seed));
    S = load(path, 'conventional_bundle');
    b = S.conventional_bundle;
    b.per_lag(1).selected_lambda = 42;
    conventional_bundle = b; %#ok<NASGU>
    save(path, 'conventional_bundle');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperConventionalCandidateTableRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    seed = testCase.TestData.cfg.model_seeds(1);
    path = fullfile(run_dir, 'shared', 'conventional', sprintf('seed_%d_conventional.mat', seed));
    S = load(path, 'conventional_bundle');
    b = S.conventional_bundle;
    b.candidate_selection_table(1).aggregate_validation_nrmse = 123;
    conventional_bundle = b; %#ok<NASGU>
    save(path, 'conventional_bundle');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperConventionalWresRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    seed = testCase.TestData.cfg.model_seeds(1);
    path = fullfile(run_dir, 'shared', 'conventional', sprintf('seed_%d_conventional.mat', seed));
    S = load(path, 'conventional_bundle');
    b = S.conventional_bundle;
    b.Wres = b.Wres * 3;
    conventional_bundle = b; %#ok<NASGU>
    save(path, 'conventional_bundle');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperNoRecurrentMetricsRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    seed = testCase.TestData.cfg.model_seeds(1);
    path = fullfile(run_dir, 'shared', 'reference_controls', ...
        sprintf('seed_%d_no_recurrent.mat', seed));
    S = load(path, 'no_recurrent_control');
    c = S.no_recurrent_control;
    c.per_lag(1).metrics.nrmse = c.per_lag(1).metrics.nrmse + 1;
    no_recurrent_control = c; %#ok<NASGU>
    save(path, 'no_recurrent_control');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperShuffledMetricsRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    seed = testCase.TestData.cfg.model_seeds(1);
    path = fullfile(run_dir, 'shared', 'reference_controls', ...
        sprintf('seed_%d_shuffled_target.mat', seed));
    S = load(path, 'shuffled_target_control');
    c = S.shuffled_target_control;
    c.per_lag(1).metrics.r2 = c.per_lag(1).metrics.r2 + 0.5;
    shuffled_target_control = c; %#ok<NASGU>
    save(path, 'shuffled_target_control');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperSharedTaskControlsRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    path = fullfile(run_dir, 'shared', 'task_controls.mat');
    S = load(path, 'task_controls');
    t = S.task_controls;
    t.current_input_only.per_lag(1).metrics.nrmse = 9;
    task_controls = t; %#ok<NASGU>
    save(path, 'task_controls');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperSavedDiagnosticConfigRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    path = fullfile(run_dir, 'diagnostic_config.mat');
    S = load(path, 'diagnostic_config');
    cfg = S.diagnostic_config;
    cfg.lags = cfg.lags(1:10);
    diagnostic_config = cfg; %#ok<NASGU>
    save(path, 'diagnostic_config');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperDiagnosticResultRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    path = fullfile(run_dir, 'diagnostic_result.mat');
    S = load(path, 'diagnostic_result');
    r = S.diagnostic_result;
    r.n_long_rows = r.n_long_rows - 1;
    diagnostic_result = r; %#ok<NASGU>
    save(path, 'diagnostic_result');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperControlSummaryRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    path = fullfile(run_dir, 'control_summary.mat');
    S = load(path, 'control_summary');
    cs = S.control_summary;
    cs.allocation.conventional_fits = 99;
    control_summary = cs; %#ok<NASGU>
    save(path, 'control_summary');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperManifestMatRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    path = fullfile(run_dir, 'diagnostic_manifest.mat');
    S = load(path, 'diagnostic_manifest');
    m = S.diagnostic_manifest;
    m.row_counts.long_table = 1;
    diagnostic_manifest = m; %#ok<NASGU>
    save(path, 'diagnostic_manifest');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperManifestJsonRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    jpath = fullfile(run_dir, 'diagnostic_manifest.json');
    J = jsondecode(fileread(jpath));
    J.row_counts.long_table = 7;
    fid = fopen(jpath, 'w'); fprintf(fid, '%s', jsonencode(J)); fclose(fid);
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperCsvStringCellNameRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    csv_path = fullfile(run_dir, 'temporal_memory_long_table.csv');
    T = readtable(csv_path);
    if iscell(T.cell_name)
        T.cell_name{1} = 'tampered_cell';
    else
        T.cell_name(1) = "tampered_cell";
    end
    writetable(T, csv_path);
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperCsvNumericMetricRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    csv_path = fullfile(run_dir, 'temporal_memory_long_table.csv');
    T = readtable(csv_path);
    T.held_out_nrmse(1) = T.held_out_nrmse(1) + 1;
    writetable(T, csv_path);
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testMissingRegistryEntryRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    Sm = load(fullfile(run_dir, 'diagnostic_manifest.mat'), 'diagnostic_manifest');
    m = Sm.diagnostic_manifest;
    m.artifact_registry.entries(1) = [];
    m.artifact_registry.n_entries = numel(m.artifact_registry.entries);
    m.artifact_registry.registry_content_hash = '0';
    diagnostic_manifest = m; %#ok<NASGU>
    save(fullfile(run_dir, 'diagnostic_manifest.mat'), 'diagnostic_manifest');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testDuplicateRegistryEntryRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    Sm = load(fullfile(run_dir, 'diagnostic_manifest.mat'), 'diagnostic_manifest');
    m = Sm.diagnostic_manifest;
    m.artifact_registry.entries(end+1) = m.artifact_registry.entries(1);
    diagnostic_manifest = m; %#ok<NASGU>
    save(fullfile(run_dir, 'diagnostic_manifest.mat'), 'diagnostic_manifest');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testUnknownCompletedCheckpointKeyRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    S = load(fullfile(run_dir, 'diagnostic_checkpoint.mat'), 'diagnostic_checkpoint');
    cp = S.diagnostic_checkpoint;
    cp.completed_keys{end+1} = 'cell:not_a_real_cell|seed:1729'; %#ok<AGROW>
    write_temporal_memory_development_checkpoint(run_dir, cp);
    cfg = load_effective_cfg_from_run(run_dir);
    testCase.verifyError(@() load_and_validate_temporal_memory_development_checkpoint( ...
        run_dir, cfg, git_head_sha_for_tests()), ...
        'load_and_validate_temporal_memory_development_checkpoint:UnknownKey');
end

function testMissingExpectedCheckpointKeyRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    S = load(fullfile(run_dir, 'diagnostic_checkpoint.mat'), 'diagnostic_checkpoint');
    cp = S.diagnostic_checkpoint;
    drop = cp.completed_keys{1};
    cp.completed_keys = cp.completed_keys(~strcmp(cp.completed_keys, drop));
    cp.completed_keys{end+1} = cp.completed_keys{1}; %#ok<AGROW>
    write_temporal_memory_development_checkpoint(run_dir, cp);
    cfg = load_effective_cfg_from_run(run_dir);
    testCase.verifyError(@() load_and_validate_temporal_memory_development_checkpoint( ...
        run_dir, cfg, git_head_sha_for_tests()), ...
        'load_and_validate_temporal_memory_development_checkpoint:DuplicateKey');
end

function testCompletedRunFinalTableTamperingRejected(testCase)
    root = tempname;
    mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
    opts = small_fixture_opts(root, 'tm_complete_tamper');
    [~, run_dir] = run_temporal_memory_development_diagnostics(opts);
    path = fullfile(run_dir, 'temporal_memory_long_table.mat');
    S = load(path, 'temporal_memory_long_table');
    T = S.temporal_memory_long_table;
    T.held_out_r2(1) = T.held_out_r2(1) + 1;
    temporal_memory_long_table = T; %#ok<NASGU>
    delete(path);
    save(path, 'temporal_memory_long_table');
    opts2 = opts;
    opts2.resume_run_dir = run_dir;
    opts2 = rmfield(opts2, 'run_id');
    testCase.verifyError(@() run_temporal_memory_development_diagnostics(opts2), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testIncorrectMC125ContrastArithmeticRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    path = fullfile(run_dir, 'temporal_memory_contrast_table.mat');
    S = load(path, 'temporal_memory_contrast_table');
    T = S.temporal_memory_contrast_table;
    T.improvement_MC_1_25(1) = T.improvement_MC_1_25(1) + 1;
    temporal_memory_contrast_table = T; %#ok<NASGU>
    delete(path);
    save(path, 'temporal_memory_contrast_table');
    writetable(T, fullfile(run_dir, 'temporal_memory_contrast_table.csv'));
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testSyntheticProvenanceAsProductionRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct( ...
        'fixture_flag_true', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    report = validate_temporal_memory_development_diagnostics(run_dir, ...
        struct('throw_on_fail', false));
    testCase.verifyFalse(report.ok);
end

function testPublicationEvidenceFlagInjectionRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    path = fullfile(run_dir, 'diagnostic_result.mat');
    S = load(path, 'diagnostic_result');
    r = S.diagnostic_result;
    r.publication_evidence = true;
    diagnostic_result = r; %#ok<NASGU>
    save(path, 'diagnostic_result');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testOneConventionalFitPerSeed(testCase)
    root = tempname;
    mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
    opts = small_fixture_opts(root, 'tm_conv_once');
    [~, run_dir] = run_temporal_memory_development_diagnostics(opts);
    conv = dir(fullfile(run_dir, 'shared', 'conventional', 'seed_*_conventional.mat'));
    testCase.verifyEqual(numel(conv), 2);
    cells = dir(fullfile(run_dir, 'seed_cell_results', 'seed_*.mat'));
    for i = 1:numel(cells)
        S = load(fullfile(cells(i).folder, cells(i).name), 'seed_cell_result');
        testCase.verifyFalse(isfield(S.seed_cell_result, 'conventional_bundle'));
        testCase.verifyFalse(isfield(S.seed_cell_result, 'n_candidates'));
    end
end

function testRegistryReconstructableAfterWriterPath(testCase)
    % Regression for checkpoint-status registry mismatch (Phase 5D-B2-R2).
    root = tempname;
    mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
    opts = small_fixture_opts(root, 'tm_registry_rebuild');
    [~, run_dir] = run_temporal_memory_development_diagnostics(opts);
    cfg = load_effective_cfg_from_run(run_dir);
    Sm = load(fullfile(run_dir, 'diagnostic_manifest.mat'), 'diagnostic_manifest');
    stored = Sm.diagnostic_manifest.artifact_registry;
    fresh = build_temporal_memory_artifact_registry(run_dir, cfg);
    testCase.verifyFalse(isfield(stored, 'checkpoint_status'));
    testCase.verifyEqual(stored.n_entries, expected_temporal_memory_registry_entry_count(cfg));
    testCase.verifyEqual(char(stored.registry_content_hash), char(fresh.registry_content_hash));
    validate_temporal_memory_artifact_registry(stored, run_dir, cfg, ...
        temporal_memory_expected_checkpoint_keys(cfg));
end

function testCheckpointStatusDoesNotChangeRegistryIdentity(testCase)
    root = tempname;
    mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
    opts = small_fixture_opts(root, 'tm_ck_status');
    [~, run_dir] = run_temporal_memory_development_diagnostics(opts);
    cfg = load_effective_cfg_from_run(run_dir);
    before = build_temporal_memory_artifact_registry(run_dir, cfg);
    S = load(fullfile(run_dir, 'diagnostic_checkpoint.mat'), 'diagnostic_checkpoint');
    cp = S.diagnostic_checkpoint;
    cp.status = 'running';
    write_temporal_memory_development_checkpoint(run_dir, cp);
    after = build_temporal_memory_artifact_registry(run_dir, cfg);
    testCase.verifyEqual(char(before.registry_content_hash), char(after.registry_content_hash));
    testCase.verifyEqual(before.n_entries, after.n_entries);
end

function testFirstExecutionValidatesBeforeReturn(testCase)
    root = tempname;
    mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
    opts = small_fixture_opts(root, 'tm_first_validate');
    [result, run_dir] = run_temporal_memory_development_diagnostics(opts);
    testCase.verifyEqual(result.status, 'complete');
    report = validate_temporal_memory_development_diagnostics(run_dir, ...
        struct('allow_test_fixture', true, 'cfg_override', load_effective_cfg_from_run(run_dir), ...
        'throw_on_fail', false));
    testCase.verifyTrue(report.ok);
end

function testCompletedResumeValidatesBeforeReturn(testCase)
    root = tempname;
    mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
    opts = small_fixture_opts(root, 'tm_resume_validate');
    [~, run_dir] = run_temporal_memory_development_diagnostics(opts);
    Sm = load(fullfile(run_dir, 'diagnostic_manifest.mat'), 'diagnostic_manifest');
    before_hash = char(Sm.diagnostic_manifest.artifact_registry.registry_content_hash);
    opts2 = opts;
    opts2.resume_run_dir = run_dir;
    opts2 = rmfield(opts2, 'run_id');
    [result2, ~] = run_temporal_memory_development_diagnostics(opts2);
    testCase.verifyEqual(result2.status, 'complete');
    Sm2 = load(fullfile(run_dir, 'diagnostic_manifest.mat'), 'diagnostic_manifest');
    after_hash = char(Sm2.diagnostic_manifest.artifact_registry.registry_content_hash);
    testCase.verifyEqual(before_hash, after_hash);
end

function testTamperJsonRegistryEntryRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    jpath = fullfile(run_dir, 'diagnostic_manifest.json');
    J = jsondecode(fileread(jpath));
    old_hash = J.artifact_registry.registry_content_hash;
    J.artifact_registry.entries(1).binary_sha256 = repmat('a', 1, 64);
  % leave registry_content_hash unchanged
    fid = fopen(jpath, 'w'); fprintf(fid, '%s', jsonencode(J)); fclose(fid);
    testCase.verifyEqual(J.artifact_registry.registry_content_hash, old_hash);
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperJsonRegistryDeletedEntryRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    jpath = fullfile(run_dir, 'diagnostic_manifest.json');
    J = jsondecode(fileread(jpath));
    J.artifact_registry.entries(1) = [];
    J.artifact_registry.n_entries = numel(J.artifact_registry.entries);
    fid = fopen(jpath, 'w'); fprintf(fid, '%s', jsonencode(J)); fclose(fid);
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperJsonRegistryDuplicatedEntryRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    jpath = fullfile(run_dir, 'diagnostic_manifest.json');
    J = jsondecode(fileread(jpath));
    J.artifact_registry.entries = [J.artifact_registry.entries; J.artifact_registry.entries(1)];
    J.artifact_registry.n_entries = numel(J.artifact_registry.entries);
    fid = fopen(jpath, 'w'); fprintf(fid, '%s', jsonencode(J)); fclose(fid);
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperJsonRegistryReorderedEntryRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    jpath = fullfile(run_dir, 'diagnostic_manifest.json');
    J = jsondecode(fileread(jpath));
    if numel(J.artifact_registry.entries) < 2
        testCase.assumeFail('Need at least two registry entries.');
    end
    entries = J.artifact_registry.entries;
    entries = [entries(2); entries(1); entries(3:end)];
    J.artifact_registry.entries = entries;
    fid = fopen(jpath, 'w'); fprintf(fid, '%s', jsonencode(J)); fclose(fid);
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperJsonRegistryBinaryHashRejected(testCase)
    assert_json_registry_field_tamper_rejected(testCase, 'binary_sha256', repmat('c', 1, 64));
end

function testTamperJsonRegistryRoleRejected(testCase)
    assert_json_registry_field_tamper_rejected(testCase, 'artifact_role', 'tampered_role');
end

function testTamperJsonRegistrySemanticHashRejected(testCase)
    assert_json_registry_field_tamper_rejected(testCase, 'semantic_content_hash', ...
        repmat('b', 1, 64));
end

function testTamperJsonRegistryCheckpointKeyRejected(testCase)
    assert_json_registry_field_tamper_rejected(testCase, 'producing_checkpoint_key', ...
        'cell:tampered|seed:9999');
end

function testTamperWinMatrixWithUnchangedHashRejected(testCase)
    cfg = testCase.TestData.cfg;
    base = synthesize_minimal_cell(cfg, cfg.diagnostic_cells.reference_r, 1729);
    base.W_in = rand(4, 1);
    base.W_in_hash = canonical_sha256(base.W_in);
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    seed = cfg.model_seeds(1);
    cell_name = char(cfg.diagnostic_cell_names{1});
    path = fullfile(run_dir, 'seed_cell_results', sprintf('seed_%d__%s.mat', seed, cell_name));
    bad = base;
    bad.W_in = bad.W_in + 0.01;
    seed_cell_result = bad; %#ok<NASGU>
    save(path, 'seed_cell_result');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testTamperWhashRejected(testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = testCase.TestData.cfg;
    cell_name = cfg.diagnostic_cell_names{1};
    seed = cfg.model_seeds(1);
    path = fullfile(run_dir, 'seed_cell_results', sprintf('seed_%d__%s.mat', seed, cell_name));
    S = load(path, 'seed_cell_result');
    scored = S.seed_cell_result;
    h = char(scored.W_in_hash);
    if h(1) == '0'
        h(1) = 'f';
    else
        h(1) = '0';
    end
    scored.W_in_hash = h;
    seed_cell_result = scored; %#ok<NASGU>
    save(path, 'seed_cell_result');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function testProductionRegistryEntryCount(testCase)
    cfg = testCase.TestData.cfg;
    testCase.verifyEqual(expected_temporal_memory_registry_entry_count(cfg), 46);
end

function testProtocolFingerprintUnchanged(testCase)
    cfg = temporal_memory_development_config();
    testCase.verifyEqual(char(cfg.protocol_fingerprint), ...
        'bb3ac4fe71985a156c519f1065b99fb1ff3c1c22ae8bc139c46f43cce4a93310');
end

function testTemporalLearningGateUnchanged(testCase)
    repo = testCase.TestData.repo_root;
    gate_files = { ...
        fullfile(repo, 'experiments', 'revalidated', 'evaluate_temporal_learning_gate.m'); ...
        fullfile(repo, 'experiments', 'revalidated', 'fit_temporal_learning_gate_seed.m')};
    for i = 1:numel(gate_files)
        testCase.verifyTrue(isfile(gate_files{i}), gate_files{i});
    end
end

function assert_json_registry_field_tamper_rejected(testCase, field_name, new_value)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    jpath = fullfile(run_dir, 'diagnostic_manifest.json');
    J = jsondecode(fileread(jpath));
    J.artifact_registry.entries(1).(field_name) = new_value;
    fid = fopen(jpath, 'w'); fprintf(fid, '%s', jsonencode(J)); fclose(fid);
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function assert_cell_field_tamper_rejected(mut_fn, testCase)
    run_dir = make_synthetic_temporal_memory_diagnostic_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = testCase.TestData.cfg;
    cell_name = cfg.diagnostic_cell_names{1};
    seed = cfg.model_seeds(1);
    path = fullfile(run_dir, 'seed_cell_results', ...
        sprintf('seed_%d__%s.mat', seed, cell_name));
    S = load(path, 'seed_cell_result');
    scored = mut_fn(S.seed_cell_result);
    seed_cell_result = scored; %#ok<NASGU>
    save(path, 'seed_cell_result');
    testCase.verifyError(@() validate_temporal_memory_development_diagnostics(run_dir), ...
        'validate_temporal_memory_development_diagnostics:Failed');
end

function scored = mutate_r2(scored)
    idx = min(10, numel(scored.per_lag));
    scored.per_lag(idx).metrics.r2 = scored.per_lag(idx).metrics.r2 + 0.11;
end

function scored = mutate_lambda(scored)
    scored.per_lag(1).selected_lambda = 1;
end

function scored = mutate_rank(scored)
    scored.per_lag(1).numerical_rank = scored.per_lag(1).numerical_rank + 3;
end

function scored = mutate_cnorm(scored)
    scored.per_lag(1).coefficient_norm = scored.per_lag(1).coefficient_norm + 2;
end

function scored = mutate_mc125(scored)
    scored.summary.MC_1_25 = scored.summary.MC_1_25 + 1;
    scored.summary.memory_capacity_sum_lags_1_25 = scored.summary.MC_1_25;
end

function scored = mutate_pr(scored)
    scored.feature_diagnostics.participation_ratio = ...
        scored.feature_diagnostics.participation_ratio + 1;
    scored.feature_diagnostics.feature_participation_ratio = ...
        scored.feature_diagnostics.participation_ratio;
end

function scored = mutate_rate(scored)
    scored.feature_diagnostics.mean_firing_rate = ...
        scored.feature_diagnostics.mean_firing_rate + 0.2;
end

function scored = mutate_win(scored)
    h = char(scored.W_in_hash);
    if h(1) == '0'
        h(1) = 'f';
    else
        h(1) = '0';
    end
    scored.W_in_hash = h;
end

function scored = mutate_w_hash(scored)
    scored.W_hash = repmat('c', 1, 64);
end

function scored = synthesize_minimal_cell(cfg, cell_spec, seed)
    lags = cfg.lags(:);
    n = min(3, numel(lags));
    lags = lags(1:n);
    per_lag = repmat(struct('lag', NaN, 'selected_lambda', 1e-6, ...
        'selected_at_grid_boundary', false, 'numerical_rank', 4, ...
        'coefficient_norm', 1, 'intercept', 0, 'coefficients', [1; 0.5], ...
        'feature_mean', [0 0], 'feature_scale', [1 1], ...
        'lambda_selection_table', struct('lambda', 1e-6), 'metrics', struct()), n, 1);
    mc = zeros(n, 1);
    lag_metrics = repmat(struct('nrmse', NaN, 'r2', NaN, 'pearson', NaN, ...
        'memory_coefficient', NaN, 'rmse', NaN, 'constant_prediction', false), n, 1);
    for i = 1:n
        m = struct('nrmse', 0.4, 'r2', 0.8, 'pearson', sqrt(0.8), ...
            'memory_coefficient', 0.8, 'rmse', 0.2, 'constant_prediction', false);
        per_lag(i).lag = lags(i);
        per_lag(i).metrics = m;
        mc(i) = m.memory_coefficient;
        lag_metrics(i) = m;
    end
    scored = struct();
    scored.model_seed = seed;
    scored.cell_name = char(cell_spec.diagnostic_name);
    scored.cell_key = char(cell_spec.cell_key);
    scored.feature_mode = 'r';
    scored.feature_dimension = 40;
    scored.include_input = false;
    scored.simulations_per_split = 1;
    scored.n_reservoir_simulations = 3;
    scored.global_rng_unchanged = true;
    scored.lags = lags;
    scored.per_lag = per_lag;
    scored.summary = summarize_temporal_memory_curve(lags, mc, lag_metrics);
    scored.feature_diagnostics = struct('numerical_rank', 4, 'rank_tolerance', 1e-12, ...
        'participation_ratio', 3, 'feature_participation_ratio', 3, ...
        'fraction_numerically_near_constant_features', 0.01, ...
        'mean_feature_standard_deviation', 0.2, 'median_feature_standard_deviation', 0.2, ...
        'median_absolute_offdiag_feature_correlation', 0.1, ...
        'maximum_absolute_offdiag_feature_correlation', 0.3, ...
        'mean_firing_rate', 0.4, 'saturation_fraction', 0.05, 'silence_fraction', 0.05, ...
        'n_neurons', 40, 'packed_state_dimension', 40, 'activity_from_neuronal_rates', true, ...
        'packed_states_counted_as_neurons', false);
    scored.W_in_hash = canonical_sha256(struct('seed', seed));
    scored.provenance = 'production';
end

function b = synthesize_minimal_conventional(cfg, seed) %#ok<INUSD>
    lags = (1:3)';
    n = numel(lags);
    sel = 1;
    hyp = struct('spectral_radius', 0.9, 'leak_rate', 0.5, 'input_scaling', 1);
    per_lag = repmat(struct('lag', NaN, 'selected_candidate_index', sel, ...
        'selected_lambda', 1e-6, 'hyperparameters', hyp, 'numerical_rank', 4, ...
        'coefficient_norm', 1, 'intercept', 0, 'coefficients', [1; 0.5], ...
        'feature_mean', [0 0], 'feature_scale', [1 1], 'metrics', struct()), n, 1);
    for i = 1:n
        per_lag(i).lag = lags(i);
        per_lag(i).metrics = struct('nrmse', 0.5, 'r2', 0.6, 'pearson', sqrt(0.6), ...
            'memory_coefficient', 0.6, 'rmse', 0.3);
    end
    b = struct();
    b.model_seed = seed;
    b.protocol_version = 'matched_conventional_memory_curve_v1';
    b.engine = 'run_conventional_leaky_esn';
    b.candidate_grid_source = 'build_matched_task_baselines_config';
    b.n_candidates = 3;
    b.reservoir_seed = seed + 2000;
    b.selection_metric = 'mean_validation_nrmse_over_all_preregistered_lags';
    b.selection_lags = lags;
    b.tie_tolerance = 1e-12;
    b.tie_break = 'earliest_candidate_in_frozen_order';
    b.execution_scope = 'once_per_model_seed_shared_across_all_diagnostic_cells';
    b.selected_candidate_index = sel;
    b.selected_hyperparameters = hyp;
    b.selected_candidate_content_hash = canonical_sha256(struct('sel', sel));
    b.same_reservoir_for_all_lags = true;
    b.test_targets_used_for_selection = false;
    b.test_targets_used_for_fitting = false;
    b.used_narma_orchestrator = false;
    b.used_mackey_glass_orchestrator = false;
    b.provenance = 'production';
    b.is_test_fixture = false;
    b.lags = lags;
    b.per_lag = per_lag;
    b.candidate_selection_table = struct('candidate_index', {1, 2, 3}, ...
        'aggregate_validation_nrmse', {0.1, 0.2, 0.3}, ...
        'selected_candidate', {true, false, false});
    b.aggregate_validation_nrmse = [0.1; 0.2; 0.3];
    b.per_candidate_per_lag_validation_nrmse = zeros(3, n);
    b.Wres = eye(2);
    b.Win = ones(2, 1);
    b.X_test = zeros(4, 2);
    b.summary = summarize_temporal_memory_curve(lags, [0.6; 0.6; 0.6], [per_lag.metrics]);
end

%% helpers
function name = cell_file_from_key(key)
    tok = regexp(key, '^cell:([^|]+)\|seed:(\d+)$', 'tokens', 'once');
    name = sprintf('seed_%s__%s.mat', tok{2}, tok{1});
end

function cfg = load_effective_cfg_from_run(run_dir)
    S = load(fullfile(run_dir, 'diagnostic_config.mat'), 'diagnostic_config');
    cfg = S.diagnostic_config;
end
