function result = rollout_mg_autonomous_conventional_esn(U, Y, split, schedule, rollout_cfg, one_step_ce)
% ROLLOUT_MG_AUTONOMOUS_CONVENTIONAL_ESN  Autonomous recursion of frozen leaky ESN.
%
%   Teacher-forced trajectory once; each origin seeds from h(i); step 1 = readout(h(i)).

    U = U(:, :);
    origins = schedule.origin_indices(:);
    H = double(schedule.forecast_horizon_steps);
    if ~isfield(one_step_ce, 'fitted_model') || isempty(one_step_ce.fitted_model)
        error('rollout_mg_autonomous_conventional_esn:MissingModel', ...
            'Frozen conventional ESN fitted_model is required.');
    end
    fitted = one_step_ce.fitted_model;
    stored_hash = char(local_get(one_step_ce, 'fitted_model_hash', ...
        local_get(fitted, 'fitted_model_hash', '')));
    recomputed_hash = hash_conventional_esn_fitted_model(fitted);
    if ~isempty(stored_hash) && ~strcmp(stored_hash, recomputed_hash)
        error('rollout_mg_autonomous_conventional_esn:ModelHashMismatch', ...
            'Frozen conventional ESN fitted_model_hash does not match payload.');
    end

    Wres = fitted.W_res;
    Win = fitted.W_in;
    alpha = fitted.leak_rate;
    readout = fitted.readout_model;
    [H_tf, run_info] = run_conventional_leaky_esn(U, Wres, Win, alpha, struct( ...
        'initial_state', fitted.zero_initial_state));
    if ~run_info.finite_state_trajectory
        error('rollout_mg_autonomous_conventional_esn:NonfiniteState', ...
            'Teacher-forced conventional ESN trajectory is nonfinite.');
    end

    % Full teacher-forced test predictions for hash alignment
    test_idx = split.test_idx(:);
    yhat_te = apply_ridge_readout(readout, H_tf(test_idx, :));
    te_hash = hash_numeric_array(yhat_te);
    stored_te = char(local_get(one_step_ce, 'test_prediction_hash', ''));
    hash_ok = isempty(stored_te) || strcmp(te_hash, stored_te);

    preds = cell(numel(origins), 1);
    step1_ok = true(numel(origins), 1);
    teacher_forced_step1 = zeros(numel(origins), 1);
    n = size(Wres, 1);
    for o = 1:numel(origins)
        i = origins(o);
        h = H_tf(i, :).';
        pred = zeros(H, 1);
        pred(1) = apply_ridge_readout(readout, h.');
        teacher_forced_step1(o) = pred(1);
        for k = 2:H
            pre = Wres * h + Win * pred(k - 1);
            h = (1 - alpha) * h + alpha * tanh(pre);
            pred(k) = apply_ridge_readout(readout, h.');
        end
        preds{o} = pred;
        frozen_one_step = apply_ridge_readout(readout, H_tf(i, :));
        step1_ok(o) = abs(pred(1) - frozen_one_step) <= ...
            1e-12 * max(1, abs(frozen_one_step));
        if numel(h) ~= n
            error('rollout_mg_autonomous_conventional_esn:StateSize', ...
                'State dimension mismatch at origin %d.', i);
        end
    end

    scored = score_mg_autonomous_forecasts(preds, Y, origins, split, rollout_cfg);
    all_finite = all(cellfun(@(p) all(isfinite(p(:))), preds)) && ...
        isfinite(scored.metrics.pooled_nrmse_full_horizon);

    result = struct();
    result.name = 'conventional_leaky_esn';
    result.model_family = 'conventional_leaky_esn';
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
    result.selected_lambda = one_step_ce.selected_lambda;
    result.selected_candidate_index = fitted.selected_candidate_index;
    result.spectral_radius = fitted.spectral_radius;
    result.achieved_spectral_radius = local_get(fitted, 'achieved_spectral_radius', ...
        local_get(one_step_ce, 'achieved_spectral_radius', NaN));
    result.leak_rate = fitted.leak_rate;
    result.input_scaling = fitted.input_scaling;
    result.reservoir_seed = fitted.reservoir_seed;
    result.fitted_model_hash = recomputed_hash;
    result.test_prediction_hash = te_hash;
    result.finite_state_trajectory = run_info.finite_state_trajectory;
    result.first_step_alignment = struct( ...
        'verified', all(step1_ok), ...
        'teacher_forced_step1', teacher_forced_step1, ...
        'test_prediction_hash_verified', hash_ok);
    result.provenance = struct( ...
        'rule', 'teacher_forced_state_then_recursive_predicted_input', ...
        'model_selection_source', 'frozen_one_step_validation_selection', ...
        'autonomous_retuning', false, ...
        'lambda_reselected', false, ...
        'candidate_reselected', false, ...
        'teacher_forced_once_per_seed', true);
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
