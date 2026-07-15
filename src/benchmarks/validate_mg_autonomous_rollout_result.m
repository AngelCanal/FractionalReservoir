function [ok, report] = validate_mg_autonomous_rollout_result(result, cfg, cell_mode)
% VALIDATE_MG_AUTONOMOUS_ROLLOUT_RESULT  Strict MG autonomous endpoint checks.
%
%   [ok, report] = validate_mg_autonomous_rollout_result(result, cfg, cell_mode)
%
% cell_mode: 'ODE' or 'DDE'

    report = struct('ok', false, 'reasons', {{}});
    reasons = {};

    if nargin < 3 || isempty(cell_mode)
        cell_mode = '';
    end
    cell_mode = char(cell_mode);

    if ~isstruct(result)
        report.reasons = {'result_not_struct'};
        ok = false;
        return;
    end

    rollout_cfg = [];
    if isstruct(cfg) && isfield(cfg, 'mg_autonomous_rollout')
        rollout_cfg = cfg.mg_autonomous_rollout;
    elseif isstruct(cfg) && isfield(cfg, 'protocol_version')
        rollout_cfg = cfg;
    end
    if isempty(rollout_cfg)
        report.reasons = {'missing_mg_autonomous_rollout_cfg'};
        ok = false;
        return;
    end

    if strcmp(cell_mode, 'DDE')
        [ok, reasons] = validate_dde(result, rollout_cfg);
    elseif strcmp(cell_mode, 'ODE')
        [ok, reasons] = validate_ode(result, rollout_cfg);
    else
        ok = false;
        reasons = {sprintf('unknown_cell_mode_%s', cell_mode)};
    end

    report.ok = ok;
    report.reasons = reasons;
end

function [ok, reasons] = validate_dde(result, rollout_cfg)
    reasons = {};
    st = local_char(result, 'status', '');
    if ~strcmp(st, 'unsupported_not_computed')
        reasons{end+1} = 'dde_status_not_unsupported_not_computed'; %#ok<AGROW>
    end
    if ~strcmp(local_char(result, 'mode', ''), 'DDE')
        reasons{end+1} = 'dde_mode_not_DDE'; %#ok<AGROW>
    end
    if ~strcmp(local_char(result, 'protocol_version', ''), ...
            char(rollout_cfg.protocol_version))
        reasons{end+1} = 'protocol_version_mismatch'; %#ok<AGROW>
    end
    if ~isfield(result, 'reason') || isempty(result.reason)
        reasons{end+1} = 'missing_dde_reason'; %#ok<AGROW>
    end
    if isfield(result, 'predictions') && ~isempty(result.predictions)
        reasons{end+1} = 'dde_has_predictions'; %#ok<AGROW>
    end
    if isfield(result, 'metrics') && ~isempty(result.metrics)
        if isstruct(result.metrics)
            if has_finite_numeric_fields(result.metrics)
                reasons{end+1} = 'dde_has_finite_metrics'; %#ok<AGROW>
            end
        elseif isnumeric(result.metrics) && any(isfinite(result.metrics(:)))
            reasons{end+1} = 'dde_has_finite_metrics'; %#ok<AGROW>
        end
    end
    if ~isfield(result, 'evaluation_provenance') || ...
            ~strcmp(local_char(result.evaluation_provenance, 'mode', ''), 'unsupported')
        reasons{end+1} = 'dde_provenance_not_unsupported'; %#ok<AGROW>
    end
    ok = isempty(reasons);
end

