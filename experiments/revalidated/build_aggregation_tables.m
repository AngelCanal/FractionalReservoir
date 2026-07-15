function tables = build_aggregation_tables(matrix, cfg)
%BUILD_AGGREGATION_TABLES  Raw cell, fixed-horizon, unique baselines, Dale rows.
%
%   tables = build_aggregation_tables(matrix, cfg)
%
% matrix is the struct from validate_aggregation_run_matrix (may be incomplete
% for diagnostic paths). Does not recompute models or run inference.
%
% Outputs (MATLAB tables):
%   .raw_cell
%   .autonomous_fixed_horizon
%   .unique_seed_baseline
%   .dale_resolution
%
% See also: aggregate_ablation_results, build_seed_level_contrast_tables

    if nargin < 2 || ~isstruct(cfg)
        error('build_aggregation_tables:InvalidCfg', 'cfg must be a struct.');
    end
    if nargin < 1 || ~isstruct(matrix)
        error('build_aggregation_tables:InvalidMatrix', 'matrix must be a struct.');
    end

    cells = local_get(matrix, 'cells', {});
    source_files = local_get(matrix, 'source_files', {});
    plan = local_get(cfg, 'aggregation_plan', struct());
    protocol_tier = char(local_get(cfg, 'protocol_tier', ''));
    protocol_fp = char(local_get(cfg, 'protocol_fingerprint', ''));
    analysis_set = char(local_get(cfg, 'active_analysis_set', ...
        local_get(plan, 'analysis_set', '')));

    raw_rows = {};
    fh_rows = {};
    for i = 1:numel(cells)
        cr = cells{i};
        if isempty(cr)
            continue;
        end
        src = '';
        if i <= numel(source_files) && ~isempty(source_files{i})
            src = char(source_files{i});
        else
            src = sprintf('seed_%d__%s.mat', double(cr.base_seed), char(cr.cell_key));
        end
        raw_rows{end+1} = build_raw_row(cr, src, protocol_tier, protocol_fp, analysis_set); %#ok<AGROW>
        fh_rows = [fh_rows, build_fixed_horizon_rows(cr, src)]; %#ok<AGROW>
    end

    tables = struct();
    tables.raw_cell = rows_to_table(raw_rows, raw_varnames());
    tables.autonomous_fixed_horizon = rows_to_table(fh_rows, fh_varnames());

    [baseline_table, baseline_index] = build_unique_seed_baseline_table( ...
        matrix, cfg, cells, source_files);
    tables.unique_seed_baseline = baseline_table;
    tables.dale_resolution = build_dale_resolution_table( ...
        cells, source_files, cfg, baseline_index);
end

% =============================================================================
% Raw cell table
% =============================================================================

function row = build_raw_row(cr, src, protocol_tier, protocol_fp, analysis_set)
    factors = parse_factors_from_cell(cr);
    mode = char(local_get(cr, 'mode', ''));
    if isempty(mode)
        if strcmp(factors.D, 'dde_on')
            mode = 'DDE';
        else
            mode = 'ODE';
        end
    end

    row = struct();
    row.protocol_tier = protocol_tier;
    row.protocol_fingerprint = protocol_fp;
    row.analysis_set = char(local_get(cr, 'analysis_set', analysis_set));
    row.seed = double(cr.base_seed);
    row.cell_key = char(cr.cell_key);
    row.adaptation = factors.A;
    row.std = factors.S;
    row.delay = factors.D;
    row.feature_mode = factors.F;
    row.mode = mode;
    row.bundle_id = char(local_get(cr, 'matched_baseline_bundle_id', ''));
    row.autonomous_control_content_hash = autonomous_content_hash(cr);
    row.source_file = src;

    row.mc_total = nested_num(cr, {'memory_capacity', 'MC_total'});
    row.narma_test_nrmse = nested_num(cr, {'narma', 'test_nrmse'});
    row.mg_onestep_test_nrmse = nested_num(cr, {'mackey_glass', 'test_nrmse'});
    row.convergence_slope_per_time = nested_num(cr, ...
        {'empirical_convergence', 'median_pair_slope'});
    row.convergence_classification = char(nested_get(cr, ...
        {'empirical_convergence', 'classification'}, ''));
    row.wall_time_seconds = local_num(cr, 'wall_time_seconds');

    row.mg_autonomous_status = autonomous_status(cr);
    row.mg_autonomous_full_nrmse = autonomous_metric(cr, 'pooled_nrmse_full_horizon');
    row.mg_autonomous_median_restricted_valid_horizon = ...
        autonomous_metric(cr, 'median_valid_horizon');
    row.mg_autonomous_fraction_right_censored = ...
        autonomous_metric(cr, 'fraction_right_censored');
