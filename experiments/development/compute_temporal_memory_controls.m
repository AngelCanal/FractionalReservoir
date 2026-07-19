function controls = compute_temporal_memory_controls(payload, cfg, options)
%COMPUTE_TEMPORAL_MEMORY_CONTROLS  Leakage-safe memory-curve control suite.
%
%   controls = compute_temporal_memory_controls(payload, cfg)
%   controls = compute_temporal_memory_controls(payload, cfg, options)
%
% Controls:
%   1. current_input_only  — features are u(t) only
%   2. no_recurrent_coupling — MESN rebuilt with W=0 (original unchanged)
%   3. exact_history — u(t),...,u(t-max_lag); lag-k column recovers target
%   4. shuffled_target — reference_r only; local preregistered shuffle seeds
%   5. conventional_leaky_esn — frozen matched candidate grid on diagnostic
%      splits (engine + grid only; no NARMA/MG orchestrator)
%
% payload fields:
%   splits, lags, lambda_grid, mesn_features (train/val/test structs with .X),
%   Y_train/Y_val/Y_test cell arrays by lag, esn (optional for no-recurrent),
%   cell_name, mesn_Win (for conventional), model_seed

    if nargin < 3 || isempty(options)
        options = struct();
    end
    lags = payload.lags(:);
    if size(payload, 1) > 1 || size(payload, 2) > 1
        error('compute_temporal_memory_controls:PayloadMustBeScalar', ...
            'payload must be a scalar struct (wrap vector fields in cells).');
    end
    lambda_grid = payload.lambda_grid(:);
    splits = payload.splits;
    max_lag = max(lags);

    controls = struct();
    controls.current_input_only = fit_score_feature_control( ...
        splits.train.U_scored, splits.validation.U_scored, splits.test.U_scored, ...
        payload.Y_train, payload.Y_val, payload.Y_test, lags, lambda_grid, ...
        'current_input_only');

    if isfield(payload, 'no_recurrent_features')
        nrf = payload.no_recurrent_features;
        controls.no_recurrent_coupling = fit_score_feature_control( ...
            nrf.train.X, nrf.validation.X, nrf.test.X, ...
            payload.Y_train, payload.Y_val, payload.Y_test, lags, lambda_grid, ...
            'no_recurrent_coupling');
        if isfield(payload, 'W_original') && isfield(payload, 'W_no_recurrent')
            controls.no_recurrent_coupling.W_is_exact_zero = ...
                all(payload.W_no_recurrent(:) == 0);
            controls.no_recurrent_coupling.original_W_unchanged = ...
                isequal(payload.W_original, payload.W_original_copy);
        end
    elseif isfield(payload, 'esn') && ~isempty(payload.esn)
        [esn_nr, ~] = rebuild_mesn_no_recurrent(payload.esn);
        W_orig = payload.esn.W;
        W_orig_copy = W_orig;
        nrf = struct();
        for name = {'train', 'validation', 'test'}
            nm = name{1};
            [nrf.(nm), ~] = extract_temporal_memory_features( ...
                esn_nr, splits.(nm), cfg, options);
        end
        controls.no_recurrent_coupling = fit_score_feature_control( ...
            nrf.train.X, nrf.validation.X, nrf.test.X, ...
            payload.Y_train, payload.Y_val, payload.Y_test, lags, lambda_grid, ...
            'no_recurrent_coupling');
        controls.no_recurrent_coupling.W_is_exact_zero = all(esn_nr.W(:) == 0);
        controls.no_recurrent_coupling.original_W_unchanged = isequal(W_orig, W_orig_copy);
    else
        controls.no_recurrent_coupling = struct('status', 'skipped', ...
            'reason', 'esn_or_features_not_provided');
    end

    Xh_tr = history_matrix(splits.train.U, splits.train.scored_idx, max_lag);
    Xh_va = history_matrix(splits.validation.U, splits.validation.scored_idx, max_lag);
    Xh_te = history_matrix(splits.test.U, splits.test.scored_idx, max_lag);
    controls.exact_history = fit_score_feature_control( ...
        Xh_tr, Xh_va, Xh_te, ...
        payload.Y_train, payload.Y_val, payload.Y_test, lags, lambda_grid, ...
        'exact_history');
    controls.exact_history.design = 'u(t),u(t-1),...,u(t-max_lag)';
    controls.exact_history.max_lag = max_lag;
    controls.exact_history.column_recovers_target = true;

    cell_name = '';
    if isfield(payload, 'cell_name'); cell_name = char(payload.cell_name); end
    if strcmp(cell_name, 'reference_r')
        shuf = cfg.shuffle_seeds;
        if isfield(options, 'shuffle_seeds'); shuf = options.shuffle_seeds; end
        assert_shuffle_seeds_allowed(cfg, shuf);
        Ytr_s = cell(numel(lags), 1);
        Yva_s = cell(numel(lags), 1);
        Yte_s = cell(numel(lags), 1);
        for i = 1:numel(lags)
            Ytr_s{i} = permute_with_seed(payload.Y_train{i}, shuf.train);
            Yva_s{i} = permute_with_seed(payload.Y_val{i}, shuf.validation);
            Yte_s{i} = permute_with_seed(payload.Y_test{i}, shuf.test);
        end
        mf = payload.mesn_features;
        controls.shuffled_target = fit_score_feature_control( ...
            mf.train.X, mf.validation.X, mf.test.X, ...
            Ytr_s, Yva_s, Yte_s, lags, lambda_grid, 'shuffled_target');
        controls.shuffled_target.shuffle_seeds = shuf;
        controls.shuffled_target.applied_to_cell = 'reference_r';
    else
        controls.shuffled_target = struct('status', 'not_required', ...
            'cell_name', cell_name);
    end

    if isfield(payload, 'mesn_Win') && ~isempty(payload.mesn_Win)
        controls.conventional_leaky_esn = fit_conventional_on_diagnostic_splits( ...
            splits, payload.Y_train, payload.Y_val, payload.Y_test, ...
            lags, lambda_grid, payload.mesn_Win, payload.model_seed, options);
    else
        controls.conventional_leaky_esn = struct('status', 'skipped', ...
            'reason', 'mesn_Win_not_provided');
    end
