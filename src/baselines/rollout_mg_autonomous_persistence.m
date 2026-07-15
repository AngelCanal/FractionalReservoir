function result = rollout_mg_autonomous_persistence(U, Y, split, schedule, rollout_cfg)
% ROLLOUT_MG_AUTONOMOUS_PERSISTENCE  Autonomous constant last-observation forecasts.
%
%   For origin i: prediction(k) = U(i) for k=1...H (never U(i+k-1)).

    U = U(:);
    origins = schedule.origin_indices(:);
    H = double(schedule.forecast_horizon_steps);
    preds = cell(numel(origins), 1);
    step1_ok = true(numel(origins), 1);
    for o = 1:numel(origins)
        i = origins(o);
        last_obs = U(i);
        pred = repmat(last_obs, H, 1);
        preds{o} = pred;
        step1_ok(o) = pred(1) == last_obs;
    end

    scored = score_mg_autonomous_forecasts(preds, Y, origins, split, rollout_cfg);

    all_finite = all(cellfun(@(p) all(isfinite(p(:))), preds)) && ...
        isfinite(scored.metrics.pooled_nrmse_full_horizon);

    result = struct();
    result.name = 'persistence';
    result.model_family = 'persistence';
    result.protocol_version = 'matched_mg_autonomous_controls_v1';
    if all_finite && all(step1_ok)
        result.status = 'computed';
    else
        result.status = 'failed';
    end
    result.predictions = preds;
    result.per_origin = scored.per_origin;
    result.metrics = scored.metrics;
    result.normalization_scale = scored.normalization_scale;
    result.normalization_reference = scored.normalization_reference;
    result.selected_lambda = NaN;
    result.fitted_model_hash = '';
    result.first_step_alignment = struct( ...
        'verified', all(step1_ok), ...
        'rule', 'prediction(1)==U(origin)');
    result.provenance = struct( ...
        'rule', 'recursive_constant_last_observation', ...
        'autonomous_retuning', false, ...
        'trainable_parameters', false, ...
        'selected_lambda', NaN);
end
