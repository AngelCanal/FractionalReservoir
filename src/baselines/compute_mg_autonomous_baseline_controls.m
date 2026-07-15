function controls = compute_mg_autonomous_baseline_controls(task, one_step_baselines, rollout_cfg, base_seed, provenance_mode, options)
% COMPUTE_MG_AUTONOMOUS_BASELINE_CONTROLS  Seed-level matched autonomous controls.
%
%   controls = compute_mg_autonomous_baseline_controls(task, one_step_baselines, ...
%       rollout_cfg, base_seed, provenance_mode)
%
% Uses frozen one-step models only. Never retunes from autonomous performance.

    if nargin < 5 || isempty(provenance_mode)
        provenance_mode = 'executed_shared_seed_bundle';
    end
    if nargin < 6 || isempty(options)
        options = struct();
    end

    failure_reasons = {};
    U = task.U;
    Y = task.Y;
    split = task.split;
    if isfield(task, 'washout_steps') && ~isfield(split, 'washout_steps')
        split.washout_steps = task.washout_steps;
    end

    schedule = build_mg_autonomous_origin_schedule(split, rollout_cfg);
    origin_identity = struct( ...
        'origin_indices', schedule.origin_indices(:), ...
        'origin_test_relative_indices', schedule.origin_test_relative_indices(:), ...
        'first_origin', schedule.first_origin, ...
        'last_origin', schedule.last_origin, ...
        'H', schedule.forecast_horizon_steps, ...
        'n_origins', schedule.n_forecast_origins, ...
        'protocol_version', schedule.protocol_version);
    origin_schedule_hash = canonical_sha256(origin_identity);

    lar = resolve_ar(one_step_baselines);
    ce = one_step_baselines.conventional_leaky_esn;

    persistence = struct('status', 'failed');
    linear_ar = struct('status', 'failed');
    conventional = struct('status', 'failed');
    try
        persistence = rollout_mg_autonomous_persistence(U, Y, split, schedule, rollout_cfg);
    catch ME
        failure_reasons{end+1} = sprintf('persistence:%s', ME.message); %#ok<AGROW>
        persistence.error_id = ME.identifier;
        persistence.status = 'failed';
    end
    try
        linear_ar = rollout_mg_autonomous_linear_ar(U, Y, split, schedule, rollout_cfg, lar);
    catch ME
        failure_reasons{end+1} = sprintf('linear_autoregression:%s', ME.message); %#ok<AGROW>
        linear_ar.error_id = ME.identifier;
        linear_ar.status = 'failed';
    end
    try
        conventional = rollout_mg_autonomous_conventional_esn( ...
            U, Y, split, schedule, rollout_cfg, ce);
    catch ME
        failure_reasons{end+1} = sprintf('conventional_leaky_esn:%s', ME.message); %#ok<AGROW>
        conventional.error_id = ME.identifier;
        conventional.status = 'failed';
    end

    dale = struct();
    dale.name = 'dale_mesn_control';
    dale.status = 'pending_paired_aggregation';
    dale.model_family = 'dale_mesn_control';
    dale.protocol_version = 'matched_mg_autonomous_controls_v1';
    dale.role = 'paired_cell_reference';
    dale.metrics = struct();
    dale.predictions = [];
    dale.provenance = struct( ...
        'note', 'Feature-specific Dale reference resolved in aggregation.', ...
        'not_computed_here', true);

    sigma_values = [];
    for c = {persistence, linear_ar, conventional}
        if isfield(c{1}, 'normalization_scale') && isfinite(c{1}.normalization_scale)
            sigma_values(end+1) = c{1}.normalization_scale; %#ok<AGROW>
        end
    end
    if isempty(sigma_values) || any(abs(sigma_values - sigma_values(1)) > 1e-12 * max(1, abs(sigma_values(1))))
        failure_reasons{end+1} = 'normalization_scale_mismatch_across_controls';
    end
    if ~isempty(sigma_values)
        normalization_scale = sigma_values(1);
    else
        normalization_scale = NaN;
    end

    required_ok = strcmp(local_get(persistence, 'status', ''), 'computed') && ...
        strcmp(local_get(linear_ar, 'status', ''), 'computed') && ...
        strcmp(local_get(conventional, 'status', ''), 'computed') && ...
        logical(local_get(persistence.first_step_alignment, 'verified', false)) && ...
        logical(local_get(linear_ar.first_step_alignment, 'verified', false)) && ...
        logical(local_get(conventional.first_step_alignment, 'verified', false));

    if ~required_ok
        if ~strcmp(local_get(persistence, 'status', ''), 'computed')
            failure_reasons{end+1} = 'persistence_not_computed'; %#ok<AGROW>
        end
        if ~strcmp(local_get(linear_ar, 'status', ''), 'computed')
            failure_reasons{end+1} = 'linear_autoregression_not_computed'; %#ok<AGROW>
        end
        if ~strcmp(local_get(conventional, 'status', ''), 'computed')
            failure_reasons{end+1} = 'conventional_leaky_esn_not_computed'; %#ok<AGROW>
        end
    end

    ac_cfg = [];
    if isfield(options, 'autonomous_controls_config')
        ac_cfg = options.autonomous_controls_config;
    end

    content_identity = struct();
    content_identity.protocol_version = 'matched_mg_autonomous_controls_v1';
    content_identity.origin_schedule_hash = origin_schedule_hash;
    content_identity.normalization_scale = normalization_scale;
    content_identity.normalization_reference = char(rollout_cfg.normalization_reference);
    content_identity.persistence_metrics_hash = hash_control_metrics(persistence);
    content_identity.linear_ar_metrics_hash = hash_control_metrics(linear_ar);
    content_identity.conventional_metrics_hash = hash_control_metrics(conventional);
    content_identity.linear_ar_fitted_model_hash = char(local_get(linear_ar, 'fitted_model_hash', ''));
    content_identity.conventional_fitted_model_hash = char(local_get(conventional, 'fitted_model_hash', ''));
    content_identity.persistence_pred_hash = hash_pred_cells(local_get(persistence, 'predictions', {}));
    content_identity.linear_ar_pred_hash = hash_pred_cells(local_get(linear_ar, 'predictions', {}));
    content_identity.conventional_pred_hash = hash_pred_cells(local_get(conventional, 'predictions', {}));
    content_hash = canonical_sha256(content_identity);

    if required_ok && isempty(failure_reasons)
        status = 'computed';
    else
        status = 'failed_required_autonomous_baseline';
    end

    controls = struct();
    controls.protocol_version = 'matched_mg_autonomous_controls_v1';
    controls.status = status;
    controls.base_seed = base_seed;
    controls.task_seed = local_get(task, 'seed', NaN);
    controls.task_data_hash = char(local_get(task, 'task_data_hash', ''));
    controls.split_hash = char(local_get(task, 'split_hash', ''));
    controls.origin_schedule = schedule;
    controls.origin_schedule_hash = origin_schedule_hash;
    controls.normalization_scale = normalization_scale;
    controls.normalization_reference = char(rollout_cfg.normalization_reference);
    controls.rollout_protocol_version = char(rollout_cfg.protocol_version);
    controls.persistence = persistence;
    controls.linear_autoregression = linear_ar;
    controls.conventional_leaky_esn = conventional;
    controls.dale_mesn_control = dale;
    if ~isempty(ac_cfg)
        controls.policy = ac_cfg;
    end
    controls.evaluation_provenance = struct( ...
        'mode', char(provenance_mode), ...
        'model_selection_source', 'frozen_one_step_validation_selection', ...
        'test_target_override_used', false, ...
        'origin_override_used', false, ...
        'model_refit_for_rollout', false, ...
        'lambda_reselected_for_rollout', false, ...
        'candidate_reselected_for_rollout', false, ...
        'autonomous_performance_used_for_selection', false, ...
        'publication_shared_bundle', strcmp(char(provenance_mode), 'executed_shared_seed_bundle'));
    controls.failure_reasons = unique(failure_reasons(:), 'stable');
    controls.content_hash = content_hash;
    controls.content_identity = content_identity;
