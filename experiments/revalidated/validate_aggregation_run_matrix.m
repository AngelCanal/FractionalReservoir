function report = validate_aggregation_run_matrix(run_dir, cfg)
%VALIDATE_AGGREGATION_RUN_MATRIX  Fail-closed seed x cell completeness check.
%
%   report = validate_aggregation_run_matrix(run_dir, cfg)
%
% Expected matrix comes from cfg.seeds x cfg.cells — never from observed unique
% keys alone. Missing seeds/conditions, duplicates, failed cells, wrong
% fingerprint/analysis_set, or nonfinite required endpoints set report.ok=false.
%
% Does not call run_ablation_cell or recompute models.
%
% See also: aggregate_ablation_results, build_aggregation_tables

    report = struct();
    report.ok = true;
    report.reasons = {};
    report.run_dir = char(run_dir);
    report.cells = {};
    report.source_files = {};
    report.expected_seeds = [];
    report.expected_cell_keys = {};
    report.expected_pairs = {};
    report.observed_pairs = {};
    report.baseline_by_seed = containers.Map('KeyType', 'double', 'ValueType', 'any');
    report.baselines_dir_present = false;
    report.expected_pair_count = 0;
    report.observed_pair_count = 0;

    if nargin < 2 || ~isstruct(cfg)
        report.ok = false;
        report.reasons = {'cfg_missing_or_invalid'};
        return;
    end

    %% Required cfg fields
    required_cfg = {'seeds', 'cells', 'protocol_fingerprint', ...
        'active_analysis_set', 'protocol_tier', 'aggregation_plan'};
    for i = 1:numel(required_cfg)
        if ~isfield(cfg, required_cfg{i}) || isempty(cfg.(required_cfg{i}))
            report = add_reason(report, sprintf('cfg_missing_%s', required_cfg{i}));
        end
    end
    if ~report.ok
        return;
    end

    %% Fingerprint match
    try
        fp = compute_protocol_fingerprint(cfg);
    catch ME
        report = add_reason(report, sprintf('fingerprint_recompute_failed:%s', ME.message));
        return;
    end
    if ~strcmp(char(cfg.protocol_fingerprint), char(fp))
        report = add_reason(report, 'protocol_fingerprint_mismatch');
    end

    tier = char(cfg.protocol_tier);
    if isempty(tier)
        report = add_reason(report, 'protocol_tier_empty');
    end

    analysis_set = char(cfg.active_analysis_set);
    if ~any(strcmp(analysis_set, ...
            {'confirmatory', 'sfa_sensitivity', 'feature_exploratory'}))
        report = add_reason(report, sprintf('unknown_active_analysis_set:%s', analysis_set));
    end

    seeds = cfg.seeds(:);
    if isempty(seeds) || any(~isfinite(double(seeds)))
        report = add_reason(report, 'cfg_seeds_invalid');
        return;
    end
    seeds = double(seeds);
    if numel(unique(seeds)) ~= numel(seeds)
        report = add_reason(report, 'cfg_seeds_duplicate');
    end

    cell_keys = cell(numel(cfg.cells), 1);
    for i = 1:numel(cfg.cells)
        cell_keys{i} = char(cfg.cells{i}.cell_key);
    end
    if numel(unique(cell_keys)) ~= numel(cell_keys)
        report = add_reason(report, 'cfg_cells_duplicate_keys');
    end

    report.expected_seeds = seeds;
    report.expected_cell_keys = cell_keys(:);

    expected_pairs = cell(numel(seeds) * numel(cell_keys), 1);
    ip = 0;
    for is = 1:numel(seeds)
        for ik = 1:numel(cell_keys)
            ip = ip + 1;
            expected_pairs{ip} = struct( ...
                'seed', seeds(is), ...
                'cell_key', cell_keys{ik}, ...
                'file', sprintf('seed_%d__%s.mat', seeds(is), cell_keys{ik}));
        end
    end
    report.expected_pairs = expected_pairs;
    report.expected_pair_count = numel(expected_pairs);

    %% Discover observed cell files
    cells_dir = fullfile(run_dir, 'cells');
    if ~isfolder(cells_dir)
        report = add_reason(report, 'cells_dir_missing');
        return;
    end
    files = dir(fullfile(cells_dir, 'seed_*.mat'));
    observed_map = containers.Map('KeyType', 'char', 'ValueType', 'any');
    observed_pairs = {};
    for i = 1:numel(files)
        fname = files(i).name;
        tok = regexp(fname, '^seed_(-?\d+)__(.+)\.mat$', 'tokens', 'once');
        if isempty(tok)
            report = add_reason(report, sprintf('unparseable_cell_filename:%s', fname));
            continue;
        end
        seed_f = str2double(tok{1});
        key_f = tok{2};
        pair_id = sprintf('%d|%s', seed_f, key_f);
        if observed_map.isKey(pair_id)
            report = add_reason(report, sprintf('duplicate_seed_cell_pair:%s', pair_id));
        end
        observed_map(pair_id) = fname;
        observed_pairs{end+1} = struct( ... %#ok<AGROW>
            'seed', seed_f, 'cell_key', key_f, 'file', fname);
    end
    report.observed_pairs = observed_pairs;
    report.observed_pair_count = numel(observed_pairs);

    %% Extra seeds / keys
    if ~isempty(observed_pairs)
        obs_seeds = unique(cellfun(@(p) p.seed, observed_pairs));
        obs_keys = unique(cellfun(@(p) p.cell_key, observed_pairs, ...
            'UniformOutput', false));
        for i = 1:numel(obs_seeds)
            if ~any(seeds == obs_seeds(i))
                report = add_reason(report, sprintf('extra_seed:%g', obs_seeds(i)));
            end
        end
        for i = 1:numel(obs_keys)
            if ~any(strcmp(obs_keys{i}, cell_keys))
                report = add_reason(report, sprintf('extra_cell_key:%s', obs_keys{i}));
            end
        end
    end

    %% Exact Cartesian product + per-cell checks
    cells = cell(numel(expected_pairs), 1);
    source_files = cell(numel(expected_pairs), 1);
    for i = 1:numel(expected_pairs)
        ep = expected_pairs{i};
        pair_id = sprintf('%d|%s', ep.seed, ep.cell_key);
        if ~observed_map.isKey(pair_id)
            report = add_reason(report, sprintf('missing_pair:seed_%d__%s', ...
                ep.seed, ep.cell_key));
            continue;
        end
        fname = observed_map(pair_id);
        fpath = fullfile(cells_dir, fname);
        source_files{i} = fname;
        try
            S = load(fpath, 'cell_result');
        catch ME
            report = add_reason(report, sprintf('load_failed:%s:%s', fname, ME.message));
            continue;
        end
        if ~isfield(S, 'cell_result')
            report = add_reason(report, sprintf('missing_cell_result_var:%s', fname));
            continue;
        end
        cr = S.cell_result;
        cells{i} = cr;

        if ~isfield(cr, 'base_seed') || double(cr.base_seed) ~= double(ep.seed)
            report = add_reason(report, sprintf('base_seed_mismatch:%s', fname));
        end
        if ~isfield(cr, 'cell_key') || ~strcmp(char(cr.cell_key), ep.cell_key)
            report = add_reason(report, sprintf('cell_key_mismatch:%s', fname));
        end

        if ~isfield(cr, 'status') || ~strcmp(char(cr.status), 'ok')
            report = add_reason(report, sprintf('failed_cell:%s:status=%s', ...
                fname, char(local_get(cr, 'status', ''))));
        end

        cr_as = char(local_get(cr, 'analysis_set', ''));
        if ~isempty(cr_as) && ~strcmp(cr_as, analysis_set)
            report = add_reason(report, sprintf('analysis_set_mismatch:%s', fname));
        end
        cr_fp = char(local_get(cr, 'protocol_fingerprint', ''));
        if ~isempty(cr_fp) && ~strcmp(cr_fp, char(cfg.protocol_fingerprint))
            report = add_reason(report, sprintf('cell_fingerprint_mismatch:%s', fname));
        end
        cr_tier = char(local_get(cr, 'protocol_tier', ''));
        if ~isempty(cr_tier) && ~strcmp(cr_tier, tier)
            report = add_reason(report, sprintf('cell_protocol_tier_mismatch:%s', fname));
        end

        [ep_ok, ep_reason] = check_nonautonomous_endpoints(cr);
        if ~ep_ok
            report = add_reason(report, sprintf('%s:%s', ep_reason, fname));
        end

        [auto_ok, auto_reason] = check_autonomous_endpoints(cr, cfg);
        if ~auto_ok
            report = add_reason(report, sprintf('%s:%s', auto_reason, fname));
        end

        [dale_ok, dale_reason] = check_dale_reference_keys(cr, cfg);
        if ~dale_ok
            report = add_reason(report, sprintf('%s:%s', dale_reason, fname));
        end
    end

    report.cells = cells;
    report.source_files = source_files;

    %% Baseline artifacts (when present)
    baselines_dir = fullfile(run_dir, 'baselines');
    report.baselines_dir_present = isfolder(baselines_dir);
    if report.baselines_dir_present
        for is = 1:numel(seeds)
            seed = seeds(is);
            bpath = fullfile(baselines_dir, ...
                sprintf('seed_%d_matched_task_baselines.mat', seed));
            if ~isfile(bpath)
                report = add_reason(report, sprintf('missing_baseline_artifact:seed_%d', seed));
                continue;
            end
            try
                Sb = load(bpath);
            catch ME
                report = add_reason(report, sprintf('baseline_load_failed:seed_%d:%s', ...
                    seed, ME.message));
                continue;
            end
            bundle = [];
            if isfield(Sb, 'matched_task_baselines')
                bundle = Sb.matched_task_baselines;
            elseif isfield(Sb, 'bundle')
                bundle = Sb.bundle;
            end
            if isempty(bundle)
                report = add_reason(report, ...
                    sprintf('baseline_bundle_missing_var:seed_%d', seed));
                continue;
            end
            if ~strcmp(char(local_get(bundle, 'schema_version', '')), ...
                    'seed_matched_baseline_bundle_v2')
                report = add_reason(report, sprintf('baseline_schema_not_v2:seed_%d', seed));
            end
            if isfield(bundle, 'protocol_fingerprint') && ...
                    ~strcmp(char(bundle.protocol_fingerprint), ...
                    char(cfg.protocol_fingerprint))
                report = add_reason(report, ...
                    sprintf('baseline_fingerprint_mismatch:seed_%d', seed));
            end
            if isfield(bundle, 'base_seed') && double(bundle.base_seed) ~= double(seed)
                report = add_reason(report, ...
                    sprintf('baseline_base_seed_mismatch:seed_%d', seed));
            end
            entry = struct( ...
                'seed', seed, ...
                'bundle', bundle, ...
                'path', bpath, ...
                'bundle_id', char(local_get(bundle, 'bundle_id', '')));
            report.baseline_by_seed(seed) = entry;
        end

        for i = 1:numel(cells)
            cr = cells{i};
            if isempty(cr)
                continue;
            end
            seed = double(cr.base_seed);
            if ~report.baseline_by_seed.isKey(seed)
                continue;
            end
            entry = report.baseline_by_seed(seed);
            bid_cell = char(local_get(cr, 'matched_baseline_bundle_id', ''));
            bid_b = char(entry.bundle_id);
            if ~isempty(bid_cell) && ~isempty(bid_b) && ~strcmp(bid_cell, bid_b)
                report = add_reason(report, sprintf( ...
                    'bundle_id_mismatch:seed_%d__%s', seed, char(cr.cell_key)));
            end
        end
    end

    %% Autonomous control content hashes consistent within seed
    hash_reasons = check_autonomous_content_hashes(cells);
    for i = 1:numel(hash_reasons)
        report = add_reason(report, hash_reasons{i});
    end

    report.ok = isempty(report.reasons);
