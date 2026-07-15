function out = build_seed_level_contrast_tables(tables, matrix, cfg)
%BUILD_SEED_LEVEL_CONTRAST_TABLES  Matched within-seed contrasts and benchmarks.
%
%   out = build_seed_level_contrast_tables(tables, matrix, cfg)
%
% Independent unit = base_seed. All marginal contrasts are computed within seed
% first (equal stratum weights). No p-values, CIs, Cliff's delta, or inference.
%
% Fixed-horizon NRMSE is omitted from seed_contrast (scalar endpoints only) and
% included in benchmark_contrast when configured.
%
% Origins never become inferential rows.
%
% See also: build_matched_aggregation_plan, aggregate_ablation_results

    if nargin < 3 || ~isstruct(cfg)
        error('build_seed_level_contrast_tables:InvalidCfg', 'cfg required.');
    end
    plan = local_get(cfg, 'aggregation_plan', []);
    if isempty(plan)
        error('build_seed_level_contrast_tables:MissingPlan', ...
            'cfg.aggregation_plan is required.');
    end

    raw = tables.raw_cell;
    seeds = local_get(matrix, 'expected_seeds', []);
    if isempty(seeds) && ~isempty(raw)
        seeds = unique(raw.seed);
    end
    seeds = double(seeds(:));

    protocol_version = char(local_get(plan, 'protocol_version', ...
        'matched_seed_contrasts_v1'));
    protocol_fp = char(local_get(cfg, 'protocol_fingerprint', ''));
    protocol_tier = char(local_get(cfg, 'protocol_tier', ''));
    analysis_set = char(local_get(cfg, 'active_analysis_set', ...
        local_get(plan, 'analysis_set', '')));

    endpoints = local_get(plan, 'endpoints', struct());
    contrasts = local_get(plan, 'contrasts', {});
    benchmarks = local_get(plan, 'benchmark_contrasts', {});
    secondary_enabled = true;
    if isfield(cfg, 'secondary_enabled')
        secondary_enabled = logical(cfg.secondary_enabled);
    end

    % Index cells by seed
    by_seed = index_raw_by_seed(raw);

    contrast_rows = {};
    for is = 1:numel(seeds)
        seed = seeds(is);
        if ~by_seed.isKey(seed)
            error('build_seed_level_contrast_tables:MissingSeed', ...
                'No rows for seed %d.', seed);
        end
        seed_rows = by_seed(seed);
        for ic = 1:numel(contrasts)
            c = contrasts{ic};
            ep_ids = local_get(c, 'supported_endpoint_ids', {});
            for ie = 1:numel(ep_ids)
                ep_id = ep_ids{ie};
                if strcmp(ep_id, 'mg_autonomous_fixed_horizon_nrmse')
                    % Scalar seed_contrast only; fixed-horizon -> benchmark table
                    continue;
                end
                if ~secondary_enabled && is_autonomous_endpoint(ep_id)
                    continue;
                end
                if ~isfield(endpoints, ep_id)
                    error('build_seed_level_contrast_tables:UnknownEndpoint', ...
                        'Unknown endpoint_id %s in contrast %s', ep_id, c.contrast_id);
                end
                ep = endpoints.(ep_id);
                row = compute_contrast_row(seed, seed_rows, c, ep, ep_id, ...
                    protocol_version, protocol_fp, protocol_tier, analysis_set);
                contrast_rows{end+1} = row; %#ok<AGROW>
            end
        end
    end

    bench_rows = {};
    baseline_T = local_get(tables, 'unique_seed_baseline', table());
    fh_T = local_get(tables, 'autonomous_fixed_horizon', table());
    baseline_map = local_get(matrix, 'baseline_by_seed', []);
    matrix_cells = local_get(matrix, 'cells', {});
    for is = 1:numel(seeds)
        seed = seeds(is);
        if ~by_seed.isKey(seed)
            continue;
        end
        seed_rows = by_seed(seed);
        brow = lookup_baseline_row(baseline_T, seed);
        bundle = [];
        if isa(baseline_map, 'containers.Map') && baseline_map.isKey(seed)
            bundle = baseline_map(seed).bundle;
        end
        if isempty(bundle)
            bundle = synthesize_bundle_from_matrix_cells(seed, matrix_cells);
        end
        for ib = 1:numel(benchmarks)
            b = benchmarks{ib};
            if ~secondary_enabled && logical(local_get(b, 'autonomous_allowed', false))
                continue;
            end
            new_rows = compute_benchmark_rows(seed, seed_rows, brow, b, ...
                endpoints, fh_T, bundle, protocol_version, protocol_fp, ...
                protocol_tier, analysis_set);
            bench_rows = [bench_rows, new_rows]; %#ok<AGROW>
        end
    end

    out = struct();
    out.seed_contrast = rows_to_table(contrast_rows, contrast_varnames());
    out.benchmark_contrast = rows_to_table(bench_rows, benchmark_varnames());
