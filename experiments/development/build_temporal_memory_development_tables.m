function tables = build_temporal_memory_development_tables(cfg, seed_results, controls)
%BUILD_TEMPORAL_MEMORY_DEVELOPMENT_TABLES  Long, summary, contrast, control tables.
%
%   tables = build_temporal_memory_development_tables(cfg, seed_results, controls)
%
% seed_results: cell array of scored MESN seed-cell structs (24 production).
% controls: struct with shared task / conventional / reference control artifacts.
%
% MESN long table: 8 cells x 3 seeds x 50 lags = 1200 rows (production).
% Control long table: 550 lag rows (B1-R allocation, production).

    cell_names = cfg.diagnostic_cell_names(:);
    seeds = cfg.model_seeds(:);
    lags = cfg.lags(:);
    n_lags = numel(lags);
    n_seeds = numel(seeds);

    n_long = 0;
    for i = 1:numel(seed_results)
        n_long = n_long + numel(seed_results{i}.per_lag);
    end
    n_summary = numel(seed_results);

    long_template = struct( ...
        'cell_name', "", ...
        'model_seed', NaN, ...
        'lag', NaN, ...
        'held_out_nrmse', NaN, ...
        'held_out_r2', NaN, ...
        'held_out_pearson_correlation', NaN, ...
        'squared_correlation_memory_coefficient', NaN, ...
        'held_out_rmse', NaN, ...
        'selected_lambda', NaN, ...
        'grid_boundary_flag', false, ...
        'effective_numerical_rank', NaN, ...
        'coefficient_norm', NaN);
    if n_long == 0
        long_rows = long_template([]);
    else
        long_rows = repmat(long_template, n_long, 1);
    end

    summary_template = struct( ...
        'cell_name', "", ...
        'model_seed', NaN, ...
        'memory_capacity_sum_lags_1_10', NaN, ...
        'memory_capacity_sum_lags_1_25', NaN, ...
        'memory_capacity_sum_lags_1_50', NaN, ...
        'lag_of_maximum_memory_coefficient', NaN, ...
        'lag10_nrmse', NaN, ...
        'lag10_r2', NaN, ...
        'feature_covariance_effective_rank', NaN, ...
        'feature_participation_ratio', NaN, ...
        'fraction_numerically_near_constant_features', NaN, ...
        'mean_feature_standard_deviation', NaN, ...
        'median_feature_standard_deviation', NaN, ...
        'mean_firing_rate', NaN, ...
        'saturation_fraction', NaN, ...
        'silence_fraction', NaN);
    if n_summary == 0
        summary_rows = summary_template([]);
    else
        summary_rows = repmat(summary_template, n_summary, 1);
    end

    li = 0;
    for i = 1:numel(seed_results)
        r = seed_results{i};
        for j = 1:numel(r.per_lag)
            pl = r.per_lag(j);
            m = pl.metrics;
            li = li + 1;
            long_rows(li).cell_name = string(char(r.cell_name));
            long_rows(li).model_seed = r.model_seed;
            long_rows(li).lag = pl.lag;
            long_rows(li).held_out_nrmse = m.nrmse;
            long_rows(li).held_out_r2 = m.r2;
            long_rows(li).held_out_pearson_correlation = m.pearson;
            long_rows(li).squared_correlation_memory_coefficient = m.memory_coefficient;
            long_rows(li).held_out_rmse = m.rmse;
            long_rows(li).selected_lambda = pl.selected_lambda;
            long_rows(li).grid_boundary_flag = logical(local_get(pl, ...
                'selected_at_grid_boundary', local_get(pl, 'grid_boundary_flag', false)));
            long_rows(li).effective_numerical_rank = pl.numerical_rank;
            long_rows(li).coefficient_norm = pl.coefficient_norm;
        end
        s = r.summary;
        fd = local_get(r, 'feature_diagnostics', struct());
        summary_rows(i).cell_name = string(char(r.cell_name));
        summary_rows(i).model_seed = r.model_seed;
        summary_rows(i).memory_capacity_sum_lags_1_10 = s.memory_capacity_sum_lags_1_10;
        summary_rows(i).memory_capacity_sum_lags_1_25 = s.memory_capacity_sum_lags_1_25;
        summary_rows(i).memory_capacity_sum_lags_1_50 = s.memory_capacity_sum_lags_1_50;
        summary_rows(i).lag_of_maximum_memory_coefficient = ...
            s.lag_of_maximum_memory_coefficient;
        summary_rows(i).lag10_nrmse = s.lag10_nrmse;
        summary_rows(i).lag10_r2 = s.lag10_r2;
        summary_rows(i).feature_covariance_effective_rank = local_get(fd, ...
            'feature_covariance_effective_rank', local_get(fd, 'numerical_rank', NaN));
        summary_rows(i).feature_participation_ratio = local_get(fd, ...
            'feature_participation_ratio', local_get(fd, 'participation_ratio', NaN));
        summary_rows(i).fraction_numerically_near_constant_features = local_get(fd, ...
            'fraction_numerically_near_constant_features', ...
            local_get(fd, 'fraction_near_constant', NaN));
        summary_rows(i).mean_feature_standard_deviation = local_get(fd, ...
            'mean_feature_standard_deviation', local_get(fd, 'mean_feature_std', NaN));
        summary_rows(i).median_feature_standard_deviation = local_get(fd, ...
            'median_feature_standard_deviation', NaN);
        summary_rows(i).mean_firing_rate = local_get(fd, 'mean_firing_rate', NaN);
        summary_rows(i).saturation_fraction = local_get(fd, 'saturation_fraction', NaN);
        summary_rows(i).silence_fraction = local_get(fd, 'silence_fraction', NaN);
    end

    tables.long_table = struct2table(long_rows);
    tables.summary_table = struct2table(summary_rows);

    tables.contrast_table = build_temporal_memory_contrast_table( ...
        tables.summary_table, seeds);

    tables.control_long_table = build_control_long_table(controls, seeds, lags);
    tables.control_summary = summarize_controls(controls, seeds, lags);

    tables.expected_long_rows = numel(cell_names) * n_seeds * n_lags;
    tables.expected_summary_rows = numel(cell_names) * n_seeds;
    tables.expected_control_lag_rows = 2 * n_lags + 3 * n_seeds * n_lags;
