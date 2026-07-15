function scored = score_mg_autonomous_forecasts(predictions, Y, origins, split, rollout_cfg, options)
% SCORE_MG_AUTONOMOUS_FORECASTS  Score MG autonomous forecasts against Y.
%
%   scored = score_mg_autonomous_forecasts(predictions, Y, origins, split, rollout_cfg)
%   scored = score_mg_autonomous_forecasts(..., options)
%
% Production always scores against the fingerprinted task Y. Test fixtures may
% pass options.Y_scoring_override to the pure helper only (never into generation).
%
% Target alignment: for origin i and step k, score Y(i+k-1).

    if nargin < 6 || isempty(options)
        options = struct();
    end

    H = double(rollout_cfg.forecast_horizon_steps);
    thr_primary = double(rollout_cfg.primary_threshold);
    thr_sens = double(rollout_cfg.threshold_sensitivity(:))';
    fixed_h = double(rollout_cfg.fixed_report_horizons(:))';

    Y_score = Y(:);
    if isfield(options, 'Y_scoring_override') && ~isempty(options.Y_scoring_override)
        Y_score = options.Y_scoring_override(:);
    end

    if iscell(predictions)
        n_origins = numel(predictions);
        pred_mat = nan(n_origins, H);
        for o = 1:n_origins
            p = predictions{o}(:);
            if numel(p) ~= H
                error('score_mg_autonomous_forecasts:BadPredLength', ...
                    'Origin %d prediction length %d ~= horizon %d.', o, numel(p), H);
            end
            pred_mat(o, :) = p.';
        end
    else
        pred_mat = predictions;
        if size(pred_mat, 2) ~= H
            error('score_mg_autonomous_forecasts:BadPredShape', ...
                'predictions must be n_origins x H.');
        end
        n_origins = size(pred_mat, 1);
    end

    origins = origins(:);
    if numel(origins) ~= n_origins
        error('score_mg_autonomous_forecasts:OriginCount', ...
            'origins length must match prediction count.');
    end

    washout = 0;
    if isfield(split, 'washout_steps')
        washout = split.washout_steps;
    end
    fit_idx = [split.train_idx(washout+1:end); split.val_idx(:)];
    Y_fit = Y_score(fit_idx);
    sigma_ref = std(Y_fit, 1);
    if ~(isfinite(sigma_ref) && sigma_ref > sqrt(eps))
        error('score_mg_autonomous_forecasts:DegenerateScale', ...
            'Normalization scale must be finite and > sqrt(eps) (got %g).', sigma_ref);
    end

    if any(~isfinite(pred_mat(:)))
        error('score_mg_autonomous_forecasts:NonfinitePredictions', ...
            'Autonomous predictions contain non-finite values.');
    end

    test_rel = zeros(n_origins, 1);
    per_origin = repmat(struct(), n_origins, 1);
    err_mat = nan(n_origins, H);
    for o = 1:n_origins
        i = origins(o);
        tgt = Y_score(i:(i + H - 1));
        if any(~isfinite(tgt))
            error('score_mg_autonomous_forecasts:NonfiniteTargets', ...
                'Targets for origin %d contain non-finite values.', i);
        end
        pred = pred_mat(o, :).';
        err = pred - tgt;
        nabs = abs(err) / sigma_ref;
        err_mat(o, :) = err.';

        [vh, first_cross, censored] = valid_horizon_from_nabs(nabs, thr_primary);
        sens = struct();
        for t = 1:numel(thr_sens)
            [vh_t, ~, cens_t] = valid_horizon_from_nabs(nabs, thr_sens(t));
            lab = sprintf('threshold_%.3g', thr_sens(t));
            lab = strrep(lab, '.', 'p');
            sens.(lab) = struct( ...
                'threshold', thr_sens(t), ...
                'role', char(rollout_cfg.threshold_sensitivity_role), ...
                'valid_horizon_steps', vh_t, ...
                'right_censored', cens_t);
        end

        rel = find(split.test_idx(:) == i, 1);
        if isempty(rel)
            error('score_mg_autonomous_forecasts:OriginNotInTest', ...
                'Origin %d is not in split.test_idx.', i);
        end
        test_rel(o) = rel;

        rmse = sqrt(mean(err.^2));
        nrmse = rmse / sigma_ref;

        per_origin(o).origin_global_index = i;
        per_origin(o).origin_test_relative_index = rel;
        per_origin(o).horizon = H;
        per_origin(o).predictions = pred;
        per_origin(o).targets = tgt;
        per_origin(o).errors = err;
        per_origin(o).normalized_absolute_errors = nabs;
        per_origin(o).full_horizon_nrmse = nrmse;
        per_origin(o).rmse = rmse;
        per_origin(o).valid_horizon_steps = vh;
        per_origin(o).first_threshold_exceedance_step = first_cross;
        per_origin(o).right_censored = censored;
        per_origin(o).threshold_sensitivity = sens;
        per_origin(o).valid_error_threshold = thr_primary;
    end

    pooled_at_h = nan(size(fixed_h));
    for hi = 1:numel(fixed_h)
        h = fixed_h(hi);
        if h < 1 || h > H
            error('score_mg_autonomous_forecasts:BadFixedHorizon', ...
                'fixed_report_horizons entry %g must lie in [1,%d].', h, H);
        end
        e = err_mat(:, 1:h);
        pooled_at_h(hi) = sqrt(mean(e(:).^2)) / sigma_ref;
    end
    pooled_full = sqrt(mean(err_mat(:).^2)) / sigma_ref;

    vh_all = [per_origin.valid_horizon_steps];
    cens_all = [per_origin.right_censored];

    metrics = struct();
    metrics.pooled_nrmse_at_fixed_horizons = pooled_at_h(:);
    metrics.fixed_report_horizons = fixed_h(:);
    metrics.pooled_nrmse_full_horizon = pooled_full;
    metrics.nrmse = pooled_full;  % compact/legacy alias
    metrics.median_valid_horizon = median(vh_all);
    metrics.mean_valid_horizon = mean(vh_all);
    metrics.min_valid_horizon = min(vh_all);
    metrics.max_valid_horizon = max(vh_all);
    metrics.fraction_right_censored = mean(double(cens_all));
    metrics.n_origins = n_origins;
    metrics.n_finite_forecasts = sum(all(isfinite(pred_mat), 2));
    metrics.sigma_ref = sigma_ref;
    metrics.normalization_reference = char(rollout_cfg.normalization_reference);
    metrics.pooled_nrmse_formula = char(rollout_cfg.pooled_nrmse_formula);
    metrics.primary_threshold = thr_primary;

    scored = struct();
    scored.per_origin = per_origin;
    scored.metrics = metrics;
    scored.normalization_scale = sigma_ref;
    scored.normalization_reference = char(rollout_cfg.normalization_reference);
    scored.normalization_definition = ...
        'std(Y(train_after_washout union val), 1)';
    scored.Y_scoring_override_used = isfield(options, 'Y_scoring_override') && ...
        ~isempty(options.Y_scoring_override);
    scored.origin_indices = origins;
    scored.origin_test_relative_indices = test_rel;
end

function [vh, first_cross, censored] = valid_horizon_from_nabs(nabs, thr)
    cross = find(nabs(:) > thr, 1, 'first');
    if isempty(cross)
        vh = numel(nabs);
        first_cross = NaN;
        censored = true;
    else
        vh = cross - 1;
        first_cross = cross;
        censored = false;
    end
end
