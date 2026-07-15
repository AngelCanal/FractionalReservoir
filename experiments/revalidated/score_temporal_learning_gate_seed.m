function seed = score_temporal_learning_gate_seed(bundle, Y_te, Y_te_shuffled, dt, target_lag_time)
% SCORE_TEMPORAL_LEARNING_GATE_SEED  Score frozen fits on test targets.
%
%   seed = score_temporal_learning_gate_seed(bundle, Y_te, Y_te_shuffled, dt, target_lag_time)
%
% Uses train/validation-frozen readouts only. Test targets may differ from the
% protocol vector for isolation tests; production scoring passes protocol targets.

    if nargin < 5
        error('score_temporal_learning_gate_seed:MissingArgs', ...
            'bundle, Y_te, Y_te_shuffled, dt, and target_lag_time are required.');
    end
    if ~isstruct(bundle) || ~isfield(bundle, 'mesn_sel')
        error('score_temporal_learning_gate_seed:InvalidBundle', ...
            'bundle must come from fit_temporal_learning_gate_seed.');
    end

    lambda_grid = bundle.lambda_grid;

    mesn_pred = apply_ridge_readout(bundle.mesn_sel.selected_model, bundle.X_te);
    mesn_metrics = compute_gate_metrics(mesn_pred, Y_te);

    cur_pred = apply_ridge_readout(bundle.cur_sel.selected_model, bundle.Xu_te);
    cur_metrics = compute_gate_metrics(cur_pred, Y_te);

    nr_pred = apply_ridge_readout(bundle.nr_sel.selected_model, bundle.Xnr_te);
    nr_metrics = compute_gate_metrics(nr_pred, Y_te);

    sh_pred = apply_ridge_readout(bundle.sh_sel.selected_model, bundle.X_te);
    sh_metrics = compute_gate_metrics(sh_pred, Y_te_shuffled);

    hist_pred = apply_ridge_readout(bundle.hist_sel.selected_model, bundle.Xh_te);
    hist_metrics = compute_gate_metrics(hist_pred, Y_te);

    seed = struct();
    seed.model_seed = bundle.model_seed;
    seed.status = 'ok';
    seed.target_lag_steps = bundle.target_lag_steps;
    seed.target_lag_time = target_lag_time;
    seed.dt = dt;
    seed.include_input = false;
    seed.feature_mode = bundle.feature_mode;
    seed.feature_dimension = bundle.feature_dimension;
    seed.train_samples_used = bundle.train_samples_used;
    seed.validation_samples_used = bundle.validation_samples_used;
    seed.test_samples_used = bundle.test_samples_used;
    seed.mesn = pack_fit(bundle.mesn_sel, mesn_metrics, mesn_pred, lambda_grid);
    seed.current_input_only_control = pack_fit(bundle.cur_sel, cur_metrics, cur_pred, lambda_grid);
    seed.no_recurrent_coupling_control = pack_fit(bundle.nr_sel, nr_metrics, nr_pred, lambda_grid);
    seed.shuffled_target_control = pack_fit(bundle.sh_sel, sh_metrics, sh_pred, lambda_grid);
    seed.exact_history_control = pack_fit(bundle.hist_sel, hist_metrics, hist_pred, lambda_grid);
    seed.delta_vs_current_nrmse = cur_metrics.nrmse - mesn_metrics.nrmse;
    seed.delta_vs_no_recurrence_nrmse = nr_metrics.nrmse - mesn_metrics.nrmse;
    seed.beats_current = seed.delta_vs_current_nrmse > 0;
    seed.beats_no_recurrence = seed.delta_vs_no_recurrence_nrmse > 0;
    seed.all_finite = all_metrics_finite(seed);
    seed.W_in_hash = bundle.W_in_hash;
    seed.W_norm = bundle.W_norm;
    seed.W_nr_norm = bundle.W_nr_norm;
end

function m = compute_gate_metrics(y_hat, y)
    y_hat = y_hat(:);
    y = y(:);
    if any(~isfinite(y_hat)) || any(~isfinite(y))
        error('score_temporal_learning_gate_seed:NonFinitePrediction', ...
            'Predictions or targets are nonfinite.');
    end
    if std(y, 1) == 0
        error('score_temporal_learning_gate_seed:ZeroTargetVariance', ...
            'Target variance is zero.');
    end
    rmse = sqrt(mean((y_hat - y).^2));
    nrmse = rmse / std(y, 1);
    ss_res = sum((y_hat - y).^2);
    ss_tot = sum((y - mean(y)).^2);
    r2 = 1 - ss_res / ss_tot;
    if std(y_hat, 1) > 0 && std(y, 1) > 0
        C = corrcoef(y_hat, y);
        pearson = C(1, 2);
    else
        pearson = NaN;
    end
    m = struct('rmse', rmse, 'nrmse', nrmse, 'r2', r2, 'pearson', pearson);
