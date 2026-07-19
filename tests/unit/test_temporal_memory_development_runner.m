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

%% helpers
function name = cell_file_from_key(key)
    tok = regexp(key, '^cell:([^|]+)\|seed:(\d+)$', 'tokens', 'once');
    name = sprintf('seed_%s__%s.mat', tok{2}, tok{1});
end

function cfg = load_effective_cfg_from_run(run_dir)
    S = load(fullfile(run_dir, 'diagnostic_config.mat'), 'diagnostic_config');
    cfg = S.diagnostic_config;
end