end

function names = raw_varnames()
    names = { ...
        'protocol_tier', 'protocol_fingerprint', 'analysis_set', 'seed', ...
        'cell_key', 'adaptation', 'std', 'delay', 'feature_mode', 'mode', ...
        'bundle_id', 'autonomous_control_content_hash', 'source_file', ...
        'mc_total', 'narma_test_nrmse', 'mg_onestep_test_nrmse', ...
        'convergence_slope_per_time', 'convergence_classification', ...
        'wall_time_seconds', 'mg_autonomous_status', ...
        'mg_autonomous_full_nrmse', ...
        'mg_autonomous_median_restricted_valid_horizon', ...
        'mg_autonomous_fraction_right_censored'};
end

function rows = build_fixed_horizon_rows(cr, src)
    rows = {};
    factors = parse_factors_from_cell(cr);
    metrics = [];
    horizons = [];
    status = autonomous_status(cr);
    if isfield(cr, 'mackey_glass') && isstruct(cr.mackey_glass) && ...
            isfield(cr.mackey_glass, 'rollout') && isstruct(cr.mackey_glass.rollout)
        ro = cr.mackey_glass.rollout;
        if isfield(ro, 'metrics') && isstruct(ro.metrics) && ...
                isfield(ro.metrics, 'pooled_nrmse_at_fixed_horizons')
            metrics = double(ro.metrics.pooled_nrmse_at_fixed_horizons(:));
        end
        if isfield(ro, 'fixed_report_horizons')
            horizons = double(ro.fixed_report_horizons(:));
        elseif isfield(ro, 'metrics') && isstruct(ro.metrics) && ...
                isfield(ro.metrics, 'fixed_report_horizons')
            horizons = double(ro.metrics.fixed_report_horizons(:));
        end
    end
    if isempty(metrics)
        return;
    end
    if isempty(horizons)
        horizons = (1:numel(metrics))';
    end
    n = min(numel(metrics), numel(horizons));
    for i = 1:n
        row = struct();
        row.seed = double(cr.base_seed);
        row.cell_key = char(cr.cell_key);
        row.feature_mode = factors.F;
        row.horizon = horizons(i);
        row.pooled_nrmse = metrics(i);
        row.status = status;
        row.source_file = src;
        rows{end+1} = row; %#ok<AGROW>
    end
end

function names = fh_varnames()
    names = {'seed', 'cell_key', 'feature_mode', 'horizon', ...
        'pooled_nrmse', 'status', 'source_file'};
end

% =============================================================================
% Unique seed baseline table
% =============================================================================

function [T, index] = build_unique_seed_baseline_table(matrix, cfg, cells, source_files)
    index = containers.Map('KeyType', 'double', 'ValueType', 'any');
    rows = {};

    seeds = local_get(matrix, 'expected_seeds', []);
    if isempty(seeds)
        seeds = unique(cellfun(@(c) double(local_get(c, 'base_seed', NaN)), ...
            cells(~cellfun(@isempty, cells))));
        seeds = seeds(isfinite(seeds));
    end

    baseline_map = local_get(matrix, 'baseline_by_seed', []);
    has_artifacts = isa(baseline_map, 'containers.Map');

    for is = 1:numel(seeds)
        seed = double(seeds(is));
        bundle = [];
        bpath = '';
        if has_artifacts && baseline_map.isKey(seed)
            entry = baseline_map(seed);
            bundle = entry.bundle;
            bpath = char(entry.path);
        end

        if isempty(bundle)
            % Extract from cells and require agreement
            [bundle_like, bpath, ok, reason] = extract_baseline_from_cells( ...
                seed, cells, source_files);
            if ~ok
                error('build_aggregation_tables:BaselineConflict', ...
                    'Seed %d baseline conflict: %s', seed, reason);
            end
            row = flatten_baseline_from_cells(seed, bundle_like, bpath);
        else
            row = flatten_baseline_from_bundle(seed, bundle, bpath);
            % Cross-check compact cell copies against unique row
            [ok, reason] = validate_cells_against_baseline_row( ...
                seed, cells, row);
            if ~ok
                error('build_aggregation_tables:BaselineCellMismatch', ...
                    'Seed %d cell baseline mismatch: %s', seed, reason);
            end
        end
        rows{end+1} = row; %#ok<AGROW>
        index(seed) = row;
    end

    T = rows_to_table(rows, baseline_varnames());