end

% =============================================================================
function by_seed = index_raw_by_seed(raw)
    by_seed = containers.Map('KeyType', 'double', 'ValueType', 'any');
    if isempty(raw) || height(raw) == 0
        return;
    end
    seeds = unique(raw.seed);
    for i = 1:numel(seeds)
        mask = raw.seed == seeds(i);
        by_seed(double(seeds(i))) = raw(mask, :);
    end
end

function names = contrast_varnames()
    names = { ...
        'protocol_version', 'protocol_fingerprint', 'protocol_tier', 'analysis_set', ...
        'seed', 'contrast_id', 'contrast_family', 'contrast_role', ...
        'endpoint_id', 'endpoint_role', 'unit', ...
        'n_strata_expected', 'n_strata_observed', ...
        'treatment_mean_within_seed', 'control_mean_within_seed', ...
        'delta_raw', 'orientation_multiplier', 'effect_oriented', ...
        'favorable_direction', 'supported', 'status', ...
        'treatment_cell_keys', 'control_cell_keys', 'source_files'};
end

function names = benchmark_varnames()
    names = { ...
        'protocol_version', 'protocol_fingerprint', 'protocol_tier', 'analysis_set', ...
        'seed', 'contrast_id', 'contrast_family', 'contrast_role', 'label', ...
        'endpoint_id', 'baseline_name', 'horizon', ...
        'feature_aggregation', 'mesn_value', 'baseline_value', ...
        'comparison_value', 'comparison_name', ...
        'mesn_cell_keys', 'status', 'source_files'};
end

% =============================================================================
% Matched contrasts
% =============================================================================

function row = compute_contrast_row(seed, seed_rows, c, ep, ep_id, ...
        protocol_version, protocol_fp, protocol_tier, analysis_set)

    is_auto = is_autonomous_endpoint(ep_id);
    if is_auto
        n_exp = local_get(c, 'expected_strata_autonomous', NaN);
        allowed = logical(local_get(c, 'autonomous_allowed', false));
        if ~allowed || (isnumeric(n_exp) && isnan(n_exp))
            row = blank_contrast_row(seed, c, ep, ep_id, protocol_version, ...
                protocol_fp, protocol_tier, analysis_set);
            row.supported = false;
            row.status = 'endpoint_not_supported_for_contrast';
            row.n_strata_expected = n_exp;
            return;
        end
    else
        n_exp = local_get(c, 'expected_strata_nonautonomous', NaN);
    end

    % Restrict autonomous to ODE / ode_off rows
    work = seed_rows;
    if is_auto
        work = filter_ode_rows(work);
    end

    ctype = char(local_get(c, 'contrast_type', 'simple_marginal'));
    switch ctype
        case {'simple_marginal', 'system_combined', 'equivalence_diagnostic'}
            [delta, t_mean, c_mean, n_obs, t_keys, c_keys, srcs, st, msg] = ...
                simple_marginal_within_seed(work, c, ep_id, n_exp);
        case 'interaction_2way'
            [delta, t_mean, c_mean, n_obs, t_keys, c_keys, srcs, st, msg] = ...
                interaction_2way_within_seed(work, c, ep_id, n_exp);
        otherwise
            error('build_seed_level_contrast_tables:UnknownContrastType', ...
                'Unknown contrast_type %s', ctype);
    end

    orient = double(local_get(ep, 'orientation_multiplier', 1));
    row = struct();
    row.protocol_version = protocol_version;
    row.protocol_fingerprint = protocol_fp;
    row.protocol_tier = protocol_tier;
    row.analysis_set = analysis_set;
    row.seed = seed;
    row.contrast_id = char(c.contrast_id);
    row.contrast_family = char(local_get(c, 'family', ''));
    row.contrast_role = char(local_get(c, 'role', ''));
    row.endpoint_id = ep_id;
    row.endpoint_role = char(local_get(ep, 'role', ''));
    row.unit = char(local_get(ep, 'unit', ''));
    row.n_strata_expected = n_exp;
    row.n_strata_observed = n_obs;
    row.treatment_mean_within_seed = t_mean;
    row.control_mean_within_seed = c_mean;
    row.delta_raw = delta;
    row.orientation_multiplier = orient;
    row.effect_oriented = orient * delta;
    row.favorable_direction = char(local_get(ep, 'favorable_direction', ''));
    row.supported = true;
    if strcmp(st, 'ok')
        row.status = 'ok';
    else
        row.status = st;
    end
    row.treatment_cell_keys = join_keys(t_keys);
    row.control_cell_keys = join_keys(c_keys);
    row.source_files = join_keys(srcs);
    if ~strcmp(row.status, 'ok') && ~isempty(msg)
        row.status = sprintf('%s:%s', st, msg);
    end

    if strcmp(st, 'ok') && isfinite(n_exp) && n_obs ~= n_exp
        error('build_seed_level_contrast_tables:StrataCount', ...
            ['Contrast %s endpoint %s seed %d: expected %g strata, observed %d'], ...
            c.contrast_id, ep_id, seed, n_exp, n_obs);
    end
    if ~strcmp(st, 'ok')
        error('build_seed_level_contrast_tables:ContrastFailed', ...
            'Contrast %s endpoint %s seed %d failed: %s', ...
            c.contrast_id, ep_id, seed, row.status);
    end