end

% =============================================================================
function report = add_reason(report, reason)
    report.ok = false;
    report.reasons{end+1} = reason; %#ok<AGROW>
end

function [ok, reason] = check_nonautonomous_endpoints(cr)
    ok = true;
    reason = '';
    checks = { ...
        'mc_total', nested_num(cr, {'memory_capacity', 'MC_total'}); ...
        'narma_test_nrmse', nested_num(cr, {'narma', 'test_nrmse'}); ...
        'mg_onestep_test_nrmse', nested_num(cr, {'mackey_glass', 'test_nrmse'}); ...
        'convergence_slope', nested_num(cr, {'empirical_convergence', 'median_pair_slope'}); ...
        'wall_time_seconds', local_num(cr, 'wall_time_seconds')};
    for i = 1:size(checks, 1)
        if ~isfinite(checks{i, 2})
            ok = false;
            reason = sprintf('nonfinite_%s', checks{i, 1});
            return;
        end
    end
end

function [ok, reason] = check_autonomous_endpoints(cr, cfg)
    ok = true;
    reason = '';
    mode = char(local_get(cr, 'mode', ''));
    if isempty(mode)
        factors = parse_factors_from_cell(cr);
        if strcmp(factors.D, 'dde_on')
            mode = 'DDE';
        else
            mode = 'ODE';
        end
    end

    status = autonomous_status(cr);
    full_nrmse = autonomous_metric(cr, 'pooled_nrmse_full_horizon');
    vh = autonomous_metric(cr, 'median_valid_horizon');
    frac = autonomous_metric(cr, 'fraction_right_censored');

    if strcmp(mode, 'DDE')
        if ~strcmp(status, 'unsupported_not_computed')
            ok = false;
            reason = sprintf('dde_autonomous_status_not_unsupported:%s', status);
            return;
        end
        if isfinite(full_nrmse) || isfinite(vh) || isfinite(frac)
            ok = false;
            reason = 'dde_autonomous_finite_values_forbidden';
            return;
        end
        return;
    end

    % ODE: required finite when secondary endpoints are in protocol, or when
    % the cell reports a computed autonomous status.
    secondary_enabled = true;
    if isfield(cfg, 'secondary_enabled')
        secondary_enabled = logical(cfg.secondary_enabled);
    end
    if any(strcmp(status, {'computed', 'ok'})) || startsWith(char(status), 'computed')
        if ~isfinite(full_nrmse)
            ok = false;
            reason = 'ode_autonomous_full_nrmse_nonfinite';
            return;
        end
        if ~isfinite(vh)
            ok = false;
            reason = 'ode_autonomous_valid_horizon_nonfinite';
            return;
        end
        if ~isfinite(frac)
            ok = false;
            reason = 'ode_autonomous_fraction_right_censored_nonfinite';
            return;
        end
        return;
    end
    if ~secondary_enabled
        % Smoke/pilot primary-only runs may omit autonomous rollout.
        return;
    end
    if strcmp(status, 'unsupported_not_computed')
        ok = false;
        reason = 'ode_autonomous_unsupported_not_computed';
        return;
    end
    if ~isempty(status)
        ok = false;
        reason = sprintf('ode_autonomous_bad_status:%s', status);
        return;
    end
    if ~(isfinite(full_nrmse) && isfinite(vh) && isfinite(frac))
        ok = false;
        reason = 'ode_autonomous_metrics_nonfinite';
    end