end

function names = baseline_varnames()
    names = { ...
        'seed', 'bundle_id', 'schema_version', 'baseline_content_hash', ...
        'narma_task_data_hash', 'narma_split_hash', ...
        'mackey_glass_task_data_hash', 'mackey_glass_split_hash', ...
        'linear_ar_fitted_model_hash', 'conventional_esn_fitted_model_hash', ...
        'autonomous_control_content_hash', 'origin_schedule_hash', ...
        'provenance_mode', 'source_baseline_file', ...
        'narma_training_target_mean_nrmse', ...
        'narma_linear_input_history_nrmse', ...
        'narma_conventional_leaky_esn_nrmse', ...
        'mg_persistence_nrmse', ...
        'mg_linear_autoregression_nrmse', ...
        'mg_conventional_leaky_esn_nrmse', ...
        'mg_auto_persistence_full_nrmse', ...
        'mg_auto_linear_ar_full_nrmse', ...
        'mg_auto_conventional_esn_full_nrmse', ...
        'mg_auto_persistence_valid_horizon', ...
        'mg_auto_linear_ar_valid_horizon', ...
        'mg_auto_conventional_esn_valid_horizon', ...
        'mg_auto_persistence_fraction_right_censored', ...
        'mg_auto_linear_ar_fraction_right_censored', ...
        'mg_auto_conventional_esn_fraction_right_censored'};
end