end

function row = blank_contrast_row(seed, c, ep, ep_id, protocol_version, ...
        protocol_fp, protocol_tier, analysis_set)
    row = struct();
    row.protocol_version = protocol_version;
    row.protocol_fingerprint = protocol_fp;
    row.protocol_tier = protocol_tier;
    row.analysis_set = analysis_set;
    row.seed = seed;
    row.contrast_id = char(c.contrast_id);
    row.contrast_family = char(local_get(c, 'family', ''));
    row.contrast_role = char(local_get(c, 'role', ''));
    row.endpoint_id = ep_id;
    row.endpoint_role = char(local_get(ep, 'role', ''));
    row.unit = char(local_get(ep, 'unit', ''));
    row.n_strata_expected = NaN;
    row.n_strata_observed = 0;
    row.treatment_mean_within_seed = NaN;
    row.control_mean_within_seed = NaN;
    row.delta_raw = NaN;
    row.orientation_multiplier = double(local_get(ep, 'orientation_multiplier', 1));
    row.effect_oriented = NaN;
    row.favorable_direction = char(local_get(ep, 'favorable_direction', ''));
    row.supported = false;
    row.status = '';
    row.treatment_cell_keys = '';
    row.control_cell_keys = '';
    row.source_files = '';
end

function [delta, t_mean, c_mean, n_obs, t_keys, c_keys, srcs, st, msg] = ...
        simple_marginal_within_seed(seed_rows, c, ep_id, n_exp)

    delta = NaN; t_mean = NaN; c_mean = NaN; n_obs = 0;
    t_keys = {}; c_keys = {}; srcs = {}; st = 'ok'; msg = '';

    matched = local_get(c, 'matched_factors', {});
    treatment = c.treatment;
    control = c.control;

    strata = enumerate_strata(seed_rows, matched, treatment, control);
    if isfinite(n_exp) && numel(strata) ~= n_exp
        % Still attempt; fail closed after if counts wrong
    end

    deltas = [];
    t_vals = [];
    c_vals = [];
    for i = 1:numel(strata)
        stratum = strata{i};
        t_mask = match_factors(seed_rows, treatment, matched, stratum);
        c_mask = match_factors(seed_rows, control, matched, stratum);
        t_sub = seed_rows(t_mask, :);
        c_sub = seed_rows(c_mask, :);
        if height(t_sub) ~= 1 || height(c_sub) ~= 1
            st = 'nonunique_stratum_cells';
            msg = sprintf('stratum_%d_t%d_c%d', i, height(t_sub), height(c_sub));
            return;
        end
        tv = endpoint_value(t_sub, ep_id);
        cv = endpoint_value(c_sub, ep_id);
        if ~(isfinite(tv) && isfinite(cv))
            st = 'nonfinite_endpoint';
            msg = sprintf('stratum_%d', i);
            return;
        end
        deltas(end+1, 1) = tv - cv; %#ok<AGROW>
        t_vals(end+1, 1) = tv; %#ok<AGROW>
        c_vals(end+1, 1) = cv; %#ok<AGROW>
        t_keys{end+1} = char(t_sub.cell_key(1)); %#ok<AGROW>
        c_keys{end+1} = char(c_sub.cell_key(1)); %#ok<AGROW>
        srcs{end+1} = char(t_sub.source_file(1)); %#ok<AGROW>
        srcs{end+1} = char(c_sub.source_file(1)); %#ok<AGROW>
    end

    n_obs = numel(deltas);
    if n_obs == 0
        st = 'no_strata';
        return;
    end
    delta = mean(deltas);
    t_mean = mean(t_vals);
    c_mean = mean(c_vals);
    t_keys = unique(t_keys, 'stable');
    c_keys = unique(c_keys, 'stable');
    srcs = unique(srcs, 'stable');
end