end

function [ok, reason] = check_dale_reference_keys(cr, cfg)
    ok = true;
    reason = '';
    factors = parse_factors_from_cell(cr);
    fm = factors.F;
    if isempty(fm) || (~strcmp(fm, 'x') && ~strcmp(fm, 'r'))
        return;
    end
    bb = local_get(cfg, 'benchmark_baselines', struct());
    dale_keys = local_get(bb, 'dale_mesn_control_keys', struct( ...
        'feat_x', 'adapt-off__std-off__delay-ode_off__feat-x', ...
        'feat_r', 'adapt-off__std-off__delay-ode_off__feat-r'));
    expect = dale_mesn_control_reference_key(fm, dale_keys);

    refs = collect_dale_refs(cr);
    for i = 1:numel(refs)
        if ~strcmp(char(refs{i}), expect)
            ok = false;
            reason = sprintf('dale_reference_key_invalid:got=%s:expect=%s', ...
                char(refs{i}), expect);
            return;
        end
    end
end

function refs = collect_dale_refs(cr)
    refs = {};
    paths = { ...
        {'narma', 'baselines', 'dale_mesn_control', 'dale_mesn_control_reference'}; ...
        {'mackey_glass', 'baselines', 'dale_mesn_control', 'dale_mesn_control_reference'}; ...
        {'mackey_glass', 'rollout', 'controls', 'dale_mesn_control', 'dale_mesn_control_reference'}};
    for i = 1:numel(paths)
        v = nested_get(cr, paths{i}, '');
        if ~isempty(v)
            refs{end+1} = char(v); %#ok<AGROW>
        end
    end
