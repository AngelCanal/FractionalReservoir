function result = select_conventional_leaky_esn(U, Y, split, washout_steps, mesn_Win, opts)
% SELECT_CONVENTIONAL_LEAKY_ESN  Validation-only conventional ESN candidate search.
%
%   result = select_conventional_leaky_esn(U, Y, split, washout_steps, mesn_Win, opts)
%
% Enumerates spectral_radius × leak × input_scaling in frozen listed order.
% Within each candidate, Phase 4A select_ridge_lambda chooses lambda.
% Across candidates: lowest finite validation NRMSE; ties within 1e-12 take the
% earliest enumerated candidate. Test data never enter selection.

    if nargin < 6 || isempty(opts)
        opts = struct();
    end

    ce = local_get(opts, 'conventional_config', default_ce_config(size(mesn_Win, 1)));
    lambda_grid = local_get(opts, 'lambda_grid', [0; logspace(-12, 2, 15)']);
    lambda_grid = lambda_grid(:);
    base_seed = local_get(opts, 'base_seed', local_get(opts, 'seed', 1));
    reservoir_seed = base_seed + local_get(ce, 'reservoir_seed_offset', 2000);
    tie_tol = local_get(opts, 'validation_tie_tolerance', 1e-12);

    train_idx = split.train_idx(washout_steps+1:end);
    val_idx = split.val_idx(:);
    test_idx = split.test_idx(:);

    rhos = ce.spectral_radius_candidates(:);
    leaks = ce.leak_rate_candidates(:);
    scales = ce.input_scaling_candidates(:);
    n_cand = numel(rhos) * numel(leaks) * numel(scales);

    blank = struct( ...
        'candidate_index', NaN, ...
        'spectral_radius', NaN, ...
        'leak_rate', NaN, ...
        'input_scaling', NaN, ...
        'achieved_spectral_radius', NaN, ...
        'selected_lambda', NaN, ...
        'validation_nrmse', NaN, ...
        'status', 'rejected', ...
        'accepted', false, ...
        'selected_candidate', false, ...
        'finite_state_trajectory', false, ...
        'numerical_rank', NaN, ...
        'coefficient_norm', NaN);
    table_rows = repmat(blank, n_cand, 1);
    candidate_payloads = cell(n_cand, 1);

    ic = 0;
    for ir = 1:numel(rhos)
        for il = 1:numel(leaks)
            for isc = 1:numel(scales)
                ic = ic + 1;
                row = blank;
                row.candidate_index = ic;
                row.spectral_radius = rhos(ir);
                row.leak_rate = leaks(il);
                row.input_scaling = scales(isc);
                try
                    [Wres, winfo] = build_conventional_leaky_esn_Wres( ...
                        size(mesn_Win, 1), rhos(ir), reservoir_seed);
                    [Win, winin] = build_conventional_leaky_esn_Win(mesn_Win, scales(isc));
                    [H, rinfo] = run_conventional_leaky_esn(U, Wres, Win, leaks(il));
                    row.achieved_spectral_radius = winfo.achieved_spectral_radius;
                    row.finite_state_trajectory = rinfo.finite_state_trajectory;
                    if ~rinfo.finite_state_trajectory
                        row.status = 'invalid_nonfinite';
                        table_rows(ic) = row;
                        continue;
                    end
                    Xtr = H(train_idx, :);
                    Ytr = Y(train_idx, :);
                    Xva = H(val_idx, :);
                    Yva = Y(val_idx, :);
                    sel = select_ridge_lambda(Xtr, Ytr, Xva, Yva, lambda_grid);
                    row.selected_lambda = sel.selected_lambda;
                    row.validation_nrmse = sel.selected_val_score;
                    row.numerical_rank = sel.selected_model.numerical_rank;
                    row.coefficient_norm = sel.selected_model.coefficient_norm;
                    row.accepted = isfinite(row.validation_nrmse);
                    if row.accepted
                        row.status = 'accepted';
                    else
                        row.status = 'rejected';
                    end
                    candidate_payloads{ic} = struct( ...
                        'Wres', Wres, 'Win', Win, 'H', H, 'selection', sel, ...
                        'win_info', winin, 'wres_info', winfo, 'run_info', rinfo);
                catch ME
                    row.status = ME.identifier;
                    if isempty(row.status)
                        row.status = 'fit_failed';
                    end
                    row.accepted = false;
                end
                table_rows(ic) = row;
            end
        end
    end

    accepted = [table_rows.accepted];
    if ~any(accepted)
        result = failed_result(table_rows, reservoir_seed, base_seed, lambda_grid);
        return;
    end

    scores = nan(n_cand, 1);
    for i = 1:n_cand
        if table_rows(i).accepted
            scores(i) = table_rows(i).validation_nrmse;
        end
    end
    best = min(scores);
    tied = accepted(:) & isfinite(scores) & (abs(scores - best) <= tie_tol);
    % earliest enumerated candidate among ties
    selected_idx = find(tied, 1, 'first');
    table_rows(selected_idx).selected_candidate = true;

    payload = candidate_payloads{selected_idx};
    sel = payload.selection;
    H = payload.H;

    Xte = H(test_idx, :);
    Yte = Y(test_idx, :);
    Yhat_te = apply_ridge_readout(sel.selected_model, Xte);
    Yhat_tr = apply_ridge_readout(sel.selected_model, H(train_idx, :));
    Yhat_va = apply_ridge_readout(sel.selected_model, H(val_idx, :));

    m_tr = compute_metrics(Yhat_tr, Y(train_idx, :));
    m_va = compute_metrics(Yhat_va, Y(val_idx, :));
    m_te = compute_metrics(Yhat_te, Yte);

    boundary = selected_idx == 1 || selected_idx == n_cand || ...
        table_rows(selected_idx).spectral_radius == rhos(1) || ...
        table_rows(selected_idx).spectral_radius == rhos(end) || ...
        table_rows(selected_idx).leak_rate == leaks(1) || ...
        table_rows(selected_idx).leak_rate == leaks(end) || ...
        table_rows(selected_idx).input_scaling == scales(1) || ...
        table_rows(selected_idx).input_scaling == scales(end);

    result = pack_conventional_result(table_rows, selected_idx, payload, ...
        m_tr, m_va, m_te, train_idx, val_idx, test_idx, ...
        reservoir_seed, base_seed, lambda_grid, boundary, tie_tol);
end

function result = pack_conventional_result(table_rows, selected_idx, payload, ...
        m_tr, m_va, m_te, train_idx, val_idx, test_idx, ...
        reservoir_seed, base_seed, lambda_grid, boundary, tie_tol)
    sel = payload.selection;
    model = sel.selected_model;
    winin = payload.win_info;
    winfo = payload.wres_info;
    row = table_rows(selected_idx);

    result = struct();
    result.name = 'conventional_leaky_esn';
    result.status = 'computed';
    result.role = 'matched_task_baseline';
    result.protocol_version = 'matched_task_baselines_v1';
    result.model_family = 'conventional_leaky_esn';
    result.feature_dimension = size(payload.H, 2);
    result.include_input = false;
    result.train_rows = numel(train_idx);
    result.validation_rows = numel(val_idx);
    result.test_rows = numel(test_idx);
    result.metrics = struct('train', m_tr, 'validation', m_va, 'test', m_te);
    result.metrics_train = m_tr;
    result.metrics_val = m_va;
    result.metrics_test = m_te;
    result.selected_lambda = sel.selected_lambda;
    result.ridge_diagnostics = extract_ridge_diag(model);
    result.lambda_selection_table = compact_lambda_table(sel);
    result.hyperparameters = struct( ...
        'spectral_radius', row.spectral_radius, ...
        'achieved_spectral_radius', row.achieved_spectral_radius, ...
        'leak_rate', row.leak_rate, ...
        'input_scaling', row.input_scaling, ...
        'activation', 'tanh', ...
        'reservoir_bias', 0);
    result.provenance = struct( ...
        'base_seed', base_seed, ...
        'reservoir_seed', reservoir_seed, ...
        'lambda_grid', lambda_grid(:), ...
        'validation_tie_tolerance', tie_tol, ...
        'readout_solver', 'phase4a_economy_svd', ...
        'selection_scope', 'train_validation_only');
    result.reservoir_seed = reservoir_seed;
    result.spectral_radius = row.spectral_radius;
    result.achieved_spectral_radius = row.achieved_spectral_radius;
    result.leak_rate = row.leak_rate;
    result.input_scaling = row.input_scaling;
    result.input_support_indices = winin.input_support_indices;
    result.input_nonzero_count = winin.input_nonzero_count;
    result.candidate_selection_table = table_rows;
    result.selected_candidate_index = selected_idx;
    result.selected_at_candidate_boundary = logical(boundary);
    result.finite_state_trajectory = payload.run_info.finite_state_trajectory;
    result.recurrent_dale_constrained = false;
    result.has_sfa = false;
    result.has_std = false;
    result.has_delay = false;
end

function result = failed_result(table_rows, reservoir_seed, base_seed, lambda_grid)
    result = struct();
    result.name = 'conventional_leaky_esn';
    result.status = 'failed';
    result.role = 'matched_task_baseline';
    result.protocol_version = 'matched_task_baselines_v1';
    result.model_family = 'conventional_leaky_esn';
    result.feature_dimension = NaN;
    result.include_input = false;
    result.train_rows = NaN;
    result.validation_rows = NaN;
    result.test_rows = NaN;
    result.metrics = struct('train', struct('nrmse', NaN), ...
        'validation', struct('nrmse', NaN), 'test', struct('nrmse', NaN));
    result.metrics_train = result.metrics.train;
    result.metrics_val = result.metrics.validation;
    result.metrics_test = result.metrics.test;
    result.selected_lambda = NaN;
    result.ridge_diagnostics = struct();
    result.lambda_selection_table = [];
    result.hyperparameters = struct();
    result.provenance = struct('base_seed', base_seed, ...
        'reservoir_seed', reservoir_seed, 'lambda_grid', lambda_grid(:));
    result.reservoir_seed = reservoir_seed;
    result.candidate_selection_table = table_rows;
    result.selected_candidate_index = NaN;
    result.selected_at_candidate_boundary = false;
    result.finite_state_trajectory = false;
    result.recurrent_dale_constrained = false;
    result.has_sfa = false;
    result.has_std = false;
    result.has_delay = false;
end

function ce = default_ce_config(n)
    ce = struct();
    ce.spectral_radius_candidates = [0.5, 0.9, 1.2];
    ce.leak_rate_candidates = [0.1, 0.3, 1.0];
    ce.input_scaling_candidates = [0.25, 0.5, 1.0];
    ce.reservoir_seed_offset = 2000;
    ce.state_dimension = n;
end

function d = extract_ridge_diag(model)
    d = struct();
    d.solver_method = local_field(model, 'solver_method', '');
    d.lambda = model.lambda;
    d.numerical_rank = local_field(model, 'numerical_rank', NaN);
    d.coefficient_norm = local_field(model, 'coefficient_norm', NaN);
    d.conditioning_status = local_field(model, 'conditioning_status', '');
    d.feature_mean = local_field(model, 'feature_mean', model.mu);
    d.feature_scale = local_field(model, 'feature_scale', model.sigma);
    d.intercept = model.intercept;
    d.coefficients = model.coefficients;
    d.n_features = model.n_features;
end

function rows = compact_lambda_table(selection)
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
        rows(i).validation_nrmse = src(i).val_score;
        if logical(src(i).accepted)
            rows(i).status = 'accepted';
        else
            rows(i).status = 'rejected';
        end
        rows(i).numerical_rank = src(i).numerical_rank;
        rows(i).coefficient_norm = src(i).coefficient_norm;
        rows(i).selected_candidate = logical(src(i).accepted) && ...
            src(i).lambda == selection.selected_lambda;
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end

function v = local_field(s, name, default)
    v = local_get(s, name, default);
end