function [delta, t_mean, c_mean, n_obs, t_keys, c_keys, srcs, st, msg] = ...
        interaction_2way_within_seed(seed_rows, c, ep_id, n_exp)

    delta = NaN; t_mean = NaN; c_mean = NaN; n_obs = 0;
    t_keys = {}; c_keys = {}; srcs = {}; st = 'ok'; msg = '';

    matched = local_get(c, 'matched_factors', {});
    treatment = c.treatment;
    control = c.control;

    % Factors that differ between treatment and control corners
    [f1, f2, t1, t2, c1, c2] = differing_factors(treatment, control);
    if isempty(f1) || isempty(f2)
        st = 'interaction_factor_parse_failed';
        return;
    end

    strata = enumerate_strata(seed_rows, matched, treatment, control);
    deltas = [];
    % For interactions, treatment_mean/control_mean are not simple; store DiD pieces avg
    corner_t = [];
    corner_c = [];

    for i = 1:numel(strata)
        stratum = strata{i};
        % Four cells: (t1,t2), (c1,t2), (t1,c2), (c1,c2)
        cell_tt = find_interaction_cell(seed_rows, treatment, control, matched, ...
            stratum, f1, f2, t1, t2);
        cell_ct = find_interaction_cell(seed_rows, treatment, control, matched, ...
            stratum, f1, f2, c1, t2);
        cell_tc = find_interaction_cell(seed_rows, treatment, control, matched, ...
            stratum, f1, f2, t1, c2);
        cell_cc = find_interaction_cell(seed_rows, treatment, control, matched, ...
            stratum, f1, f2, c1, c2);
        if any(cellfun(@isempty, {cell_tt, cell_ct, cell_tc, cell_cc}))
            st = 'missing_interaction_cell';
            msg = sprintf('stratum_%d', i);
            return;
        end
        v_tt = endpoint_value(cell_tt, ep_id);
        v_ct = endpoint_value(cell_ct, ep_id);
        v_tc = endpoint_value(cell_tc, ep_id);
        v_cc = endpoint_value(cell_cc, ep_id);
        if ~all(isfinite([v_tt, v_ct, v_tc, v_cc]))
            st = 'nonfinite_endpoint';
            msg = sprintf('stratum_%d', i);
            return;
        end
        did = (v_tt - v_ct) - (v_tc - v_cc);
        deltas(end+1, 1) = did; %#ok<AGROW>
        corner_t(end+1, 1) = v_tt; %#ok<AGROW>
        corner_c(end+1, 1) = v_cc; %#ok<AGROW>
        t_keys{end+1} = char(cell_tt.cell_key(1)); %#ok<AGROW>
        t_keys{end+1} = char(cell_tc.cell_key(1)); %#ok<AGROW>
        c_keys{end+1} = char(cell_ct.cell_key(1)); %#ok<AGROW>
        c_keys{end+1} = char(cell_cc.cell_key(1)); %#ok<AGROW>
        for cell_T = {cell_tt, cell_ct, cell_tc, cell_cc}
            srcs{end+1} = char(cell_T{1}.source_file(1)); %#ok<AGROW>
        end
    end

    n_obs = numel(deltas);
    if n_obs == 0
        st = 'no_strata';
        return;
    end
    delta = mean(deltas);
    t_mean = mean(corner_t);
    c_mean = mean(corner_c);
    t_keys = unique(t_keys, 'stable');
    c_keys = unique(c_keys, 'stable');
    srcs = unique(srcs, 'stable');
end

function sub = find_interaction_cell(seed_rows, treatment, control, matched, ...
        stratum, f1, f2, v1, v2)
    factors = struct('A', '', 'S', '', 'D', '', 'F', '');
    % Start from shared fixed levels (those equal in treatment & control)
    for f = {'A', 'S', 'D', 'F'}
        nm = f{1};
        tv = char(treatment.(nm));
        cv = char(control.(nm));
        if ~isempty(tv) && strcmp(tv, cv)
            factors.(nm) = tv;
        end
    end
    factors.(f1) = v1;
    factors.(f2) = v2;
    mask = match_factors(seed_rows, factors, matched, stratum);
    sub = seed_rows(mask, :);
    if height(sub) ~= 1
        sub = table();
    end
end

function [f1, f2, t1, t2, c1, c2] = differing_factors(treatment, control)
    f1 = ''; f2 = ''; t1 = ''; t2 = ''; c1 = ''; c2 = '';
    diffs = {};
    for f = {'A', 'S', 'D', 'F'}
        nm = f{1};
        tv = char(treatment.(nm));
        cv = char(control.(nm));
        if ~isempty(tv) && ~isempty(cv) && ~strcmp(tv, cv)
            diffs{end+1} = struct('f', nm, 't', tv, 'c', cv); %#ok<AGROW>
        end
    end
    if numel(diffs) < 2
        return;
    end
    f1 = diffs{1}.f; t1 = diffs{1}.t; c1 = diffs{1}.c;
    f2 = diffs{2}.f; t2 = diffs{2}.t; c2 = diffs{2}.c;
