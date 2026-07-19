function report = validate_temporal_memory_development_diagnostics(run_dir, options)
%VALIDATE_TEMPORAL_MEMORY_DEVELOPMENT_DIAGNOSTICS  Independent production check.
%
%   report = validate_temporal_memory_development_diagnostics(run_dir)
%   report = validate_temporal_memory_development_diagnostics(run_dir, options)
%
% Phase 5D-B2-R integrity hardening. Reconstructs expected identities from
% temporal_memory_development_config() (frozen) for production runs. Rejects
% fixture / synthetic provenance when allow_test_fixture is false.
%
% options:
%   throw_on_fail       (default true)
%   allow_test_fixture  (default false) — use cfg_override or saved config for
%                       geometry; skip validate_temporal_memory_seed_result
%   cfg_override        fixture cfg with possibly reduced seeds/lags/cells
%
% Throws validate_temporal_memory_development_diagnostics:Failed when report.ok
% is false unless options.throw_on_fail=false.
    if nargin < 1 || isempty(run_dir)
        error('validate_temporal_memory_development_diagnostics:MissingRunDir', ...
            'run_dir is required.');
    end
    if nargin < 2 || isempty(options)
        options = struct();
    end
    run_dir = char(run_dir);
    throw_on_fail = local_get(options, 'throw_on_fail', true);
    allow_test_fixture = logical(local_get(options, 'allow_test_fixture', false));
    checks = {};
    reasons = {};
    fresh_cfg = temporal_memory_development_config();
    commit_sha = try_git_head();
    required = { ...
        'diagnostic_config.mat', ...
        'diagnostic_result.mat', ...
        'diagnostic_manifest.mat', ...
        'diagnostic_manifest.json', ...
        'diagnostic_checkpoint.mat', ...
        'temporal_memory_long_table.mat', ...
        'temporal_memory_long_table.csv', ...
        'temporal_memory_summary_table.mat', ...
        'temporal_memory_summary_table.csv', ...
        'temporal_memory_contrast_table.mat', ...
        'temporal_memory_contrast_table.csv', ...
        'temporal_memory_control_long_table.mat', ...
        'temporal_memory_control_long_table.csv', ...
        'control_summary.mat', ...
        'shared/splits.mat', ...
        'shared/task_controls.mat'};
    files_ok = true;
    for i = 1:numel(required)
        if ~isfile(fullfile(run_dir, required{i}))
            files_ok = false;
            reasons{end+1} = ['missing_' strrep(required{i}, '/', '_')]; %#ok<AGROW>
        end
    end
    checks{end+1} = make_check('artifact_files_present', files_ok, run_dir);
    if ~files_ok
        report = finish(checks, reasons, throw_on_fail);
        return;
    end
    Sdc = load(fullfile(run_dir, 'diagnostic_config.mat'), 'diagnostic_config');
    saved_cfg = Sdc.diagnostic_config;
    if allow_test_fixture
        if isfield(options, 'cfg_override') && ~isempty(options.cfg_override)
            cfg = options.cfg_override;
        else
            cfg = saved_cfg;
        end
    else
        cfg = fresh_cfg;
    end
    Sm = load(fullfile(run_dir, 'diagnostic_manifest.mat'), 'diagnostic_manifest');
    manifest = Sm.diagnostic_manifest;
    Sr = load(fullfile(run_dir, 'diagnostic_result.mat'), 'diagnostic_result');
    result = Sr.diagnostic_result;
    Scp = load(fullfile(run_dir, 'diagnostic_checkpoint.mat'), 'diagnostic_checkpoint');
    checkpoint = Scp.diagnostic_checkpoint;
    % --- saved diagnostic_config (never trust in-memory cfg alone) ---
    cfg_saved_ok = verify_saved_diagnostic_config(saved_cfg, fresh_cfg, allow_test_fixture);
    checks{end+1} = make_check('saved_diagnostic_config', cfg_saved_ok.pass, ...
        cfg_saved_ok.detail);
    if ~cfg_saved_ok.pass
        reasons{end+1} = cfg_saved_ok.reason; %#ok<AGROW>
    end
    fixture_flag = detect_fixture_provenance(manifest, result, checkpoint, saved_cfg, ...
        run_dir, cfg);
    if ~allow_test_fixture
        checks{end+1} = make_check('not_fixture_run', ~fixture_flag, '');
        if fixture_flag
            reasons{end+1} = 'fixture_or_synthetic_provenance'; %#ok<AGROW>
            report = finish(checks, reasons, throw_on_fail);
            return;
        end
    end
    schema_ok = strcmp(char(local_get(manifest, 'schema_version', '')), ...
        'temporal_memory_development_artifact_v1') && ...
        strcmp(char(local_get(result, 'schema_version', '')), ...
        'temporal_memory_development_result_v1') && ...
        strcmp(char(local_get(checkpoint, 'schema_version', '')), ...
        'temporal_memory_development_checkpoint_v1');
    checks{end+1} = make_check('exact_schema', schema_ok, '');
    if ~schema_ok
        reasons{end+1} = 'schema_mismatch'; %#ok<AGROW>
    end
    fp_ok = strcmp(char(manifest.protocol_fingerprint), char(cfg.protocol_fingerprint)) && ...
        strcmp(char(result.protocol_fingerprint), char(cfg.protocol_fingerprint)) && ...
        strcmp(char(checkpoint.protocol_fingerprint), char(cfg.protocol_fingerprint));
    checks{end+1} = make_check('protocol_fingerprint_match', fp_ok, '');
    if ~fp_ok
        reasons{end+1} = 'protocol_fingerprint_mismatch'; %#ok<AGROW>
    end
    ver_ok = strcmp(char(manifest.protocol_version), char(cfg.protocol_version)) && ...
        strcmp(char(result.protocol_version), char(cfg.protocol_version)) && ...
        strcmp(char(checkpoint.protocol_version), char(cfg.protocol_version));
    checks{end+1} = make_check('protocol_version_match', ver_ok, '');
    if ~ver_ok
        reasons{end+1} = 'protocol_version_mismatch'; %#ok<AGROW>
    end
    if ~allow_test_fixture
        commit_ok = strcmp(char(manifest.code_commit_sha), commit_sha) && ...
            strcmp(char(checkpoint.code_commit_sha), commit_sha) && ...
            strcmp(char(result.code_commit_sha), commit_sha);
        checks{end+1} = make_check('commit_sha_match', commit_ok, commit_sha);
        if ~commit_ok
            reasons{end+1} = 'commit_sha_mismatch'; %#ok<AGROW>
        end
    end
    Sl = load(fullfile(run_dir, 'temporal_memory_long_table.mat'), ...
        'temporal_memory_long_table');
    long_table = Sl.temporal_memory_long_table;
    Ss = load(fullfile(run_dir, 'temporal_memory_summary_table.mat'), ...
        'temporal_memory_summary_table');
    summary_table = Ss.temporal_memory_summary_table;
    Sct = load(fullfile(run_dir, 'temporal_memory_contrast_table.mat'), ...
        'temporal_memory_contrast_table');
    contrast_table = Sct.temporal_memory_contrast_table;
    Scl = load(fullfile(run_dir, 'temporal_memory_control_long_table.mat'), ...
        'temporal_memory_control_long_table');
    control_long = Scl.temporal_memory_control_long_table;
    Scs = load(fullfile(run_dir, 'control_summary.mat'), 'control_summary');
    control_summary = Scs.control_summary;
    geom = expected_geometry(cfg);
    long_ok = height(long_table) == geom.n_long;
    checks{end+1} = make_check('long_table_row_count', long_ok, ...
        sprintf('%d expected %d', height(long_table), geom.n_long));
    if ~long_ok
        reasons{end+1} = 'long_table_row_count'; %#ok<AGROW>
    end
    sum_ok = height(summary_table) == geom.n_summary;
    checks{end+1} = make_check('summary_table_row_count', sum_ok, ...
        sprintf('%d expected %d', height(summary_table), geom.n_summary));
    if ~sum_ok
        reasons{end+1} = 'summary_table_row_count'; %#ok<AGROW>
    end
    ctrl_ok = height(control_long) == geom.n_control;
    checks{end+1} = make_check('control_long_row_count', ctrl_ok, ...
        sprintf('%d expected %d', height(control_long), geom.n_control));
    if ~ctrl_ok
        reasons{end+1} = 'control_long_row_count'; %#ok<AGROW>
    end
    contrast_n_ok = height(contrast_table) == geom.n_contrast;
    checks{end+1} = make_check('contrast_table_row_count', contrast_n_ok, ...
        sprintf('%d expected %d', height(contrast_table), geom.n_contrast));
    if ~contrast_n_ok
        reasons{end+1} = 'contrast_row_count'; %#ok<AGROW>
    end
    keys_ok = verify_cell_seed_lag_keys(long_table, cfg);
    checks{end+1} = make_check('cell_seed_lag_keys', keys_ok.pass, keys_ok.detail);
    if ~keys_ok.pass
        reasons{end+1} = 'missing_or_duplicate_cell_seed_lag'; %#ok<AGROW>
    end
    lags_ok = isempty(setdiff(cfg.lags(:)', long_table.lag(:)')) && ...
        isempty(setdiff(long_table.lag(:)', cfg.lags(:)'));
    checks{end+1} = make_check('lags_exact', lags_ok, '');
    if ~lags_ok
        reasons{end+1} = 'lags_mismatch'; %#ok<AGROW>
    end
    cells_ok = isempty(setdiff(string(cfg.diagnostic_cell_names(:)), ...
        unique(string(long_table.cell_name)))) && ...
        isempty(setdiff(unique(string(long_table.cell_name)), ...
        string(cfg.diagnostic_cell_names(:))));
    checks{end+1} = make_check('cells_exact', cells_ok, '');
    if ~cells_ok
        reasons{end+1} = 'cells_mismatch'; %#ok<AGROW>
    end
    seeds_ok = isequal(sort(unique(long_table.model_seed)), sort(cfg.model_seeds(:)));
    checks{end+1} = make_check('model_seeds_exact', seeds_ok, '');
    if ~seeds_ok
        reasons{end+1} = 'model_seeds_mismatch'; %#ok<AGROW>
    end
    if ~allow_test_fixture
        reserved = flatten_numeric(cfg.reserved_future_v2);
        reserved_ok = ~any(ismember(unique(long_table.model_seed), reserved(:))) && ...
            ~any(unique(long_table.model_seed) == 9003);
        checks{end+1} = make_check('no_reserved_seeds', reserved_ok, '');
        if ~reserved_ok
            reasons{end+1} = 'reserved_or_forbidden_seed'; %#ok<AGROW>
        end
    end
    cp_ok = try_validate_checkpoint(run_dir, cfg, commit_sha, allow_test_fixture);
    checks{end+1} = make_check('checkpoint_validated', cp_ok.pass, cp_ok.detail);
    if ~cp_ok.pass
        reasons{end+1} = cp_ok.reason; %#ok<AGROW>
    end
    expected_keys = temporal_memory_expected_checkpoint_keys(cfg);
    reg_ok = try_validate_artifact_registry(manifest, run_dir, cfg, expected_keys);
    checks{end+1} = make_check('artifact_registry_valid', reg_ok.pass, reg_ok.detail);
    if ~reg_ok.pass
        reasons{end+1} = reg_ok.reason; %#ok<AGROW>
    end
    hash_ok = verify_recomputed_hashes(manifest, result, long_table, summary_table, ...
        contrast_table, control_long, control_summary, run_dir, cfg);
    checks{end+1} = make_check('content_hashes', hash_ok.pass, hash_ok.detail);
    if ~hash_ok.pass
        reasons{end+1} = 'content_hash_mismatch'; %#ok<AGROW>
    end
    man_row_ok = verify_manifest_row_counts(manifest, long_table, summary_table, ...
        contrast_table, control_long, result, geom);
    checks{end+1} = make_check('manifest_row_counts', man_row_ok.pass, man_row_ok.detail);
    if ~man_row_ok.pass
        reasons{end+1} = 'manifest_row_count_mismatch'; %#ok<AGROW>
    end
    man_id_ok = verify_manifest_identities(manifest, cfg);
    checks{end+1} = make_check('manifest_identities', man_id_ok.pass, man_id_ok.detail);
    if ~man_id_ok.pass
        reasons{end+1} = 'manifest_identity_mismatch'; %#ok<AGROW>
    end
    pub_ok = verify_publication_prohibition(manifest, result, checkpoint);
    checks{end+1} = make_check('publication_prohibition', pub_ok.pass, pub_ok.detail);
    if ~pub_ok.pass
        reasons = [reasons, pub_ok.reasons]; %#ok<AGROW>
    end
    mj_ok = verify_manifest_mat_json_equality(run_dir, manifest);
    checks{end+1} = make_check('manifest_mat_json_equality', mj_ok.pass, mj_ok.detail);
    if ~mj_ok.pass
        reasons{end+1} = 'manifest_mat_json_mismatch'; %#ok<AGROW>
    end
    csv_ok = verify_all_mat_csv_agreement(run_dir);
    checks{end+1} = make_check('mat_csv_agreement', csv_ok.pass, csv_ok.detail);
    if ~csv_ok.pass
        reasons{end+1} = 'mat_csv_disagreement'; %#ok<AGROW>
    end
    cell_ok = verify_cell_artifacts(run_dir, cfg, checkpoint, allow_test_fixture);
    checks{end+1} = make_check('cell_artifacts', cell_ok.pass, cell_ok.detail);
    if ~cell_ok.pass
        reasons{end+1} = cell_ok.reason; %#ok<AGROW>
    end
    long_met_ok = verify_long_table_metrics(long_table, cfg);
    checks{end+1} = make_check('long_table_metrics', long_met_ok.pass, long_met_ok.detail);
    if ~long_met_ok.pass
        reasons{end+1} = 'long_table_metric_failure'; %#ok<AGROW>
    end
    sum_met_ok = verify_summary_table_metrics(summary_table, long_table, cfg);
    checks{end+1} = make_check('summary_table_metrics', sum_met_ok.pass, sum_met_ok.detail);
    if ~sum_met_ok.pass
        reasons{end+1} = 'summary_table_metric_failure'; %#ok<AGROW>
    end
    contrast_ok = verify_contrast_table(contrast_table, summary_table, cfg);
    checks{end+1} = make_check('contrast_arithmetic', contrast_ok.pass, contrast_ok.detail);
    if ~contrast_ok.pass
        reasons{end+1} = 'contrast_arithmetic_mismatch'; %#ok<AGROW>
    end
    alloc_ok = verify_control_allocation(control_long, control_summary, run_dir, cfg, geom);
    checks{end+1} = make_check('control_allocation', alloc_ok.pass, alloc_ok.detail);
    if ~alloc_ok.pass
        reasons{end+1} = 'control_allocation_failure'; %#ok<AGROW>
    end
    if ~allow_test_fixture
        conv_ok = verify_conventional_bundles(run_dir, cfg);
        checks{end+1} = make_check('conventional_identity', conv_ok.pass, conv_ok.detail);
        if ~conv_ok.pass
            reasons{end+1} = 'conventional_identity_failure'; %#ok<AGROW>
        end
    end
    ck_keys_ok = verify_checkpoint_key_set(checkpoint, cfg);
    checks{end+1} = make_check('checkpoint_key_set', ck_keys_ok.pass, ck_keys_ok.detail);
    if ~ck_keys_ok.pass
        reasons{end+1} = 'checkpoint_key_set_mismatch'; %#ok<AGROW>
    end
    shared_ok = verify_shared_control_artifacts(run_dir, cfg);
    checks{end+1} = make_check('shared_control_artifacts', shared_ok.pass, shared_ok.detail);
    if ~shared_ok.pass
        reasons{end+1} = 'shared_control_artifacts_missing'; %#ok<AGROW>
    end
    rng_ok = logical(local_get(result, 'global_rng_restored', false));
    checks{end+1} = make_check('global_rng_restored', rng_ok, '');
    if ~rng_ok
        reasons{end+1} = 'global_rng_not_restored'; %#ok<AGROW>
    end
    report = finish(checks, reasons, throw_on_fail);