end

function reasons = check_autonomous_content_hashes(cells)
    reasons = {};
    by_seed = containers.Map('KeyType', 'double', 'ValueType', 'any');
    for i = 1:numel(cells)
        cr = cells{i};
        if isempty(cr)
            continue;
        end
        seed = double(local_get(cr, 'base_seed', NaN));
        if ~isfinite(seed)
            continue;
        end
        h = autonomous_content_hash(cr);
        if isempty(h)
            continue;
        end
        if ~by_seed.isKey(seed)
            by_seed(seed) = {h};
        else
            lst = by_seed(seed);
            lst{end+1} = h; %#ok<AGROW>
            by_seed(seed) = lst;
        end
    end
    ks = by_seed.keys;
    for i = 1:numel(ks)
        lst = unique(by_seed(ks{i}));
        if numel(lst) > 1
            reasons{end+1} = sprintf( ... %#ok<AGROW>
                'autonomous_content_hash_mismatch:seed_%d', ks{i});
        end
    end
end

function h = autonomous_content_hash(cr)
    h = '';
    if isfield(cr, 'mackey_glass') && isstruct(cr.mackey_glass)
        mg = cr.mackey_glass;
        if isfield(mg, 'rollout') && isstruct(mg.rollout) && ...
                isfield(mg.rollout, 'controls') && isstruct(mg.rollout.controls)
            h = char(local_get(mg.rollout.controls, 'content_hash', ''));
        end
        if isempty(h)
            h = char(local_get(mg, 'autonomous_control_content_hash', ''));
        end
    end