end

function T = build_temporal_memory_contrast_table(summary_table, seeds)
% Paired descriptive contrasts by model seed. No p-values.
    defs = { ...
        'representation', 'reference_x', 'reference_r'; ...
        'delay', 'reference_r', 'delay_removed_r'; ...
        'STD', 'reference_r', 'std_removed_r'; ...
        'combined_STD_and_delay', 'reference_r', 'std_and_delay_removed_r'; ...
        'SFA_distribution', 'reference_r', 'single_moment_matched_r'; ...
        'SFA_presence', 'reference_r', 'adaptation_removed_r'; ...
        'full_mechanisms', 'reference_r', 'mechanisms_off_r'};

    n_expected = numel(seeds) * size(defs, 1);
    row_template = struct( ...
        'contrast_name', "", ...
        'model_seed', NaN, ...
        'reference_cell', "", ...
        'control_cell', "", ...
        'reference_lag10_nrmse', NaN, ...
        'control_lag10_nrmse', NaN, ...
        'improvement_nrmse', NaN, ...
        'reference_lag10_r2', NaN, ...
        'control_lag10_r2', NaN, ...
        'improvement_r2', NaN, ...
        'reference_MC_1_50', NaN, ...
        'control_MC_1_50', NaN, ...
        'improvement_MC_1_50', NaN, ...
        'reference_MC_1_10', NaN, ...
        'control_MC_1_10', NaN, ...
        'improvement_MC_1_10', NaN);
    if n_expected == 0
        rows = row_template([]);
    else
        rows = repmat(row_template, n_expected, 1);
    end
    k = 0;
    for is = 1:numel(seeds)
        seed = seeds(is);
        for id = 1:size(defs, 1)
            contrast_name = defs{id, 1};
            ref_name = defs{id, 2};
            ctrl_name = defs{id, 3};
            ref = lookup_summary(summary_table, ref_name, seed, false);
            ctrl = lookup_summary(summary_table, ctrl_name, seed, false);
            if isempty(ref) || isempty(ctrl)
                continue;
            end
            k = k + 1;
            rows(k).contrast_name = string(contrast_name);
            rows(k).model_seed = seed;
            rows(k).reference_cell = string(ref_name);
            rows(k).control_cell = string(ctrl_name);
            rows(k).reference_lag10_nrmse = ref.lag10_nrmse;
            rows(k).control_lag10_nrmse = ctrl.lag10_nrmse;
            rows(k).improvement_nrmse = ctrl.lag10_nrmse - ref.lag10_nrmse;
            rows(k).reference_lag10_r2 = ref.lag10_r2;
            rows(k).control_lag10_r2 = ctrl.lag10_r2;
            rows(k).improvement_r2 = ref.lag10_r2 - ctrl.lag10_r2;
            rows(k).reference_MC_1_50 = ref.memory_capacity_sum_lags_1_50;
            rows(k).control_MC_1_50 = ctrl.memory_capacity_sum_lags_1_50;
            rows(k).improvement_MC_1_50 = ...
                ref.memory_capacity_sum_lags_1_50 - ctrl.memory_capacity_sum_lags_1_50;
            rows(k).reference_MC_1_10 = ref.memory_capacity_sum_lags_1_10;
            rows(k).control_MC_1_10 = ctrl.memory_capacity_sum_lags_1_10;
            rows(k).improvement_MC_1_10 = ...
                ref.memory_capacity_sum_lags_1_10 - ctrl.memory_capacity_sum_lags_1_10;
        end
    end
    if k == 0
        rows = row_template([]);
    else
        rows = rows(1:k);
    end
    T = struct2table(rows);
end

