function tests = test_protocol_fingerprint
% test_protocol_fingerprint  Deterministic MESN protocol identity hashing.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    testCase.TestData.repo_root = repo_root;
end

function testSmokeNeverPublicationReady(testCase)
    cfg = mechanism_ablation_config('smoke');
    testCase.verifyEqual(cfg.protocol_tier, 'smoke');
    testCase.verifyTrue(cfg.pilot_not_for_publication);

    records = synthetic_full_grid(cfg, struct('finite', true));
    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', records, ...
        'has_manifest', true, ...
        'has_commit_sha', true, ...
        'has_artifact_hashes', true));
    testCase.verifyFalse(report.publication_protocol_complete);
    testCase.verifyFalse(report.publication_ready);
end

function testPilotNeverPublicationReady(testCase)
    cfg = mechanism_ablation_config('pilot');
    testCase.verifyEqual(cfg.protocol_tier, 'pilot');
    records = synthetic_full_grid(cfg, struct('finite', true));
    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', records, ...
        'has_manifest', true, ...
        'has_commit_sha', true, ...
        'has_artifact_hashes', true));
    testCase.verifyFalse(report.publication_ready);
end

function testFullAliasIsPublication(testCase)
    cfg_full = mechanism_ablation_config('full');
    cfg_pub = mechanism_ablation_config('publication');
    testCase.verifyEqual(cfg_full.protocol_tier, 'publication');
    testCase.verifyEqual(cfg_full.protocol_fingerprint, cfg_pub.protocol_fingerprint);
end

function testChangingPublicationLengthChangesFingerprint(testCase)
    cfg_a = mechanism_ablation_config('publication');
    cfg_b = mechanism_ablation_config('publication');
    cfg_b.lengths.narma_T = cfg_b.lengths.narma_T + 1;
    fp_b = compute_protocol_fingerprint(cfg_b);
    testCase.verifyNotEqual(cfg_a.protocol_fingerprint, fp_b);
end

function testTimestampsDoNotChangeFingerprint(testCase)
    cfg_a = mechanism_ablation_config('publication');
    cfg_b = mechanism_ablation_config('publication');
    cfg_b.created_utc = '2099-01-01T00:00:00Z';
    testCase.verifyNotEqual(cfg_a.created_utc, cfg_b.created_utc);
    testCase.verifyEqual(cfg_a.protocol_fingerprint, ...
        compute_protocol_fingerprint(cfg_b));
end

function testFingerprintIgnoresStoredFingerprintField(testCase)
    cfg = mechanism_ablation_config('publication');
    cfg2 = cfg;
    cfg2.protocol_fingerprint = 'deadbeef';
    testCase.verifyEqual( ...
        compute_protocol_fingerprint(cfg), ...
        compute_protocol_fingerprint(cfg2));
end

function testFunctionHandleCanonicalizedByName(testCase)
    cfg = mechanism_ablation_config('smoke');
    testCase.verifyTrue(isa(cfg.lengths.ode_solver, 'function_handle'));
    fp1 = compute_protocol_fingerprint(cfg);
    cfg.lengths.ode_solver = @ode45;
    fp2 = compute_protocol_fingerprint(cfg);
    testCase.verifyEqual(fp1, fp2);
end

function testThirtySmokeSeedsFailPublicationReadiness(testCase)
    % Even a structurally complete 30-seed reduced/smoke design cannot be ready.
    smoke = mechanism_ablation_config('smoke');
    pub = mechanism_ablation_config('publication');

    cfg = pub;
    cfg.lengths = smoke.lengths;
    cfg.base.n = smoke.base.n;
    cfg.secondary_enabled = false;
    cfg = force_smoke_protocol(cfg, ...
        'reduced_lengths_for_compute_feasibility_not_publication_inference');
    cfg.seeds = pub.full_seeds;  % keep 30 seeds
    cfg.n_seeds = numel(cfg.seeds);
    cfg.n_paired_runs = cfg.n_cells * cfg.n_seeds;
    cfg.protocol_fingerprint = compute_protocol_fingerprint(cfg);

    testCase.verifyEqual(numel(cfg.seeds), 30);
    testCase.verifyEqual(cfg.protocol_tier, 'smoke');

    records = synthetic_full_grid(cfg, struct('finite', true));
    testCase.verifyEqual(numel(records), 30 * cfg.n_cells);
    testCase.verifyEqual(cfg.n_cells, 24);

    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', records, ...
        'has_manifest', true, ...
        'has_commit_sha', true, ...
        'has_artifact_hashes', true));

    testCase.verifyTrue(report.structurally_complete, ...
        'Structural completeness may hold for 30-seed smoke fixtures.');
    testCase.verifyFalse(report.publication_protocol_complete);
    testCase.verifyFalse(report.publication_ready);