end

%% --- geometry ---
function geom = expected_geometry(cfg)
    cells = cfg.diagnostic_cell_names(:);
    seeds = cfg.model_seeds(:);
    lags = cfg.lags(:);
    n_lags = numel(lags);
    n_seeds = numel(seeds);
    n_cells = numel(cells);
    geom = struct();
    geom.n_long = n_cells * n_seeds * n_lags;
    geom.n_summary = n_cells * n_seeds;
    geom.n_control = 2 * n_lags + 3 * n_seeds * n_lags;
    geom.n_contrast = 7 * n_seeds;
    geom.n_lags = n_lags;
    geom.n_seeds = n_seeds;
    geom.n_cells = n_cells;
end

%% --- saved config ---
function out = verify_saved_diagnostic_config(saved_cfg, fresh_cfg, allow_test_fixture)
    out = struct('pass', true, 'detail', '', 'reason', '');
    if ~isstruct(saved_cfg)
        out.pass = false;
        out.detail = 'not a struct';
        out.reason = 'saved_config_invalid';
        return;
    end
    if allow_test_fixture
        return;
    end
    if logical(local_get(saved_cfg, 'is_test_fixture', false)) || ...
            logical(local_get(saved_cfg, 'synthetic_provenance', false))
        out.pass = false;
        out.detail = 'fixture flag on saved config';
        out.reason = 'saved_config_fixture_provenance';
        return;
    end
    if ~strcmp(char(local_get(saved_cfg, 'protocol_version', '')), ...
            char(fresh_cfg.protocol_version))
        out.pass = false;
        out.detail = 'protocol_version';
        out.reason = 'saved_config_protocol_mismatch';
        return;
    end
    if ~strcmp(char(local_get(saved_cfg, 'protocol_fingerprint', '')), ...
            char(fresh_cfg.protocol_fingerprint))
        out.pass = false;
        out.detail = 'protocol_fingerprint';
        out.reason = 'saved_config_fingerprint_mismatch';
        return;
    end
    ledger_fields = {'seed_ledger', 'v1_observed', 'retired_from_future_publication', ...
        'reserved_future_v2', 'forbidden_executed_seeds', 'model_seeds', ...
        'task_seeds', 'shuffle_seeds'};
    for i = 1:numel(ledger_fields)
        f = ledger_fields{i};
        if ~isfield(saved_cfg, f) || ~isfield(fresh_cfg, f)
            out.pass = false;
            out.detail = ['missing ' f];
            out.reason = 'saved_config_seed_ledger_mismatch';
            return;
        end
        if ~structs_equal_for_config(saved_cfg.(f), fresh_cfg.(f))
            out.pass = false;
            out.detail = f;
            out.reason = 'saved_config_seed_ledger_mismatch';
            return;
        end
    end
    if ~isequal(saved_cfg.diagnostic_cell_names(:)', fresh_cfg.diagnostic_cell_names(:)') || ...
            ~cells_specs_equal(saved_cfg.cells, fresh_cfg.cells)
        out.pass = false;
        out.detail = 'cells';
        out.reason = 'saved_config_cells_mismatch';
        return;
    end
    if ~isequal(saved_cfg.lags(:)', fresh_cfg.lags(:)') || ...
            ~isequal(saved_cfg.lambda_grid(:)', fresh_cfg.lambda_grid(:)')
        out.pass = false;
        out.detail = 'lags or lambda_grid';
        out.reason = 'saved_config_geometry_mismatch';
        return;
    end
    if ~structs_equal_for_config(saved_cfg.lengths, fresh_cfg.lengths)
        out.pass = false;
        out.detail = 'lengths';
        out.reason = 'saved_config_lengths_mismatch';
        return;
    end
    if ~structs_equal_for_config(saved_cfg.frozen_operating_point, ...
            fresh_cfg.frozen_operating_point) || ...
            ~operating_base_equal(saved_cfg.base, fresh_cfg.base)
        out.pass = false;
        out.detail = 'operating_point';
        out.reason = 'saved_config_operating_point_mismatch';
        return;
    end
    if ~structs_equal_for_config(saved_cfg.conventional_memory_baseline, ...
            fresh_cfg.conventional_memory_baseline)
        out.pass = false;
        out.detail = 'conventional_memory_baseline';
        out.reason = 'saved_config_baseline_policy_mismatch';
        return;
    end
    if ~structs_equal_for_config(saved_cfg.control_allocation, ...
            fresh_cfg.control_allocation)
        out.pass = false;
        out.detail = 'control_allocation';
        out.reason = 'saved_config_control_allocation_mismatch';
        return;
    end
    pub_fields = {'publication_evidence', 'publication_ready', ...
        'can_satisfy_publication_readiness'};
    for i = 1:numel(pub_fields)
        f = pub_fields{i};
        if isfield(saved_cfg, f) && logical(saved_cfg.(f))
            out.pass = false;
            out.detail = f;
            out.reason = 'saved_config_publication_field_true';
            return;
        end
    end
    saved_hash = temporal_memory_development_config_content_hash(saved_cfg);
    fresh_hash = temporal_memory_development_config_content_hash(fresh_cfg);
    if ~strcmp(saved_hash, fresh_hash)
        out.pass = false;
        out.detail = 'config_content_hash';
        out.reason = 'saved_config_content_hash_mismatch';
    end