end

function strata = enumerate_strata(seed_rows, matched, treatment, control)
% Unique combinations of matched-factor levels among cells compatible with
% either treatment or control fixed constraints (empty = free).
    if isempty(matched)
        strata = {struct()};
        return;
    end
    t_mask = match_fixed_only(seed_rows, treatment);
    c_mask = match_fixed_only(seed_rows, control);
    pool = seed_rows(t_mask | c_mask, :);
    if height(pool) == 0
        pool = seed_rows;
    end

    keys = cell(height(pool), 1);
    levels = cell(height(pool), 1);
    for i = 1:height(pool)
        s = struct();
        parts = cell(numel(matched), 1);
        for k = 1:numel(matched)
            mf = matched{k};
            col = factor_column(mf);
            val = char_cell(pool.(col)(i));
            s.(mf) = val;
            parts{k} = sprintf('%s=%s', mf, val);
        end
        keys{i} = strjoin(parts, '|');
        levels{i} = s;
    end
    [~, ia] = unique(keys, 'stable');
    strata = levels(ia);
end

function mask = match_factors(seed_rows, fixed, matched, stratum)
    mask = match_fixed_only(seed_rows, fixed);
    for k = 1:numel(matched)
        mf = matched{k};
        if ~isfield(stratum, mf)
            continue;
        end
        col = factor_column(mf);
        want = char(stratum.(mf));
        colvals = seed_rows.(col);
        for i = 1:height(seed_rows)
            if mask(i) && ~strcmp(char_cell(colvals(i)), want)
                mask(i) = false;
            end
        end
    end
end

function mask = match_fixed_only(seed_rows, fixed)
    n = height(seed_rows);
    mask = true(n, 1);
    for f = {'A', 'S', 'D', 'F'}
        nm = f{1};
        want = char(fixed.(nm));
        if isempty(want)
            continue;
        end
        col = factor_column(nm);
        colvals = seed_rows.(col);
        for i = 1:n
            if ~strcmp(char_cell(colvals(i)), want)
                mask(i) = false;
            end
        end
    end
end

function col = factor_column(mf)
    switch char(mf)
        case 'A', col = 'adaptation';
        case 'S', col = 'std';
        case 'D', col = 'delay';
        case 'F', col = 'feature_mode';
        otherwise
            error('build_seed_level_contrast_tables:BadFactor', ...
                'Unknown matched factor %s', char(mf));
    end
end

function work = filter_ode_rows(seed_rows)
    if height(seed_rows) == 0
        work = seed_rows;
        return;
    end
    mask = false(height(seed_rows), 1);
    for i = 1:height(seed_rows)
        d = char_cell(seed_rows.delay(i));
        m = char_cell(seed_rows.mode(i));
        mask(i) = strcmp(d, 'ode_off') || strcmp(m, 'ODE');
    end
    work = seed_rows(mask, :);
end

function v = endpoint_value(rowT, ep_id)
    if height(rowT) < 1
        v = NaN;
        return;
    end
    switch ep_id
        case 'mc_total'
            v = double(rowT.mc_total(1));
        case 'narma_test_nrmse'
            v = double(rowT.narma_test_nrmse(1));
        case 'mg_onestep_test_nrmse'
            v = double(rowT.mg_onestep_test_nrmse(1));
        case 'empirical_convergence_slope_per_time'
            v = double(rowT.convergence_slope_per_time(1));
        case 'wall_time_seconds'
            v = double(rowT.wall_time_seconds(1));
        case 'mg_autonomous_full_nrmse'
            v = double(rowT.mg_autonomous_full_nrmse(1));
        case 'mg_autonomous_restricted_valid_horizon'
            v = double(rowT.mg_autonomous_median_restricted_valid_horizon(1));
        otherwise
            error('build_seed_level_contrast_tables:BadEndpoint', ...
                'Unsupported scalar endpoint %s', ep_id);
    end
end

function tf = is_autonomous_endpoint(ep_id)
    tf = any(strcmp(ep_id, { ...
        'mg_autonomous_full_nrmse', ...
        'mg_autonomous_restricted_valid_horizon', ...
        'mg_autonomous_fixed_horizon_nrmse'}));
end

% =============================================================================
% Benchmarks
% =============================================================================