end

function testMissingWholeConditionDetected(testCase)
    cfg = mechanism_ablation_config('publication');
    records = synthetic_full_grid(cfg, struct('finite', true));
    drop_key = cfg.cells{1}.cell_key;
    keep = ~strcmp({records.cell_key}, drop_key);
    records = records(keep);

    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', records, ...
        'has_manifest', true, ...
        'has_commit_sha', true, ...
        'has_artifact_hashes', true));
    testCase.verifyFalse(check_pass(report, 'no_missing_whole_condition'));
    testCase.verifyFalse(report.structurally_complete);
    testCase.verifyFalse(report.publication_ready);
end

function testMissingWholeSeedDetected(testCase)
    cfg = mechanism_ablation_config('publication');
    records = synthetic_full_grid(cfg, struct('finite', true));
    drop_seed = cfg.seeds(1);
    keep = [records.base_seed] ~= drop_seed;
    records = records(keep);

    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', records, ...
        'has_manifest', true, ...
        'has_commit_sha', true, ...
        'has_artifact_hashes', true));
    testCase.verifyFalse(check_pass(report, 'no_missing_whole_seed'));
    testCase.verifyFalse(report.structurally_complete);
    testCase.verifyFalse(report.publication_ready);
end

function testDuplicateRowsDetected(testCase)
    cfg = mechanism_ablation_config('publication');
    records = synthetic_full_grid(cfg, struct('finite', true));
    records(end+1) = records(1); %#ok<AGROW>

    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', records, ...
        'has_manifest', true, ...
        'has_commit_sha', true, ...
        'has_artifact_hashes', true));
    testCase.verifyFalse(check_pass(report, 'no_duplicate_seed_condition_pairs'));
    testCase.verifyFalse(report.publication_ready);
end

function testNanPrimaryEndpointFailsReadiness(testCase)
    cfg = mechanism_ablation_config('publication');
    records = synthetic_full_grid(cfg, struct('finite', true));
    records(1).memory_capacity.MC_total = NaN;

    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', records, ...
        'has_manifest', true, ...
        'has_commit_sha', true, ...
        'has_artifact_hashes', true));
    testCase.verifyFalse(report.all_primary_endpoints_finite);
    testCase.verifyFalse(report.publication_ready);
end

function testValidatePublicationRunOnSyntheticDirectory(testCase)
    cfg = mechanism_ablation_config('publication');
    records = synthetic_full_grid(cfg, struct('finite', true));
    run_dir = make_synthetic_run_dir(cfg, records, true);
    cleaner = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>

    report = validate_publication_run(run_dir);
    testCase.verifyTrue(report.publication_protocol_complete);
    testCase.verifyTrue(report.structurally_complete);
    testCase.verifyTrue(report.all_primary_endpoints_finite);
    % Artifact hashes intentionally absent until Phase 9 export.
    testCase.verifyFalse(report.artifact_package_complete);
    testCase.verifyFalse(report.publication_ready);
end

function testReducedFullPathForcesSmokeFields(testCase)
    pub = mechanism_ablation_config('publication');
    smoke = mechanism_ablation_config('smoke');
    cfg = pub;
    cfg.lengths = smoke.lengths;
    cfg.base.n = smoke.base.n;
    cfg = force_smoke_protocol(cfg);
    testCase.verifyEqual(cfg.protocol_tier, 'smoke');
    testCase.verifyTrue(cfg.pilot_not_for_publication);
    testCase.verifyNotEqual(cfg.protocol_fingerprint, pub.protocol_fingerprint);
end

%% --- helpers ---

function tf = check_pass(report, name)
    names = {report.checks.name};
    idx = find(strcmp(names, name), 1);
    tf = ~isempty(idx) && report.checks(idx).pass;
end

