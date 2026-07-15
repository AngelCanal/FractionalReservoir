function [ok, report] = validate_mg_autonomous_baseline_controls(controls, expectations)
% VALIDATE_MG_AUTONOMOUS_BASELINE_CONTROLS  Fail-closed matched autonomous controls.
%
%   [ok, report] = validate_mg_autonomous_baseline_controls(controls, expectations)
%
% expectations fields (production ODE comparison):
%   base_seed, task_seed, task_data_hash, split_hash, bundle_id,
%   rollout_cfg, one_step_baselines, feature_mode, dale_keys,
%   model_metrics (optional, for comparison arithmetic),
%   require_production_provenance (default true),
%   cell_mode ('ODE'|'DDE')

    report = struct('ok', false, 'reasons', {{}});
    reasons = {};
    if nargin < 2 || isempty(expectations)
        expectations = struct();
    end
    cell_mode = char(local_get(expectations, 'cell_mode', 'ODE'));

    if ~isstruct(controls)
        report.reasons = {'controls_not_struct'};
        ok = false;
        return;
    end

    if strcmp(cell_mode, 'DDE')
        [ok, reasons] = validate_dde_controls(controls);
        report.ok = ok;
        report.reasons = reasons;
        return;
    end

    if ~strcmp(char(local_get(controls, 'protocol_version', '')), ...
            'matched_mg_autonomous_controls_v1')
        reasons{end+1} = 'protocol_version_mismatch';
    end
    if ~strcmp(char(local_get(controls, 'status', '')), 'computed')
        reasons{end+1} = 'status_not_computed';
    end
    if isfield(expectations, 'base_seed') && ...
            local_get(controls, 'base_seed', NaN) ~= expectations.base_seed
        reasons{end+1} = 'base_seed_mismatch';
    end
    if isfield(expectations, 'task_seed') && ...
            local_get(controls, 'task_seed', NaN) ~= expectations.task_seed
        reasons{end+1} = 'task_seed_mismatch';
    end
    if isfield(expectations, 'task_data_hash') && ...
            ~strcmp(char(local_get(controls, 'task_data_hash', '')), ...
            char(expectations.task_data_hash))
        reasons{end+1} = 'task_data_hash_mismatch';
    end
    if isfield(expectations, 'split_hash') && ...
            ~strcmp(char(local_get(controls, 'split_hash', '')), ...
            char(expectations.split_hash))
        reasons{end+1} = 'split_hash_mismatch';
    end
    if isfield(expectations, 'bundle_id') && ...
            ~strcmp(char(local_get(controls, 'bundle_id', ...
            local_get(local_get(controls, 'evaluation_provenance', struct()), ...
            'bundle_id', ''))), char(expectations.bundle_id)) && ...
            ~(isfield(controls, 'bundle_id') && ...
            strcmp(char(controls.bundle_id), char(expectations.bundle_id)))
        % attached cell form uses controls.bundle_id
        if isfield(controls, 'bundle_id')
            if ~strcmp(char(controls.bundle_id), char(expectations.bundle_id))
                reasons{end+1} = 'bundle_id_mismatch';
            end
        elseif isfield(expectations, 'require_bundle_id') && expectations.require_bundle_id
            reasons{end+1} = 'bundle_id_mismatch';
        end
    end

    if isfield(expectations, 'rollout_cfg')
        rollout_cfg = expectations.rollout_cfg;
        if isfield(controls, 'origin_schedule')
            [vok, vrep] = validate_mg_autonomous_rollout_result(struct( ...
                'status', 'computed', ...
                'protocol_version', rollout_cfg.protocol_version, ...
                'mode', 'ODE', ...
                'role', rollout_cfg.role, ...
                'forecast_horizon_steps', rollout_cfg.forecast_horizon_steps, ...
                'origin_schedule', controls.origin_schedule, ...
                'fixed_report_horizons', rollout_cfg.fixed_report_horizons, ...
                'normalization_scale', controls.normalization_scale, ...
                'normalization_reference', controls.normalization_reference, ...
                'per_origin', build_dummy_per_origin(controls), ...
                'metrics', build_dummy_metrics(controls, rollout_cfg), ...
                'evaluation_provenance', struct( ...
                    'mode', 'executed', ...
                    'test_target_override_used', false, ...
                    'origin_override_used', false, ...
                    'model_refit_for_rollout', false, ...
                    'lambda_reselected_for_rollout', false, ...
                    'autonomous_performance_used_for_selection', false, ...
                    'first_prediction_alignment_verified', true, ...
                    'object_state_unchanged', true)), ...
                struct('mg_autonomous_rollout', rollout_cfg), 'ODE');
            if ~vok
                % Origin schedule subset only — filter irrelevant reasons
                sch_reasons = vrep.reasons;
                keep = {};
                for i = 1:numel(sch_reasons)
                    if startsWith(sch_reasons{i}, 'schedule_') || ...
                            strcmp(sch_reasons{i}, 'origin_count_mismatch') || ...
                            strcmp(sch_reasons{i}, 'horizon_mismatch') || ...
                            strcmp(sch_reasons{i}, 'fixed_horizons_mismatch') || ...
                            strcmp(sch_reasons{i}, 'metrics_fixed_horizons_mismatch') || ...
                            strcmp(sch_reasons{i}, 'per_origin_count_mismatch')
                        keep{end+1} = sch_reasons{i}; %#ok<AGROW>
                    end
                end
                % Prefer direct schedule field checks below when shared controls lack per_origin
            end
        end
        if isfield(controls, 'origin_schedule')
            expected_sch = reconstruct_schedule(controls, rollout_cfg);
            if ~isequal(double(controls.origin_schedule.origin_indices(:)), ...
                    double(expected_sch.origin_indices(:)))
                reasons{end+1} = 'origin_schedule_mismatch';
            end
        end
        exp_hash = '';
        if isfield(controls, 'origin_schedule_hash')
            if ~isfield(controls, 'origin_schedule') || ~isstruct(controls.origin_schedule)
                reasons{end+1} = 'origin_schedule_missing'; %#ok<AGROW>
            else
                id = struct( ...
                    'origin_indices', controls.origin_schedule.origin_indices(:), ...
                    'origin_test_relative_indices', ...
                        controls.origin_schedule.origin_test_relative_indices(:), ...
                    'first_origin', controls.origin_schedule.first_origin, ...
                    'last_origin', controls.origin_schedule.last_origin, ...
                    'H', controls.origin_schedule.forecast_horizon_steps, ...
                    'n_origins', controls.origin_schedule.n_forecast_origins, ...
                    'protocol_version', controls.origin_schedule.protocol_version);
                exp_hash = canonical_sha256(id);
                if ~strcmp(char(controls.origin_schedule_hash), exp_hash)
                    reasons{end+1} = 'origin_schedule_hash_mismatch'; %#ok<AGROW>
                end
            end
        end
    end

    for nm = {'persistence', 'linear_autoregression', 'conventional_leaky_esn'}
        c = local_get(controls, nm{1}, struct());
        if ~strcmp(char(local_get(c, 'status', '')), 'computed')
            reasons{end+1} = sprintf('%s_not_computed', nm{1}); %#ok<AGROW>
        end
        m = local_get(c, 'metrics', struct());
        if ~isfinite(local_get(m, 'pooled_nrmse_full_horizon', NaN))
            reasons{end+1} = sprintf('%s_nonfinite_metrics', nm{1}); %#ok<AGROW>
        end
        fa = local_get(c, 'first_step_alignment', struct());
        if isstruct(fa) && isfield(fa, 'verified') && ~logical(fa.verified)
            reasons{end+1} = sprintf('%s_first_step_alignment_failed', nm{1}); %#ok<AGROW>
        end
    end

    if isfield(expectations, 'one_step_baselines')
        os = expectations.one_step_baselines;
        lar = resolve_ar(os);
        ce = os.conventional_leaky_esn;
        if isfield(controls, 'linear_autoregression')
            if ~strcmp(char(local_get(controls.linear_autoregression, 'fitted_model_hash', '')), ...
                    char(local_get(lar, 'fitted_model_hash', '')))
                reasons{end+1} = 'linear_ar_fitted_model_hash_mismatch';
            end
        end
        if isfield(controls, 'conventional_leaky_esn')
            if ~strcmp(char(local_get(controls.conventional_leaky_esn, 'fitted_model_hash', '')), ...
                    char(local_get(ce, 'fitted_model_hash', '')))
                reasons{end+1} = 'conventional_fitted_model_hash_mismatch';
            end
            if local_get(controls.conventional_leaky_esn, 'selected_candidate_index', NaN) ~= ...
                    local_get(ce, 'selected_candidate_index', NaN)
                reasons{end+1} = 'conventional_candidate_index_mismatch';
            end
        end
    end

    prov = local_get(controls, 'evaluation_provenance', struct());
    require_prod = logical(local_get(expectations, 'require_production_provenance', true));
    if require_prod
        if ~strcmp(char(local_get(prov, 'mode', '')), 'executed_shared_seed_bundle')
            reasons{end+1} = 'provenance_not_shared_seed_bundle';
        end
        if logical(local_get(prov, 'model_refit_for_rollout', true))
            reasons{end+1} = 'model_refit_for_rollout';
        end
        if logical(local_get(prov, 'lambda_reselected_for_rollout', true))
            reasons{end+1} = 'lambda_reselected_for_rollout';
        end
        if logical(local_get(prov, 'candidate_reselected_for_rollout', true))
            reasons{end+1} = 'candidate_reselected_for_rollout';
        end
        if logical(local_get(prov, 'autonomous_performance_used_for_selection', true))
            reasons{end+1} = 'autonomous_performance_used_for_selection';
        end
    end

    % Comparison arithmetic when model metrics present
    if isfield(expectations, 'model_metrics') && ...
            logical(local_get(controls, 'comparisons_attached', true))
        mm = expectations.model_metrics;
        for nm = {'persistence', 'linear_autoregression', 'conventional_leaky_esn'}
            c = controls.(nm{1});
            if ~isfield(c, 'comparison')
                reasons{end+1} = sprintf('%s_missing_comparison', nm{1}); %#ok<AGROW>
                continue;
            end
            exp_cmp = mg_autonomous_control_comparison(mm, c.metrics);
            got = c.comparison;
            if abs(local_get(got, 'improvement_nrmse_full_horizon', NaN) - ...
                    exp_cmp.improvement_nrmse_full_horizon) > 1e-12
                reasons{end+1} = sprintf('%s_improvement_arithmetic_mismatch', nm{1}); %#ok<AGROW>
            end
            if strcmp(exp_cmp.ratio_status_full_horizon, 'defined')
                if abs(local_get(got, 'ratio_nrmse_full_horizon', NaN) - ...
                        exp_cmp.ratio_nrmse_full_horizon) > 1e-12
                    reasons{end+1} = sprintf('%s_ratio_arithmetic_mismatch', nm{1}); %#ok<AGROW>
                end
            else
                if ~isnan(local_get(got, 'ratio_nrmse_full_horizon', 0)) || ...
                        ~strcmp(char(local_get(got, 'ratio_status_full_horizon', '')), ...
                        'undefined_nonfinite_denominator')
                    reasons{end+1} = sprintf('%s_ratio_undefined_status_mismatch', nm{1}); %#ok<AGROW>
                end
            end
            if abs(local_get(got, 'difference_restricted_valid_horizon', NaN) - ...
                    exp_cmp.difference_restricted_valid_horizon) > 1e-12
                reasons{end+1} = sprintf('%s_restricted_vh_diff_mismatch', nm{1}); %#ok<AGROW>
            end
        end
    end

    % Dale pending, feature-specific, no superiority
    if isfield(controls, 'dale_mesn_control')
        dale = controls.dale_mesn_control;
        if ~strcmp(char(local_get(dale, 'status', '')), 'pending_paired_aggregation')
            reasons{end+1} = 'dale_status_not_pending';
        end
        if isfield(expectations, 'feature_mode') && isfield(expectations, 'dale_keys')
            expect_key = dale_mesn_control_reference_key( ...
                expectations.feature_mode, expectations.dale_keys);
            got_key = char(local_get(dale, 'dale_mesn_control_reference', ''));
            if ~strcmp(got_key, expect_key)
                reasons{end+1} = 'dale_reference_key_mismatch';
            end
        end
        if isfield(dale, 'comparison')
            cmp = dale.comparison;
            if isfield(cmp, 'improvement_nrmse') || isfield(cmp, 'improvement_nrmse_full_horizon')
                reasons{end+1} = 'dale_has_numerical_superiority_metrics';
            end
            if logical(local_get(cmp, 'numerical_superiority_claim', false))
                reasons{end+1} = 'dale_numerical_superiority_claim';
            end
        end
    else
        reasons{end+1} = 'missing_dale_mesn_control';
    end

    report.reasons = unique(reasons(:), 'stable');
    report.ok = isempty(report.reasons);
    ok = report.ok;