function [ok, reasons] = validate_ode(result, rollout_cfg)
    reasons = {};
    st = local_char(result, 'status', '');
    if ~strcmp(st, 'computed')
        reasons{end+1} = sprintf('ode_status_%s', st); %#ok<AGROW>
        ok = false;
        return;
    end
    if ~strcmp(local_char(result, 'protocol_version', ''), ...
            char(rollout_cfg.protocol_version))
        reasons{end+1} = 'protocol_version_mismatch'; %#ok<AGROW>
    end
    if ~strcmp(local_char(result, 'mode', ''), 'ODE')
        reasons{end+1} = 'ode_mode_not_ODE'; %#ok<AGROW>
    end
    if ~strcmp(local_char(result, 'role', ''), char(rollout_cfg.role))
        reasons{end+1} = 'role_mismatch'; %#ok<AGROW>
    end
    if ~(isfield(result, 'forecast_horizon_steps') && ...
            result.forecast_horizon_steps == rollout_cfg.forecast_horizon_steps)
        reasons{end+1} = 'horizon_mismatch'; %#ok<AGROW>
    end
    if ~isfield(result, 'origin_schedule') || ~isstruct(result.origin_schedule)
        reasons{end+1} = 'missing_origin_schedule'; %#ok<AGROW>
        ok = false;
        return;
    end

    sch = result.origin_schedule;
    if isfield(sch, 'test_idx_first') && isfield(sch, 'test_idx_last')
        expected = reconstruct_expected_schedule(result, rollout_cfg);
        for fn = {'origin_indices', 'origin_test_relative_indices'}
            if ~isfield(sch, fn{1})
                reasons{end+1} = sprintf('missing_schedule_field_%s', fn{1}); %#ok<AGROW>
            elseif ~isequal(double(sch.(fn{1})(:)), double(expected.(fn{1})(:)))
                reasons{end+1} = sprintf('schedule_%s_mismatch', fn{1}); %#ok<AGROW>
            end
        end
        for fn = {'first_origin', 'last_origin', 'test_idx_first', 'test_idx_last', ...
                'n_test', 'forecast_horizon_steps', 'n_forecast_origins'}
            if ~isfield(sch, fn{1})
                reasons{end+1} = sprintf('missing_schedule_field_%s', fn{1}); %#ok<AGROW>
            elseif ~isequal(double(sch.(fn{1})), double(expected.(fn{1})))
                reasons{end+1} = sprintf('schedule_%s_mismatch', fn{1}); %#ok<AGROW>
            end
        end
        if ~isfield(sch, 'origin_policy') || ...
                ~strcmp(char(sch.origin_policy), char(expected.origin_policy))
            reasons{end+1} = 'schedule_origin_policy_mismatch'; %#ok<AGROW>
        end
        if ~isfield(sch, 'protocol_version') || ...
                ~strcmp(char(sch.protocol_version), char(expected.protocol_version))
            reasons{end+1} = 'schedule_protocol_version_mismatch'; %#ok<AGROW>
        end
    else
        % Legacy/minimal fixtures: require at least origin count and indices.
        if ~(isfield(sch, 'origin_indices') && ...
                numel(sch.origin_indices) == rollout_cfg.n_forecast_origins)
            reasons{end+1} = 'origin_indices_count_mismatch'; %#ok<AGROW>
        end
    end
    if ~(isfield(sch, 'n_forecast_origins') && ...
            sch.n_forecast_origins == rollout_cfg.n_forecast_origins)
        reasons{end+1} = 'origin_count_mismatch'; %#ok<AGROW>
    end
    if ~isfield(result, 'fixed_report_horizons') || ...
            ~isequal(result.fixed_report_horizons(:), rollout_cfg.fixed_report_horizons(:))
        reasons{end+1} = 'fixed_horizons_mismatch'; %#ok<AGROW>
    end
    if ~isfield(result, 'normalization_scale') || ...
            ~(isfinite(result.normalization_scale) && result.normalization_scale > sqrt(eps))
        reasons{end+1} = 'bad_normalization_scale'; %#ok<AGROW>
    end
    if ~strcmp(local_char(result, 'normalization_reference', ''), ...
            char(rollout_cfg.normalization_reference))
        reasons{end+1} = 'normalization_reference_mismatch'; %#ok<AGROW>
    end
    if ~isfield(result, 'per_origin') || isempty(result.per_origin)
        reasons{end+1} = 'missing_per_origin'; %#ok<AGROW>
    else
        H = rollout_cfg.forecast_horizon_steps;
        n_exp = rollout_cfg.n_forecast_origins;
        if numel(result.per_origin) ~= n_exp
            reasons{end+1} = 'per_origin_count_mismatch'; %#ok<AGROW>
        end
        for o = 1:min(numel(result.per_origin), n_exp)
            po = result.per_origin(o);
            if isfield(sch, 'origin_indices') && ...
                    local_get(po, 'origin_global_index', NaN) ~= sch.origin_indices(o)
                reasons{end+1} = sprintf('per_origin_%d_global_index_mismatch', o); %#ok<AGROW>
            end
            if isfield(sch, 'origin_test_relative_indices') && ...
                    local_get(po, 'origin_test_relative_index', NaN) ~= ...
                    sch.origin_test_relative_indices(o)
                reasons{end+1} = sprintf('per_origin_%d_relative_index_mismatch', o); %#ok<AGROW>
            end
            if local_get(po, 'horizon', NaN) ~= H
                reasons{end+1} = sprintf('per_origin_%d_horizon_mismatch', o); %#ok<AGROW>
            end
            if isfield(po, 'predictions') && isfield(po, 'targets')
                if any(~isfinite(po.predictions(:))) || any(~isfinite(po.targets(:)))
                    reasons{end+1} = 'nonfinite_pred_or_target'; %#ok<AGROW>
                end
            end
            vh = local_get(po, 'valid_horizon_steps', NaN);
            if ~(isfinite(vh) && vh >= 0 && vh <= H)
                reasons{end+1} = 'valid_horizon_out_of_range'; %#ok<AGROW>
            end
            if ~isfield(po, 'right_censored')
                reasons{end+1} = 'missing_right_censored'; %#ok<AGROW>
            end
        end
    end
    if ~isfield(result, 'metrics') || ~isstruct(result.metrics)
        reasons{end+1} = 'missing_metrics'; %#ok<AGROW>
    else
        m = result.metrics;
        if ~isfield(m, 'pooled_nrmse_at_fixed_horizons') || ...
                any(~isfinite(m.pooled_nrmse_at_fixed_horizons(:)))
            reasons{end+1} = 'nonfinite_fixed_horizon_metrics'; %#ok<AGROW>
        elseif numel(m.pooled_nrmse_at_fixed_horizons) ~= ...
                numel(rollout_cfg.fixed_report_horizons)
            reasons{end+1} = 'fixed_horizon_metric_count_mismatch'; %#ok<AGROW>
        end
        if ~isfield(m, 'fixed_report_horizons') || ...
                ~isequal(m.fixed_report_horizons(:), rollout_cfg.fixed_report_horizons(:))
            reasons{end+1} = 'metrics_fixed_horizons_mismatch'; %#ok<AGROW>
        end
        if ~isfield(m, 'pooled_nrmse_full_horizon') || ...
                ~isfinite(m.pooled_nrmse_full_horizon)
            reasons{end+1} = 'nonfinite_full_horizon_nrmse'; %#ok<AGROW>
        end
    end
    if ~isfield(result, 'evaluation_provenance')
        reasons{end+1} = 'missing_provenance'; %#ok<AGROW>
    else
        p = result.evaluation_provenance;
        if ~strcmp(local_char(p, 'mode', ''), 'executed')
            reasons{end+1} = 'provenance_mode_not_executed'; %#ok<AGROW>
        end
        if logical(local_get(p, 'test_target_override_used', true))
            reasons{end+1} = 'test_target_override_used'; %#ok<AGROW>
        end
        if logical(local_get(p, 'origin_override_used', true))
            reasons{end+1} = 'origin_override_used'; %#ok<AGROW>
        end
        if logical(local_get(p, 'model_refit_for_rollout', true))
            reasons{end+1} = 'model_refit_for_rollout'; %#ok<AGROW>
        end
        if logical(local_get(p, 'lambda_reselected_for_rollout', true))
            reasons{end+1} = 'lambda_reselected_for_rollout'; %#ok<AGROW>
        end
        if logical(local_get(p, 'autonomous_performance_used_for_selection', true))
            reasons{end+1} = 'autonomous_performance_used_for_selection'; %#ok<AGROW>
        end
        if ~logical(local_get(p, 'first_prediction_alignment_verified', false))
            reasons{end+1} = 'first_prediction_alignment_not_verified'; %#ok<AGROW>
        end
        if ~logical(local_get(p, 'object_state_unchanged', false))
            reasons{end+1} = 'object_state_may_have_mutated'; %#ok<AGROW>
        end
    end
    ok = isempty(reasons);
end

function expected = reconstruct_expected_schedule(result, rollout_cfg)
    sch = result.origin_schedule;
    split = struct();
    split.test_idx = (double(sch.test_idx_first):double(sch.test_idx_last))';
    expected = build_mg_autonomous_origin_schedule(split, rollout_cfg);
end

function tf = has_finite_numeric_fields(s)
    tf = false;
    fn = fieldnames(s);
    for i = 1:numel(fn)
        v = s.(fn{i});
        if isnumeric(v) && any(isfinite(v(:)))
            tf = true;
            return;
        end
    end
end

function v = local_char(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = char(string(s.(name)));
    else
        v = default;
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