function row = lookup_summary(T, cell_name, seed, require)
    if nargin < 4
        require = true;
    end
    mask = strcmp(string(T.cell_name), string(cell_name)) & T.model_seed == seed;
    n = sum(mask);
    if n == 0
        if require
            error('build_temporal_memory_development_tables:SummaryLookup', ...
                'Expected one summary row for %s seed %d.', cell_name, seed);
        end
        row = [];
        return;
    end
    if n ~= 1
        error('build_temporal_memory_development_tables:SummaryLookup', ...
            'Expected one summary row for %s seed %d.', cell_name, seed);
    end
    row = T(mask, :);
end

function T = build_control_long_table(controls, seeds, lags)
    n_lags = numel(lags);
    n_rows = 2 * n_lags + 3 * numel(seeds) * n_lags;
    row_template = struct( ...
        'control_name', "", ...
        'model_seed', NaN, ...
        'lag', NaN, ...
        'held_out_nrmse', NaN, ...
        'held_out_r2', NaN, ...
        'held_out_pearson_correlation', NaN, ...
        'squared_correlation_memory_coefficient', NaN, ...
        'held_out_rmse', NaN);
    if n_rows == 0
        rows = row_template([]);
    else
        rows = repmat(row_template, n_rows, 1);
    end
    k = 0;
    [rows, k] = append_control_lags(rows, k, controls.current_input_only, ...
        'current_input_only', NaN, lags);
    [rows, k] = append_control_lags(rows, k, controls.exact_history, ...
        'exact_history', NaN, lags);
    for is = 1:numel(seeds)
        seed = seeds(is);
        sf = sprintf('seed_%d', seed);
        [rows, k] = append_control_lags(rows, k, controls.conventional.(sf), ...
            'conventional_leaky_esn', seed, lags);
        [rows, k] = append_control_lags(rows, k, controls.no_recurrent.(sf), ...
            'no_recurrent_coupling', seed, lags);
        [rows, k] = append_control_lags(rows, k, controls.shuffled_target.(sf), ...
            'shuffled_target', seed, lags);
    end
    if k == 0
        rows = row_template([]);
    else
        rows = rows(1:k);
    end
    T = struct2table(rows);
end

function [rows, k] = append_control_lags(rows, k, scored, name, seed, lags)
    if isfield(scored, 'scored') && isfield(scored.scored, 'per_lag')
        per_lag = scored.scored.per_lag;
    elseif isfield(scored, 'per_lag')
        per_lag = scored.per_lag;
    else
        error('build_temporal_memory_development_tables:ControlShape', ...
            'Control %s missing per_lag.', name);
    end
    for i = 1:numel(lags)
        pl = per_lag(i);
        m = pl.metrics;
        k = k + 1;
        rows(k).control_name = string(name);
        rows(k).model_seed = seed;
        rows(k).lag = lags(i);
        rows(k).held_out_nrmse = m.nrmse;
        rows(k).held_out_r2 = m.r2;
        rows(k).held_out_pearson_correlation = m.pearson;
        rows(k).squared_correlation_memory_coefficient = m.memory_coefficient;
        rows(k).held_out_rmse = m.rmse;
    end
end

function cs = summarize_controls(controls, seeds, lags)
    n_lags = numel(lags);
    n_seeds = numel(seeds);
    cs = struct();
    cs.allocation = struct( ...
        'current_input_only_lag_rows', n_lags, ...
        'exact_history_lag_rows', n_lags, ...
        'conventional_lag_rows', n_seeds * n_lags, ...
        'no_recurrent_lag_rows', n_seeds * n_lags, ...
        'shuffled_target_lag_rows', n_seeds * n_lags, ...
        'total_control_lag_rows', 2 * n_lags + 3 * n_seeds * n_lags, ...
        'conventional_fits', n_seeds, ...
        'mesn_cell_seed_fits', numel(local_get_cells(controls)) * n_seeds);
    % Prefer explicit mesn fit count from caller when present on allocation note.
    if isfield(controls, 'mesn_cell_seed_fits')
        cs.allocation.mesn_cell_seed_fits = controls.mesn_cell_seed_fits;
    else
        % Production default when full geometry used
        if n_seeds == 3 && n_lags == 50
            cs.allocation.mesn_cell_seed_fits = 24;
        end
    end
    cs.current_input_only = extract_summary(controls.current_input_only);
    cs.exact_history = extract_summary(controls.exact_history);
    cs.by_seed = struct();
    for is = 1:numel(seeds)
        sf = sprintf('seed_%d', seeds(is));
        cs.by_seed.(sf) = struct( ...
            'conventional', extract_summary(controls.conventional.(sf)), ...
            'no_recurrent', extract_summary(controls.no_recurrent.(sf)), ...
            'shuffled_target', extract_summary(controls.shuffled_target.(sf)));
    end
end

function s = extract_summary(ctrl)
    if isfield(ctrl, 'summary')
        s = ctrl.summary;
    elseif isfield(ctrl, 'scored') && isfield(ctrl.scored, 'summary')
        s = ctrl.scored.summary;
    else
        s = struct();
    end
end

function n = local_get_cells(~)
    n = 8;
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