end

function [ok, reasons] = validate_dde_controls(controls)
    reasons = {};
    app = char(local_get(controls, 'applicability', ''));
    if ~strcmp(app, 'not_applicable_dde_model_rollout_unsupported')
        reasons{end+1} = 'dde_applicability_mismatch';
    end
    for nm = {'persistence', 'linear_autoregression', 'conventional_leaky_esn'}
        if isfield(controls, nm{1})
            c = controls.(nm{1});
            if isfield(c, 'comparison') && isstruct(c.comparison) && ...
                    (isfield(c.comparison, 'improvement_nrmse_full_horizon') || ...
                    isfield(c.comparison, 'improvement_nrmse'))
                reasons{end+1} = sprintf('dde_has_computed_comparison_%s', nm{1}); %#ok<AGROW>
            end
            m = local_get(c, 'metrics', struct());
            if isstruct(m) && isfield(m, 'pooled_nrmse_full_horizon') && ...
                    isfinite(m.pooled_nrmse_full_horizon)
                reasons{end+1} = sprintf('dde_has_finite_control_metric_%s', nm{1}); %#ok<AGROW>
            end
        end
    end
    ok = isempty(reasons);
end

function sch = reconstruct_schedule(controls, rollout_cfg)
    s = controls.origin_schedule;
    split = struct('test_idx', (double(s.test_idx_first):double(s.test_idx_last))');
    sch = build_mg_autonomous_origin_schedule(split, rollout_cfg);
end

function per = build_dummy_per_origin(controls)
    n = controls.origin_schedule.n_forecast_origins;
    H = controls.origin_schedule.forecast_horizon_steps;
    per = repmat(struct( ...
        'origin_global_index', NaN, ...
        'origin_test_relative_index', NaN, ...
        'horizon', H, ...
        'valid_horizon_steps', 0, ...
        'right_censored', false), n, 1);
    for o = 1:n
        per(o).origin_global_index = controls.origin_schedule.origin_indices(o);
        per(o).origin_test_relative_index = ...
            controls.origin_schedule.origin_test_relative_indices(o);
    end
end

function m = build_dummy_metrics(controls, rollout_cfg)
    m = struct();
    m.pooled_nrmse_at_fixed_horizons = ones(numel(rollout_cfg.fixed_report_horizons), 1);
    m.fixed_report_horizons = rollout_cfg.fixed_report_horizons(:);
    m.pooled_nrmse_full_horizon = 1;
end

function lar = resolve_ar(baselines)
    if isfield(baselines, 'linear_autoregression')
        lar = baselines.linear_autoregression;
    else
        lar = baselines.linear_ar;
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end

function tf = startsWith(str, prefix)
    tf = strncmp(str, prefix, numel(prefix));
end
