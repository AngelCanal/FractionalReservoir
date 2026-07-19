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
    cell_name = '';
    if isfield(payload, 'cell_name'); cell_name = char(payload.cell_name); end

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
    elseif strcmp(cell_name, 'reference_r') && isfield(payload, 'esn') && ...
            ~isempty(payload.esn)
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
        controls.no_recurrent_coupling = struct('status', 'not_required', ...
            'cell_name', cell_name, ...
            'reason', 'reference_r_only');
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

    if isfield(payload, 'conventional_precomputed') && ...
            ~isempty(payload.conventional_precomputed)
        % Once-per-model-seed reuse across diagnostic cells (Phase 5D-B2 policy).
        pre = payload.conventional_precomputed;
        if isfield(pre, 'status') && strcmp(pre.status, 'fitted')
            controls.conventional_leaky_esn = score_conventional_memory_curve( ...
                pre, payload.Y_test);
        else
            controls.conventional_leaky_esn = pre;
        end
        controls.conventional_leaky_esn.reused_shared_baseline = true;
    elseif isfield(payload, 'mesn_Win') && ~isempty(payload.mesn_Win)
        fit_opts = options;
        if isfield(cfg, 'conventional_memory_baseline')
            fit_opts.conventional_memory_baseline = cfg.conventional_memory_baseline;
        end
        conv_bundle = fit_conventional_memory_curve( ...
            splits, payload.Y_train, payload.Y_val, lags, lambda_grid, ...
            payload.mesn_Win, payload.model_seed, fit_opts);
        controls.conventional_leaky_esn = score_conventional_memory_curve( ...
            conv_bundle, payload.Y_test);
        controls.conventional_leaky_esn.reused_shared_baseline = false;
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