end
function tf = cells_specs_equal(a, b)
    tf = numel(a) == numel(b);
    if ~tf
        return;
    end
    for i = 1:numel(a)
        if ~strcmp(char(a{i}.cell_key), char(b{i}.cell_key))
            tf = false;
            return;
        end
        if isfield(a{i}, 'diagnostic_name') && isfield(b{i}, 'diagnostic_name')
            if ~strcmp(char(a{i}.diagnostic_name), char(b{i}.diagnostic_name))
                tf = false;
                return;
            end
        end
    end
end
function tf = operating_base_equal(a, b)
    keys = {'n', 'fraction_E', 'n_inputs', 'dt', 'tau_d', 'dale', ...
        'input_scaling', 'level_of_chaos', 'include_input'};
    tf = true;
    for i = 1:numel(keys)
        k = keys{i};
        if ~isfield(a, k) || ~isfield(b, k) || ~isequal(a.(k), b.(k))
            tf = false;
            return;
        end
    end
end
function tf = structs_equal_for_config(a, b)
    try
        tf = isequal(a, b);
    catch
        tf = false;
    end
end

%% --- provenance ---
function flag = detect_fixture_provenance(manifest, result, checkpoint, saved_cfg, ...
        run_dir, cfg)
    flag = logical(local_get(manifest, 'is_test_fixture', false)) || ...
        logical(local_get(manifest, 'synthetic_provenance', false)) || ...
        logical(local_get(result, 'is_test_fixture', false)) || ...
        logical(local_get(result, 'synthetic_provenance', false)) || ...
        logical(local_get(checkpoint, 'is_test_fixture', false)) || ...
        logical(local_get(checkpoint, 'synthetic_provenance', false)) || ...
        logical(local_get(saved_cfg, 'is_test_fixture', false)) || ...
        logical(local_get(saved_cfg, 'synthetic_provenance', false));
    if flag
        return;
    end
    cells = cfg.diagnostic_cell_names(:);
    seeds = cfg.model_seeds(:);
    for is = 1:numel(seeds)
        for ic = 1:numel(cells)
            p = fullfile(run_dir, 'seed_cell_results', ...
                sprintf('seed_%d__%s.mat', seeds(is), cells{ic}));
            if ~isfile(p)
                continue;
            end
            S = load(p, 'seed_cell_result');
            r = S.seed_cell_result;
            if logical(local_get(r, 'is_test_fixture', false)) || ...
                    logical(local_get(r, 'synthetic_provenance', false))
                flag = true;
                return;
            end
            prov = char(string(local_get(r, 'provenance', 'production')));
            if ~strcmp(prov, 'production')
                flag = true;
                return;
            end
        end
    end