function row = flatten_baseline_from_bundle(seed, bundle, bpath)
    row = blank_baseline_row();
    row.seed = seed;
    row.bundle_id = char(local_get(bundle, 'bundle_id', ''));
    row.schema_version = char(local_get(bundle, 'schema_version', ''));
    row.baseline_content_hash = char(local_get(bundle, 'bundle_id', ''));
    row.narma_task_data_hash = char(local_get(bundle, 'narma_task_data_hash', ''));
    row.narma_split_hash = char(local_get(bundle, 'narma_split_hash', ''));
    row.mackey_glass_task_data_hash = char(local_get(bundle, ...
        'mackey_glass_task_data_hash', ''));
    row.mackey_glass_split_hash = char(local_get(bundle, ...
        'mackey_glass_split_hash', ''));
    row.linear_ar_fitted_model_hash = char(local_get(bundle, ...
        'linear_ar_fitted_model_hash', ''));
    row.conventional_esn_fitted_model_hash = char(local_get(bundle, ...
        'conventional_esn_fitted_model_hash', ''));
    row.autonomous_control_content_hash = char(local_get(bundle, ...
        'autonomous_control_content_hash', ''));
    row.origin_schedule_hash = char(local_get(bundle, 'origin_schedule_hash', ''));
    prov = local_get(bundle, 'evaluation_provenance', struct());
    row.provenance_mode = char(local_get(prov, 'mode', ...
        'executed_shared_seed_bundle'));
    row.source_baseline_file = char(bpath);

    if isfield(bundle, 'narma') && isfield(bundle.narma, 'baselines')
        nb = bundle.narma.baselines;
        row.narma_training_target_mean_nrmse = baseline_nrmse(nb, ...
            'training_target_mean');
        row.narma_linear_input_history_nrmse = baseline_nrmse(nb, ...
            'linear_input_history');
        row.narma_conventional_leaky_esn_nrmse = baseline_nrmse(nb, ...
            'conventional_leaky_esn');
    end
    if isfield(bundle, 'mackey_glass_onestep') && ...
            isfield(bundle.mackey_glass_onestep, 'baselines')
        mb = bundle.mackey_glass_onestep.baselines;
        row.mg_persistence_nrmse = baseline_nrmse(mb, 'persistence');
        row.mg_linear_autoregression_nrmse = baseline_nrmse(mb, ...
            'linear_autoregression');
        row.mg_conventional_leaky_esn_nrmse = baseline_nrmse(mb, ...
            'conventional_leaky_esn');
    end
    if isfield(bundle, 'mackey_glass_autonomous')
        ac = bundle.mackey_glass_autonomous;
        row.mg_auto_persistence_full_nrmse = auto_ctrl_metric(ac, ...
            'persistence', 'pooled_nrmse_full_horizon');
        row.mg_auto_linear_ar_full_nrmse = auto_ctrl_metric(ac, ...
            'linear_autoregression', 'pooled_nrmse_full_horizon');
        row.mg_auto_conventional_esn_full_nrmse = auto_ctrl_metric(ac, ...
            'conventional_leaky_esn', 'pooled_nrmse_full_horizon');
        row.mg_auto_persistence_valid_horizon = auto_ctrl_metric(ac, ...
            'persistence', 'median_valid_horizon');
        row.mg_auto_linear_ar_valid_horizon = auto_ctrl_metric(ac, ...
            'linear_autoregression', 'median_valid_horizon');
        row.mg_auto_conventional_esn_valid_horizon = auto_ctrl_metric(ac, ...
            'conventional_leaky_esn', 'median_valid_horizon');
        row.mg_auto_persistence_fraction_right_censored = auto_ctrl_metric(ac, ...
            'persistence', 'fraction_right_censored');
        row.mg_auto_linear_ar_fraction_right_censored = auto_ctrl_metric(ac, ...
            'linear_autoregression', 'fraction_right_censored');
        row.mg_auto_conventional_esn_fraction_right_censored = auto_ctrl_metric(ac, ...
            'conventional_leaky_esn', 'fraction_right_censored');
        if isempty(row.autonomous_control_content_hash)
            row.autonomous_control_content_hash = char(local_get(ac, ...
                'content_hash', ''));
        end
    end
end

function row = flatten_baseline_from_cells(seed, snap, bpath)
    row = blank_baseline_row();
    row.seed = seed;
    row.bundle_id = char(local_get(snap, 'bundle_id', ''));
    row.schema_version = 'extracted_from_cells';
    row.baseline_content_hash = char(local_get(snap, 'content_hash', ''));
    row.provenance_mode = 'extracted_from_cell_copies';
    row.source_baseline_file = char(bpath);
    fn = fieldnames(snap);
    for i = 1:numel(fn)
        if isfield(row, fn{i})
            row.(fn{i}) = snap.(fn{i});
        end
    end
end

function row = blank_baseline_row()
    names = baseline_varnames();
    row = struct();
    for i = 1:numel(names)
        nm = names{i};
        if any(strcmp(nm, {'seed'}))
            row.(nm) = NaN;
        elseif contains(nm, 'nrmse') || contains(nm, 'horizon') || ...
                contains(nm, 'censored')
            row.(nm) = NaN;
        else
            row.(nm) = '';
        end
    end
end

function [snap, bpath, ok, reason] = extract_baseline_from_cells(seed, cells, source_files)
    ok = true;
    reason = '';
    snap = struct();
    bpath = '';
    seen = false;
    for i = 1:numel(cells)
        cr = cells{i};
        if isempty(cr) || double(cr.base_seed) ~= seed
            continue;
        end
        src = '';
        if i <= numel(source_files)
            src = char(source_files{i});
        end
        cand = snapshot_from_cell(cr);
        cand.bundle_id = char(local_get(cr, 'matched_baseline_bundle_id', ''));
        if ~seen
            snap = cand;
            bpath = src;
            seen = true;
        else
            [same, diff_field] = snapshots_equal(snap, cand);
            if ~same
                ok = false;
                reason = sprintf('disagree_on_%s_between_cells', diff_field);
                return;
            end
        end
    end
    if ~seen
        ok = false;
        reason = 'no_cells_for_seed';
    end