end

function st = autonomous_status(cr)
    st = '';
    if isfield(cr, 'mackey_glass') && isstruct(cr.mackey_glass)
        mg = cr.mackey_glass;
        if isfield(mg, 'rollout') && isstruct(mg.rollout) && isfield(mg.rollout, 'status')
            st = char(mg.rollout.status);
        elseif isfield(mg, 'autonomous_status')
            st = char(mg.autonomous_status);
        end
    end
end

function v = autonomous_metric(cr, field_name)
    v = NaN;
    if ~(isfield(cr, 'mackey_glass') && isstruct(cr.mackey_glass))
        return;
    end
    mg = cr.mackey_glass;
    if isfield(mg, 'rollout') && isstruct(mg.rollout) && ...
            isfield(mg.rollout, 'metrics') && isstruct(mg.rollout.metrics) && ...
            isfield(mg.rollout.metrics, field_name)
        v = double(mg.rollout.metrics.(field_name));
        if ~isscalar(v)
            v = NaN;
        end
        return;
    end
    % Unsupported DDE leaves metrics empty — remain NaN
end

function factors = parse_factors_from_cell(cr)
    factors = struct('A', '', 'S', '', 'D', '', 'F', '');
    key = char(local_get(cr, 'cell_key', ''));
    tok = regexp(key, '^adapt-(.+)__std-(.+)__delay-(.+)__feat-(.+)$', ...
        'tokens', 'once');
    if ~isempty(tok)
        factors.A = tok{1};
        factors.S = tok{2};
        factors.D = tok{3};
        factors.F = tok{4};
    end
    if isfield(cr, 'adaptation') && ~isempty(cr.adaptation)
        factors.A = char(cr.adaptation);
    end
    if isfield(cr, 'which_states') && ~isempty(cr.which_states)
        ws = char(cr.which_states);
        if any(strcmp(ws, {'x', 'r'}))
            factors.F = ws;
        end
    end
end

function v = nested_num(s, path)
    v = nested_get(s, path, NaN);
    if isempty(v)
        v = NaN;
    else
        v = double(v);
        if ~isscalar(v)
            v = NaN;
        end
    end
end

function v = nested_get(s, path, default)
    v = default;
    cur = s;
    for i = 1:numel(path)
        if ~(isstruct(cur) && isfield(cur, path{i}))
            return;
        end
        cur = cur.(path{i});
    end
    if isempty(cur)
        return;
    end
    v = cur;
end

function v = local_num(s, name)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = double(s.(name));
        if ~isscalar(v)
            v = NaN;
        end
    else
        v = NaN;
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
