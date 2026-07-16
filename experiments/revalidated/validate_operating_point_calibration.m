function report = validate_operating_point_calibration(calibration_run_dir)
%VALIDATE_OPERATING_POINT_CALIBRATION  Independent calibration artifact check.
%
%   report = validate_operating_point_calibration(calibration_run_dir)
%
% Reloads artifacts from disk. Does not trust in-memory calibration structs.

    if nargin < 1 || isempty(calibration_run_dir)
        error('validate_operating_point_calibration:MissingRunDir', ...
            'calibration_run_dir is required.');
    end
    calibration_run_dir = char(calibration_run_dir);

    checks = {};
    reasons = {};

    required_files = { ...
        'calibration_config.mat', ...
        'calibration_trial_table.mat', ...
        'calibration_candidate_table.mat', ...
        'calibration_result.mat', ...
        'calibration_manifest.mat', ...
        'calibration_manifest.json' ...
        };
    files_ok = true;
    for i = 1:numel(required_files)
        if ~isfile(fullfile(calibration_run_dir, required_files{i}))
            files_ok = false;
            reasons{end+1} = ['missing_' required_files{i}]; %#ok<AGROW>
        end
    end
    checks{end+1} = make_check('artifact_files_present', files_ok, ...
        sprintf('dir=%s', calibration_run_dir));
    if ~files_ok
        report = build_validation_report(checks, reasons, '', false, struct([]), '');
        return;
    end

    Sm = load(fullfile(calibration_run_dir, 'calibration_manifest.mat'), ...
        'calibration_manifest');
    manifest = Sm.calibration_manifest;
    St = load(fullfile(calibration_run_dir, 'calibration_trial_table.mat'), ...
        'calibration_trial_table');
    trial_table = St.calibration_trial_table;
    Sc = load(fullfile(calibration_run_dir, 'calibration_candidate_table.mat'), ...
        'calibration_candidate_table');
    candidate_table = Sc.calibration_candidate_table;
    Sr = load(fullfile(calibration_run_dir, 'calibration_result.mat'), ...
        'calibration_result');
    result = Sr.calibration_result;

    expected_schema = 'publication_operating_point_calibration_artifact_v1';
    expected_protocol = 'publication_operating_point_calibration_v1';
    schema_ok = strcmp(char(local_get(manifest, 'schema_version', '')), expected_schema);
    checks{end+1} = make_check('schema_version_match', schema_ok, expected_schema);
    if ~schema_ok
        reasons{end+1} = 'schema_version_mismatch'; %#ok<AGROW>
    end

    protocol_ok = strcmp(char(local_get(manifest, 'calibration_protocol_version', '')), ...
        expected_protocol);
    checks{end+1} = make_check('calibration_protocol_version_match', protocol_ok, ...
        expected_protocol);
    if ~protocol_ok
        reasons{end+1} = 'calibration_protocol_version_mismatch'; %#ok<AGROW>
    end

    n_ok = isequal(local_get(manifest, 'network_size', NaN), 40);
    checks{end+1} = make_check('network_size_is_40', n_ok, 'n=40');
    if ~n_ok
        reasons{end+1} = 'network_size_mismatch'; %#ok<AGROW>
    end

    ref_cfg = mechanism_ablation_config('publication', 'confirmatory');
    dt_ok = abs(local_get(manifest, 'dt', NaN) - ref_cfg.base.dt) < 1e-12;
    checks{end+1} = make_check('dt_match_publication', dt_ok, sprintf('dt=%g', ref_cfg.base.dt));
    if ~dt_ok
        reasons{end+1} = 'dt_mismatch'; %#ok<AGROW>
    end

    seeds_ok = isequal(local_get(manifest, 'calibration_seeds', []), [1729, 2718]);
    checks{end+1} = make_check('calibration_seeds_exact', seeds_ok, '[1729,2718]');
    if ~seeds_ok
        reasons{end+1} = 'calibration_seeds_mismatch'; %#ok<AGROW>
    end

    overlap_ok = isempty(intersect(manifest.calibration_seeds, ref_cfg.publication_seeds));
    checks{end+1} = make_check('calibration_publication_seed_disjoint', overlap_ok, ...
        'seed sets disjoint');
    if ~overlap_ok
        reasons{end+1} = 'calibration_publication_seed_overlap'; %#ok<AGROW>
    end

    expected_probe = expected_operating_point_calibration_probe_keys();
    probe_ok = isequal(manifest.probe_cell_keys(:)', expected_probe);
    checks{end+1} = make_check('probe_cell_keys_exact', probe_ok, ...
        sprintf('n=%d', numel(expected_probe)));
    if ~probe_ok
        reasons{end+1} = 'probe_cell_keys_mismatch'; %#ok<AGROW>
    end

    candidate_ok = verify_candidate_order(manifest.candidate_order, ref_cfg.operating_point);
    checks{end+1} = make_check('candidate_order_exact', candidate_ok.pass, candidate_ok.detail);
    if ~candidate_ok.pass
        reasons{end+1} = 'candidate_order_mismatch'; %#ok<AGROW>
    end

    row_ok = height(trial_table) == 512 && ...
        manifest.expected_trial_row_count == 512 && ...
        manifest.observed_trial_row_count == 512;
    checks{end+1} = make_check('trial_row_count_512', row_ok, ...
        sprintf('observed=%d', height(trial_table)));
    if ~row_ok
        reasons{end+1} = 'trial_row_count_mismatch'; %#ok<AGROW>
    end

    dup_ok = verify_no_duplicate_trial_rows(trial_table);
    checks{end+1} = make_check('no_duplicate_trial_rows', dup_ok.pass, dup_ok.detail);
    if ~dup_ok.pass
        reasons{end+1} = 'duplicate_trial_rows'; %#ok<AGROW>
    end

    complete_ok = verify_complete_trial_matrix(trial_table, ref_cfg, expected_probe);
    checks{end+1} = make_check('trial_matrix_complete', complete_ok.pass, complete_ok.detail);
    if ~complete_ok.pass
        reasons{end+1} = 'trial_matrix_incomplete'; %#ok<AGROW>
    end

    finite_ok = verify_finite_metrics(trial_table);
    checks{end+1} = make_check('trial_metrics_finite', finite_ok.pass, finite_ok.detail);
    if ~finite_ok.pass
        reasons{end+1} = 'nonfinite_trial_metric'; %#ok<AGROW>
    end

    range_ok = verify_activity_ranges(trial_table);
    checks{end+1} = make_check('activity_metrics_in_unit_interval', range_ok.pass, ...
        range_ok.detail);
    if ~range_ok.pass
        reasons{end+1} = 'activity_metric_out_of_range'; %#ok<AGROW>
    end

    dale_ok = verify_dale_violations(trial_table);
    checks{end+1} = make_check('dale_violations_valid', dale_ok.pass, dale_ok.detail);
    if ~dale_ok.pass
        reasons{end+1} = 'dale_violations_invalid'; %#ok<AGROW>
    end

    input_ok = verify_input_hashes(trial_table, manifest);
    checks{end+1} = make_check('input_hash_consistency', input_ok.pass, input_ok.detail);
    if ~input_ok.pass
        reasons{end+1} = 'input_hash_inconsistent'; %#ok<AGROW>
    end

    tol_ok = verify_solver_tolerances(trial_table, ref_cfg.operating_point);
    checks{end+1} = make_check('solver_tolerances_exact', tol_ok.pass, tol_ok.detail);
    if ~tol_ok.pass
        reasons{end+1} = 'solver_tolerance_mismatch'; %#ok<AGROW>
    end

    wash_ok = verify_washout_evaluation(trial_table, ref_cfg.operating_point);
    checks{end+1} = make_check('washout_evaluation_counts', wash_ok.pass, wash_ok.detail);
    if ~wash_ok.pass
        reasons{end+1} = 'washout_evaluation_mismatch'; %#ok<AGROW>
    end

    pass_ok = verify_pass_flags_recomputed(trial_table, ref_cfg.operating_point);
    checks{end+1} = make_check('pass_flags_recomputed', pass_ok.pass, pass_ok.detail);
    if ~pass_ok.pass
        reasons{end+1} = 'pass_flag_mismatch'; %#ok<AGROW>
    end

    cand_ok = verify_candidate_feasibility(candidate_table, trial_table);
    checks{end+1} = make_check('candidate_feasibility_recomputed', cand_ok.pass, ...
        cand_ok.detail);
    if ~cand_ok.pass
        reasons{end+1} = 'candidate_feasibility_mismatch'; %#ok<AGROW>
    end

    select_ok = verify_selection_rule(candidate_table, manifest);
    checks{end+1} = make_check('selection_rule_first_feasible', select_ok.pass, ...
        select_ok.detail);
    if ~select_ok.pass
        reasons{end+1} = 'selection_rule_mismatch'; %#ok<AGROW>
    end

    forbidden_ok = verify_no_forbidden_fields(manifest, trial_table, result);
    checks{end+1} = make_check('no_forbidden_outcome_fields', forbidden_ok.pass, ...
        forbidden_ok.detail);
    if ~forbidden_ok.pass
        reasons{end+1} = 'forbidden_outcome_field_present'; %#ok<AGROW>
    end

    rng_ok = ~logical(local_get(manifest, 'global_rng_mutated', true));
    checks{end+1} = make_check('global_rng_unmutated', rng_ok, ...
        sprintf('global_rng_mutated=%d', ~rng_ok));
    if ~rng_ok
        reasons{end+1} = 'global_rng_mutated'; %#ok<AGROW>
    end

    override_ok = ~logical(local_get(manifest, 'scientific_overrides_used', true));
    checks{end+1} = make_check('scientific_overrides_unused', override_ok, ...
        sprintf('scientific_overrides_used=%d', ~override_ok));
    if ~override_ok
        reasons{end+1} = 'scientific_overrides_used'; %#ok<AGROW>
    end

    fp_ok = strcmp(char(manifest.calibration_protocol_fingerprint), ...
        compute_calibration_protocol_fingerprint(ref_cfg, expected_probe));
    checks{end+1} = make_check('calibration_protocol_fingerprint_match', fp_ok, ...
        'recomputed fingerprint');
    if ~fp_ok
        reasons{end+1} = 'calibration_protocol_fingerprint_mismatch'; %#ok<AGROW>
    end

    hash_ok = verify_manifest_hashes(manifest, trial_table, candidate_table);
    checks{end+1} = make_check('artifact_hashes_match', hash_ok.pass, hash_ok.detail);
    if ~hash_ok.pass
        reasons{end+1} = 'artifact_hash_mismatch'; %#ok<AGROW>
    end

    rand_ok = verify_no_randstream_objects(calibration_run_dir);
    checks{end+1} = make_check('no_randstream_objects', rand_ok.pass, rand_ok.detail);
    if ~rand_ok.pass
        reasons{end+1} = 'randstream_object_present'; %#ok<AGROW>
    end

    check_arr = [checks{:}];
    valid = all([check_arr.pass]);

    status = char(local_get(manifest, 'status', ''));
    frozen_operating_point = local_get(manifest, 'frozen_operating_point', struct([]));
    authorizes = valid && strcmp(status, 'frozen') && ...
        sum(candidate_table.selected) == 1 && ...
        isstruct(frozen_operating_point) && ~isempty(frozen_operating_point) && ...
        all(isfinite([frozen_operating_point.input_scaling, ...
        frozen_operating_point.level_of_chaos]));

    if authorizes
        sel_idx = find(candidate_table.selected, 1);
        sel_row = candidate_table(sel_idx, :);
        authorizes = authorizes && ...
            abs(sel_row.input_scaling - frozen_operating_point.input_scaling) < 1e-12 && ...
            abs(sel_row.level_of_chaos - frozen_operating_point.level_of_chaos) < 1e-12;
    end

    manifest_hash = char(local_get(manifest, 'artifact_content_hash', ''));
    report = build_validation_report(checks, reasons, status, valid, ...
        frozen_operating_point, manifest_hash);
    report.authorizes_publication_run = authorizes;
    report.calibration_protocol_fingerprint = char(manifest.calibration_protocol_fingerprint);
end

function report = build_validation_report(checks, reasons, status, valid, ...
        frozen_operating_point, manifest_hash)
    report = struct();
    report.valid = valid;
    report.status = status;
    report.frozen_operating_point = frozen_operating_point;
    report.calibration_manifest_hash = manifest_hash;
    report.checks = [checks{:}];
    report.reasons = reasons;
    report.authorizes_publication_run = false;
    report.calibration_protocol_fingerprint = '';
end

function c = make_check(name, pass, detail)
    c = struct('name', name, 'pass', logical(pass), 'detail', char(string(detail)));
end

function out = verify_candidate_order(candidate_order, op)
    out = struct('pass', false, 'detail', '');
    if numel(candidate_order) ~= 16
        out.detail = sprintf('n=%d', numel(candidate_order));
        return;
    end
    for i = 1:16
        exp = op.candidate_order{i};
        got = candidate_order{i};
        if abs(got.input_scaling - exp.input_scaling) > 1e-12 || ...
                abs(got.level_of_chaos - exp.level_of_chaos) > 1e-12
            out.detail = sprintf('index=%d mismatch', i);
            return;
        end
    end
    out.pass = true;
    out.detail = '16 pairs frozen order';
end

function out = verify_no_duplicate_trial_rows(trial_table)
    keys = strcat(string(trial_table.candidate_index), '|', ...
        trial_table.cell_key, '|', string(trial_table.calibration_seed));
    out = struct();
    out.pass = numel(unique(keys)) == height(trial_table);
    out.detail = sprintf('n_rows=%d n_unique=%d', height(trial_table), numel(unique(keys)));
end

function out = verify_complete_trial_matrix(trial_table, cfg, probe_keys)
    op = cfg.operating_point;
    seeds = op.calibration_seeds(:)';
    missing = 0;
    for ic = 1:16
        for ip = 1:numel(probe_keys)
            for is = 1:numel(seeds)
                mask = trial_table.candidate_index == ic & ...
                    strcmp(trial_table.cell_key, probe_keys{ip}) & ...
                    trial_table.calibration_seed == seeds(is);
                if ~any(mask)
                    missing = missing + 1;
                end
            end
        end
    end
    out = struct();
    out.pass = missing == 0;
    out.detail = sprintf('missing=%d', missing);
end

function out = verify_finite_metrics(trial_table)
    bad = any(~isfinite(trial_table.mean_rate)) || ...
        any(~isfinite(trial_table.saturation_fraction)) || ...
        any(~isfinite(trial_table.silent_fraction)) || ...
        any(~isfinite(trial_table.dale_violations));
    out = struct('pass', ~bad, 'detail', sprintf('nonfinite=%d', bad));
end

function out = verify_activity_ranges(trial_table)
    bad = any(trial_table.mean_rate < 0 | trial_table.mean_rate > 1) || ...
        any(trial_table.saturation_fraction < 0 | trial_table.saturation_fraction > 1) || ...
        any(trial_table.silent_fraction < 0 | trial_table.silent_fraction > 1);
    out = struct('pass', ~bad, 'detail', sprintf('out_of_range=%d', bad));
end

function out = verify_dale_violations(trial_table)
    v = trial_table.dale_violations;
    bad = any(~isfinite(v)) || any(v < 0) || any(abs(v - round(v)) > 1e-12);
    out = struct('pass', ~bad, 'detail', sprintf('invalid=%d', bad));
end

function out = verify_input_hashes(trial_table, manifest)
    seeds = manifest.calibration_seeds(:)';
    bad = 0;
    for i = 1:numel(seeds)
        seed = seeds(i);
        sub = trial_table(trial_table.calibration_seed == seed, :);
        hashes = unique(sub.input_hash);
        if numel(hashes) ~= 1
            bad = bad + 1;
        end
    end
    if numel(seeds) == 2
        h1 = unique(trial_table.input_hash(trial_table.calibration_seed == seeds(1)));
        h2 = unique(trial_table.input_hash(trial_table.calibration_seed == seeds(2)));
        if isequal(h1, h2)
            bad = bad + 1;
        end
    end
    out = struct('pass', bad == 0, 'detail', sprintf('bad=%d', bad));
end

function out = verify_solver_tolerances(trial_table, op)
    bad = any(abs(trial_table.ode_reltol - op.ode_reltol) > 0) || ...
        any(abs(trial_table.ode_abstol - op.ode_abstol) > 0) || ...
        any(abs(trial_table.dde_reltol - op.dde_reltol) > 0) || ...
        any(abs(trial_table.dde_abstol - op.dde_abstol) > 0);
    out = struct('pass', ~bad, 'detail', sprintf('mismatch=%d', bad));
end

function out = verify_washout_evaluation(trial_table, op)
    bad = any(trial_table.washout_steps ~= op.washout_steps) || ...
        any(trial_table.evaluation_steps ~= op.evaluation_steps);
    out = struct('pass', ~bad, 'detail', sprintf('mismatch=%d', bad));
end

function out = verify_pass_flags_recomputed(trial_table, op)
    bad = 0;
    for i = 1:height(trial_table)
        row = trial_table(i, :);
        mean_ok = row.mean_rate >= op.mean_rate_band(1) && ...
            row.mean_rate <= op.mean_rate_band(2);
        sat_ok = row.saturation_fraction <= op.saturation_fraction_max;
        sil_ok = row.silent_fraction <= op.silent_fraction_max;
        dale_ok = row.dale_violations == 0;
        row_ok = mean_ok && sat_ok && sil_ok && dale_ok;
        if row.mean_rate_pass ~= mean_ok || row.saturation_pass ~= sat_ok || ...
                row.silent_pass ~= sil_ok || row.dale_pass ~= dale_ok || ...
                row.row_pass ~= row_ok
            bad = bad + 1;
        end
    end
    out = struct('pass', bad == 0, 'detail', sprintf('bad=%d', bad));
end

function out = verify_candidate_feasibility(candidate_table, trial_table)
    bad = 0;
    for ic = 1:height(candidate_table)
        row = candidate_table(ic, :);
        sub = trial_table(trial_table.candidate_index == row.candidate_index, :);
        all_finite = all(isfinite(sub.mean_rate)) && all(isfinite(sub.saturation_fraction)) && ...
            all(isfinite(sub.silent_fraction)) && all(isfinite(sub.dale_violations));
        all_pass = all(sub.row_pass);
        feasible = height(sub) == 32 && all_finite && all_pass;
        if row.feasible ~= feasible || row.n_observed_rows ~= height(sub) || ...
                row.all_rows_finite ~= all_finite || row.all_rows_pass ~= all_pass
            bad = bad + 1;
        end
    end
    out = struct('pass', bad == 0, 'detail', sprintf('bad=%d', bad));
end

function out = verify_selection_rule(candidate_table, manifest)
    feasible_idx = find(candidate_table.feasible);
    if isempty(feasible_idx)
        ok = ~any(candidate_table.selected) && ...
            (~isfield(manifest, 'selected_candidate_index') || ...
            isempty(manifest.selected_candidate_index)) && ...
            strcmp(char(local_get(manifest, 'status', '')), 'no_feasible_operating_point');
        out = struct('pass', ok, 'detail', 'no feasible candidate');
        return;
    end
    first = feasible_idx(1);
    ok = candidate_table.selected(first) && sum(candidate_table.selected) == 1;
    if isfield(manifest, 'selected_candidate_index') && ~isempty(manifest.selected_candidate_index)
        ok = ok && manifest.selected_candidate_index == first;
    end
    if numel(feasible_idx) > 1
        ok = ok && ~any(candidate_table.selected(feasible_idx(2:end)));
    end
    out = struct('pass', ok, 'detail', sprintf('first_feasible=%d', first));
end

function out = verify_no_forbidden_fields(manifest, trial_table, result)
    forbidden = {'nrmse', 'memory_capacity', 'temporal_gate', 'task_outcome', ...
        'readout_coefficients'};
    bad = contains_field_recursive(manifest, forbidden) || ...
        contains_field_recursive(trial_table, forbidden) || ...
        contains_field_recursive(result, forbidden);
    out = struct('pass', ~bad, 'detail', sprintf('forbidden=%d', bad));
end

function tf = contains_field_recursive(obj, forbidden)
    tf = false;
    if istable(obj)
        fn = obj.Properties.VariableNames;
        for i = 1:numel(fn)
            if any(strcmpi(fn{i}, forbidden))
                tf = true;
                return;
            end
        end
        return;
    end
    if ~isstruct(obj)
        return;
    end
    fn = fieldnames(obj);
    for i = 1:numel(fn)
        if any(strcmpi(fn{i}, forbidden))
            tf = true;
            return;
        end
        val = obj.(fn{i});
        if isstruct(val) || istable(val)
            tf = contains_field_recursive(val, forbidden);
            if tf
                return;
            end
        end
    end
end

function out = verify_manifest_hashes(manifest, trial_table, candidate_table)
    trial_hash = canonical_sha256(table2struct(trial_table));
    cand_hash = canonical_sha256(table2struct(candidate_table));
    th = local_get(manifest.table_content_hashes, 'calibration_trial_table', '');
    ch = local_get(manifest.table_content_hashes, 'calibration_candidate_table', '');
    ok = strcmp(char(th), trial_hash) && strcmp(char(ch), cand_hash);
    cfg_hash = canonical_sha256(manifest_for_config_hash(manifest));
    ok = ok && strcmp(char(local_get(manifest, 'configuration_hash', '')), cfg_hash);
    content_hash = canonical_sha256(manifest_for_content_hash(manifest));
    ok = ok && strcmp(char(local_get(manifest, 'artifact_content_hash', '')), content_hash);
    out = struct('pass', ok, 'detail', sprintf('hash_ok=%d', ok));
end

function out = verify_no_randstream_objects(calibration_run_dir)
    files = dir(fullfile(calibration_run_dir, '*.mat'));
    bad = false;
    for i = 1:numel(files)
        S = load(fullfile(calibration_run_dir, files(i).name));
        if struct_contains_randstream(S)
            bad = true;
            break;
        end
    end
    out = struct('pass', ~bad, 'detail', sprintf('randstream=%d', bad));
end

function tf = struct_contains_randstream(s)
    tf = false;
    if ~isstruct(s)
        return;
    end
    fn = fieldnames(s);
    for i = 1:numel(fn)
        val = s.(fn{i});
        if isa(val, 'RandStream')
            tf = true;
            return;
        end
        if isstruct(val)
            tf = struct_contains_randstream(val);
            if tf
                return;
            end
        end
    end
end

function m = manifest_for_config_hash(manifest)
    m = manifest;
    drop = {'created_utc', 'artifact_content_hash', 'creation_code_commit_sha', ...
        'configuration_hash'};
    for i = 1:numel(drop)
        if isfield(m, drop{i})
            m = rmfield(m, drop{i});
        end
    end
end

function m = manifest_for_content_hash(manifest)
    m = manifest_for_config_hash(manifest);
    if isfield(m, 'configuration_hash')
        m = rmfield(m, 'configuration_hash');
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    elseif istable(s) && ismember(name, s.Properties.VariableNames)
        v = s.(name);
    else
        v = default;
    end
end