end

%% --- checkpoint / registry (must call helpers, not inspect status alone) ---
function out = try_validate_checkpoint(run_dir, cfg, commit_sha, allow_test_fixture)
    out = struct('pass', true, 'detail', '', 'reason', '');
    try
        if allow_test_fixture
            cp = load_checkpoint_from_run(run_dir);
            use_sha = char(local_get(cp, 'code_commit_sha', commit_sha));
        else
            use_sha = commit_sha;
        end
        load_and_validate_temporal_memory_development_checkpoint(run_dir, cfg, use_sha);
    catch ME
        out.pass = false;
        out.detail = ME.message;
        out.reason = 'checkpoint_validation_failed';
    end
end
function cp = load_checkpoint_from_run(run_dir)
    S = load(fullfile(run_dir, 'diagnostic_checkpoint.mat'), 'diagnostic_checkpoint');
    cp = S.diagnostic_checkpoint;
end
function out = try_validate_artifact_registry(manifest, run_dir, cfg, expected_keys)
    out = struct('pass', true, 'detail', '', 'reason', '');
    if ~isfield(manifest, 'artifact_registry')
        out.pass = false;
        out.detail = 'missing artifact_registry';
        out.reason = 'artifact_registry_missing';
        return;
    end
    try
        validate_temporal_memory_artifact_registry(manifest.artifact_registry, ...
            run_dir, cfg, expected_keys);
    catch ME
        out.pass = false;
        out.detail = ME.message;
        out.reason = 'artifact_registry_validation_failed';
    end
end
function out = verify_checkpoint_key_set(checkpoint, cfg)
    out = struct('pass', true, 'detail', '');
    expected = temporal_memory_expected_checkpoint_keys(cfg);
    keys = cellstr(string(local_get(checkpoint, 'completed_keys', {})));
    keys = keys(:);
    if ~strcmp(char(local_get(checkpoint, 'status', '')), 'complete')
        out.pass = false;
        out.detail = 'checkpoint not complete';
        return;
    end
    if numel(keys) ~= numel(expected) || ~isempty(setdiff(expected, keys)) || ...
            ~isempty(setdiff(keys, expected))
        out.pass = false;
        out.detail = sprintf('expected %d keys, got %d', numel(expected), numel(keys));
    end
end

%% --- content hashes ---
function out = verify_recomputed_hashes(manifest, result, long_table, summary_table, ...
        contrast_table, control_long, control_summary, run_dir, cfg)
    out = struct('pass', true, 'detail', '');
    got_man = recompute_manifest_content_hash(manifest);
    if ~strcmp(char(local_get(manifest, 'manifest_content_hash', '')), got_man)
        out.pass = false;
        out.detail = 'manifest_content_hash';
        return;
    end
    stored = local_get(manifest, 'table_content_hashes', struct());
    pairs = { ...
        'long_table', long_table; ...
        'summary_table', summary_table; ...
        'contrast_table', contrast_table; ...
        'control_long_table', control_long};
    for i = 1:size(pairs, 1)
        name = pairs{i, 1};
        T = pairs{i, 2};
        if ~isfield(stored, name)
            out.pass = false;
            out.detail = ['missing hash ' name];
            return;
        end
        got = temporal_memory_table_content_hash(T);
        if ~strcmp(char(stored.(name)), got)
            out.pass = false;
            out.detail = ['table hash mismatch ' name];
            return;
        end
    end
    got_cs = canonical_sha256(sanitize_for_hash(control_summary));
    if ~isfield(stored, 'control_summary') || ...
            ~strcmp(char(stored.control_summary), got_cs)
        out.pass = false;
        out.detail = 'control_summary hash';
        return;
    end
    got_res = canonical_sha256(sanitize_for_hash(result));
    if ~isfield(stored, 'diagnostic_result') || ...
            ~strcmp(char(stored.diagnostic_result), got_res)
        out.pass = false;
        out.detail = 'diagnostic_result hash';
        return;
    end
    if ~isfield(manifest, 'artifact_registry')
        out.pass = false;
        out.detail = 'missing artifact_registry';
        return;
    end
    fresh_reg = build_temporal_memory_artifact_registry(run_dir, cfg, struct());
    if ~strcmp(char(manifest.artifact_registry.registry_content_hash), ...
            char(fresh_reg.registry_content_hash))
        out.pass = false;
        out.detail = 'artifact_registry hash';
        return;
    end
    if ~isfield(stored, 'artifact_registry') || ...
            ~strcmp(char(stored.artifact_registry), ...
            char(manifest.artifact_registry.registry_content_hash))
        out.pass = false;
        out.detail = 'manifest table_content_hashes.artifact_registry';
    end