end

function snap = snapshot_from_cell(cr)
    snap = struct();
    snap.content_hash = autonomous_content_hash(cr);
    snap.narma_training_target_mean_nrmse = cell_baseline_nrmse(cr, ...
        'narma', 'training_target_mean');
    snap.narma_linear_input_history_nrmse = cell_baseline_nrmse(cr, ...
        'narma', 'linear_input_history');
    snap.narma_conventional_leaky_esn_nrmse = cell_baseline_nrmse(cr, ...
        'narma', 'conventional_leaky_esn');
    snap.mg_persistence_nrmse = cell_baseline_nrmse(cr, ...
        'mackey_glass', 'persistence');
    snap.mg_linear_autoregression_nrmse = cell_baseline_nrmse(cr, ...
        'mackey_glass', 'linear_autoregression');
    snap.mg_conventional_leaky_esn_nrmse = cell_baseline_nrmse(cr, ...
        'mackey_glass', 'conventional_leaky_esn');
    snap.autonomous_control_content_hash = autonomous_content_hash(cr);
    snap.mg_auto_persistence_full_nrmse = cell_auto_ctrl_metric(cr, ...
        'persistence', 'pooled_nrmse_full_horizon');
    snap.mg_auto_linear_ar_full_nrmse = cell_auto_ctrl_metric(cr, ...
        'linear_autoregression', 'pooled_nrmse_full_horizon');
    snap.mg_auto_conventional_esn_full_nrmse = cell_auto_ctrl_metric(cr, ...
        'conventional_leaky_esn', 'pooled_nrmse_full_horizon');
    snap.mg_auto_persistence_valid_horizon = cell_auto_ctrl_metric(cr, ...
        'persistence', 'median_valid_horizon');
    snap.mg_auto_linear_ar_valid_horizon = cell_auto_ctrl_metric(cr, ...
        'linear_autoregression', 'median_valid_horizon');
    snap.mg_auto_conventional_esn_valid_horizon = cell_auto_ctrl_metric(cr, ...
        'conventional_leaky_esn', 'median_valid_horizon');
    snap.mg_auto_persistence_fraction_right_censored = cell_auto_ctrl_metric(cr, ...
        'persistence', 'fraction_right_censored');
    snap.mg_auto_linear_ar_fraction_right_censored = cell_auto_ctrl_metric(cr, ...
        'linear_autoregression', 'fraction_right_censored');
    snap.mg_auto_conventional_esn_fraction_right_censored = cell_auto_ctrl_metric(cr, ...
        'conventional_leaky_esn', 'fraction_right_censored');
end

function [ok, reason] = validate_cells_against_baseline_row(seed, cells, row)
    ok = true;
    reason = '';
    for i = 1:numel(cells)
        cr = cells{i};
        if isempty(cr) || double(cr.base_seed) ~= seed
            continue;
        end
        snap = snapshot_from_cell(cr);
        checks = { ...
            'narma_conventional_leaky_esn_nrmse', ...
            'mg_conventional_leaky_esn_nrmse', ...
            'autonomous_control_content_hash'};
        for k = 1:numel(checks)
            nm = checks{k};
            if ~isfield(snap, nm) || ~isfield(row, nm)
                continue;
            end
            a = snap.(nm);
            b = row.(nm);
            if ischar(a) || isstring(a)
                if ~isempty(char(a)) && ~isempty(char(b)) && ~strcmp(char(a), char(b))
                    ok = false;
                    reason = nm;
                    return;
                end
            else
                if isfinite(a) && isfinite(b) && abs(a - b) > 1e-12
                    ok = false;
                    reason = nm;
                    return;
                end
            end
        end
        bid = char(local_get(cr, 'matched_baseline_bundle_id', ''));
        if ~isempty(bid) && ~isempty(row.bundle_id) && ~strcmp(bid, row.bundle_id)
            ok = false;
            reason = 'bundle_id';
            return;
        end
    end
