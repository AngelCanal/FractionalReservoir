function result = rollout_mg_autonomous_linear_ar(U, Y, split, schedule, rollout_cfg, one_step_ar)
% ROLLOUT_MG_AUTONOMOUS_LINEAR_AR  Recursive AR using frozen one-step ridge model.
%
%   history = [U(i), U(i-1), ..., U(i-L+1)]; never inserts true future U/Y.

    U = U(:);
    origins = schedule.origin_indices(:);
    H = double(schedule.forecast_horizon_steps);
    L = double(local_get(one_step_ar, 'lag_count', local_get(one_step_ar, 'n_lags', NaN)));
    if ~(isfinite(L) && L >= 1)
        error('rollout_mg_autonomous_linear_ar:MissingLags', ...
            'Frozen linear-AR lag count is required.');
    end
    if ~isfield(one_step_ar, 'fitted_model') || isempty(one_step_ar.fitted_model)
        error('rollout_mg_autonomous_linear_ar:MissingModel', ...
            'Frozen linear-AR fitted_model is required.');
    end
    model = one_step_ar.fitted_model;
    stored_hash = char(local_get(one_step_ar, 'fitted_model_hash', ''));
    recomputed_hash = hash_fitted_ridge_model(model);
    if ~isempty(stored_hash) && ~strcmp(stored_hash, recomputed_hash)
        error('rollout_mg_autonomous_linear_ar:ModelHashMismatch', ...
            'Frozen linear-AR fitted_model_hash does not match model payload.');
    end

    if any(origins < L)
        error('rollout_mg_autonomous_linear_ar:OriginBeforeLags', ...
            'Every origin must satisfy i >= L=%d.', L);
    end

    preds = cell(numel(origins), 1);
    teacher_forced_step1 = zeros(numel(origins), 1);
    step1_ok = true(numel(origins), 1);
    for o = 1:numel(origins)
        i = origins(o);
        history = U(i:-1:(i - L + 1)).';
        pred = zeros(H, 1);
        for k = 1:H
            pred(k) = apply_ridge_readout(model, history);
            history = [pred(k), history(1:end-1)];
        end
        preds{o} = pred;
        teacher_forced_step1(o) = apply_ridge_readout(model, U(i:-1:(i - L + 1)).');
        step1_ok(o) = abs(pred(1) - teacher_forced_step1(o)) <= ...
            1e-12 * max(1, abs(teacher_forced_step1(o)));
    end

    % Recompute full teacher-forced test predictions and verify hash
    test_idx = split.test_idx(:);
    keep = test_idx(test_idx >= L);
    n_keep = numel(keep);
    Xte = zeros(n_keep, L);
    for j = 1:n_keep
        t = keep(j);
        Xte(j, :) = U(t:-1:(t - L + 1)).';
    end
    yhat_te = apply_ridge_readout(model, Xte);
    te_hash = hash_numeric_array(yhat_te);
    stored_te = char(local_get(one_step_ar, 'test_prediction_hash', ''));
    hash_ok = isempty(stored_te) || strcmp(te_hash, stored_te);

    scored = score_mg_autonomous_forecasts(preds, Y, origins, split, rollout_cfg);
    all_finite = all(cellfun(@(p) all(isfinite(p(:))), preds)) && ...
        isfinite(scored.metrics.pooled_nrmse_full_horizon);

    result = struct();
    result.name = 'linear_autoregression';
    result.model_family = 'linear_autoregression';
    result.protocol_version = 'matched_mg_autonomous_controls_v1';
    if all_finite && all(step1_ok) && hash_ok
        result.status = 'computed';
    else
        result.status = 'failed';
    end
    result.predictions = preds;
    result.per_origin = scored.per_origin;
    result.metrics = scored.metrics;
    result.normalization_scale = scored.normalization_scale;
    result.normalization_reference = scored.normalization_reference;
    result.selected_lambda = one_step_ar.selected_lambda;
    result.lag_count = L;
    result.fitted_model_hash = recomputed_hash;
    result.test_prediction_hash = te_hash;
    result.first_step_alignment = struct( ...
        'verified', all(step1_ok), ...
        'teacher_forced_step1', teacher_forced_step1, ...
        'test_prediction_hash_verified', hash_ok);
    result.provenance = struct( ...
        'rule', 'recursive_ar_with_frozen_one_step_ridge', ...
        'model_selection_source', 'frozen_one_step_validation_selection', ...
        'autonomous_retuning', false, ...
        'lambda_reselected', false, ...
        'one_step_selection_provenance', local_get(one_step_ar, 'provenance', struct()));
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