end
function hex = recompute_manifest_content_hash(manifest)
    m = manifest_for_hash(manifest);
    hex = canonical_sha256(m);
end
function m = manifest_for_hash(manifest)
    m = manifest;
    drop = {'created_utc', 'manifest_content_hash'};
    for i = 1:numel(drop)
        if isfield(m, drop{i})
            m = rmfield(m, drop{i});
        end
    end
end
function out = sanitize_for_hash(value)
    out = value;
    if isstruct(value)
        drop = {'created_utc', 'updated_utc', 'hostname', 'matlab_version'};
        for i = 1:numel(drop)
            if isfield(out, drop{i})
                out = rmfield(out, drop{i});
            end
        end
    end
end

%% --- manifest consistency ---
function out = verify_manifest_row_counts(manifest, long_table, summary_table, ...
        contrast_table, control_long, result, geom)
    out = struct('pass', true, 'detail', '');
    rc = local_get(manifest, 'row_counts', struct());
    if height(long_table) ~= local_get(rc, 'long_table', NaN) || ...
            height(summary_table) ~= local_get(rc, 'summary_table', NaN) || ...
            height(contrast_table) ~= local_get(rc, 'contrast_table', NaN) || ...
            height(control_long) ~= local_get(rc, 'control_long_table', NaN)
        out.pass = false;
        out.detail = 'manifest row_counts';
        return;
    end
    if isfield(result, 'n_long_rows') && result.n_long_rows ~= height(long_table)
        out.pass = false;
        out.detail = 'result.n_long_rows';
        return;
    end
    if isfield(result, 'n_summary_rows') && result.n_summary_rows ~= height(summary_table)
        out.pass = false;
        out.detail = 'result.n_summary_rows';
        return;
    end
    if isfield(result, 'n_control_long_rows') && ...
            result.n_control_long_rows ~= height(control_long)
        out.pass = false;
        out.detail = 'result.n_control_long_rows';
        return;
    end
    if height(long_table) ~= geom.n_long || height(summary_table) ~= geom.n_summary || ...
            height(control_long) ~= geom.n_control || height(contrast_table) ~= geom.n_contrast
        out.pass = false;
        out.detail = 'geometry row counts';
    end
end
function out = verify_manifest_identities(manifest, cfg)
    out = struct('pass', true, 'detail', '');
    if ~isequal(manifest.model_seeds(:)', cfg.model_seeds(:)')
        out.pass = false;
        out.detail = 'model_seeds';
        return;
    end
    if ~isequal(cellstr(string(manifest.diagnostic_cell_names(:))), ...
            cellstr(string(cfg.diagnostic_cell_names(:))))
        out.pass = false;
        out.detail = 'diagnostic_cell_names';
        return;
    end
    if ~isequal(manifest.lags(:)', cfg.lags(:)')
        out.pass = false;
        out.detail = 'lags';
    end
end
function out = verify_publication_prohibition(manifest, result, checkpoint)
    out = struct('pass', true, 'detail', '', 'reasons', {{}});
    objs = {manifest, result, checkpoint};
    for o = 1:numel(objs)
        obj = objs{o};
        if logical(local_get(obj, 'publication_evidence', false))
            out.pass = false;
            out.reasons{end+1} = 'publication_evidence_true'; %#ok<AGROW>
        end
        if logical(local_get(obj, 'publication_ready', false))
            out.pass = false;
            out.reasons{end+1} = 'publication_ready_true'; %#ok<AGROW>
        end
        if logical(local_get(obj, 'can_authorize_publication', false))
            out.pass = false;
            out.reasons{end+1} = 'can_authorize_publication_true'; %#ok<AGROW>
        end
        if logical(local_get(obj, 'can_satisfy_publication_readiness', false))
            out.pass = false;
            out.reasons{end+1} = 'can_satisfy_publication_readiness_true'; %#ok<AGROW>
        end
    end
    if out.pass == false
        out.detail = strjoin(out.reasons, ', ');
    end
end
function out = verify_manifest_mat_json_equality(run_dir, manifest_mat)
    out = struct('pass', true, 'detail', '');
    json_path = fullfile(run_dir, 'diagnostic_manifest.json');
    raw = fileread(json_path);
    manifest_json = jsondecode(raw);
    norm_mat = normalize_manifest_for_compare(manifest_mat);
    norm_json = normalize_manifest_for_compare(manifest_json);
    if ~manifests_substantively_equal(norm_mat, norm_json)
        out.pass = false;
        out.detail = 'substantive field mismatch';
    end
end
function m = normalize_manifest_for_compare(m)
    m = m;
    if isfield(m, 'created_utc')
        m = rmfield(m, 'created_utc');
    end
    if isfield(m, 'manifest_content_hash')
        m = rmfield(m, 'manifest_content_hash');
    end
    m = normalize_manifest_types(m);
end
function m = normalize_manifest_types(m)
    if isstruct(m)
        if numel(m) ~= 1
            out = cell(size(m));
            for i = 1:numel(m)
                out{i} = normalize_manifest_types(m(i));
            end
            m = out;
            return;
        end
        fn = fieldnames(m);
        for i = 1:numel(fn)
            m.(fn{i}) = normalize_manifest_types(m.(fn{i}));
        end
        return;
    end
    if iscell(m)
        for i = 1:numel(m)
            m{i} = normalize_manifest_types(m{i});
        end
        return;
    end
    if isstring(m)
        m = char(m);
    end