function rows = compute_benchmark_rows(seed, seed_rows, brow, b, ~, ...
        fh_T, bundle, protocol_version, protocol_fp, protocol_tier, analysis_set)

    rows = {};
    candidate = b.candidate;
    ep_ids = local_get(b, 'supported_endpoint_ids', {});
    baselines_map = local_get(b, 'baselines', struct());
    label = char(local_get(b, 'label', ''));

    % Average F=x and F=r equally for candidate ASD (feature free)
    cand_mask = match_fixed_only(seed_rows, candidate);
    cand = seed_rows(cand_mask, :);
    if height(cand) == 0
        error('build_seed_level_contrast_tables:BenchmarkCandidateMissing', ...
            'No candidate cells for benchmark %s seed %d', b.contrast_id, seed);
    end

    for ie = 1:numel(ep_ids)
        ep_id = ep_ids{ie};
        if ~isfield(baselines_map, ep_id)
            error('build_seed_level_contrast_tables:BenchmarkBaselines', ...
                'No baselines listed for endpoint %s', ep_id);
        end
        blist = baselines_map.(ep_id);
        if strcmp(ep_id, 'mg_autonomous_fixed_horizon_nrmse')
            rows = [rows, benchmark_fixed_horizon(seed, cand, bundle, b, blist, ...
                fh_T, protocol_version, protocol_fp, protocol_tier, analysis_set, label)]; %#ok<AGROW>
            continue;
        end

        mesn_val = mean_endpoint_over_features(cand, ep_id);
        mesn_keys = cellstr(cand.cell_key);
        srcs = cellstr(cand.source_file);
        for ib = 1:numel(blist)
            bname = blist{ib};
            bval = baseline_value_for(brow, ep_id, bname);
            [cmp_val, cmp_name] = benchmark_comparison(ep_id, mesn_val, bval);
            row = struct();
            row.protocol_version = protocol_version;
            row.protocol_fingerprint = protocol_fp;
            row.protocol_tier = protocol_tier;
            row.analysis_set = analysis_set;
            row.seed = seed;
            row.contrast_id = char(b.contrast_id);
            row.contrast_family = char(local_get(b, 'family', 'benchmark'));
            row.contrast_role = char(local_get(b, 'role', 'benchmark'));
            row.label = label;
            row.endpoint_id = ep_id;
            row.baseline_name = bname;
            row.horizon = NaN;
            row.feature_aggregation = char(local_get(b, 'feature_aggregation', ...
                'equal_x_r_within_seed'));
            row.mesn_value = mesn_val;
            row.baseline_value = bval;
            row.comparison_value = cmp_val;
            row.comparison_name = cmp_name;
            row.mesn_cell_keys = join_keys(mesn_keys);
            row.status = 'ok';
            row.source_files = join_keys(srcs);
            if ~(isfinite(mesn_val) && isfinite(bval))
                error('build_seed_level_contrast_tables:BenchmarkNonfinite', ...
                    'Nonfinite benchmark values seed=%d ep=%s baseline=%s', ...
                    seed, ep_id, bname);
            end
            rows{end+1} = row; %#ok<AGROW>
        end
    end
end

function rows = benchmark_fixed_horizon(seed, cand, bundle, b, blist, fh_T, ...
        protocol_version, protocol_fp, protocol_tier, analysis_set, label)
    rows = {};
    keys = cellstr(cand.cell_key);
    if isempty(fh_T) || height(fh_T) == 0
        error('build_seed_level_contrast_tables:NoFixedHorizon', ...
            'Missing autonomous_fixed_horizon rows for seed %d', seed);
    end
    mask = fh_T.seed == seed;
    key_mask = false(height(fh_T), 1);
    for i = 1:height(fh_T)
        key_mask(i) = any(strcmp(char_cell(fh_T.cell_key(i)), keys));
    end
    sub = fh_T(mask & key_mask, :);
    if height(sub) == 0
        error('build_seed_level_contrast_tables:NoFixedHorizonMatch', ...
            'No fixed-horizon rows matched candidate for seed %d', seed);
    end
    if isempty(bundle)
        error('build_seed_level_contrast_tables:FixedHorizonBaselineMissing', ...
            'Seed baseline bundle required for fixed-horizon benchmarks (seed %d).', seed);
    end
    horizons = unique(sub.horizon);
    for ih = 1:numel(horizons)
        h = horizons(ih);
        hmask = sub.horizon == h;
        hsub = sub(hmask, :);
        mesn_val = mean(hsub.pooled_nrmse);
        for ib = 1:numel(blist)
            bname = blist{ib};
            bval = baseline_fixed_horizon_from_bundle(bundle, bname, h);
            cmp_val = bval - mesn_val; % improvement_nrmse
            row = struct();
            row.protocol_version = protocol_version;
            row.protocol_fingerprint = protocol_fp;
            row.protocol_tier = protocol_tier;
            row.analysis_set = analysis_set;
            row.seed = seed;
            row.contrast_id = char(b.contrast_id);
            row.contrast_family = 'benchmark';
            row.contrast_role = 'benchmark';
            row.label = label;
            row.endpoint_id = 'mg_autonomous_fixed_horizon_nrmse';
            row.baseline_name = bname;
            row.horizon = h;
            row.feature_aggregation = 'equal_x_r_within_seed';
            row.mesn_value = mesn_val;
            row.baseline_value = bval;
            row.comparison_value = cmp_val;
            row.comparison_name = 'improvement_nrmse';
            row.mesn_cell_keys = join_keys(keys);
            row.status = 'ok';
            row.source_files = join_keys(cellstr(hsub.source_file));
            if ~(isfinite(mesn_val) && isfinite(bval))
                error('build_seed_level_contrast_tables:BenchmarkNonfinite', ...
                    'Nonfinite fixed-horizon benchmark seed=%d baseline=%s h=%g', ...
                    seed, bname, h);
            end
            rows{end+1} = row; %#ok<AGROW>
        end
    end