end

function out = fit_score_feature_control(Xtr, Xva, Xte, Ytr, Yva, Yte, lags, lambda_grid, name)
    if isvector(Xtr); Xtr = Xtr(:); end
    if isvector(Xva); Xva = Xva(:); end
    if isvector(Xte); Xte = Xte(:); end
    fit_opts = struct('X_test', Xte);
    bundle = fit_temporal_memory_curve(Xtr, Xva, Ytr, Yva, lags, lambda_grid, fit_opts);
    scored = score_temporal_memory_curve(bundle, Yte);
    out = struct();
    out.name = name;
    out.status = 'computed';
    out.bundle = bundle;
    out.scored = scored;
    out.summary = scored.summary;
    out.per_lag = scored.per_lag;
end

function Xh = history_matrix(U, scored_idx, max_lag)
    n = numel(scored_idx);
    Xh = zeros(n, max_lag + 1);
    for j = 0:max_lag
        Xh(:, j + 1) = U(scored_idx - j);
    end
end

function y = permute_with_seed(y_in, seed)
    stream = RandStream('mt19937ar', 'Seed', seed);
    y = y_in(randperm(stream, numel(y_in)));
    y = y(:);
end

function assert_shuffle_seeds_allowed(cfg, shuf)
    vals = [shuf.train, shuf.validation, shuf.test];
    if any(vals == 9003)
        error('compute_temporal_memory_controls:ForbiddenSeed9003', ...
            'v1 test seed 9003 forbidden for shuffle roles.');
    end
    if isfield(cfg, 'reserved_future_v2')
        reserved = flatten_numeric(cfg.reserved_future_v2);
        bad = intersect(vals, reserved(:)');
        if ~isempty(bad)
            error('compute_temporal_memory_controls:ReservedFutureSeed', ...
                'Reserved future seed(s) in shuffle roles: %s', mat2str(bad));
        end
    end
end

function result = fit_conventional_on_diagnostic_splits(splits, Ytr, Yva, Yte, ...
        lags, lambda_grid, mesn_Win, model_seed, options)
% Use existing conventional ESN engine + frozen candidate grid only.
    bb = build_matched_task_baselines_config(struct('base', struct('n', size(mesn_Win, 1))));
    ce = bb.conventional_leaky_esn;
    if isfield(options, 'conventional_config') && ~isempty(options.conventional_config)
        ce = options.conventional_config;
    end
    rhos = ce.spectral_radius_candidates(:);
    leaks = ce.leak_rate_candidates(:);
    scales = ce.input_scaling_candidates(:);
    reservoir_seed = model_seed + local_get(ce, 'reservoir_seed_offset', 2000);
    tie_tol = 1e-12;

    n_cand = numel(rhos) * numel(leaks) * numel(scales);
    cand = cell(n_cand, 1);
    meta = repmat(struct('spectral_radius', NaN, 'leak_rate', NaN, ...
        'input_scaling', NaN, 'achieved_spectral_radius', NaN, ...
        'finite', false), n_cand, 1);
    ic = 0;
    n_simulations = 0;
    for ir = 1:numel(rhos)
        for il = 1:numel(leaks)
            for isc = 1:numel(scales)
                ic = ic + 1;
                [Wres, winfo] = build_conventional_leaky_esn_Wres( ...
                    size(mesn_Win, 1), rhos(ir), reservoir_seed);
                [Win, ~] = build_conventional_leaky_esn_Win(mesn_Win, scales(isc));
                Htr = [];
                Hva = [];
                Hte = [];
                finite = true;
                for nm = {'train', 'validation', 'test'}
                    name = nm{1};
                    [H, rinfo] = run_conventional_leaky_esn( ...
                        splits.(name).U, Wres, Win, leaks(il));
                    n_simulations = n_simulations + 1;
                    finite = finite && rinfo.finite_state_trajectory;
                    idx = splits.(name).scored_idx;
                    switch name
                        case 'train', Htr = H(idx, :);
                        case 'validation', Hva = H(idx, :);
                        case 'test', Hte = H(idx, :);
                    end
                end
                meta(ic).spectral_radius = rhos(ir);
                meta(ic).leak_rate = leaks(il);
                meta(ic).input_scaling = scales(isc);
                meta(ic).achieved_spectral_radius = winfo.achieved_spectral_radius;
                meta(ic).finite = finite;
                cand{ic} = struct('Htr', Htr, 'Hva', Hva, 'Hte', Hte, ...
                    'Wres', Wres, 'Win', Win);
            end
        end
    end

    n_lags = numel(lags);
    per_lag = repmat(struct('lag', NaN, 'selected_candidate_index', NaN, ...
        'selected_lambda', NaN, 'metrics', struct(), 'hyperparameters', struct()), ...
        n_lags, 1);
    mc = zeros(n_lags, 1);

    for li = 1:n_lags
        scores = nan(n_cand, 1);
        sels = cell(n_cand, 1);
        for ic = 1:n_cand
            if ~meta(ic).finite
                continue;
            end
            try
                sel = select_ridge_lambda(cand{ic}.Htr, Ytr{li}, ...
                    cand{ic}.Hva, Yva{li}, lambda_grid);
            catch
                continue;
            end
            if isfinite(sel.selected_val_score)
                scores(ic) = sel.selected_val_score;
                sels{ic} = sel;
            end
        end
        finite_mask = isfinite(scores);
        if ~any(finite_mask)
            error('compute_temporal_memory_controls:NoConventionalCandidate', ...
                'No finite conventional ESN candidate at lag %d.', lags(li));
        end
        best_score = min(scores(finite_mask));
        tied = finite_mask & (abs(scores - best_score) <= tie_tol);
        best_ic = find(tied, 1, 'first');
        best_sel = sels{best_ic};
        best_payload = cand{best_ic};
        model = fit_ridge_readout( ...
            [best_payload.Htr; best_payload.Hva], ...
            [Ytr{li}(:); Yva{li}(:)], best_sel.selected_lambda);
        y_hat = apply_ridge_readout(model, best_payload.Hte);
        metrics = compute_temporal_memory_metrics(y_hat, Yte{li});
        per_lag(li).lag = lags(li);
        per_lag(li).selected_candidate_index = best_ic;
        per_lag(li).selected_lambda = best_sel.selected_lambda;
        per_lag(li).metrics = metrics;
        per_lag(li).hyperparameters = meta(best_ic);
        per_lag(li).model = model;
        mc(li) = metrics.memory_coefficient;
    end

    metrics_only = [per_lag.metrics];
    result = struct();
    result.name = 'conventional_leaky_esn';
    result.status = 'computed';
    result.protocol_version = 'matched_task_baselines_v1';
    result.engine = 'run_conventional_leaky_esn';
    result.candidate_grid_source = 'build_matched_task_baselines_config';
    result.n_candidates = n_cand;
    result.n_reservoir_simulations = n_simulations;
    result.reservoir_seed = reservoir_seed;
    result.per_lag = per_lag;
    result.summary = summarize_temporal_memory_curve(lags, mc, metrics_only);
    result.used_narma_orchestrator = false;
    result.used_mackey_glass_orchestrator = false;
end

function vals = flatten_numeric(S)
    vals = [];
    if isnumeric(S)
        vals = S(:)';
        return;
    end
    if ~isstruct(S) || numel(S) ~= 1
        return;
    end
    fn = fieldnames(S);
    for i = 1:numel(fn)
        vals = [vals, flatten_numeric(S.(fn{i}))]; %#ok<AGROW>
    end
end

function v = local_get(S, name, default)
    if isstruct(S) && isfield(S, name) && ~isempty(S.(name))
        v = S.(name);
    else
        v = default;
    end
end
