function report = evaluate_publication_readiness(cfg, options)
% evaluate_publication_readiness  Compute strict publication gate fields.
%
%   report = evaluate_publication_readiness(cfg, options)
%
% options fields (optional):
%   cell_records  - struct array/cell with per-cell outcomes
%   expected_cfg  - frozen publication reference (default: mechanism_ablation_config('publication'))
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

    expected_cfg = local_get(options, 'expected_cfg', []);
    if isempty(expected_cfg)
        expected_cfg = mechanism_ablation_config('publication');
    end
    % Reference fingerprint independent of expected_cfg.created_utc
    expected_fp = compute_protocol_fingerprint(expected_cfg);

    cell_records = local_get(options, 'cell_records', {});
    cell_records = normalize_records(cell_records);

    checks = {};

    tier = '';
    if isfield(cfg, 'protocol_tier')
        tier = char(cfg.protocol_tier);
    end
    checks{end+1} = make_check('protocol_tier_is_publication', ...
        strcmp(tier, 'publication'), ...
        sprintf('protocol_tier=%s', tier)); %#ok<*AGROW>

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
        check_named(check_arr, 'stored_fingerprint_matches_cfg') && ...
        check_named(check_arr, 'fingerprint_matches_publication_reference') && ...
        check_named(check_arr, 'pilot_not_for_publication_false') && ...
        check_named(check_arr, 'exact_expected_seeds') && ...
        check_named(check_arr, 'exact_expected_condition_keys');

    all_primary_endpoints_finite = check_named(check_arr, 'all_primary_endpoints_finite');
    all_qa_checks_pass = check_named(check_arr, 'dale_violations_zero') && ...
        check_named(check_arr, 'qa_resource_and_operating_bands') && ...
        check_named(check_arr, 'no_unsupported_dde_metric_as_computed');
    artifact_package_complete = check_named(check_arr, 'manifest_present') && ...
        check_named(check_arr, 'commit_sha_present') && ...
        check_named(check_arr, 'artifact_hashes_present');

    publication_ready = publication_protocol_complete && structurally_complete && ...
        all_primary_endpoints_finite && all_qa_checks_pass && artifact_package_complete;

    report = struct();
    report.cfg_protocol_tier = tier;
    report.cfg_protocol_fingerprint = cfg_fp;
    report.expected_protocol_fingerprint = expected_fp;
    report.run_dir = local_get(options, 'run_dir', '');
    report.checks = check_arr;
    report.structurally_complete = structurally_complete;
    report.publication_protocol_complete = publication_protocol_complete;
    report.all_primary_endpoints_finite = all_primary_endpoints_finite;
    report.all_qa_checks_pass = all_qa_checks_pass;
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

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