end

function v = baseline_fixed_horizon_from_bundle(bundle, bname, horizon)
    v = NaN;
    if ~(isstruct(bundle) && isfield(bundle, 'mackey_glass_autonomous'))
        error('build_seed_level_contrast_tables:NoAutonomousBundle', ...
            'Bundle missing mackey_glass_autonomous for fixed-horizon baseline.');
    end
    ac = bundle.mackey_glass_autonomous;
    if ~isfield(ac, bname)
        error('build_seed_level_contrast_tables:BadBaseline', ...
            'Autonomous control %s missing on seed bundle.', bname);
    end
    ctrl = ac.(bname);
    if ~(isfield(ctrl, 'metrics') && isstruct(ctrl.metrics) && ...
            isfield(ctrl.metrics, 'pooled_nrmse_at_fixed_horizons'))
        error('build_seed_level_contrast_tables:FixedHorizonBaselineMissing', ...
            'Control %s missing pooled_nrmse_at_fixed_horizons.', bname);
    end
    vals = double(ctrl.metrics.pooled_nrmse_at_fixed_horizons(:));
    horizons = [];
    if isfield(ctrl.metrics, 'fixed_report_horizons')
        horizons = double(ctrl.metrics.fixed_report_horizons(:));
    elseif isfield(ac, 'fixed_report_horizons')
        horizons = double(ac.fixed_report_horizons(:));
    elseif isfield(ctrl, 'fixed_report_horizons')
        horizons = double(ctrl.fixed_report_horizons(:));
    end
    if isempty(horizons)
        error('build_seed_level_contrast_tables:FixedHorizonBaselineMissing', ...
            'No fixed_report_horizons for control %s.', bname);
    end
    idx = find(horizons == horizon, 1);
    if isempty(idx) || idx > numel(vals)
        error('build_seed_level_contrast_tables:FixedHorizonBaselineMissing', ...
            'Horizon %g not found for control %s.', horizon, bname);
    end
    v = vals(idx);
end

function bundle = synthesize_bundle_from_matrix_cells(seed, cells)
    bundle = [];
    for i = 1:numel(cells)
        cr = cells{i};
        if isempty(cr) || double(local_get(cr, 'base_seed', NaN)) ~= seed
            continue;
        end
        if ~(isfield(cr, 'mackey_glass') && isstruct(cr.mackey_glass) && ...
                isfield(cr.mackey_glass, 'rollout') && ...
                isstruct(cr.mackey_glass.rollout) && ...
                isfield(cr.mackey_glass.rollout, 'controls'))
            continue;
        end
        ctrl = cr.mackey_glass.rollout.controls;
        mode = char(local_get(cr, 'mode', ''));
        if strcmp(mode, 'DDE')
            continue;
        end
        % Shared controls are identical within seed; take first ODE copy.
        bundle = struct('mackey_glass_autonomous', ctrl);
        return;
    end
end

function v = mean_endpoint_over_features(cand, ep_id)
    vals = zeros(height(cand), 1);
    for i = 1:height(cand)
        vals(i) = endpoint_value(cand(i, :), ep_id);
    end
    if any(~isfinite(vals))
        error('build_seed_level_contrast_tables:NonfiniteMesn', ...
            'Nonfinite MESN values for endpoint %s', ep_id);
    end
    % Equal weight x and r (and any other feature rows present)
    v = mean(vals);
end