end
function tf = manifests_substantively_equal(a, b)
    keys = { ...
        'schema_version', 'protocol_version', 'protocol_fingerprint', ...
        'protocol_role', 'protocol_tier', 'code_commit_sha', ...
        'model_seeds', 'diagnostic_cell_names', 'lags', 'row_counts', ...
        'table_content_hashes', 'artifact_registry', 'control_allocation', ...
        'publication_evidence', 'publication_ready', 'can_authorize_publication', ...
        'can_satisfy_publication_readiness', 'is_test_fixture', ...
        'synthetic_provenance'};
    tf = true;
    for i = 1:numel(keys)
        k = keys{i};
        if isfield(a, k) ~= isfield(b, k)
            tf = false;
            return;
        end
        if ~isfield(a, k)
            continue;
        end
        if strcmp(k, 'artifact_registry')
            if ~strcmp(char(a.artifact_registry.registry_content_hash), ...
                    char(b.artifact_registry.registry_content_hash))
                tf = false;
                return;
            end
            continue;
        end
        if ~isequal(a.(k), b.(k))
            tf = false;
            return;
        end
    end
end

%% --- MAT/CSV agreement ---
function out = verify_all_mat_csv_agreement(run_dir)
    out = struct('pass', true, 'detail', '');
    bases = {'temporal_memory_long_table', 'temporal_memory_summary_table', ...
        'temporal_memory_contrast_table', 'temporal_memory_control_long_table'};
    for i = 1:numel(bases)
        base = bases{i};
        cmp = compare_mat_csv_table(run_dir, base);
        if ~cmp.pass
            out.pass = false;
            out.detail = cmp.detail;
            return;
        end
    end
end
function out = compare_mat_csv_table(run_dir, base)
    out = struct('pass', true, 'detail', '');
    Sm = load(fullfile(run_dir, [base, '.mat']), base);
    Tm = Sm.(base);
    Tc = readtable(fullfile(run_dir, [base, '.csv']));
    if ~isequal(Tm.Properties.VariableNames, Tc.Properties.VariableNames)
        out.pass = false;
        out.detail = [base ' variable names/order'];
        return;
    end
    if height(Tm) ~= height(Tc)
        out.pass = false;
        out.detail = [base ' height'];
        return;
    end
    for c = 1:width(Tm)
        col = Tm.Properties.VariableNames{c};
        vm = Tm.(col);
        vc = Tc.(col);
        if ~columns_semantically_equal(vm, vc)
            out.pass = false;
            out.detail = sprintf('%s.%s', base, col);
            return;
        end
    end
end
function tf = columns_semantically_equal(vm, vc)
    tf = false;
    if isnumeric(vm) || islogical(vm)
        vd = coerce_to_double(vc);
        vm_d = double(vm);
        if islogical(vm)
            vm_d = double(vm);
            vd = double(vd ~= 0);
        end
        both_nan = isnan(vm_d) & isnan(vd);
        diff = abs(vm_d - vd);
        tf = numel(vm_d) == numel(vd) && all((diff <= 1e-9) | both_nan) && ...
            all(isnan(vm_d) == isnan(vd));
        return;
    end
    if isstring(vm) || iscellstr(vm) || ischar(vm) || iscategorical(vm)
        sm = string(vm);
        sc = string(vc);
        miss_m = ismissing(sm) | sm == "";
        miss_c = ismissing(sc) | sc == "";
        tf = all(miss_m == miss_c) && all(sm(~miss_m) == sc(~miss_c));
        return;
    end
    try
        tf = isequal(string(vm), string(vc));
    catch
        tf = isequal(vm, vc);
    end
end
function vd = coerce_to_double(vc)
    if isnumeric(vc)
        vd = double(vc);
    elseif islogical(vc)
        vd = double(vc);
    elseif iscell(vc)
        vd = str2double(string(vc));
    else
        vd = str2double(string(vc));
    end
end

%% --- cell artifacts ---
function out = verify_cell_artifacts(run_dir, cfg, checkpoint, allow_test_fixture)
    out = struct('pass', true, 'detail', '', 'reason', '');
    cells = cfg.diagnostic_cell_names(:);
    seeds = cfg.model_seeds(:);
    result_hashes = local_get(checkpoint, 'result_hashes', struct());
    for is = 1:numel(seeds)
        seed = seeds(is);
        for ic = 1:numel(cells)
            cell_name = cells{ic};
            p = fullfile(run_dir, 'seed_cell_results', ...
                sprintf('seed_%d__%s.mat', seed, cell_name));
            if ~isfile(p)
                out.pass = false;
                out.detail = p;
                out.reason = 'missing_cell_artifact';
                return;
            end
            S = load(p, 'seed_cell_result');
            scored = S.seed_cell_result;
            key = temporal_memory_checkpoint_key('cell', cell_name, seed);
            field = key_to_field(key);
            expected_hash = '';
            if isfield(result_hashes, field)
                expected_hash = char(result_hashes.(field));
            end
            got_hash = temporal_memory_seed_result_content_hash(scored);
            if ~isempty(expected_hash) && ~strcmp(got_hash, expected_hash)
                out.pass = false;
                out.detail = key;
                out.reason = 'cell_result_hash_mismatch';
                return;
            end
            if ~allow_test_fixture
                try
                    validate_temporal_memory_seed_result(scored, cfg);
                catch ME
                    out.pass = false;
                    out.detail = sprintf('%s: %s', key, ME.message);
                    out.reason = 'cell_seed_result_validation_failed';
                    return;
                end
            end
        end
    end
end

%% --- long table metrics ---
function out = verify_long_table_metrics(long_table, cfg)
    out = struct('pass', true, 'detail', '');
    grid = cfg.lambda_grid(:);
    metric_cols = {'held_out_rmse', 'held_out_nrmse', 'held_out_r2', ...
        'held_out_pearson_correlation', 'squared_correlation_memory_coefficient'};
    for i = 1:numel(metric_cols)
        col = metric_cols{i};
        if any(~isfinite(long_table.(col)))
            out.pass = false;
            out.detail = ['nonfinite ' col];
            return;
        end
    end
    mc = long_table.squared_correlation_memory_coefficient;
    if any(mc < -1e-12 | mc > 1 + 1e-12)
        out.pass = false;
        out.detail = 'memory_coefficient_range';
        return;
    end
    for i = 1:height(long_table)
        lam = long_table.selected_lambda(i);
        if ~ismember(lam, grid)
            out.pass = false;
            out.detail = sprintf('lambda row %d', i);
            return;
        end
        if ~isfinite(long_table.effective_numerical_rank(i)) || ...
                ~isfinite(long_table.coefficient_norm(i))
            out.pass = false;
            out.detail = sprintf('rank/norm row %d', i);
            return;
        end
        gbf = long_table.grid_boundary_flag(i);
        if ~(islogical(gbf) || (isnumeric(gbf) && (gbf == 0 || gbf == 1)))
            out.pass = false;
            out.detail = sprintf('grid_boundary_flag row %d', i);
            return;
        end
    end
end