function records = synthetic_full_grid(cfg, opts)
    if nargin < 2
        opts = struct();
    end
    finite = true;
    if isfield(opts, 'finite')
        finite = logical(opts.finite);
    end
    n = numel(cfg.seeds) * numel(cfg.cells);
    records = repmat(blank_record(), n, 1);
    k = 0;
    for is = 1:numel(cfg.seeds)
        for ic = 1:numel(cfg.cells)
            k = k + 1;
            cell_spec = cfg.cells{ic};
            r = blank_record();
            r.cell_key = cell_spec.cell_key;
            r.cell_id = cell_spec.cell_id;
            r.base_seed = cfg.seeds(is);
            r.mode = cell_spec.mode;
            r.protocol_tier = cfg.protocol_tier;
            r.protocol_fingerprint = cfg.protocol_fingerprint;
            r.pilot_not_for_publication = cfg.pilot_not_for_publication;
            r.status = 'ok';
            r.dale_violations = 0;
            r.wall_time_seconds = 1.0;
            if finite
                r.memory_capacity = struct('MC_total', 1.0);
                r.narma = struct('test_nrmse', 0.1);
                r.mackey_glass = struct('test_nrmse', 0.2);
                r.empirical_convergence = struct( ...
                    'classification', 'empirically_contracting_on_test_set', ...
                    'classification_reason', 'synthetic', ...
                    'median_pair_slope', -0.5, ...
                    'mean_pair_slope', -0.4, ...
                    'final_max_spread', 1e-3, ...
                    'final_median_spread', 1e-3, ...
                    'convergence_ratio', 0.1);
            else
                r.memory_capacity = struct('MC_total', NaN);
                r.narma = struct('test_nrmse', NaN);
                r.mackey_glass = struct('test_nrmse', NaN);
                r.empirical_convergence = struct( ...
                    'classification', 'inconclusive', ...
                    'classification_reason', 'synthetic_nan', ...
                    'median_pair_slope', NaN, ...
                    'mean_pair_slope', NaN, ...
                    'final_max_spread', NaN, ...
                    'final_median_spread', NaN, ...
                    'convergence_ratio', NaN);
            end
            r.qa = struct( ...
                'mean_rate', 0.4, ...
                'saturation_fraction', 0.1, ...
                'silent_fraction', 0.1, ...
                'resource_in_unit_interval', true);
            if strcmp(cell_spec.mode, 'DDE')
                r.lle = NaN;
                r.lle_status = 'unsupported_not_computed';
                r.unsupported = struct('dde_lle', 'unsupported_not_computed');
            else
                r.lle = NaN;
                r.lle_status = 'not_requested';
                r.unsupported = struct();
            end
            records(k) = r;
        end
    end
end

function r = blank_record()
    r = struct( ...
        'cell_key', '', ...
        'cell_id', 0, ...
        'base_seed', 0, ...
        'mode', '', ...
        'protocol_tier', '', ...
        'protocol_fingerprint', '', ...
        'pilot_not_for_publication', true, ...
        'status', '', ...
        'dale_violations', 0, ...
        'wall_time_seconds', NaN, ...
        'memory_capacity', struct('MC_total', NaN), ...
        'narma', struct('test_nrmse', NaN), ...
        'mackey_glass', struct('test_nrmse', NaN), ...
        'empirical_convergence', struct( ...
            'classification', 'inconclusive', ...
            'classification_reason', '', ...
            'pair_slopes', [], ...
            'median_pair_slope', NaN, ...
            'mean_pair_slope', NaN, ...
            'slope_per_time_units', 'per_second', ...
            'pair_slopes_per_sample_compat', [], ...
            'final_max_spread', NaN, ...
            'final_median_spread', NaN, ...
            'convergence_ratio', NaN, ...
            'n_usable_tail_points', NaN, ...
            'fraction_at_floor', NaN, ...
            'fit_interval_seconds', [NaN, NaN], ...
            'fit_quality_r2', NaN, ...
            'dde_empirical_only', false, ...
            'history_space_sampled', false, ...
            'dde_constant_history_limitation', false), ...
        'qa', struct( ...
            'mean_rate', NaN, ...
            'saturation_fraction', NaN, ...
            'silent_fraction', NaN, ...
            'resource_in_unit_interval', false), ...
        'lle', NaN, ...
        'lle_status', '', ...
        'unsupported', struct());
end

function run_dir = make_synthetic_run_dir(cfg, records, with_manifest)
    root = tempname;
    mkdir(root);
    run_id = 'synth_publication_gate';
    run_dir = fullfile(root, run_id);
    mkdir(run_dir);
    mkdir(fullfile(run_dir, 'cells'));
    save(fullfile(run_dir, 'preregistered_config.mat'), 'cfg');
    for i = 1:numel(records)
        cell_result = records(i);
        fname = sprintf('seed_%d__%s.mat', cell_result.base_seed, cell_result.cell_key);
        save(fullfile(run_dir, 'cells', fname), 'cell_result');
    end
    if with_manifest
        ctx = struct( ...
            'run_dir', run_dir, ...
            'run_id', run_id, ...
            'utc_timestamp', '2026-07-14T00:00:00Z', ...
            'git_sha_full', 'bf7873337d3e8df5a04f7bb32858910d380b1252', ...
            'git_sha_short', 'bf78733', ...
            'git_dirty', false, ...
            'matlab_version', version, ...
            'operating_system', computer('arch'), ...
            'hostname', 'testhost', ...
            'experiment_name', 'mechanism_ablation', ...
            'master_seed', cfg.seeds(1), ...
            'solver_options', struct());
        save_run_manifest(ctx, cfg, struct('stage', 'synthetic'));
    end
end