function v = baseline_value_for(brow, ep_id, bname)
    if isempty(brow)
        error('build_seed_level_contrast_tables:MissingBaselineRow', ...
            'Unique seed baseline row required for benchmarks.');
    end
    switch ep_id
        case 'narma_test_nrmse'
            switch bname
                case 'conventional_leaky_esn'
                    v = brow.narma_conventional_leaky_esn_nrmse;
                case 'linear_input_history'
                    v = brow.narma_linear_input_history_nrmse;
                case 'training_target_mean'
                    v = brow.narma_training_target_mean_nrmse;
                otherwise
                    error('build_seed_level_contrast_tables:BadBaseline', bname);
            end
        case 'mg_onestep_test_nrmse'
            switch bname
                case 'conventional_leaky_esn'
                    v = brow.mg_conventional_leaky_esn_nrmse;
                case 'linear_autoregression'
                    v = brow.mg_linear_autoregression_nrmse;
                case 'persistence'
                    v = brow.mg_persistence_nrmse;
                otherwise
                    error('build_seed_level_contrast_tables:BadBaseline', bname);
            end
        case 'mg_autonomous_full_nrmse'
            switch bname
                case 'conventional_leaky_esn'
                    v = brow.mg_auto_conventional_esn_full_nrmse;
                case 'linear_autoregression'
                    v = brow.mg_auto_linear_ar_full_nrmse;
                case 'persistence'
                    v = brow.mg_auto_persistence_full_nrmse;
                otherwise
                    error('build_seed_level_contrast_tables:BadBaseline', bname);
            end
        case 'mg_autonomous_restricted_valid_horizon'
            switch bname
                case 'conventional_leaky_esn'
                    v = brow.mg_auto_conventional_esn_valid_horizon;
                case 'linear_autoregression'
                    v = brow.mg_auto_linear_ar_valid_horizon;
                case 'persistence'
                    v = brow.mg_auto_persistence_valid_horizon;
                otherwise
                    error('build_seed_level_contrast_tables:BadBaseline', bname);
            end
        otherwise
            error('build_seed_level_contrast_tables:BadEp', ep_id);
    end
    v = double(v);
end

function [cmp_val, cmp_name] = benchmark_comparison(ep_id, mesn_val, bval)
    switch ep_id
        case {'narma_test_nrmse', 'mg_onestep_test_nrmse', 'mg_autonomous_full_nrmse'}
            cmp_val = bval - mesn_val;
            cmp_name = 'improvement_nrmse';
        case 'mg_autonomous_restricted_valid_horizon'
            cmp_val = mesn_val - bval;
            cmp_name = 'difference_restricted_valid_horizon';
        otherwise
            cmp_val = mesn_val - bval;
            cmp_name = 'difference';
    end
end

function brow = lookup_baseline_row(baseline_T, seed)
    brow = [];
    if isempty(baseline_T) || height(baseline_T) == 0
        return;
    end
    mask = baseline_T.seed == seed;
    sub = baseline_T(mask, :);
    if height(sub) == 0
        return;
    end
    if height(sub) > 1
        error('build_seed_level_contrast_tables:DuplicateBaseline', ...
            'Multiple baseline rows for seed %d', seed);
    end
    brow = sub;
end

function s = join_keys(keys)
    if isempty(keys)
        s = '';
        return;
    end
    if isstring(keys)
        keys = cellstr(keys);
    end
    keys = keys(:)';
    for i = 1:numel(keys)
        keys{i} = char(keys{i});
    end
    s = strjoin(keys, ';');
end

function s = char_cell(v)
    if iscell(v)
        s = char(v{1});
    else
        s = char(v);
    end
end

function T = rows_to_table(rows, varnames)
    if isempty(rows)
        n = numel(varnames);
        types = cell(1, n);
        for i = 1:n
            if is_num_col(varnames{i})
                types{i} = 'double';
            else
                types{i} = 'cell';
            end
        end
        T = table('Size', [0, n], 'VariableTypes', types, 'VariableNames', varnames);
        return;
    end
    for i = 1:numel(rows)
        for k = 1:numel(varnames)
            nm = varnames{k};
            if ~isfield(rows{i}, nm)
                if is_num_col(nm)
                    rows{i}.(nm) = NaN;
                else
                    rows{i}.(nm) = {''};
                end
            elseif is_num_col(nm)
                if islogical(rows{i}.(nm))
                    rows{i}.(nm) = double(rows{i}.(nm));
                else
                    rows{i}.(nm) = double(rows{i}.(nm));
                end
            else
                rows{i}.(nm) = {char(string(rows{i}.(nm)))};
            end
        end
    end
    S = [rows{:}];
    T = struct2table(S, 'AsArray', true);
    T = T(:, varnames);
end

function tf = is_num_col(nm)
    tf = any(strcmp(nm, {'seed', 'horizon', 'n_strata_expected', ...
        'n_strata_observed', 'treatment_mean_within_seed', ...
        'control_mean_within_seed', 'delta_raw', 'orientation_multiplier', ...
        'effect_oriented', 'mesn_value', 'baseline_value', 'comparison_value'})) ...
        || strcmp(nm, 'supported');
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    elseif istable(s) && any(strcmp(s.Properties.VariableNames, name))
        v = s.(name);
        if iscell(v) && isscalar(v)
            v = v{1};
        elseif istable(s) && height(s) == 1
            % keep as-is for numeric
        end
    else
        v = default;
    end
end
