function report = validate_temporal_memory_development_diagnostics(run_dir, options)
%VALIDATE_TEMPORAL_MEMORY_DEVELOPMENT_DIAGNOSTICS  Independent production check.
%
%   report = validate_temporal_memory_development_diagnostics(run_dir)
%   report = validate_temporal_memory_development_diagnostics(run_dir, options)
%
% Reconstructs expected identities from temporal_memory_development_config()
% (frozen). Rejects fixture / synthetic provenance runs as not production-valid.
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

    checks = {};
    reasons = {};

    cfg = temporal_memory_development_config();
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

    Sm = load(fullfile(run_dir, 'diagnostic_manifest.mat'), 'diagnostic_manifest');
    manifest = Sm.diagnostic_manifest;
    Sr = load(fullfile(run_dir, 'diagnostic_result.mat'), 'diagnostic_result');
    result = Sr.diagnostic_result;
    Scp = load(fullfile(run_dir, 'diagnostic_checkpoint.mat'), 'diagnostic_checkpoint');
    checkpoint = Scp.diagnostic_checkpoint;

    % Fixture / synthetic rejection for production validator
    fixture_flag = logical(local_get(manifest, 'is_test_fixture', false)) || ...
        logical(local_get(manifest, 'synthetic_provenance', false)) || ...
        logical(local_get(result, 'is_test_fixture', false)) || ...
        logical(local_get(result, 'synthetic_provenance', false));
    checks{end+1} = make_check('not_fixture_run', ~fixture_flag, '');
    if fixture_flag
        reasons{end+1} = 'fixture_or_synthetic_provenance'; %#ok<AGROW>
        report = finish(checks, reasons, throw_on_fail);
        return;
    end

    schema_ok = strcmp(char(local_get(manifest, 'schema_version', '')), ...
        'temporal_memory_development_artifact_v1') && ...
        strcmp(char(local_get(result, 'schema_version', '')), ...
        'temporal_memory_development_result_v1') && ...
        strcmp(char(local_get(checkpoint, 'schema_version', '')), ...
        'temporal_memory_development_checkpoint_v1');
    checks{end+1} = make_check('exact_schema', schema_ok, '');
    if ~schema_ok; reasons{end+1} = 'schema_mismatch'; end %#ok<AGROW>

    fp_ok = strcmp(char(manifest.protocol_fingerprint), char(cfg.protocol_fingerprint)) && ...
        strcmp(char(result.protocol_fingerprint), char(cfg.protocol_fingerprint)) && ...
        strcmp(char(checkpoint.protocol_fingerprint), char(cfg.protocol_fingerprint));
    checks{end+1} = make_check('protocol_fingerprint_match', fp_ok, '');
    if ~fp_ok; reasons{end+1} = 'protocol_fingerprint_mismatch'; end %#ok<AGROW>

    ver_ok = strcmp(char(manifest.protocol_version), char(cfg.protocol_version));
    checks{end+1} = make_check('protocol_version_match', ver_ok, '');
    if ~ver_ok; reasons{end+1} = 'protocol_version_mismatch'; end %#ok<AGROW>

    commit_ok = strcmp(char(manifest.code_commit_sha), commit_sha) && ...
        strcmp(char(checkpoint.code_commit_sha), commit_sha);
    checks{end+1} = make_check('commit_sha_match', commit_ok, commit_sha);
    if ~commit_ok; reasons{end+1} = 'commit_sha_mismatch'; end %#ok<AGROW>

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

    long_ok = height(long_table) == 1200;
    checks{end+1} = make_check('long_table_1200', long_ok, sprintf('%d', height(long_table)));
    if ~long_ok; reasons{end+1} = 'long_table_row_count'; end %#ok<AGROW>

    sum_ok = height(summary_table) == 24;
    checks{end+1} = make_check('summary_table_24', sum_ok, sprintf('%d', height(summary_table)));
    if ~sum_ok; reasons{end+1} = 'summary_table_row_count'; end %#ok<AGROW>

    ctrl_ok = height(control_long) == 550;
    checks{end+1} = make_check('control_long_550', ctrl_ok, sprintf('%d', height(control_long)));
    if ~ctrl_ok; reasons{end+1} = 'control_long_row_count'; end %#ok<AGROW>

    keys_ok = verify_cell_seed_lag_keys(long_table, cfg);
    checks{end+1} = make_check('cell_seed_lag_keys', keys_ok.pass, keys_ok.detail);
    if ~keys_ok.pass; reasons{end+1} = 'missing_or_duplicate_cell_seed_lag'; end %#ok<AGROW>

    lags_ok = isequal(sort(unique(long_table.lag)), (1:50)') || ...
        isequal(unique(long_table.lag), (1:50)');
    % Prefer exact set equality
    lags_ok = isempty(setdiff(1:50, long_table.lag(:)')) && ...
        isempty(setdiff(long_table.lag(:)', 1:50));
    checks{end+1} = make_check('lags_exact_1_50', lags_ok, '');
    if ~lags_ok; reasons{end+1} = 'lags_not_1_to_50'; end %#ok<AGROW>

    cells_ok = isempty(setdiff(string(cfg.diagnostic_cell_names(:)), ...
        unique(string(long_table.cell_name)))) && ...
        isempty(setdiff(unique(string(long_table.cell_name)), ...
        string(cfg.diagnostic_cell_names(:))));
    checks{end+1} = make_check('cells_exact', cells_ok, '');
    if ~cells_ok; reasons{end+1} = 'cells_mismatch'; end %#ok<AGROW>

    seeds_ok = isequal(sort(unique(long_table.model_seed)), sort(cfg.model_seeds(:)));
    checks{end+1} = make_check('model_seeds_exact', seeds_ok, '');
    if ~seeds_ok; reasons{end+1} = 'model_seeds_mismatch'; end %#ok<AGROW>

    reserved = flatten_numeric(cfg.reserved_future_v2);
    reserved_ok = ~any(ismember(unique(long_table.model_seed), reserved(:))) && ...
        ~any(unique(long_table.model_seed) == 9003);
    checks{end+1} = make_check('no_reserved_seeds', reserved_ok, '');
    if ~reserved_ok; reasons{end+1} = 'reserved_or_forbidden_seed'; end %#ok<AGROW>

    finite_ok = verify_finite_metrics(long_table, summary_table);
    checks{end+1} = make_check('required_metrics_finite', finite_ok.pass, finite_ok.detail);
    if ~finite_ok.pass; reasons{end+1} = 'nonfinite_metric'; end %#ok<AGROW>

    alloc_ok = verify_control_allocation(control_long, control_summary, run_dir, cfg);
    checks{end+1} = make_check('control_allocation', alloc_ok.pass, alloc_ok.detail);
    if ~alloc_ok.pass; reasons{end+1} = 'control_allocation_failure'; end %#ok<AGROW>

    conv_ok = verify_conventional_bundles(run_dir, cfg);
    checks{end+1} = make_check('conventional_identity', conv_ok.pass, conv_ok.detail);
    if ~conv_ok.pass; reasons{end+1} = 'conventional_identity_failure'; end %#ok<AGROW>

    contrast_ok = verify_contrast_arithmetic(contrast_table, summary_table);
    checks{end+1} = make_check('contrast_arithmetic', contrast_ok.pass, contrast_ok.detail);
    if ~contrast_ok.pass; reasons{end+1} = 'contrast_arithmetic_mismatch'; end %#ok<AGROW>

    hash_ok = verify_content_hashes(manifest, long_table, summary_table, ...
        contrast_table, control_long);
    checks{end+1} = make_check('content_hashes', hash_ok.pass, hash_ok.detail);
    if ~hash_ok.pass; reasons{end+1} = 'content_hash_mismatch'; end %#ok<AGROW>

    csv_ok = verify_mat_csv_agreement(run_dir);
    checks{end+1} = make_check('mat_csv_agreement', csv_ok.pass, csv_ok.detail);
    if ~csv_ok.pass; reasons{end+1} = 'mat_csv_disagreement'; end %#ok<AGROW>

    man_ok = verify_manifest_consistency(manifest, result, cfg, long_table, ...
        summary_table, control_long);
    checks{end+1} = make_check('manifest_consistency', man_ok.pass, man_ok.detail);
    if ~man_ok.pass; reasons{end+1} = 'manifest_inconsistency'; end %#ok<AGROW>

    rng_ok = logical(local_get(result, 'global_rng_restored', false));
    checks{end+1} = make_check('global_rng_restored', rng_ok, '');
    if ~rng_ok; reasons{end+1} = 'global_rng_not_restored'; end %#ok<AGROW>

    pub_ev = ~logical(local_get(manifest, 'publication_evidence', true)) && ...
        ~logical(local_get(result, 'publication_evidence', true)) && ...
        ~logical(local_get(checkpoint, 'publication_evidence', true));
    checks{end+1} = make_check('publication_evidence_false', pub_ev, '');
    if ~pub_ev; reasons{end+1} = 'publication_evidence_true'; end %#ok<AGROW>

    pub_ready = (~isfield(manifest, 'publication_ready') || ...
        ~logical(manifest.publication_ready)) && ...
        (~isfield(result, 'publication_ready') || ~logical(result.publication_ready)) && ...
        (~isfield(checkpoint, 'publication_ready') || ~logical(checkpoint.publication_ready));
    checks{end+1} = make_check('publication_ready_false', pub_ready, '');
    if ~pub_ready; reasons{end+1} = 'publication_ready_true'; end %#ok<AGROW>

    can_auth = ~logical(local_get(manifest, 'can_authorize_publication', true)) && ...
        ~logical(local_get(result, 'can_authorize_publication', true)) && ...
        ~logical(local_get(checkpoint, 'can_authorize_publication', true));
    checks{end+1} = make_check('cannot_authorize_publication', can_auth, '');
    if ~can_auth; reasons{end+1} = 'can_authorize_publication_true'; end %#ok<AGROW>

    contrast_n_ok = height(contrast_table) == 21;
    checks{end+1} = make_check('contrast_table_21', contrast_n_ok, ...
        sprintf('%d', height(contrast_table)));
    if ~contrast_n_ok; reasons{end+1} = 'contrast_row_count'; end %#ok<AGROW>

    shared_ok = verify_shared_control_artifacts(run_dir, cfg);
    checks{end+1} = make_check('shared_control_artifacts', shared_ok.pass, shared_ok.detail);
    if ~shared_ok.pass; reasons{end+1} = 'shared_control_artifacts_missing'; end %#ok<AGROW>

    cp_status_ok = strcmp(char(checkpoint.status), 'complete');
    checks{end+1} = make_check('checkpoint_complete', cp_status_ok, '');
    if ~cp_status_ok; reasons{end+1} = 'checkpoint_not_complete'; end %#ok<AGROW>

    report = finish(checks, reasons, throw_on_fail);
end

function out = verify_shared_control_artifacts(run_dir, cfg)
    out = struct('pass', true, 'detail', '');
    seeds = cfg.model_seeds(:);
    cells = cfg.diagnostic_cell_names(:);
    for is = 1:numel(seeds)
        seed = seeds(is);
        req = { ...
            fullfile(run_dir, 'shared', 'conventional', sprintf('seed_%d_conventional.mat', seed)), ...
            fullfile(run_dir, 'shared', 'reference_controls', sprintf('seed_%d_no_recurrent.mat', seed)), ...
            fullfile(run_dir, 'shared', 'reference_controls', sprintf('seed_%d_shuffled_target.mat', seed))};
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

function out = verify_finite_metrics(long_table, summary_table)
    out = struct('pass', true, 'detail', '');
    cols = {'held_out_nrmse', 'held_out_r2', 'held_out_pearson_correlation', ...
        'squared_correlation_memory_coefficient', 'held_out_rmse'};
    for i = 1:numel(cols)
        if any(~isfinite(long_table.(cols{i})))
            out.pass = false;
            out.detail = cols{i};
            return;
        end
    end
    scols = {'memory_capacity_sum_lags_1_10', 'memory_capacity_sum_lags_1_50', ...
        'lag10_nrmse', 'lag10_r2'};
    for i = 1:numel(scols)
        if any(~isfinite(summary_table.(scols{i})))
            out.pass = false;
            out.detail = scols{i};
            return;
        end
    end
end

function out = verify_control_allocation(control_long, control_summary, run_dir, cfg)
    out = struct('pass', true, 'detail', '');
    names = cellstr(string(control_long.control_name));
    counts = struct();
    counts.current_input_only = sum(strcmp(names, 'current_input_only'));
    counts.exact_history = sum(strcmp(names, 'exact_history'));
    counts.conventional_leaky_esn = sum(strcmp(names, 'conventional_leaky_esn'));
    counts.no_recurrent_coupling = sum(strcmp(names, 'no_recurrent_coupling'));
    counts.shuffled_target = sum(strcmp(names, 'shuffled_target'));
    if counts.current_input_only ~= 50 || counts.exact_history ~= 50 || ...
            counts.conventional_leaky_esn ~= 150 || ...
            counts.no_recurrent_coupling ~= 150 || ...
            counts.shuffled_target ~= 150
        out.pass = false;
        out.detail = 'row allocation counts';
        return;
    end
    alloc = local_get(control_summary, 'allocation', struct());
    if local_get(alloc, 'conventional_fits', NaN) ~= 3 || ...
            local_get(alloc, 'total_control_lag_rows', NaN) ~= 550
        out.pass = false;
        out.detail = 'control_summary allocation';
        return;
    end
    % Reject duplicated conventional bundles inside cell artifacts
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
    % Exactly 3 conventional files
    conv_dir = fullfile(run_dir, 'shared', 'conventional');
    conv_files = dir(fullfile(conv_dir, 'seed_*_conventional.mat'));
    if numel(conv_files) ~= 3
        out.pass = false;
        out.detail = sprintf('expected 3 conventional files, got %d', numel(conv_files));
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
            out.pass = false; out.detail = 'n_candidates'; return;
        end
        if ~isequal(b.selection_lags(:), cmb.selection_lags(:))
            out.pass = false; out.detail = 'selection_lags'; return;
        end
        if ~isscalar(b.selected_candidate_index) || ~isfinite(b.selected_candidate_index)
            out.pass = false; out.detail = 'selected_candidate_index'; return;
        end
        idx = [b.per_lag.selected_candidate_index];
        if ~all(idx == b.selected_candidate_index)
            out.pass = false; out.detail = 'lag candidate mismatch'; return;
        end
        if ~logical(b.same_reservoir_for_all_lags)
            out.pass = false; out.detail = 'same_reservoir'; return;
        end
        if logical(b.test_targets_used_for_selection)
            out.pass = false; out.detail = 'test leakage'; return;
        end
        if ~strcmp(char(local_get(b, 'provenance', '')), 'production')
            out.pass = false; out.detail = 'provenance'; return;
        end
    end
end

function out = verify_contrast_arithmetic(contrast_table, summary_table)
    out = struct('pass', true, 'detail', '');
    for i = 1:height(contrast_table)
        ref_name = char(string(contrast_table.reference_cell(i)));
        ctrl_name = char(string(contrast_table.control_cell(i)));
        seed = contrast_table.model_seed(i);
        ref = summary_table(strcmp(string(summary_table.cell_name), string(ref_name)) & ...
            summary_table.model_seed == seed, :);
        ctrl = summary_table(strcmp(string(summary_table.cell_name), string(ctrl_name)) & ...
            summary_table.model_seed == seed, :);
        if height(ref) ~= 1 || height(ctrl) ~= 1
            out.pass = false;
            out.detail = sprintf('lookup row %d', i);
            return;
        end
        exp_nrmse = ctrl.lag10_nrmse - ref.lag10_nrmse;
        exp_r2 = ref.lag10_r2 - ctrl.lag10_r2;
        exp_mc50 = ref.memory_capacity_sum_lags_1_50 - ctrl.memory_capacity_sum_lags_1_50;
        exp_mc10 = ref.memory_capacity_sum_lags_1_10 - ctrl.memory_capacity_sum_lags_1_10;
        if abs(contrast_table.improvement_nrmse(i) - exp_nrmse) > 1e-12 || ...
                abs(contrast_table.improvement_r2(i) - exp_r2) > 1e-12 || ...
                abs(contrast_table.improvement_MC_1_50(i) - exp_mc50) > 1e-12 || ...
                abs(contrast_table.improvement_MC_1_10(i) - exp_mc10) > 1e-12
            out.pass = false;
            out.detail = sprintf('arithmetic row %d', i);
            return;
        end
    end
end

function out = verify_content_hashes(manifest, long_table, summary_table, ...
        contrast_table, control_long)
    out = struct('pass', true, 'detail', '');
    hashes = local_get(manifest, 'table_content_hashes', struct());
    pairs = { ...
        'long_table', long_table; ...
        'summary_table', summary_table; ...
        'contrast_table', contrast_table; ...
        'control_long_table', control_long};
    for i = 1:size(pairs, 1)
        name = pairs{i, 1};
        T = pairs{i, 2};
        if ~isfield(hashes, name)
            out.pass = false;
            out.detail = ['missing hash ' name];
            return;
        end
        got = hash_table_content(T);
        if ~strcmp(char(hashes.(name)), got)
            out.pass = false;
            out.detail = ['hash mismatch ' name];
            return;
        end
    end
end

function out = verify_mat_csv_agreement(run_dir)
    out = struct('pass', true, 'detail', '');
    bases = {'temporal_memory_long_table', 'temporal_memory_summary_table', ...
        'temporal_memory_contrast_table', 'temporal_memory_control_long_table'};
    for i = 1:numel(bases)
        base = bases{i};
        Sm = load(fullfile(run_dir, [base, '.mat']), base);
        Tm = Sm.(base);
        Tc = readtable(fullfile(run_dir, [base, '.csv']));
        if height(Tm) ~= height(Tc)
            out.pass = false;
            out.detail = [base ' height'];
            return;
        end
        num_cols = Tm.Properties.VariableNames;
        for c = 1:numel(num_cols)
            col = num_cols{c};
            if ~ismember(col, Tc.Properties.VariableNames)
                continue;
            end
            vm = Tm.(col);
            vc = Tc.(col);
            if isnumeric(vm)
                if iscell(vc)
                    vc = cellfun(@str2double, cellstr(string(vc)));
                elseif isstring(vc) || iscellstr(vc)
                    vc = str2double(string(vc));
                end
                if any(abs(double(vm(:)) - double(vc(:))) > 1e-9 & ...
                        ~(isnan(vm(:)) & isnan(vc(:))))
                    out.pass = false;
                    out.detail = sprintf('%s.%s', base, col);
                    return;
                end
            end
        end
    end
end

function out = verify_manifest_consistency(manifest, result, cfg, long_table, ...
        summary_table, control_long)
    out = struct('pass', true, 'detail', '');
    if height(long_table) ~= manifest.row_counts.long_table || ...
            height(summary_table) ~= manifest.row_counts.summary_table || ...
            height(control_long) ~= manifest.row_counts.control_long_table
        out.pass = false;
        out.detail = 'row_counts';
        return;
    end
    if ~isequal(manifest.model_seeds(:), cfg.model_seeds(:))
        out.pass = false;
        out.detail = 'manifest seeds';
        return;
    end
    if result.n_long_rows ~= 1200 || result.n_control_long_rows ~= 550
        out.pass = false;
        out.detail = 'result row counts';
    end
end

function hex = hash_table_content(T)
    if isempty(T) || height(T) == 0
        hex = canonical_sha256(struct('empty', true, ...
            'varnames', {T.Properties.VariableNames}));
        return;
    end
    try
        S = table2struct(T);
    catch
        S = struct('nrows', height(T), 'varnames', {T.Properties.VariableNames});
    end
    hex = canonical_sha256(S);
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
