function controls_out = attach_shared_mg_autonomous_controls_for_cell( ...
        shared_controls, model_rollout, feature_mode, bundle_id, rollout_cfg, bb)
% ATTACH_SHARED_MG_AUTONOMOUS_CONTROLS_FOR_CELL  Compact controls + cell comparisons.
%
% ODE: attach computed controls with descriptive MESN-vs-control comparisons.
% DDE: applicability only; no model-vs-control numerical comparisons.

    if nargin < 6 || isempty(bb)
        bb = build_matched_task_baselines_config(struct('base', struct('n', 1)));
    end
    dale_key = dale_mesn_control_reference_key(feature_mode, bb.dale_mesn_control_keys);

    mode = '';
    if isstruct(model_rollout) && isfield(model_rollout, 'mode')
        mode = char(model_rollout.mode);
    end

    controls_out = struct();
    controls_out.protocol_version = 'matched_mg_autonomous_controls_v1';
    controls_out.bundle_id = bundle_id;
    controls_out.content_hash = char(local_get(shared_controls, 'content_hash', ''));
    controls_out.origin_schedule_hash = char(local_get(shared_controls, 'origin_schedule_hash', ''));
    controls_out.normalization_scale = local_get(shared_controls, 'normalization_scale', NaN);
    controls_out.normalization_reference = char(local_get(shared_controls, ...
        'normalization_reference', ''));
    controls_out.status = char(local_get(shared_controls, 'status', ''));
    controls_out.evaluation_provenance = local_get(shared_controls, 'evaluation_provenance', struct());

    if strcmp(mode, 'DDE')
        controls_out.applicability = 'not_applicable_dde_model_rollout_unsupported';
        controls_out.persistence = compact_control_shell('persistence');
        controls_out.linear_autoregression = compact_control_shell('linear_autoregression');
        controls_out.conventional_leaky_esn = compact_control_shell('conventional_leaky_esn');
        controls_out.dale_mesn_control = pending_dale(dale_key);
        controls_out.comparisons_attached = false;
        return;
    end

    controls_out.applicability = 'ode_cell_comparison_required';
    model_metrics = local_get(model_rollout, 'metrics', struct());

    for name = {'persistence', 'linear_autoregression', 'conventional_leaky_esn'}
        nm = name{1};
        src = shared_controls.(nm);
        slim = compact_computed_control(src);
        slim.comparison = mg_autonomous_control_comparison(model_metrics, src.metrics);
        controls_out.(nm) = slim;
    end
    controls_out.dale_mesn_control = pending_dale(dale_key);
    controls_out.comparisons_attached = true;
    controls_out.fixed_report_horizons = rollout_cfg.fixed_report_horizons(:);
end

function dale = pending_dale(dale_key)
    dale = struct();
    dale.name = 'dale_mesn_control';
    dale.status = 'pending_paired_aggregation';
    dale.model_family = 'dale_mesn_control';
    dale.protocol_version = 'matched_mg_autonomous_controls_v1';
    dale.dale_mesn_control_reference = dale_key;
    dale.metrics = struct();
    dale.comparison = struct( ...
        'status', 'pending_paired_aggregation', ...
        'dale_mesn_control_reference', dale_key, ...
        'numerical_superiority_claim', false);
    dale.provenance = struct( ...
        'dale_mesn_control_reference', dale_key, ...
        'not_conventional_esn', true);
end

function slim = compact_control_shell(name)
    slim = struct();
    slim.name = name;
    slim.status = 'not_applicable_dde_model_rollout_unsupported';
    slim.model_family = name;
    slim.protocol_version = 'matched_mg_autonomous_controls_v1';
    slim.metrics = struct();
    slim.comparison = struct();
end

function slim = compact_computed_control(src)
    slim = struct();
    keep = {'name', 'status', 'model_family', 'protocol_version', ...
        'selected_lambda', 'fitted_model_hash', 'lag_count', ...
        'selected_candidate_index', 'spectral_radius', 'achieved_spectral_radius', ...
        'leak_rate', 'input_scaling', 'reservoir_seed', ...
        'normalization_scale', 'normalization_reference', ...
        'metrics', 'first_step_alignment', 'provenance', 'test_prediction_hash', ...
        'finite_state_trajectory'};
    for i = 1:numel(keep)
        if isfield(src, keep{i})
            slim.(keep{i}) = src.(keep{i});
        end
    end
    % Explicitly omit predictions, per_origin full arrays, fitted models, W_res/W_in
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
