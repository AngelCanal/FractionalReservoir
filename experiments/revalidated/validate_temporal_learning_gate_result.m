function [ok, report] = validate_temporal_learning_gate_result(gate_result, cfg)
% VALIDATE_TEMPORAL_LEARNING_GATE_RESULT  Independent gate-artifact verification.
%
%   [ok, report] = validate_temporal_learning_gate_result(gate_result, cfg)
%
% Recomputes paired deltas, aggregates, and gate conditions from seed rows.
% Never accepts gate_result.passed without recomputation. Scientific failure
% (passed=false with honest metrics) can still yield ok=true when the artifact
% is complete and internally consistent.

    report = struct();
    report.reasons = {};
    report.recomputed_conditions = struct();
    report.recomputed_passed = false;
    report.stored_passed = false;

    if nargin < 2 || ~isstruct(cfg)
        ok = false;
        report.reasons = {'cfg_missing_or_invalid'};
        return;
    end
    if ~isstruct(gate_result) || numel(gate_result) ~= 1
        ok = false;
        report.reasons = {'gate_result_not_scalar_struct'};
        return;
    end
    if ~isfield(cfg, 'temporal_learning_gate')
        ok = false;
        report.reasons = {'cfg_temporal_learning_gate_missing'};
        return;
    end

    gate = cfg.temporal_learning_gate;
    reasons = {};

    if ~strcmp(char(local_get(gate_result, 'protocol_version', '')), ...
            char(gate.protocol_version))
        reasons{end+1} = 'protocol_version_mismatch'; %#ok<AGROW>
    end
    if ~strcmp(char(local_get(gate_result, 'protocol_tier', '')), ...
            char(cfg.protocol_tier))
        reasons{end+1} = 'protocol_tier_mismatch'; %#ok<AGROW>
    end
    expected_fp = '';
    if isfield(cfg, 'protocol_fingerprint')
        expected_fp = char(cfg.protocol_fingerprint);
    end
    got_fp = char(local_get(gate_result, 'protocol_fingerprint', ''));
    if ~strcmp(got_fp, expected_fp)
        reasons{end+1} = 'protocol_fingerprint_mismatch'; %#ok<AGROW>
    end
    if ~strcmp(char(local_get(gate_result, 'status', '')), 'complete')
        reasons{end+1} = 'status_not_complete'; %#ok<AGROW>
    end

    prov = local_get(gate_result, 'evaluation_provenance', struct());
    tier = char(local_get(cfg, 'protocol_tier', ''));
    if strcmp(tier, 'publication')
        if ~strcmp(char(local_get(prov, 'mode', '')), 'executed')
            reasons{end+1} = 'evaluation_provenance_mode_not_executed'; %#ok<AGROW>
        end
        if logical(local_get(prov, 'test_override_used', true))
            reasons{end+1} = 'evaluation_provenance_test_override_used'; %#ok<AGROW>
        end
        if logical(local_get(prov, 'test_target_mutated', true))
            reasons{end+1} = 'evaluation_provenance_test_target_mutated'; %#ok<AGROW>
        end
    elseif strcmp(char(local_get(prov, 'mode', '')), 'injected_test_fixture')
        reasons{end+1} = 'evaluation_provenance_injected_test_fixture'; %#ok<AGROW>
    elseif strcmp(char(local_get(prov, 'mode', '')), 'test_target_mutated')
        reasons{end+1} = 'evaluation_provenance_test_target_mutated_mode'; %#ok<AGROW>
    elseif logical(local_get(prov, 'test_target_mutated', false))
        reasons{end+1} = 'evaluation_provenance_test_target_mutated'; %#ok<AGROW>
    end

    if logical(local_get(gate_result, 'include_input', true))
        reasons{end+1} = 'include_input_not_false'; %#ok<AGROW>
    end
    if ~strcmp(char(local_get(gate_result, 'feature_mode', '')), char(gate.feature_mode))
        reasons{end+1} = 'feature_mode_mismatch'; %#ok<AGROW>
    end
    if ~isequal(local_get(gate_result, 'feature_dimension', NaN), gate.feature_dimension)
        reasons{end+1} = 'feature_dimension_mismatch'; %#ok<AGROW>
    end
    if ~isequal(local_get(gate_result, 'target_lag_steps', NaN), gate.target_lag_steps)
        reasons{end+1} = 'target_lag_steps_mismatch'; %#ok<AGROW>
    end
    dt = cfg.base.dt;
    if isfield(gate_result, 'dt')
        if abs(gate_result.dt - dt) > 1e-12
            reasons{end+1} = 'dt_mismatch'; %#ok<AGROW>
        end
    elseif abs(gate.dt - dt) > 1e-12
        reasons{end+1} = 'cfg_gate_dt_mismatch'; %#ok<AGROW>
    end
    expected_lag_time = gate.target_lag_steps * dt;
    if abs(local_get(gate_result, 'target_lag_time', NaN) - expected_lag_time) > 1e-12
        reasons{end+1} = 'target_lag_time_mismatch'; %#ok<AGROW>
    end

    if ~isequal(local_get(gate_result, 'train_samples_requested', NaN), gate.train_samples) || ...
            ~isequal(local_get(gate_result, 'validation_samples_requested', NaN), ...
                gate.validation_samples) || ...
            ~isequal(local_get(gate_result, 'test_samples_requested', NaN), gate.test_samples)
        reasons{end+1} = 'requested_sample_lengths_mismatch'; %#ok<AGROW>
    end
    if ~isequal(local_get(gate_result, 'train_samples_used', NaN), gate.train_samples) || ...
            ~isequal(local_get(gate_result, 'validation_samples_used', NaN), ...
                gate.validation_samples) || ...
            ~isequal(local_get(gate_result, 'test_samples_used', NaN), gate.test_samples)
        reasons{end+1} = 'used_sample_lengths_mismatch'; %#ok<AGROW>
    end

    seed_fields = { ...
        'train_input_seed', 'validation_input_seed', 'test_input_seed', ...
        'shuffle_train_seed', 'shuffle_validation_seed', 'shuffle_test_seed'};
    for i = 1:numel(seed_fields)
        name = seed_fields{i};
        if ~isequal(local_get(gate_result, name, NaN), gate.(name))
            reasons{end+1} = [name '_mismatch']; %#ok<AGROW>
        end
    end
    if ~isfield(gate_result, 'split_seeds') || ~isstruct(gate_result.split_seeds)
        reasons{end+1} = 'split_seeds_missing'; %#ok<AGROW>
    else
        ss = gate_result.split_seeds;
        for i = 1:numel(seed_fields)
            name = seed_fields{i};
            if ~isfield(ss, name) || ~isequal(ss.(name), gate.(name))
                reasons{end+1} = ['split_seeds_' name '_mismatch']; %#ok<AGROW>
            end
        end
    end
    if ~isfield(gate_result, 'split_independence') || ~isstruct(gate_result.split_independence)
        reasons{end+1} = 'split_independence_missing'; %#ok<AGROW>
    end

    if ~isequal(local_get(gate_result, 'lambda_grid', []), gate.lambda_grid(:)) && ...
            ~isequal(local_get(gate_result, 'lambda_grid', [])', gate.lambda_grid(:))
        g_grid = local_get(gate_result, 'lambda_grid', []);
        if ~isequal(g_grid(:), gate.lambda_grid(:))
            reasons{end+1} = 'lambda_grid_mismatch'; %#ok<AGROW>
        end
    end

    if ~thresholds_equal(local_get(gate_result, 'thresholds', struct()), gate.thresholds)
        reasons{end+1} = 'thresholds_mismatch'; %#ok<AGROW>
    end

    expected_seeds = gate.model_seeds(:);
    if ~isfield(gate_result, 'model_seeds') || ~isequal(gate_result.model_seeds(:), expected_seeds)
        reasons{end+1} = 'model_seeds_mismatch'; %#ok<AGROW>
    end
    if ~isfield(gate_result, 'seed_results') || isempty(gate_result.seed_results)
        reasons{end+1} = 'seed_results_missing'; %#ok<AGROW>
        report.reasons = unique(reasons, 'stable');
        report.stored_passed = logical(local_get(gate_result, 'passed', false));
        ok = false;
        return;
    end

    seed_results = gate_result.seed_results(:);
    if numel(seed_results) ~= numel(expected_seeds)
        reasons{end+1} = 'seed_row_count_mismatch'; %#ok<AGROW>
    end
    for i = 1:min(numel(seed_results), numel(expected_seeds))
        if ~isequal(seed_results(i).model_seed, expected_seeds(i))
            reasons{end+1} = 'seed_identity_or_order_mismatch'; %#ok<AGROW>
            break;
        end
    end

    required_controls = { ...
        'current_input_only_control', ...
        'no_recurrent_coupling_control', ...
        'shuffled_target_control', ...
        'exact_history_control'};
    fit_names = [{'mesn'}, required_controls];
    lambda_grid = gate.lambda_grid(:);
    thr = gate.thresholds;

    all_finite = true;
    for i = 1:numel(seed_results)
        sr = seed_results(i);
        if ~strcmp(char(local_get(sr, 'status', '')), 'ok')
            all_finite = false;
            reasons{end+1} = sprintf('seed_%d_status_not_ok', i); %#ok<AGROW>
            continue;
        end
        for c = 1:numel(required_controls)
            if ~isfield(sr, required_controls{c})
                reasons{end+1} = ['missing_' required_controls{c}]; %#ok<AGROW>
            end
        end
        for f = 1:numel(fit_names)
            name = fit_names{f};
            if ~isfield(sr, name)
                reasons{end+1} = ['missing_fit_' name]; %#ok<AGROW>
                all_finite = false;
                continue;
            end
            fit = sr.(name);
            m = local_get(fit, 'metrics', struct());
            vals = [local_get(m, 'rmse', NaN), local_get(m, 'nrmse', NaN), ...
                local_get(m, 'r2', NaN)];
            if any(~isfinite(vals))
                reasons{end+1} = [name '_metrics_nonfinite']; %#ok<AGROW>
                all_finite = false;
            end
            lam = local_get(fit, 'selected_lambda', NaN);
            if ~isfinite(lam) || ~any(abs(lambda_grid - lam) <= 0)
                % exact membership
                if ~isfinite(lam) || ~any(lambda_grid == lam)
                    reasons{end+1} = [name '_lambda_not_in_grid']; %#ok<AGROW>
                end
            end
            if ~isfield(fit, 'ridge') || ~diagnostics_ok(fit.ridge)
                reasons{end+1} = [name '_diagnostics_missing_or_nonfinite']; %#ok<AGROW>
                all_finite = false;
            end
            if ~isfield(fit, 'lambda_selection_table') || isempty(fit.lambda_selection_table)
                reasons{end+1} = [name '_lambda_selection_table_missing']; %#ok<AGROW>
            end
            if ~isfield(fit, 'selected_at_grid_boundary')
                reasons{end+1} = [name '_selected_at_grid_boundary_missing']; %#ok<AGROW>
            end
        end

        mesn_n = sr.mesn.metrics.nrmse;
        cur_n = sr.current_input_only_control.metrics.nrmse;
        nr_n = sr.no_recurrent_coupling_control.metrics.nrmse;
        d_cur = cur_n - mesn_n;
        d_nr = nr_n - mesn_n;
        if ~isfinite(local_get(sr, 'delta_vs_current_nrmse', NaN)) || ...
                abs(sr.delta_vs_current_nrmse - d_cur) > 1e-12
            reasons{end+1} = 'delta_vs_current_recompute_mismatch'; %#ok<AGROW>
        end
        if ~isfinite(local_get(sr, 'delta_vs_no_recurrence_nrmse', NaN)) || ...
                abs(sr.delta_vs_no_recurrence_nrmse - d_nr) > 1e-12
            reasons{end+1} = 'delta_vs_no_recurrence_recompute_mismatch'; %#ok<AGROW>
        end
    end

    agg_re = recompute_aggregate(seed_results, thr, numel(expected_seeds));
    if isfield(gate_result, 'aggregate_results')
        if ~aggregates_match(gate_result.aggregate_results, agg_re)
            reasons{end+1} = 'aggregate_recompute_mismatch'; %#ok<AGROW>
        end
    else
        reasons{end+1} = 'aggregate_results_missing'; %#ok<AGROW>
    end

    split_meta = struct();
    split_meta.split_independence = local_get(gate_result, 'split_independence', struct( ...
        'task_seeds_distinct', false, 'sequences_distinct', false, 'verified', false));
    controls_ok = controls_present(seed_results, required_controls);
    diagnostics_ok_flag = all_diagnostics_present(seed_results, fit_names);
    if ~controls_ok
        reasons{end+1} = 'controls_present_check_failed'; %#ok<AGROW>
    end
    if ~diagnostics_ok_flag
        reasons{end+1} = 'diagnostics_present_check_failed'; %#ok<AGROW>
    end

    target_lag_time = expected_lag_time;
    recomputed = recompute_gate_conditions(agg_re, gate, thr, all_finite, ...
        numel(expected_seeds), target_lag_time, split_meta, controls_ok, diagnostics_ok_flag);
    recomputed_passed = true;
    cond_names = fieldnames(recomputed);
    for i = 1:numel(cond_names)
        if ~logical(recomputed.(cond_names{i}))
            recomputed_passed = false;
            break;
        end
    end
    if isfield(gate_result, 'gate_conditions')
        if ~conditions_match(gate_result.gate_conditions, recomputed)
            reasons{end+1} = 'gate_conditions_recompute_mismatch'; %#ok<AGROW>
        end
    else
        reasons{end+1} = 'gate_conditions_missing'; %#ok<AGROW>
    end

    stored_passed = logical(local_get(gate_result, 'passed', false));
    if xor(stored_passed, recomputed_passed)
        reasons{end+1} = 'passed_flag_does_not_match_recomputed_conditions'; %#ok<AGROW>
    end

    report.reasons = unique(reasons, 'stable');
    report.recomputed_conditions = recomputed;
    report.recomputed_passed = recomputed_passed;
    report.stored_passed = stored_passed;
    report.aggregate_recomputed = agg_re;
    ok = isempty(report.reasons);
end

function tf = thresholds_equal(a, b)
    tf = false;
    if ~isstruct(a) || ~isstruct(b)
        return;
    end
    fa = sort(fieldnames(a));
    fb = sort(fieldnames(b));
    if ~isequal(fa, fb)
        return;
    end
    for i = 1:numel(fa)
        if ~isequaln(a.(fa{i}), b.(fa{i}))
            return;
        end
    end
    tf = true;
end

function tf = diagnostics_ok(d)
    tf = false;
    if ~isstruct(d)
        return;
    end
    required_finite = {'numerical_rank', 'coefficient_norm', 'lambda', 'intercept'};
    for i = 1:numel(required_finite)
        name = required_finite{i};
        if ~isfield(d, name) || any(~isfinite(d.(name)(:)))
            return;
        end
    end
    if ~isfield(d, 'solver_method') || isempty(char(string(d.solver_method)))
        return;
    end
    if ~isfield(d, 'feature_mean') || ~isfield(d, 'feature_scale') || ...
            any(~isfinite(d.feature_mean(:))) || any(~isfinite(d.feature_scale(:)))
        return;
    end
    tf = true;
end

function tf = controls_present(seed_results, required_controls)
    tf = ~isempty(seed_results);
    for i = 1:numel(seed_results)
        if ~strcmp(char(local_get(seed_results(i), 'status', '')), 'ok')
            tf = false;
            return;
        end
        for c = 1:numel(required_controls)
            name = required_controls{c};
            if ~isfield(seed_results(i), name)
                tf = false;
                return;
            end
            fit = seed_results(i).(name);
            if ~isstruct(fit) || ~strcmp(char(local_get(fit, 'fit_status', '')), 'ok')
                tf = false;
                return;
            end
        end
    end
end

function tf = all_diagnostics_present(seed_results, fit_names)
    tf = ~isempty(seed_results);
    for i = 1:numel(seed_results)
        if ~strcmp(char(local_get(seed_results(i), 'status', '')), 'ok')
            tf = false;
            return;
        end
        for f = 1:numel(fit_names)
            fit = seed_results(i).(fit_names{f});
            if ~isfield(fit, 'ridge') || ~diagnostics_ok(fit.ridge) || ...
                    ~isfield(fit, 'lambda_selection_table') || ...
                    isempty(fit.lambda_selection_table) || ...
                    ~isfield(fit, 'selected_at_grid_boundary')
                tf = false;
                return;
            end
        end
    end
end

function agg = recompute_aggregate(seed_results, thresholds, n_requested)
    ok = strcmp({seed_results.status}, 'ok');
    n_ok = nnz(ok);
    agg = struct();
    agg.n_seeds_requested = n_requested;
    agg.n_seeds_completed = n_ok;
    metric_names = {'mesn', 'current_input_only_control', ...
        'no_recurrent_coupling_control', 'shuffled_target_control', ...
        'exact_history_control'};
    fields = {'nrmse', 'r2', 'rmse'};
    for mi = 1:numel(metric_names)
        for fi = 1:numel(fields)
            vals = nan(n_requested, 1);
            for i = 1:min(n_requested, numel(seed_results))
                if i <= numel(ok) && ok(i)
                    vals(i) = seed_results(i).(metric_names{mi}).metrics.(fields{fi});
                end
            end
            agg.([metric_names{mi} '_' fields{fi}]) = summarize_vec(vals);
        end
    end
    d_cur = nan(n_requested, 1);
    d_nr = nan(n_requested, 1);
    beat_cur = false(n_requested, 1);
    beat_nr = false(n_requested, 1);
    for i = 1:min(n_requested, numel(seed_results))
        if ok(i)
            d_cur(i) = seed_results(i).delta_vs_current_nrmse;
            d_nr(i) = seed_results(i).delta_vs_no_recurrence_nrmse;
            beat_cur(i) = seed_results(i).beats_current;
            beat_nr(i) = seed_results(i).beats_no_recurrence;
        end
    end
    agg.delta_vs_current_nrmse = summarize_vec(d_cur);
    agg.delta_vs_no_recurrence_nrmse = summarize_vec(d_nr);
    if n_ok == 0
        agg.fraction_beating_current = NaN;
        agg.fraction_beating_no_recurrence = NaN;
    else
        ok_mask = false(n_requested, 1);
        n_ok_use = min(n_requested, numel(ok));
        ok_mask(1:n_ok_use) = ok(1:n_ok_use);
        agg.fraction_beating_current = mean(beat_cur(ok_mask));
        agg.fraction_beating_no_recurrence = mean(beat_nr(ok_mask));
    end
    ok_mask = false(n_requested, 1);
    n_ok_use = min(n_requested, numel(ok));
    ok_mask(1:n_ok_use) = ok(1:n_ok_use);
    agg.n_beating_current = nnz(beat_cur & ok_mask);
    agg.n_beating_no_recurrence = nnz(beat_nr & ok_mask);
    agg.thresholds = thresholds;
end

function s = summarize_vec(vals)
    v = vals(isfinite(vals));
    s = struct();
    if isempty(v)
        s.median = NaN;
        s.iqr = NaN;
        s.mean = NaN;
        s.values = vals(:);
        return;
    end
    s.median = median(v);
    vv = sort(v(:));
    n = numel(vv);
    q1 = vv(max(1, ceil(0.25 * n)));
    q3 = vv(max(1, ceil(0.75 * n)));
    s.iqr = q3 - q1;
    s.mean = mean(v);
    s.values = vals(:);
end

function tf = aggregates_match(a, b)
    tf = false;
    keys = {'mesn_nrmse', 'mesn_r2', 'delta_vs_current_nrmse', ...
        'delta_vs_no_recurrence_nrmse', 'shuffled_target_control_nrmse', ...
        'exact_history_control_nrmse'};
    for i = 1:numel(keys)
        k = keys{i};
        if ~isfield(a, k) || ~isfield(b, k)
            return;
        end
        if abs(a.(k).median - b.(k).median) > 1e-12 && ...
                ~(isnan(a.(k).median) && isnan(b.(k).median))
            return;
        end
    end
    if abs(a.fraction_beating_current - b.fraction_beating_current) > 1e-12 && ...
            ~(isnan(a.fraction_beating_current) && isnan(b.fraction_beating_current))
        return;
    end
    if abs(a.fraction_beating_no_recurrence - b.fraction_beating_no_recurrence) > 1e-12 && ...
            ~(isnan(a.fraction_beating_no_recurrence) && isnan(b.fraction_beating_no_recurrence))
        return;
    end
    tf = true;
end

function gc = recompute_gate_conditions(agg, gate, thr, all_finite, n_seeds, ...
        target_lag_time, split_meta, controls_ok, diagnostics_ok)
    gc = struct();
    gc.all_fits_and_metrics_finite = all_finite && ...
        isfinite(agg.mesn_nrmse.median) && isfinite(agg.mesn_r2.median);
    gc.include_input_false = ~logical(gate.include_input);
    gc.target_lag_positive = gate.target_lag_steps > 0;
    gc.target_lag_time_consistent = abs(target_lag_time - gate.target_lag_steps * gate.dt) <= 1e-12;
    si = split_meta.split_independence;
    gc.splits_independent = logical(local_get(si, 'task_seeds_distinct', false)) && ...
        logical(local_get(si, 'sequences_distinct', false)) && ...
        logical(local_get(si, 'verified', false));
    gc.mesn_median_nrmse_ok = isfinite(agg.mesn_nrmse.median) && ...
        agg.mesn_nrmse.median <= thr.mesn_median_nrmse_max;
    gc.mesn_median_r2_ok = isfinite(agg.mesn_r2.median) && ...
        agg.mesn_r2.median >= thr.mesn_median_r2_min;
    gc.median_delta_vs_current_ok = isfinite(agg.delta_vs_current_nrmse.median) && ...
        agg.delta_vs_current_nrmse.median >= thr.median_delta_vs_current_min;
    gc.fraction_beating_current_ok = isfinite(agg.fraction_beating_current) && ...
        agg.fraction_beating_current >= thr.fraction_beating_current_min;
    gc.median_delta_vs_no_recurrence_ok = isfinite(agg.delta_vs_no_recurrence_nrmse.median) && ...
        agg.delta_vs_no_recurrence_nrmse.median >= thr.median_delta_vs_no_recurrence_min;
    gc.fraction_beating_no_recurrence_ok = isfinite(agg.fraction_beating_no_recurrence) && ...
        agg.fraction_beating_no_recurrence >= thr.fraction_beating_no_recurrence_min;
    gc.shuffled_median_nrmse_ok = isfinite(agg.shuffled_target_control_nrmse.median) && ...
        agg.shuffled_target_control_nrmse.median >= thr.shuffled_median_nrmse_min;
    gc.exact_history_median_nrmse_ok = isfinite(agg.exact_history_control_nrmse.median) && ...
        agg.exact_history_control_nrmse.median <= thr.exact_history_median_nrmse_max;
    gc.seed_rows_complete = agg.n_seeds_completed == n_seeds;
    gc.controls_present = logical(controls_ok);
    gc.diagnostics_present = logical(diagnostics_ok);
end

function tf = conditions_match(a, b)
    tf = false;
    if ~isstruct(a) || ~isstruct(b)
        return;
    end
    fa = sort(fieldnames(a));
    fb = sort(fieldnames(b));
    if ~isequal(fa, fb)
        return;
    end
    for i = 1:numel(fa)
        if xor(logical(a.(fa{i})), logical(b.(fa{i})))
            return;
        end
    end
    tf = true;
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