end

function [same, diff_field] = snapshots_equal(a, b)
    same = true;
    diff_field = '';
    fn = fieldnames(a);
    for i = 1:numel(fn)
        nm = fn{i};
        if ~isfield(b, nm)
            continue;
        end
        va = a.(nm);
        vb = b.(nm);
        if ischar(va) || isstring(va) || ischar(vb) || isstring(vb)
            if ~strcmp(char(va), char(vb))
                same = false;
                diff_field = nm;
                return;
            end
        else
            if ~(isnan(va) && isnan(vb)) && ~(isfinite(va) && isfinite(vb) && va == vb)
                if ~(isnan(va) && isnan(vb))
                    same = false;
                    diff_field = nm;
                    return;
                end
            end
        end
    end
end

% =============================================================================
% Dale resolution
% =============================================================================

function T = build_dale_resolution_table(cells, source_files, cfg, ~)
    rows = {};
    % Index cells by seed|key
    cmap = containers.Map('KeyType', 'char', 'ValueType', 'any');
    smap = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for i = 1:numel(cells)
        cr = cells{i};
        if isempty(cr)
            continue;
        end
        id = sprintf('%d|%s', double(cr.base_seed), char(cr.cell_key));
        cmap(id) = cr;
        if i <= numel(source_files)
            smap(id) = char(source_files{i});
        else
            smap(id) = sprintf('seed_%d__%s.mat', double(cr.base_seed), char(cr.cell_key));
        end
    end

    bb = local_get(cfg, 'benchmark_baselines', struct());
    dale_keys = local_get(bb, 'dale_mesn_control_keys', struct( ...
        'feat_x', 'adapt-off__std-off__delay-ode_off__feat-x', ...
        'feat_r', 'adapt-off__std-off__delay-ode_off__feat-r'));

    ids = cmap.keys;
    for i = 1:numel(ids)
        cr = cmap(ids{i});
        factors = parse_factors_from_cell(cr);
        fm = factors.F;
        if ~any(strcmp(fm, {'x', 'r'}))
            continue;
        end
        refs = collect_pending_dale(cr);
        if isempty(refs)
            continue;
        end
        expect_key = dale_mesn_control_reference_key(fm, dale_keys);
        ref_key = char(refs{1});
        if ~strcmp(ref_key, expect_key)
            error('build_aggregation_tables:DaleKeyInvalid', ...
                'Seed %d cell %s Dale key %s != expected %s', ...
                double(cr.base_seed), char(cr.cell_key), ref_key, expect_key);
        end

        ref_id = sprintf('%d|%s', double(cr.base_seed), ref_key);
        if ~cmap.isKey(ref_id)
            error('build_aggregation_tables:DaleRefMissing', ...
                'Missing Dale reference cell seed=%d key=%s for target %s', ...
                double(cr.base_seed), ref_key, char(cr.cell_key));
        end
        ref_cr = cmap(ref_id);
        ref_factors = parse_factors_from_cell(ref_cr);
        if ~strcmp(ref_factors.F, fm)
            error('build_aggregation_tables:DaleFeatureMismatch', ...
                'Dale reference feature %s != target feature %s', ...
                ref_factors.F, fm);
        end
        if ~strcmp(char(local_get(ref_cr, 'status', '')), 'ok')
            error('build_aggregation_tables:DaleRefFailed', ...
                'Dale reference cell not ok: %s', ref_id);
        end
        % Never conventional ESN: reference must be the Dale control key
        if contains(ref_key, 'conventional') 
            error('build_aggregation_tables:DaleConventionalForbidden', ...
                'Dale resolution must not use conventional ESN.');
        end

        tgt_src = smap(ids{i});
        ref_src = smap(ref_id);

        % One-step NARMA
        rows{end+1} = dale_row(cr, ref_cr, fm, ref_key, 'narma', ... %#ok<AGROW>
            nested_num(cr, {'narma', 'test_nrmse'}), ...
            nested_num(ref_cr, {'narma', 'test_nrmse'}), ...
            NaN, NaN, NaN, NaN, tgt_src, ref_src, 'resolved_paired_seed_cell');

        % One-step MG
        rows{end+1} = dale_row(cr, ref_cr, fm, ref_key, 'mg_onestep', ... %#ok<AGROW>
            nested_num(cr, {'mackey_glass', 'test_nrmse'}), ...
            nested_num(ref_cr, {'mackey_glass', 'test_nrmse'}), ...
            NaN, NaN, NaN, NaN, tgt_src, ref_src, 'resolved_paired_seed_cell');

        % Autonomous
        mode = char(local_get(cr, 'mode', ''));
        if isempty(mode)
            if strcmp(factors.D, 'dde_on'), mode = 'DDE'; else, mode = 'ODE'; end
        end
        if strcmp(mode, 'DDE')
            rows{end+1} = dale_row(cr, ref_cr, fm, ref_key, 'mg_autonomous', ... %#ok<AGROW>
                NaN, NaN, NaN, NaN, NaN, NaN, tgt_src, ref_src, ...
                'not_applicable_dde');
        else
            t_full = autonomous_metric(cr, 'pooled_nrmse_full_horizon');
            r_full = autonomous_metric(ref_cr, 'pooled_nrmse_full_horizon');
            t_vh = autonomous_metric(cr, 'median_valid_horizon');
            r_vh = autonomous_metric(ref_cr, 'median_valid_horizon');
            t_fc = autonomous_metric(cr, 'fraction_right_censored');
            r_fc = autonomous_metric(ref_cr, 'fraction_right_censored');
            rows{end+1} = dale_row(cr, ref_cr, fm, ref_key, 'mg_autonomous', ... %#ok<AGROW>
                t_full, r_full, t_vh, r_vh, t_fc, r_fc, tgt_src, ref_src, ...
                'resolved_paired_seed_cell');
        end
    end

    T = rows_to_table(rows, dale_varnames());