end

function lar = resolve_ar(baselines)
    if isfield(baselines, 'linear_autoregression')
        lar = baselines.linear_autoregression;
    elseif isfield(baselines, 'linear_ar')
        lar = baselines.linear_ar;
    else
        error('compute_mg_autonomous_baseline_controls:MissingAR', ...
            'one_step_baselines.linear_autoregression is required.');
    end
end

function h = hash_control_metrics(ctrl)
    if ~isstruct(ctrl) || ~isfield(ctrl, 'metrics') || ~isstruct(ctrl.metrics)
        h = '';
        return;
    end
    m = ctrl.metrics;
    id = struct();
    id.pooled_full = local_get(m, 'pooled_nrmse_full_horizon', NaN);
    id.pooled_fixed = local_get(m, 'pooled_nrmse_at_fixed_horizons', []);
    id.median_vh = local_get(m, 'median_valid_horizon', NaN);
    id.frac_cens = local_get(m, 'fraction_right_censored', NaN);
    if isnumeric(id.pooled_fixed)
        id.pooled_fixed_hash = hash_numeric_array(id.pooled_fixed);
        id = rmfield(id, 'pooled_fixed');
    end
    h = canonical_sha256(id);
end

function h = hash_pred_cells(preds)
    if isempty(preds)
        h = '';
        return;
    end
    if ~iscell(preds)
        h = hash_numeric_array(preds);
        return;
    end
    parts = cell(numel(preds), 1);
    for i = 1:numel(preds)
        parts{i} = hash_numeric_array(preds{i}(:));
    end
    h = canonical_sha256(struct('parts', {parts}));
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
