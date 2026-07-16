function report = evaluate_publication_readiness(cfg, options)
% evaluate_publication_readiness  Compute strict publication gate fields.
%
%   report = evaluate_publication_readiness(cfg, options)
%
% options fields (optional):
%   cell_records  - struct array/cell with per-cell outcomes
%   expected_cfg  - forbidden for protocol_tier=publication (internal reference only)
%   has_manifest  - logical
%   has_commit_sha - logical
%   has_artifact_hashes - logical
%   run_dir       - char path (recorded only)
%
% report includes:
%   structurally_complete
%   publication_protocol_complete
%   all_primary_endpoints_finite
%   all_qa_checks_pass
%   artifact_package_complete
%   publication_ready
%   checks  - table-like struct array of named pass/fail items

    if nargin < 2 || isempty(options)
        options = struct();
    end
    options = collapse_options_struct(options);

    tier = '';
    if isfield(cfg, 'protocol_tier')
        tier = char(cfg.protocol_tier);
    end
    if strcmp(tier, 'publication') && isfield(options, 'expected_cfg') && ...
            ~isempty(options.expected_cfg)
        error('evaluate_publication_readiness:ExpectedCfgOverrideForbidden', ...
            ['options.expected_cfg is forbidden for publication readiness; ', ...
             'the protocol reference must be constructed internally.']);
    end

    analysis_set = char(local_get(cfg, 'active_analysis_set', 'confirmatory'));
    expected_cfg = mechanism_ablation_config('publication', analysis_set);
    % Reference fingerprint independent of expected_cfg.created_utc.
    % Until Phase 6 calibration, cfg with frozen_operating_point will not match.
    expected_fp = compute_protocol_fingerprint(expected_cfg);

    cell_records = local_get(options, 'cell_records', {});
    cell_records = normalize_records(cell_records);

    checks = {};

    checks{end+1} = make_check('protocol_tier_is_publication', ...
        strcmp(tier, 'publication'), ...
        sprintf('protocol_tier=%s', tier)); %#ok<*AGROW>

    analysis_set_inferential = is_publication_inferential_analysis_set(analysis_set);
    checks{end+1} = make_check('analysis_set_is_publication_inferential', ...
        analysis_set_inferential, ...
        sprintf('active_analysis_set=%s', analysis_set));

    cfg_fp = '';
    if isfield(cfg, 'protocol_fingerprint')
        cfg_fp = char(cfg.protocol_fingerprint);
    end
    recomputed_fp = compute_protocol_fingerprint(cfg);
    checks{end+1} = make_check('stored_fingerprint_matches_cfg', ...
        strcmp(cfg_fp, recomputed_fp), ...
        sprintf('stored=%s recomputed=%s', cfg_fp, recomputed_fp));
    checks{end+1} = make_check('fingerprint_matches_publication_reference', ...
        strcmp(recomputed_fp, expected_fp), ...
        sprintf('cfg=%s expected=%s', recomputed_fp, expected_fp));

    checks{end+1} = make_check('pilot_not_for_publication_false', ...
        isfield(cfg, 'pilot_not_for_publication') && ~logical(cfg.pilot_not_for_publication), ...
        sprintf('pilot_not_for_publication=%s', mat2str(local_get(cfg, 'pilot_not_for_publication', true))));

    expected_seeds = expected_cfg.seeds(:)';
    expected_keys = cellfun(@(c) c.cell_key, expected_cfg.cells, 'UniformOutput', false);
    expected_keys = expected_keys(:);

    [observed_seeds, observed_keys, pair_keys, statuses] = extract_pairs(cell_records);

    seed_set = unique(observed_seeds);
    checks{end+1} = make_check('exact_expected_seeds', ...
        isempty(setdiff(expected_seeds, seed_set)) && isempty(setdiff(seed_set, expected_seeds)), ...
        sprintf('n_observed_seeds=%d n_expected=%d', numel(seed_set), numel(expected_seeds)));

    missing_seeds = setdiff(expected_seeds, seed_set);
    checks{end+1} = make_check('no_missing_whole_seed', ...
        isempty(missing_seeds), ...
        sprintf('missing_seeds=%s', mat2str(missing_seeds(:)')));

    key_set = unique(observed_keys);
    checks{end+1} = make_check('exact_expected_condition_keys', ...
        isempty(setdiff(expected_keys, key_set)) && isempty(setdiff(key_set, expected_keys)), ...
        sprintf('n_observed_keys=%d n_expected=%d', numel(key_set), numel(expected_keys)));

    missing_keys = setdiff(expected_keys, key_set);
    checks{end+1} = make_check('no_missing_whole_condition', ...
        isempty(missing_keys), ...
        sprintf('missing_keys=%s', strjoin(missing_keys(:)', ',')));

    [~, unique_idx] = unique(pair_keys, 'stable');
    n_dup = numel(pair_keys) - numel(unique_idx);
    checks{end+1} = make_check('no_duplicate_seed_condition_pairs', ...
        n_dup == 0, sprintf('n_duplicates=%d', n_dup));

    expected_pairs = expected_pair_keys(expected_seeds, expected_keys);
    missing_pairs = setdiff(expected_pairs, pair_keys);
    checks{end+1} = make_check('no_missing_pairs', ...
        isempty(missing_pairs), ...
        sprintf('n_missing_pairs=%d', numel(missing_pairs)));

    all_ok = ~isempty(statuses) && all(strcmp(statuses, 'ok'));
    checks{end+1} = make_check('all_cells_status_ok', all_ok, ...
        sprintf('n_status=%d', numel(statuses)));

    [primary_finite, primary_detail] = check_primary_endpoints_finite(cell_records);
    checks{end+1} = make_check('all_primary_endpoints_finite', primary_finite, primary_detail);

    [dale_ok, dale_detail] = check_dale_zero(cell_records);
    checks{end+1} = make_check('dale_violations_zero', dale_ok, dale_detail);

    [qa_ok, qa_detail] = check_qa_bounds(cell_records, cfg);
    checks{end+1} = make_check('qa_resource_and_operating_bands', qa_ok, qa_detail);

    [dde_ok, dde_detail] = check_no_unsupported_dde_as_computed(cell_records);
    checks{end+1} = make_check('no_unsupported_dde_metric_as_computed', dde_ok, dde_detail);

    [tl_ok, tl_detail] = check_temporal_learning_gate(options, cfg);
    checks{end+1} = make_check('temporal_learning_gate_passed', tl_ok, tl_detail);

    [mg_auto_ok, mg_auto_detail] = check_mg_autonomous_protocol_complete(cell_records, cfg);
    checks{end+1} = make_check('mg_autonomous_protocol_complete', mg_auto_ok, mg_auto_detail);

    [mg_ctrl_ok, mg_ctrl_detail] = check_mg_autonomous_matched_controls_complete(cell_records, cfg);
    checks{end+1} = make_check('mg_autonomous_matched_controls_complete', mg_ctrl_ok, mg_ctrl_detail);

    [agg_struct_ok, agg_struct_detail] = check_matched_seed_contrast_structure(options, cfg);
    checks{end+1} = make_check('matched_seed_contrast_structure_complete', ...
        agg_struct_ok, agg_struct_detail);

    % Phase 5B: inference readiness from independently validated artifact only.
    if isfield(options, 'aggregation_inference_complete')
        tier_check = '';
        if isfield(cfg, 'protocol_tier')
            tier_check = char(cfg.protocol_tier);
        end
        if strcmp(tier_check, 'publication')
            error('evaluate_publication_readiness:AggregationInferenceBooleanForbidden', ...
                ['options.aggregation_inference_complete is forbidden for publication ', ...
                 'readiness; use validate_aggregation_inference_artifact(run_dir, cfg).']);
        end
    end

    inf_report = load_and_validate_inference_artifact(options, cfg);
    checks{end+1} = make_check('aggregation_inference_artifact_present', ...
        inf_report.artifact_present, inf_report.artifact_present_detail);
    checks{end+1} = make_check('aggregation_inference_artifact_valid', ...
        inf_report.artifact_valid, inf_report.artifact_valid_detail);
    checks{end+1} = make_check('aggregation_inference_source_hashes_match', ...
        inf_report.source_hashes_match, inf_report.source_hashes_detail);
    checks{end+1} = make_check('aggregation_inference_seed_set_complete', ...
        inf_report.seed_set_complete, inf_report.seed_set_detail);
    checks{end+1} = make_check('aggregation_inference_families_complete', ...
        inf_report.families_complete, inf_report.families_detail);
    checks{end+1} = make_check('aggregation_inference_provenance_valid', ...
        inf_report.provenance_valid, inf_report.provenance_detail);
    checks{end+1} = make_check('aggregation_inference_no_overrides', ...
        inf_report.no_overrides, inf_report.no_overrides_detail);
    agg_inf_ok = inf_report.aggregation_inference_complete;
    checks{end+1} = make_check('aggregation_inference_complete', agg_inf_ok, ...
        sprintf('aggregation_inference_complete=%d', agg_inf_ok));

    has_manifest = logical(local_get(options, 'has_manifest', false));
    has_commit_sha = logical(local_get(options, 'has_commit_sha', false));
    has_artifact_hashes = logical(local_get(options, 'has_artifact_hashes', false));
    checks{end+1} = make_check('manifest_present', has_manifest, sprintf('has_manifest=%d', has_manifest));
    checks{end+1} = make_check('commit_sha_present', has_commit_sha, sprintf('has_commit_sha=%d', has_commit_sha));
    checks{end+1} = make_check('artifact_hashes_present', has_artifact_hashes, ...
        sprintf('has_artifact_hashes=%d', has_artifact_hashes));

    check_arr = [checks{:}];
    pass = [check_arr.pass];

    structurally_complete = ...
        check_named(check_arr, 'no_missing_pairs') && ...
        check_named(check_arr, 'no_duplicate_seed_condition_pairs') && ...
        check_named(check_arr, 'all_cells_status_ok') && ...
        numel(pair_keys) == numel(expected_pairs);

    publication_protocol_complete = ...
        check_named(check_arr, 'protocol_tier_is_publication') && ...
        check_named(check_arr, 'analysis_set_is_publication_inferential') && ...
        check_named(check_arr, 'stored_fingerprint_matches_cfg') && ...
        check_named(check_arr, 'fingerprint_matches_publication_reference') && ...
        check_named(check_arr, 'pilot_not_for_publication_false') && ...
        check_named(check_arr, 'exact_expected_seeds') && ...
        check_named(check_arr, 'exact_expected_condition_keys');

    all_primary_endpoints_finite = check_named(check_arr, 'all_primary_endpoints_finite');
    all_qa_checks_pass = check_named(check_arr, 'dale_violations_zero') && ...
        check_named(check_arr, 'qa_resource_and_operating_bands') && ...
        check_named(check_arr, 'no_unsupported_dde_metric_as_computed') && ...
        check_named(check_arr, 'temporal_learning_gate_passed');
    all_required_secondary_endpoints_complete = ...
        check_named(check_arr, 'mg_autonomous_protocol_complete') && ...
        check_named(check_arr, 'mg_autonomous_matched_controls_complete');
    matched_seed_contrast_structure_complete = ...
        check_named(check_arr, 'matched_seed_contrast_structure_complete');
    aggregation_inference_complete = ...
        check_named(check_arr, 'aggregation_inference_complete');
    artifact_package_complete = check_named(check_arr, 'manifest_present') && ...
        check_named(check_arr, 'commit_sha_present') && ...
        check_named(check_arr, 'artifact_hashes_present');

    publication_ready = publication_protocol_complete && structurally_complete && ...
        all_primary_endpoints_finite && all_qa_checks_pass && ...
        all_required_secondary_endpoints_complete && artifact_package_complete && ...
        matched_seed_contrast_structure_complete && aggregation_inference_complete;

    report = struct();
    report.cfg_protocol_tier = tier;
    report.cfg_active_analysis_set = analysis_set;
    report.cfg_protocol_fingerprint = cfg_fp;
    report.expected_protocol_fingerprint = expected_fp;
    report.run_dir = local_get(options, 'run_dir', '');
    report.checks = check_arr;
    report.structurally_complete = structurally_complete;
    report.publication_protocol_complete = publication_protocol_complete;
    report.all_primary_endpoints_finite = all_primary_endpoints_finite;
    report.all_qa_checks_pass = all_qa_checks_pass;
    report.all_required_secondary_endpoints_complete = all_required_secondary_endpoints_complete;
    report.matched_seed_contrast_structure_complete = matched_seed_contrast_structure_complete;
    report.aggregation_inference_complete = aggregation_inference_complete;
    report.artifact_package_complete = artifact_package_complete;
    report.publication_ready = publication_ready;
    report.n_cells_observed = numel(pair_keys);
    report.n_cells_expected = numel(expected_pairs);
end

function c = make_check(name, pass, detail)
    c = struct('name', name, 'pass', logical(pass), 'detail', char(string(detail)));
end

function tf = check_named(checks, name)
    names = {checks.name};
    idx = find(strcmp(names, name), 1);
    if isempty(idx)
        tf = false;
    else
        tf = checks(idx).pass;
    end
end

function records = normalize_records(cell_records)
    if isempty(cell_records)
        records = struct([]);
        return;
    end
    if iscell(cell_records)
        records = [cell_records{:}];
    else
        records = cell_records;
    end
end

function [seeds, keys, pairs, statuses] = extract_pairs(records)
    if isempty(records)
        seeds = zeros(0, 1);
        keys = {};
        pairs = {};
        statuses = {};
        return;
    end
    n = numel(records);
    seeds = zeros(n, 1);
    keys = cell(n, 1);
    pairs = cell(n, 1);
    statuses = cell(n, 1);
    for i = 1:n
        r = records(i);
        seeds(i) = local_get(r, 'base_seed', local_get(r, 'seed', NaN));
        keys{i} = char(local_get(r, 'cell_key', ''));
        pairs{i} = sprintf('%g|%s', seeds(i), keys{i});
        statuses{i} = char(local_get(r, 'status', ''));
    end
end

function pairs = expected_pair_keys(seeds, keys)
    pairs = {};
    for i = 1:numel(seeds)
        for j = 1:numel(keys)
            pairs{end+1} = sprintf('%g|%s', seeds(i), keys{j}); %#ok<AGROW>
        end
    end
    pairs = pairs(:);
end

function [ok, detail] = check_primary_endpoints_finite(records)
    if isempty(records)
        ok = false;
        detail = 'no_records';
        return;
    end
    bad = 0;
    for i = 1:numel(records)
        r = records(i);
        if ~strcmp(local_get(r, 'status', ''), 'ok')
            bad = bad + 1;
            continue;
        end
        vals = primary_endpoint_values(r);
        if any(~isfinite(vals))
            bad = bad + 1;
        end
    end
    ok = bad == 0;
    detail = sprintf('n_bad_primary=%d / %d', bad, numel(records));
end

function vals = primary_endpoint_values(r)
    mc = NaN;
    if isfield(r, 'memory_capacity') && isfield(r.memory_capacity, 'MC_total')
        mc = r.memory_capacity.MC_total;
    end
    narma = NaN;
    if isfield(r, 'narma') && isfield(r.narma, 'test_nrmse')
        narma = r.narma.test_nrmse;
    end
    mg = NaN;
    if isfield(r, 'mackey_glass') && isfield(r.mackey_glass, 'test_nrmse')
        mg = r.mackey_glass.test_nrmse;
    end
    conv = NaN;
    inconcl = false;
    if isfield(r, 'empirical_convergence')
        ec = r.empirical_convergence;
        if isfield(ec, 'classification') && strcmp(ec.classification, 'inconclusive')
            inconcl = true;
        end
        if isfield(ec, 'median_pair_slope')
            conv = ec.median_pair_slope;
        elseif isfield(ec, 'median_slope')
            conv = ec.median_slope;
        elseif isfield(ec, 'mean_pair_slope')
            conv = ec.mean_pair_slope;
        elseif isfield(ec, 'mean_slope')
            conv = ec.mean_slope;
        end
    end
    wall = local_get(r, 'wall_time_seconds', NaN);
    if inconcl
        vals = [mc; narma; mg; wall];
    else
        vals = [mc; narma; mg; conv; wall];
    end
end

function [ok, detail] = check_dale_zero(records)
    if isempty(records)
        ok = false;
        detail = 'no_records';
        return;
    end
    bad = 0;
    for i = 1:numel(records)
        v = local_get(records(i), 'dale_violations', 0);
        if ~(isfinite(v) && v == 0)
            bad = bad + 1;
        end
    end
    ok = bad == 0;
    detail = sprintf('n_dale_bad=%d', bad);
end

function [ok, detail] = check_qa_bounds(records, cfg)
    if isempty(records)
        ok = false;
        detail = 'no_records';
        return;
    end
    band = [0.05, 0.85];
    sat_max = 0.35;
    silent_max = 0.35;
    if isfield(cfg, 'operating_point')
        op = cfg.operating_point;
        if isfield(op, 'mean_rate_band'); band = op.mean_rate_band; end
        if isfield(op, 'saturation_fraction_max'); sat_max = op.saturation_fraction_max; end
        if isfield(op, 'silent_fraction_max'); silent_max = op.silent_fraction_max; end
    end
    bad = 0;
    for i = 1:numel(records)
        r = records(i);
        if ~isfield(r, 'qa')
            bad = bad + 1;
            continue;
        end
        qa = r.qa;
        if ~(local_get(qa, 'resource_in_unit_interval', false))
            bad = bad + 1;
            continue;
        end
        mr = local_get(qa, 'mean_rate', NaN);
        sat = local_get(qa, 'saturation_fraction', NaN);
        sil = local_get(qa, 'silent_fraction', NaN);
        if ~(isfinite(mr) && mr >= band(1) && mr <= band(2) && ...
                isfinite(sat) && sat <= sat_max && ...
                isfinite(sil) && sil <= silent_max)
            bad = bad + 1;
        end
    end
    ok = bad == 0;
    detail = sprintf('n_qa_bad=%d', bad);
end

function [ok, detail] = check_no_unsupported_dde_as_computed(records)
    if isempty(records)
        ok = false;
        detail = 'no_records';
        return;
    end
    bad = 0;
    for i = 1:numel(records)
        r = records(i);
        mode = char(local_get(r, 'mode', ''));
        if ~strcmp(mode, 'DDE')
            continue;
        end
        % Finite LLE must not appear as a computed DDE metric.
        if isfield(r, 'lle') && isfinite(r.lle)
            status = char(local_get(r, 'lle_status', ''));
            if ~contains(status, 'unsupported')
                bad = bad + 1;
            end
        end
    end
    ok = bad == 0;
    detail = sprintf('n_dde_lle_as_computed=%d', bad);
end

function [ok, detail] = check_temporal_learning_gate(options, cfg)
% Fail closed unless a complete temporal_learning_gate_v1 result is present
% and passed. Legacy direct-input / instantaneous readout checks never satisfy
% this condition.
    g = local_get(options, 'temporal_learning_gate', []);
    if isempty(g) || ~isstruct(g) || numel(g) ~= 1
        ok = false;
        detail = 'temporal_learning_gate_missing';
        return;
    end
    expected_version = 'temporal_learning_gate_v1';
    n_expected = NaN;
    if isfield(cfg, 'temporal_learning_gate')
        tg = cfg.temporal_learning_gate;
        if isfield(tg, 'protocol_version')
            expected_version = char(tg.protocol_version);
        end
        if isfield(tg, 'model_seeds')
            n_expected = numel(tg.model_seeds);
        end
    end
    reasons = {};
    if ~strcmp(char(local_get(g, 'status', '')), 'complete')
        reasons{end+1} = 'status_not_complete'; %#ok<AGROW>
    end
    if ~logical(local_get(g, 'passed', false))
        reasons{end+1} = 'passed_false'; %#ok<AGROW>
    end
    if logical(local_get(g, 'include_input', true))
        reasons{end+1} = 'include_input_not_false'; %#ok<AGROW>
    end
    if ~strcmp(char(local_get(g, 'protocol_version', '')), expected_version)
        reasons{end+1} = 'protocol_version_mismatch'; %#ok<AGROW>
    end
    required_controls = { ...
        'current_input_only_control', ...
        'no_recurrent_coupling_control', ...
        'shuffled_target_control', ...
        'exact_history_control'};
    if ~isfield(g, 'seed_results') || isempty(g.seed_results)
        reasons{end+1} = 'seed_results_missing'; %#ok<AGROW>
    else
        if isfinite(n_expected) && numel(g.seed_results) ~= n_expected
            reasons{end+1} = 'seed_row_count_mismatch'; %#ok<AGROW>
        end
        for i = 1:numel(g.seed_results)
            sr = g.seed_results(i);
            for c = 1:numel(required_controls)
                if ~isfield(sr, required_controls{c})
                    reasons{end+1} = ['missing_' required_controls{c}]; %#ok<AGROW>
                end
            end
            if isfield(sr, 'mesn') && isfield(sr.mesn, 'metrics')
                m = sr.mesn.metrics;
                if any(~isfinite([local_get(m, 'nrmse', NaN), local_get(m, 'r2', NaN)]))
                    reasons{end+1} = 'nonfinite_mesn_metric'; %#ok<AGROW>
                end
            else
                reasons{end+1} = 'mesn_metrics_missing'; %#ok<AGROW>
            end
        end
    end
    % Legacy direct-input pipeline must not be accepted as this gate.
    if isfield(g, 'legacy_direct_input_check') && logical(g.legacy_direct_input_check)
        reasons{end+1} = 'legacy_direct_input_check_cannot_satisfy_gate'; %#ok<AGROW>
    end
    if isfield(g, 'gate_name') && contains(lower(char(g.gate_name)), 'direct_input')
        reasons{end+1} = 'direct_input_name_rejected'; %#ok<AGROW>
    end
    ok = isempty(reasons);
    if ok
        detail = 'temporal_learning_gate_ok';
    else
        detail = strjoin(unique(reasons, 'stable'), ',');
    end
end

function [ok, detail] = check_mg_autonomous_protocol_complete(records, cfg)
% Every publication ODE cell must have a valid computed MG autonomous result;
% every DDE cell must have unsupported_not_computed. Secondary endpoint only.
    if isempty(records)
        ok = false;
        detail = 'no_records';
        return;
    end
    rollout_cfg = [];
    if isfield(cfg, 'mg_autonomous_rollout')
        rollout_cfg = cfg.mg_autonomous_rollout;
    end
    if isempty(rollout_cfg)
        ok = false;
        detail = 'missing_mg_autonomous_rollout_cfg';
        return;
    end
    bad = 0;
    for i = 1:numel(records)
        r = records(i);
        mode = char(local_get(r, 'mode', ''));
        rollout = extract_cell_rollout(r);
        if isempty(rollout)
            bad = bad + 1;
            continue;
        end
        [vok, ~] = validate_mg_autonomous_rollout_result(rollout, ...
            struct('mg_autonomous_rollout', rollout_cfg), mode);
        if ~vok
            bad = bad + 1;
            continue;
        end
        st = char(local_get(rollout, 'status', ''));
        if strcmp(mode, 'ODE') && strcmp(st, 'skipped')
            bad = bad + 1;
        elseif strcmp(mode, 'ODE') && ~strcmp(st, 'computed')
            bad = bad + 1;
        elseif strcmp(mode, 'DDE') && ~strcmp(st, 'unsupported_not_computed')
            bad = bad + 1;
        end
    end
    ok = bad == 0;
    detail = sprintf('n_mg_autonomous_bad=%d / %d', bad, numel(records));
end

function [ok, detail] = check_mg_autonomous_matched_controls_complete(records, cfg)
% Matched autonomous controls: shared-bundle provenance for ODE; DDE N/A.
    if isempty(records)
        ok = false;
        detail = 'no_records';
        return;
    end
    rollout_cfg = local_get(cfg, 'mg_autonomous_rollout', []);
    bb = local_get(cfg, 'benchmark_baselines', []);
    if isempty(rollout_cfg) || isempty(bb)
        ok = false;
        detail = 'missing_rollout_or_baseline_cfg';
        return;
    end
    bad = 0;
    for i = 1:numel(records)
        r = records(i);
        mode = char(local_get(r, 'mode', ''));
        rollout = extract_cell_rollout(r);
        if isempty(rollout) || ~isfield(rollout, 'controls')
            bad = bad + 1;
            continue;
        end
        ctrl = rollout.controls;
        feature_mode = char(local_get(r, 'which_states', ...
            local_get(r, 'feature_mode', 'x')));
        if strcmp(mode, 'DDE')
            [vok, ~] = validate_mg_autonomous_baseline_controls(ctrl, struct( ...
                'cell_mode', 'DDE', ...
                'require_production_provenance', false));
            if ~vok
                bad = bad + 1;
            end
            continue;
        end
        % ODE
        if ~strcmp(char(local_get(ctrl, 'status', '')), 'computed')
            bad = bad + 1;
            continue;
        end
        bundle_id = '';
        if isfield(r, 'matched_baseline_bundle_id')
            bundle_id = char(r.matched_baseline_bundle_id);
        elseif isfield(ctrl, 'bundle_id')
            bundle_id = char(ctrl.bundle_id);
        end
        exp = struct( ...
            'cell_mode', 'ODE', ...
            'require_production_provenance', true, ...
            'rollout_cfg', rollout_cfg, ...
            'feature_mode', feature_mode, ...
            'dale_keys', bb.dale_mesn_control_keys, ...
            'model_metrics', local_get(rollout, 'metrics', struct()), ...
            'bundle_id', bundle_id, ...
            'require_bundle_id', true);
        if isfield(r, 'base_seed')
            exp.base_seed = r.base_seed;
        end
        [vok, ~] = validate_mg_autonomous_baseline_controls(ctrl, exp);
        if ~vok
            bad = bad + 1;
            continue;
        end
        if isfield(ctrl, 'bundle_id') && ~isempty(bundle_id) && ...
                ~strcmp(char(ctrl.bundle_id), bundle_id)
            bad = bad + 1;
        end
    end
    ok = bad == 0;
    detail = sprintf('n_mg_autonomous_controls_bad=%d / %d', bad, numel(records));
end

function rollout = extract_cell_rollout(r)
    rollout = [];
    if isfield(r, 'mackey_glass') && isstruct(r.mackey_glass)
        mg = r.mackey_glass;
        if isfield(mg, 'rollout') && isstruct(mg.rollout)
            rollout = mg.rollout;
            return;
        end
        % Reconstruct minimal DDE/ODE status from compact fields when present
        if isfield(mg, 'autonomous_status')
            st = char(mg.autonomous_status);
            mode = char(local_get(r, 'mode', ''));
            rollout = struct('status', st, 'mode', mode);
            if isfield(mg, 'rollout')
                rollout = mg.rollout;
            else
                if strcmp(st, 'unsupported_not_computed')
                    rollout.protocol_version = 'mackey_glass_autonomous_rollout_v1';
                    rollout.reason = 'DDE autonomous continuation is not implemented';
                    rollout.predictions = [];
                    rollout.metrics = [];
                    rollout.evaluation_provenance = struct('mode', 'unsupported');
                end
            end
        end
    end
end

function [ok, detail] = check_matched_seed_contrast_structure(options, cfg)
% Phase 5A structural aggregation gate (no inference).
    agg = local_get(options, 'aggregation', struct());
    if isempty(agg) || ~isstruct(agg)
        % Fall back to explicit option or artifact presence under run_dir.
        if isfield(options, 'matched_seed_contrast_structure_complete')
            ok = logical(options.matched_seed_contrast_structure_complete);
            detail = sprintf('option_flag=%d', ok);
            return;
        end
        run_dir = char(local_get(options, 'run_dir', ''));
        if ~isempty(run_dir)
            art = fullfile(run_dir, 'aggregation', 'aggregate_seed_contrasts.mat');
            if isfile(art)
                try
                    S = load(art, 'aggregate');
                    if isfield(S, 'aggregate') && isfield(S.aggregate, ...
                            'matched_seed_contrast_structure_complete')
                        ok = logical(S.aggregate.matched_seed_contrast_structure_complete);
                        detail = sprintf('artifact_flag=%d', ok);
                        return;
                    end
                catch
                end
            end
        end
        ok = false;
        detail = 'aggregation_missing';
        return;
    end
    ok = isfield(agg, 'matched_seed_contrast_structure_complete') && ...
        logical(agg.matched_seed_contrast_structure_complete) && ...
        strcmp(char(local_get(agg, 'status', '')), 'ok');
    inf_status = char(local_get(agg, 'inference_status', ''));
    if ~isempty(inf_status) && ...
            ~(strcmp(inf_status, 'deferred_to_phase_5b') || strcmp(inf_status, 'complete'))
        ok = false;
    end
    % Partial publication runs cannot satisfy this gate
    if isfield(cfg, 'protocol_tier') && strcmp(char(cfg.protocol_tier), 'publication')
        if isfield(agg, 'status') && ...
                strcmp(char(agg.status), 'diagnostic_incomplete_not_for_inference')
            ok = false;
        end
    end
    detail = sprintf('status=%s structure_complete=%d', ...
        char(local_get(agg, 'status', '')), ok);
end

function options = collapse_options_struct(options)
% Repair the common footgun struct('cell_records', records, 'flag', true)
% which expands into a struct array when records is non-scalar.
    if ~isstruct(options) || numel(options) <= 1
        return;
    end
    collapsed = struct();
    fn = fieldnames(options);
    for i = 1:numel(fn)
        name = fn{i};
        if strcmp(name, 'cell_records')
            collapsed.cell_records = [options.(name)];
        else
            collapsed.(name) = options(1).(name);
        end
    end
    options = collapsed;
end

function v = local_get(s, name, default)
    if ~isstruct(s) || numel(s) ~= 1 || ~isfield(s, name)
        v = default;
        return;
    end
    v = s.(name);
    if isempty(v)
        v = default;
    end
end

function inf_report = load_and_validate_inference_artifact(options, cfg)
    inf_report = struct();
    inf_report.artifact_present = false;
    inf_report.artifact_present_detail = 'no_run_dir';
    inf_report.artifact_valid = false;
    inf_report.artifact_valid_detail = 'not_validated';
    inf_report.source_hashes_match = false;
    inf_report.source_hashes_detail = 'not_validated';
    inf_report.seed_set_complete = false;
    inf_report.seed_set_detail = 'not_validated';
    inf_report.families_complete = false;
    inf_report.families_detail = 'not_validated';
    inf_report.provenance_valid = false;
    inf_report.provenance_detail = 'not_validated';
    inf_report.no_overrides = false;
    inf_report.no_overrides_detail = 'not_validated';
    inf_report.aggregation_inference_complete = false;

    run_dir = char(local_get(options, 'run_dir', ''));
    if isempty(run_dir)
        inf_report.artifact_present_detail = 'run_dir_missing';
        return;
    end

    manifest_path = fullfile(run_dir, 'aggregation', 'inference', ...
        'inference_manifest.mat');
    inf_report.artifact_present = isfile(manifest_path);
    inf_report.artifact_present_detail = manifest_path;
    if ~inf_report.artifact_present
        return;
    end

    try
        val = validate_aggregation_inference_artifact(run_dir, cfg);
    catch ME
        inf_report.artifact_valid_detail = ME.identifier;
        return;
    end

    inf_report.artifact_valid = val.valid;
    inf_report.artifact_valid_detail = strjoin(val.reasons, ',');
    if isempty(inf_report.artifact_valid_detail)
        inf_report.artifact_valid_detail = 'valid';
    end

    inf_report.aggregation_inference_complete = val.aggregation_inference_complete;

    names = {val.checks.name};
    pass = [val.checks.pass];
    inf_report.source_hashes_match = named_pass(val.checks, ...
        'aggregation_inference_source_hashes_match');
    inf_report.source_hashes_detail = detail_for(val.checks, ...
        'aggregation_inference_source_hashes_match');
    inf_report.seed_set_complete = named_pass(val.checks, ...
        'aggregation_inference_seed_set_complete');
    inf_report.seed_set_detail = detail_for(val.checks, ...
        'aggregation_inference_seed_set_complete');
    inf_report.families_complete = named_pass(val.checks, ...
        'aggregation_inference_families_complete');
    inf_report.families_detail = detail_for(val.checks, ...
        'aggregation_inference_families_complete');
    inf_report.provenance_valid = named_pass(val.checks, ...
        'aggregation_inference_provenance_valid');
    inf_report.provenance_detail = detail_for(val.checks, ...
        'aggregation_inference_provenance_valid');
    inf_report.no_overrides = named_pass(val.checks, ...
        'aggregation_inference_no_overrides');
    inf_report.no_overrides_detail = detail_for(val.checks, ...
        'aggregation_inference_no_overrides');
end

function tf = named_pass(checks, name)
    idx = find(strcmp({checks.name}, name), 1);
    if isempty(idx)
        tf = false;
    else
        tf = checks(idx).pass;
    end
end

function d = detail_for(checks, name)
    idx = find(strcmp({checks.name}, name), 1);
    if isempty(idx)
        d = 'missing_check';
    else
        d = checks(idx).detail;
    end
end