%% --- summary table metrics ---
function out = verify_summary_table_metrics(summary_table, long_table, cfg)
    out = struct('pass', true, 'detail', '');
    mc_cols = {'memory_capacity_sum_lags_1_10', 'memory_capacity_sum_lags_1_25', ...
        'memory_capacity_sum_lags_1_50'};
    lag10_cols = {'lag10_nrmse', 'lag10_r2'};
    feat_cols = {'feature_covariance_effective_rank', 'feature_participation_ratio', ...
        'fraction_numerically_near_constant_features', ...
        'mean_feature_standard_deviation', 'median_feature_standard_deviation', ...
        'mean_firing_rate', 'saturation_fraction', 'silence_fraction'};
    all_cols = [mc_cols, lag10_cols, feat_cols];
    for i = 1:numel(all_cols)
        col = all_cols{i};
        if any(~isfinite(summary_table.(col)))
            out.pass = false;
            out.detail = ['nonfinite ' col];
            return;
        end
    end
    lags = cfg.lags(:);
    max_lag = max(lags);
    for i = 1:height(summary_table)
        cn = char(string(summary_table.cell_name(i)));
        seed = summary_table.model_seed(i);
        mask = strcmp(string(long_table.cell_name), cn) & long_table.model_seed == seed;
        sub = long_table(mask, :);
        sub = sortrows(sub, 'lag');
        mc = sub.squared_correlation_memory_coefficient;
        lag_vals = sub.lag;
        exp10 = sum_mc_upto(lag_vals, mc, min(10, max_lag));
        exp25 = sum_mc_upto(lag_vals, mc, min(25, max_lag));
        exp50 = sum_mc_upto(lag_vals, mc, min(50, max_lag));
        if abs(summary_table.memory_capacity_sum_lags_1_10(i) - exp10) > 1e-9 || ...
                abs(summary_table.memory_capacity_sum_lags_1_25(i) - exp25) > 1e-9 || ...
                abs(summary_table.memory_capacity_sum_lags_1_50(i) - exp50) > 1e-9
            out.pass = false;
            out.detail = sprintf('MC recompute %s seed %d', cn, seed);
            return;
        end
        if ismember(10, lag_vals)
            row10 = sub(sub.lag == 10, :);
            if abs(summary_table.lag10_nrmse(i) - row10.held_out_nrmse) > 1e-9 || ...
                    abs(summary_table.lag10_r2(i) - row10.held_out_r2) > 1e-9
                out.pass = false;
                out.detail = sprintf('lag10 %s seed %d', cn, seed);
                return;
            end
        end
    end
end
function s = sum_mc_upto(lags, mc, K)
    mask = lags >= 1 & lags <= K;
    s = sum(mc(mask));
end

%% --- contrast table ---
function out = verify_contrast_table(contrast_table, summary_table, cfg)
    out = struct('pass', true, 'detail', '');
    defs = contrast_definitions();
    n_seeds = numel(cfg.model_seeds(:));
    expected_n = size(defs, 1) * n_seeds;
    if height(contrast_table) ~= expected_n
        out.pass = false;
        out.detail = sprintf('expected %d rows', expected_n);
        return;
    end
    keys = strcat(string(contrast_table.contrast_name), '|', ...
        string(contrast_table.model_seed));
    if numel(unique(keys)) ~= numel(keys)
        out.pass = false;
        out.detail = 'duplicate contrast keys';
        return;
    end
    for is = 1:n_seeds
        seed = cfg.model_seeds(is);
        for id = 1:size(defs, 1)
            cname = defs{id, 1};
            ref_name = defs{id, 2};
            ctrl_name = defs{id, 3};
            mask = strcmp(string(contrast_table.contrast_name), cname) & ...
                contrast_table.model_seed == seed;
            if sum(mask) ~= 1
                out.pass = false;
                out.detail = sprintf('missing contrast %s seed %d', cname, seed);
                return;
            end
            row = contrast_table(mask, :);
            ref = summary_table(strcmp(string(summary_table.cell_name), ref_name) & ...
                summary_table.model_seed == seed, :);
            ctrl = summary_table(strcmp(string(summary_table.cell_name), ctrl_name) & ...
                summary_table.model_seed == seed, :);
            if height(ref) ~= 1 || height(ctrl) ~= 1
                out.pass = false;
                out.detail = sprintf('summary lookup %s seed %d', cname, seed);
                return;
            end
            tol = 1e-9;
            if abs(row.improvement_nrmse - (ctrl.lag10_nrmse - ref.lag10_nrmse)) > tol || ...
                    abs(row.improvement_r2 - (ref.lag10_r2 - ctrl.lag10_r2)) > tol || ...
                    abs(row.improvement_MC_1_50 - ...
                    (ref.memory_capacity_sum_lags_1_50 - ctrl.memory_capacity_sum_lags_1_50)) > tol || ...
                    abs(row.improvement_MC_1_10 - ...
                    (ref.memory_capacity_sum_lags_1_10 - ctrl.memory_capacity_sum_lags_1_10)) > tol || ...
                    abs(row.improvement_MC_1_25 - ...
                    (ref.memory_capacity_sum_lags_1_25 - ctrl.memory_capacity_sum_lags_1_25)) > tol
                out.pass = false;
                out.detail = sprintf('arithmetic %s seed %d', cname, seed);
                return;
            end
        end
    end
end
function defs = contrast_definitions()
    defs = { ...
        'representation', 'reference_x', 'reference_r'; ...
        'delay', 'reference_r', 'delay_removed_r'; ...
        'STD', 'reference_r', 'std_removed_r'; ...
        'combined_STD_and_delay', 'reference_r', 'std_and_delay_removed_r'; ...
        'SFA_distribution', 'reference_r', 'single_moment_matched_r'; ...
        'SFA_presence', 'reference_r', 'adaptation_removed_r'; ...
        'full_mechanisms', 'reference_r', 'mechanisms_off_r'};
end

%% --- control allocation ---
function out = verify_control_allocation(control_long, control_summary, run_dir, cfg, geom)
    out = struct('pass', true, 'detail', '');
    names = cellstr(string(control_long.control_name));
    n_lags = geom.n_lags;
    n_seeds = geom.n_seeds;
    counts = struct();
    counts.current_input_only = sum(strcmp(names, 'current_input_only'));
    counts.exact_history = sum(strcmp(names, 'exact_history'));
    counts.conventional_leaky_esn = sum(strcmp(names, 'conventional_leaky_esn'));
    counts.no_recurrent_coupling = sum(strcmp(names, 'no_recurrent_coupling'));
    counts.shuffled_target = sum(strcmp(names, 'shuffled_target'));
    exp_current = n_lags;
    exp_exact = n_lags;
    exp_conv = n_seeds * n_lags;
    exp_nr = n_seeds * n_lags;
    exp_sh = n_seeds * n_lags;
    if counts.current_input_only ~= exp_current || counts.exact_history ~= exp_exact || ...
            counts.conventional_leaky_esn ~= exp_conv || ...
            counts.no_recurrent_coupling ~= exp_nr || ...
            counts.shuffled_target ~= exp_sh
        out.pass = false;
        out.detail = 'row allocation counts';
        return;
    end
    alloc = local_get(control_summary, 'allocation', struct());
    if local_get(alloc, 'total_control_lag_rows', NaN) ~= geom.n_control || ...
            local_get(alloc, 'conventional_fits', NaN) ~= n_seeds
        out.pass = false;
        out.detail = 'control_summary allocation';
        return;
    end
    cell_dir = fullfile(run_dir, 'seed_cell_results');
    if isfolder(cell_dir)
        files = dir(fullfile(cell_dir, 'seed_*.mat'));
        for i = 1:numel(files)
            S = load(fullfile(cell_dir, files(i).name), 'seed_cell_result');
            r = S.seed_cell_result;
            if isfield(r, 'controls') && isfield(r.controls, 'conventional_leaky_esn')
                c = r.controls.conventional_leaky_esn;
                if isfield(c, 'n_candidates') || isfield(c, 'candidate_selection_table')
                    out.pass = false;
                    out.detail = sprintf('per-cell conventional in %s', files(i).name);
                    return;
                end
            end
            if isfield(r, 'conventional_bundle') || isfield(r, 'n_candidates')
                out.pass = false;
                out.detail = sprintf('embedded conventional fields in %s', files(i).name);
                return;
            end
        end
    end
    conv_dir = fullfile(run_dir, 'shared', 'conventional');
    conv_files = dir(fullfile(conv_dir, 'seed_*_conventional.mat'));
    if numel(conv_files) ~= n_seeds
        out.pass = false;
        out.detail = sprintf('expected %d conventional files, got %d', ...
            n_seeds, numel(conv_files));
    end