end

function pack = pack_fit(selection, metrics, y_hat, lambda_grid)
    model = selection.selected_model;
    pack = struct();
    pack.metrics = metrics;
    pack.selected_lambda = selection.selected_lambda;
    pack.selected_val_score = selection.selected_val_score;
    pack.ridge = extract_ridge_diagnostics(model);
    pack.y_hat_finite = all(isfinite(y_hat(:)));
    pack.fit_status = 'ok';
    pack.lambda_selection_table = compact_lambda_selection_table(selection);
    grid = lambda_grid(:);
    pack.selected_at_grid_boundary = isfinite(selection.selected_lambda) && ...
        (selection.selected_lambda == min(grid) || selection.selected_lambda == max(grid));
end

function d = extract_ridge_diagnostics(model)
    d = struct();
    d.solver_method = local_field(model, 'solver_method', '');
    d.lambda = model.lambda;
    d.n_samples = local_field(model, 'n_samples', NaN);
    d.n_features = model.n_features;
    d.numerical_rank = local_field(model, 'numerical_rank', NaN);
    d.rank_tolerance = local_field(model, 'rank_tolerance', NaN);
    d.singular_values = local_field(model, 'singular_values', []);
    d.largest_singular_value = local_field(model, 'largest_singular_value', NaN);
    d.smallest_retained_singular_value = ...
        local_field(model, 'smallest_retained_singular_value', NaN);
    d.raw_condition_estimate = local_field(model, 'raw_condition_estimate', NaN);
    d.regularized_condition_estimate = ...
        local_field(model, 'regularized_condition_estimate', NaN);
    d.conditioning_status = local_field(model, 'conditioning_status', '');
    d.coefficient_norm = local_field(model, 'coefficient_norm', NaN);
    d.zero_variance_mask = local_field(model, 'zero_variance_mask', ...
        local_field(model, 'constant_feature', false(1, model.n_features)));
    d.n_zero_variance_features = local_field(model, 'n_zero_variance_features', ...
        nnz(d.zero_variance_mask));
    d.feature_mean = local_field(model, 'feature_mean', model.mu);
    d.feature_scale = local_field(model, 'feature_scale', model.sigma);
    d.target_mean = local_field(model, 'target_mean', model.intercept);
    d.intercept = model.intercept;
    d.coefficients = model.coefficients;
end

function rows = compact_lambda_selection_table(selection)
    src = selection.table;
    n = numel(src);
    rows = repmat(struct( ...
        'candidate_lambda', NaN, ...
        'validation_nrmse', NaN, ...
        'status', 'rejected', ...
        'numerical_rank', NaN, ...
        'coefficient_norm', NaN, ...
        'selected_candidate', false), n, 1);
    for i = 1:n
        rows(i).candidate_lambda = src(i).lambda;
        if isfinite(src(i).val_score)
            rows(i).validation_nrmse = src(i).val_score;
        elseif ~isempty(src(i).val_nrmse)
            rows(i).validation_nrmse = mean(src(i).val_nrmse);
        else
            rows(i).validation_nrmse = NaN;
        end
        if logical(src(i).accepted)
            rows(i).status = 'accepted';
        else
            rows(i).status = 'rejected';
        end
        rows(i).numerical_rank = src(i).numerical_rank;
        rows(i).coefficient_norm = src(i).coefficient_norm;
        rows(i).selected_candidate = logical(src(i).accepted) && ...
            isfinite(src(i).lambda) && isfinite(selection.selected_lambda) && ...
            src(i).lambda == selection.selected_lambda;
    end
end

function tf = all_metrics_finite(seed)
    names = {'mesn', 'current_input_only_control', 'no_recurrent_coupling_control', ...
        'shuffled_target_control', 'exact_history_control'};
    tf = true;
    for i = 1:numel(names)
        m = seed.(names{i}).metrics;
        if ~all(isfinite([m.rmse, m.nrmse, m.r2])) || ...
                ~isfinite(seed.(names{i}).selected_lambda) || ...
                ~seed.(names{i}).y_hat_finite
            tf = false;
            return;
        end
    end
    tf = tf && isfinite(seed.delta_vs_current_nrmse) && ...
        isfinite(seed.delta_vs_no_recurrence_nrmse);
end

function v = local_field(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