end

function names = dale_varnames()
    names = { ...
        'seed', 'target_cell_key', 'reference_cell_key', 'feature_mode', 'task', ...
        'target_nrmse_or_full', 'reference_nrmse_or_full', ...
        'improvement_nrmse', ...
        'target_valid_horizon', 'reference_valid_horizon', ...
        'difference_restricted_valid_horizon', ...
        'target_fraction_right_censored', 'reference_fraction_right_censored', ...
        'target_source_file', 'reference_source_file', ...
        'status', 'provenance'};
end

function row = dale_row(cr, ref_cr, fm, ref_key, task, t_n, r_n, t_vh, r_vh, ...
        t_fc, r_fc, tgt_src, ref_src, status)
    row = struct();
    row.seed = double(cr.base_seed);
    row.target_cell_key = char(cr.cell_key);
    row.reference_cell_key = ref_key;
    row.feature_mode = fm;
    row.task = task;
    row.target_nrmse_or_full = t_n;
    row.reference_nrmse_or_full = r_n;
    row.improvement_nrmse = r_n - t_n;
    row.target_valid_horizon = t_vh;
    row.reference_valid_horizon = r_vh;
    row.difference_restricted_valid_horizon = t_vh - r_vh;
    row.target_fraction_right_censored = t_fc;
    row.reference_fraction_right_censored = r_fc;
    row.target_source_file = tgt_src;
    row.reference_source_file = ref_src;
    row.status = status;
    row.provenance = 'resolved_from_seed_cell_table';
end

function refs = collect_pending_dale(cr)
    refs = {};
    specs = { ...
        {'narma', 'baselines', 'dale_mesn_control'}; ...
        {'mackey_glass', 'baselines', 'dale_mesn_control'}; ...
        {'mackey_glass', 'rollout', 'controls', 'dale_mesn_control'}};
    for i = 1:numel(specs)
        d = nested_get(cr, specs{i}, []);
        if isempty(d) || ~isstruct(d)
            continue;
        end
        st = char(local_get(d, 'status', ''));
        if strcmp(st, 'pending_paired_aggregation') || ...
                isfield(d, 'dale_mesn_control_reference')
            key = char(local_get(d, 'dale_mesn_control_reference', ''));
            if isempty(key) && isfield(d, 'provenance')
                key = char(local_get(d.provenance, 'dale_mesn_control_reference', ''));
            end
            if ~isempty(key)
                refs{end+1} = key; %#ok<AGROW>
            end
        end
    end
    refs = unique(refs, 'stable');