end
function out = verify_conventional_bundles(run_dir, cfg)
    out = struct('pass', true, 'detail', '');
    cmb = cfg.conventional_memory_baseline;
    seeds = cfg.model_seeds(:);
    for is = 1:numel(seeds)
        seed = seeds(is);
        path = fullfile(run_dir, 'shared', 'conventional', ...
            sprintf('seed_%d_conventional.mat', seed));
        if ~isfile(path)
            out.pass = false;
            out.detail = sprintf('missing conventional seed %d', seed);
            return;
        end
        S = load(path, 'conventional_bundle');
        b = S.conventional_bundle;
        if local_get(b, 'n_candidates', NaN) ~= cmb.candidate_count
            out.pass = false;
            out.detail = 'n_candidates';
            return;
        end
        if ~isequal(b.selection_lags(:), cmb.selection_lags(:))
            out.pass = false;
            out.detail = 'selection_lags';
            return;
        end
        if ~isscalar(b.selected_candidate_index) || ~isfinite(b.selected_candidate_index)
            out.pass = false;
            out.detail = 'selected_candidate_index';
            return;
        end
        idx = [b.per_lag.selected_candidate_index];
        if ~all(idx == b.selected_candidate_index)
            out.pass = false;
            out.detail = 'lag candidate mismatch';
            return;
        end
        if ~logical(b.same_reservoir_for_all_lags)
            out.pass = false;
            out.detail = 'same_reservoir';
            return;
        end
        if logical(b.test_targets_used_for_selection)
            out.pass = false;
            out.detail = 'test leakage';
            return;
        end
        if ~strcmp(char(local_get(b, 'provenance', '')), 'production')
            out.pass = false;
            out.detail = 'provenance';
            return;
        end
        got = temporal_memory_conventional_bundle_content_hash(b);
        if isfield(b, 'bundle_content_hash') && ~isempty(b.bundle_content_hash) && ...
                ~strcmp(char(b.bundle_content_hash), got)
            out.pass = false;
            out.detail = sprintf('bundle hash seed %d', seed);
            return;
        end
    end
end
function out = verify_shared_control_artifacts(run_dir, cfg)
    out = struct('pass', true, 'detail', '');
    seeds = cfg.model_seeds(:);
    cells = cfg.diagnostic_cell_names(:);
    for is = 1:numel(seeds)
        seed = seeds(is);
        req = { ...
            fullfile(run_dir, 'shared', 'conventional', ...
                sprintf('seed_%d_conventional.mat', seed)), ...
            fullfile(run_dir, 'shared', 'reference_controls', ...
                sprintf('seed_%d_no_recurrent.mat', seed)), ...
            fullfile(run_dir, 'shared', 'reference_controls', ...
                sprintf('seed_%d_shuffled_target.mat', seed))};
        for i = 1:numel(req)
            if ~isfile(req{i})
                out.pass = false;
                out.detail = req{i};
                return;
            end
        end
        for ic = 1:numel(cells)
            p = fullfile(run_dir, 'seed_cell_results', ...
                sprintf('seed_%d__%s.mat', seed, cells{ic}));
            if ~isfile(p)
                out.pass = false;
                out.detail = p;
                return;
            end
        end
    end
end
function out = verify_cell_seed_lag_keys(T, cfg)
    out = struct('pass', true, 'detail', '');
    cells = cfg.diagnostic_cell_names(:);
    seeds = cfg.model_seeds(:);
    lags = cfg.lags(:);
    expected = {};
    for ic = 1:numel(cells)
        for is = 1:numel(seeds)
            for il = 1:numel(lags)
                expected{end+1} = sprintf('%s|%d|%d', cells{ic}, seeds(is), lags(il)); %#ok<AGROW>
            end
        end
    end
    observed = cell(height(T), 1);
    for i = 1:height(T)
        observed{i} = sprintf('%s|%d|%d', char(string(T.cell_name(i))), ...
            T.model_seed(i), T.lag(i));
    end
    if numel(unique(observed)) ~= numel(observed)
        out.pass = false;
        out.detail = 'duplicate keys';
        return;
    end
    if ~isempty(setdiff(expected, observed)) || ~isempty(setdiff(observed, expected))
        out.pass = false;
        out.detail = 'missing or unexpected keys';
    end
end

%% --- report helpers ---
function report = finish(checks, reasons, throw_on_fail)
    report = struct();
    report.ok = isempty(reasons);
    report.valid = report.ok;
    report.checks = checks;
    report.failure_reasons = reasons;
    report.publication_evidence = false;
    report.publication_ready = false;
    report.can_authorize_publication = false;
    if throw_on_fail && ~report.ok
        error('validate_temporal_memory_development_diagnostics:Failed', ...
            'Validation failed: %s', strjoin(reasons, ', '));
    end
end
function c = make_check(name, pass, detail)
    c = struct('name', name, 'pass', logical(pass), 'detail', char(string(detail)));
end
function sha = try_git_head()
    [status, out] = system('git rev-parse HEAD');
    if status == 0
        sha = strtrim(out);
    else
        sha = 'unknown';
    end
end
function field = key_to_field(key)
    field = regexprep(key, '[^A-Za-z0-9]', '_');
    if ~isempty(field) && field(1) >= '0' && field(1) <= '9'
        field = ['k_', field];
    end
end
function vals = flatten_numeric(S)
    vals = [];
    if isnumeric(S)
        vals = S(:);
        return;
    end
    if ~isstruct(S) || numel(S) ~= 1
        return;
    end
    fn = fieldnames(S);
    for i = 1:numel(fn)
        vals = [vals; flatten_numeric(S.(fn{i}))]; %#ok<AGROW>
    end
end
function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
