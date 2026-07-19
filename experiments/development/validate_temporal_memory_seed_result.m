function report = validate_temporal_memory_seed_result(result, cfg)
%VALIDATE_TEMPORAL_MEMORY_SEED_RESULT  Fail-closed production seed-result checks.
%
%   report = validate_temporal_memory_seed_result(result, cfg)
%
% Production results must use exact preregistered model seed, cell, lag vector
% 1:50, complete finite metrics, and neuronal-rate activity. Synthetic /
% test-fixture provenance never passes.

    if nargin < 2 || ~isstruct(cfg)
        error('validate_temporal_memory_seed_result:InvalidCfg', ...
            'cfg must be a struct.');
    end
    if ~isstruct(result)
        error('validate_temporal_memory_seed_result:InvalidResult', ...
            'result must be a struct.');
    end

    reasons = {};
    checks = {};

    if local_get(result, 'is_test_fixture', false) || ...
            local_get(result, 'synthetic_provenance', false)
        reasons{end+1} = 'synthetic_or_test_fixture_provenance'; %#ok<*AGROW>
        checks{end+1} = make_check('production_provenance', false, 'fixture');
        report = fail_report(result, checks, reasons);
        return;
    end

    seed = local_get(result, 'model_seed', NaN);
    model_ok = ismember(seed, cfg.model_seeds(:)');
    checks{end+1} = make_check('model_seed_in_cfg', model_ok, mat2str(seed));
    if ~model_ok; reasons{end+1} = 'model_seed_not_executable'; end

    seed_9003_ok = seed ~= 9003;
    checks{end+1} = make_check('v1_test_seed_9003_rejected', seed_9003_ok, '');
    if ~seed_9003_ok; reasons{end+1} = 'v1_test_seed_9003_used'; end

    reserved = flatten_numeric(local_get(cfg, 'reserved_future_v2', struct()));
    reserved_ok = ~any(reserved(:) == seed);
    checks{end+1} = make_check('reserved_future_seed_rejected', reserved_ok, '');
    if ~reserved_ok; reasons{end+1} = 'reserved_future_seed_used'; end

    retired = local_get(cfg, 'retired_from_future_publication', []);
    retired_ok = ~any(retired(:) == seed);
    checks{end+1} = make_check('retired_seed_absent', retired_ok, '');
    if ~retired_ok; reasons{end+1} = 'retired_seed_used'; end

    cell_name = char(string(local_get(result, 'cell_name', '')));
    names = cfg.diagnostic_cell_names;
    cell_ok = any(strcmp(cell_name, names));
    checks{end+1} = make_check('cell_name_registered', cell_ok, cell_name);
    if ~cell_ok; reasons{end+1} = 'cell_name_mismatch'; end

    key_ok = false;
    if cell_ok
        idx = find(strcmp(cell_name, names), 1);
        expected_key = char(cfg.cells{idx}.cell_key);
        key_ok = strcmp(char(string(local_get(result, 'cell_key', ''))), expected_key);
    end
    checks{end+1} = make_check('cell_key_matches', key_ok, '');
    if ~key_ok; reasons{end+1} = 'cell_key_mismatch'; end

    lags = local_get(result, 'lags', []);
    lags = lags(:);
    expected_lags = cfg.lags(:);
    lags_exact = isequal(lags, expected_lags) && isequal(lags(:)', 1:50);
    checks{end+1} = make_check('lags_exact_1_to_50', lags_exact, ...
        sprintf('n=%d', numel(lags)));
    if ~lags_exact; reasons{end+1} = 'lags_not_exact_1_to_50'; end

    n_ok = isfield(result, 'per_lag') && numel(result.per_lag) == 50;
    checks{end+1} = make_check('per_lag_count_50', n_ok, '');
    if ~n_ok; reasons{end+1} = 'per_lag_count_not_50'; end

    lag_ids_ok = false;
    dup_ok = false;
    if n_ok
        lag_ids = [result.per_lag.lag];
        lag_ids_ok = isequal(lag_ids(:)', 1:50);
        dup_ok = numel(unique(lag_ids)) == 50;
    end
    checks{end+1} = make_check('per_lag_identities_1_to_50', lag_ids_ok, '');
    if ~lag_ids_ok; reasons{end+1} = 'per_lag_identities_mismatch'; end
    checks{end+1} = make_check('no_duplicate_lags', dup_ok, '');
    if ~dup_ok; reasons{end+1} = 'duplicate_or_missing_lags'; end

    metrics_ok = n_ok && all_metrics_finite(result.per_lag, cfg.lambda_grid);
    checks{end+1} = make_check('required_metrics_finite', metrics_ok, '');
    if ~metrics_ok; reasons{end+1} = 'nonfinite_or_invalid_metrics'; end

    mc_ok = n_ok && memory_coeffs_in_unit_interval(result.per_lag);
    checks{end+1} = make_check('memory_coefficients_in_0_1', mc_ok, '');
    if ~mc_ok; reasons{end+1} = 'memory_coefficient_out_of_range'; end

    inc_ok = isfield(result, 'include_input') && ~logical(result.include_input);
    checks{end+1} = make_check('include_input_false', inc_ok, '');
    if ~inc_ok; reasons{end+1} = 'include_input_true'; end

    sim_ok = isfield(result, 'simulations_per_split') && ...
        result.simulations_per_split == 1 && ...
        isfield(result, 'n_reservoir_simulations') && ...
        result.n_reservoir_simulations == 3;
    checks{end+1} = make_check('three_sims_one_per_split', sim_ok, '');
    if ~sim_ok; reasons{end+1} = 'simulation_count_mismatch'; end

    rng_ok = isfield(result, 'global_rng_unchanged') && ...
        logical(result.global_rng_unchanged);
    checks{end+1} = make_check('global_rng_unchanged', rng_ok, '');
    if ~rng_ok; reasons{end+1} = 'global_rng_mutated'; end

    feat_ok = isfield(result, 'feature_dimension') && result.feature_dimension == 40;
    checks{end+1} = make_check('feature_dimension_40', feat_ok, '');
    if ~feat_ok; reasons{end+1} = 'feature_dimension_mismatch'; end

    act_ok = true;
    if isfield(result, 'feature_diagnostics')
        fd = result.feature_diagnostics;
        act_ok = isfield(fd, 'n_neurons') && fd.n_neurons == 40 && ...
            isfield(fd, 'activity_from_neuronal_rates') && ...
            logical(fd.activity_from_neuronal_rates) && ...
            isfield(fd, 'packed_states_counted_as_neurons') && ...
            ~logical(fd.packed_states_counted_as_neurons);
    else
        act_ok = false;
    end
    checks{end+1} = make_check('activity_neuronal_n40', act_ok, '');
    if ~act_ok; reasons{end+1} = 'activity_not_neuronal_rate_based'; end

    sum_ok = false;
    lag10_ok = false;
    recompute_ok = false;
    if isfield(result, 'summary') && n_ok && ...
            all(isfield(result.summary, {'MC_1_10','MC_1_25','MC_1_50', ...
            'lag10_nrmse','lag10_r2'}))
        s = result.summary;
        sum_ok = all(isfinite([s.MC_1_10, s.MC_1_25, s.MC_1_50]));
        mc = zeros(50, 1);
        try
            for i = 1:50
                mc(i) = result.per_lag(i).metrics.memory_coefficient;
            end
            recompute_ok = abs(s.MC_1_10 - sum(mc(1:10))) <= 1e-12 && ...
                abs(s.MC_1_25 - sum(mc(1:25))) <= 1e-12 && ...
                abs(s.MC_1_50 - sum(mc(1:50))) <= 1e-12;
            m10 = result.per_lag(10).metrics;
            lag10_ok = abs(s.lag10_nrmse - m10.nrmse) <= 1e-12 && ...
                abs(s.lag10_r2 - m10.r2) <= 1e-12;
        catch
            recompute_ok = false;
            lag10_ok = false;
        end
    end
    checks{end+1} = make_check('mc_sums_finite', sum_ok, '');
    if ~sum_ok; reasons{end+1} = 'memory_summaries_missing'; end
    checks{end+1} = make_check('mc_sums_recompute', recompute_ok, '');
    if ~recompute_ok; reasons{end+1} = 'mc_sums_incorrect'; end
    checks{end+1} = make_check('lag10_summary_matches_row', lag10_ok, '');
    if ~lag10_ok; reasons{end+1} = 'lag10_summary_mismatch'; end

    if isfield(result, 'controls')
        ctrl_ok = validate_controls_identity(result.controls, cell_name);
        checks{end+1} = make_check('controls_identity', ctrl_ok, '');
        if ~ctrl_ok; reasons{end+1} = 'controls_identity_invalid'; end
    end

    report = struct();
    report.ok = isempty(reasons);
    report.checks = [checks{:}];
    report.failure_reasons = reasons;
    report.model_seed = seed;
    if ~report.ok
        error('validate_temporal_memory_seed_result:Failed', ...
            'Seed result validation failed: %s', strjoin(reasons, ', '));
    end
end

function report = fail_report(result, checks, reasons)
    report = struct();
    report.ok = false;
    report.checks = [checks{:}];
    report.failure_reasons = reasons;
    report.model_seed = local_get(result, 'model_seed', NaN);
    error('validate_temporal_memory_seed_result:Failed', ...
        'Seed result validation failed: %s', strjoin(reasons, ', '));
end

function tf = all_metrics_finite(per_lag, lambda_grid)
    grid = lambda_grid(:);
    tf = true;
    for i = 1:numel(per_lag)
        if ~isfield(per_lag, 'metrics') && ~isfield(per_lag(i), 'metrics')
            tf = false;
            return;
        end
        try
            m = per_lag(i).metrics;
            lam = per_lag(i).selected_lambda;
            nrank = per_lag(i).numerical_rank;
            cnorm = per_lag(i).coefficient_norm;
        catch
            tf = false;
            return;
        end
        if ~isstruct(m) || ~all(isfield(m, {'rmse','nrmse','r2','pearson','memory_coefficient'}))
            tf = false;
            return;
        end
        vals = [m.rmse, m.nrmse, m.r2, m.pearson, m.memory_coefficient, ...
            lam, nrank, cnorm];
        if ~all(isfinite(vals))
            tf = false;
            return;
        end
        if ~ismember(lam, grid)
            tf = false;
            return;
        end
    end
end

function tf = memory_coeffs_in_unit_interval(per_lag)
    tf = true;
    for i = 1:numel(per_lag)
        try
            mc = per_lag(i).metrics.memory_coefficient;
        catch
            tf = false;
            return;
        end
        if ~(isfinite(mc) && mc >= -1e-12 && mc <= 1 + 1e-12)
            tf = false;
            return;
        end
    end
end

function tf = validate_controls_identity(controls, cell_name)
    tf = true;
    if ~isstruct(controls)
        tf = false;
        return;
    end
    if isfield(controls, 'conventional_leaky_esn') && ...
            isfield(controls.conventional_leaky_esn, 'status') && ...
            strcmp(controls.conventional_leaky_esn.status, 'computed')
        c = controls.conventional_leaky_esn;
        tf = tf && logical(local_get(c, 'same_reservoir_for_all_lags', false));
        tf = tf && local_get(c, 'n_candidates', 0) == 27;
        tf = tf && ~logical(local_get(c, 'test_targets_used_for_selection', true));
        tf = tf && ~logical(local_get(c, 'used_narma_orchestrator', true));
        tf = tf && ~logical(local_get(c, 'used_mackey_glass_orchestrator', true));
        if isfield(c, 'per_lag')
            idxs = [c.per_lag.selected_candidate_index];
            tf = tf && numel(unique(idxs)) == 1;
        end
    end
    if strcmp(cell_name, 'reference_r')
        if isfield(controls, 'shuffled_target')
            st = controls.shuffled_target;
            tf = tf && (~isfield(st, 'status') || ~strcmp(st.status, 'not_required'));
        end
    end
end

function c = make_check(name, pass, detail)
    c = struct('name', name, 'pass', logical(pass), 'detail', char(string(detail)));
end

function v = local_get(S, name, default)
    if isstruct(S) && isfield(S, name)
        v = S.(name);
    else
        v = default;
    end
end

function vals = flatten_numeric(S)
    vals = [];
    if isnumeric(S)
        vals = S(:)';
        return;
    end
    if ~isstruct(S) || numel(S) ~= 1
        return;
    end
    fn = fieldnames(S);
    for i = 1:numel(fn)
        vals = [vals, flatten_numeric(S.(fn{i}))]; %#ok<AGROW>
    end
end