end

% =============================================================================
% Metric helpers
% =============================================================================

function v = baseline_nrmse(baselines, name)
    v = NaN;
    if ~(isstruct(baselines) && isfield(baselines, name))
        return;
    end
    b = baselines.(name);
    if isfield(b, 'metrics_test') && isfield(b.metrics_test, 'nrmse')
        v = double(b.metrics_test.nrmse);
    elseif isfield(b, 'metrics') && isfield(b.metrics, 'test') && ...
            isfield(b.metrics.test, 'nrmse')
        v = double(b.metrics.test.nrmse);
    end
end

function v = auto_ctrl_metric(ac, name, field_name)
    v = NaN;
    if ~(isstruct(ac) && isfield(ac, name))
        return;
    end
    c = ac.(name);
    if isfield(c, 'metrics') && isstruct(c.metrics) && isfield(c.metrics, field_name)
        v = double(c.metrics.(field_name));
        if ~isscalar(v)
            v = NaN;
        end
    end
end

function v = cell_baseline_nrmse(cr, task, name)
    v = NaN;
    if ~isfield(cr, task) || ~isstruct(cr.(task))
        return;
    end
    t = cr.(task);
    if ~isfield(t, 'baselines') || ~isstruct(t.baselines)
        return;
    end
    v = baseline_nrmse(t.baselines, name);
end

function v = cell_auto_ctrl_metric(cr, name, field_name)
    v = NaN;
    if ~(isfield(cr, 'mackey_glass') && isstruct(cr.mackey_glass) && ...
            isfield(cr.mackey_glass, 'rollout') && ...
            isstruct(cr.mackey_glass.rollout) && ...
            isfield(cr.mackey_glass.rollout, 'controls'))
        return;
    end
    v = auto_ctrl_metric(cr.mackey_glass.rollout.controls, name, field_name);
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
    end
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
end

function T = rows_to_table(rows, varnames)
    if isempty(rows)
        T = empty_table(varnames);
        return;
    end
    % Normalize missing fields; store text as cellstr for struct2table safety
    for i = 1:numel(rows)
        for k = 1:numel(varnames)
            nm = varnames{k};
            if ~isfield(rows{i}, nm)
                if is_numeric_col(nm)
                    rows{i}.(nm) = NaN;
                else
                    rows{i}.(nm) = {''};
                end
            elseif is_numeric_col(nm)
                rows{i}.(nm) = double(rows{i}.(nm));
            else
                rows{i}.(nm) = {char(string(rows{i}.(nm)))};
            end
        end
    end
    S = [rows{:}];
    T = struct2table(S, 'AsArray', true);
    T = T(:, varnames);
end

function T = empty_table(varnames)
    n = numel(varnames);
    types = cell(1, n);
    for i = 1:n
        if is_numeric_col(varnames{i})
            types{i} = 'double';
        else
            types{i} = 'cell';
        end
    end
    T = table('Size', [0, n], 'VariableTypes', types, 'VariableNames', varnames);
end

function tf = is_numeric_col(nm)
    tf = any(strcmp(nm, {'seed', 'horizon'})) || ...
        contains(nm, 'nrmse') || contains(nm, 'mc_total') || ...
        contains(nm, 'slope') || contains(nm, 'wall_time') || ...
        contains(nm, 'horizon') || contains(nm, 'censored') || ...
        contains(nm, 'improvement') || contains(nm, 'difference') || ...
        contains(nm, 'pooled_nrmse') || contains(nm, 'target_nrmse') || ...
        contains(nm, 'reference_nrmse') || contains(nm, 'target_valid') || ...
        contains(nm, 'reference_valid') || contains(nm, 'target_fraction') || ...
        contains(nm, 'reference_fraction');
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
