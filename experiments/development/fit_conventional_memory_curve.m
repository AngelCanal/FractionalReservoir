function bundle = fit_conventional_memory_curve(splits, Ytr, Yva, lags, ...
        lambda_grid, mesn_Win, model_seed, options)
%FIT_CONVENTIONAL_MEMORY_CURVE  One-reservoir conventional memory-curve fit.
%
%   bundle = fit_conventional_memory_curve(splits, Ytr, Yva, lags, ...
%       lambda_grid, mesn_Win, model_seed)
%   bundle = fit_conventional_memory_curve(..., options)
%
% Protocol matched_conventional_memory_curve_v1:
%   1. Enumerate frozen candidate grid (27 in production).
%   2. Simulate each candidate once per split (train/val/test inputs).
%   3. Per candidate x lag: select_ridge_lambda on train/validation only.
%   4. aggregate_validation_nrmse = mean(val_nrmse over selection lags).
%   5. Select one candidate: lowest aggregate; ties within 1e-12 take earliest.
%   6. Freeze reservoir; per lag retain selected lambda and refit train+val.
%
% Test targets are never accepted. Score with score_conventional_memory_curve.

    if nargin < 8 || isempty(options)
        options = struct();
    end
    lags = lags(:);
    lambda_grid = lambda_grid(:);
    policy = default_policy(options, lags);
    tie_tol = policy.tie_tolerance;
    selection_lags = policy.selection_lags(:);
    if ~all(ismember(selection_lags, lags))
        error('fit_conventional_memory_curve:SelectionLags', ...
            'selection_lags must be a subset of provided lags.');
    end
    sel_idx = zeros(numel(selection_lags), 1);
    for i = 1:numel(selection_lags)
        hit = find(lags == selection_lags(i), 1);
        if isempty(hit)
            error('fit_conventional_memory_curve:MissingSelectionLag', ...
                'selection lag %d not in lags.', selection_lags(i));
        end
        sel_idx(i) = hit;
    end

    bb = build_matched_task_baselines_config(struct('base', struct('n', size(mesn_Win, 1))));
    ce = bb.conventional_leaky_esn;
    if isfield(options, 'conventional_config') && ~isempty(options.conventional_config)
        ce = options.conventional_config;
    end
    rhos = ce.spectral_radius_candidates(:);
    leaks = ce.leak_rate_candidates(:);
    scales = ce.input_scaling_candidates(:);
    reservoir_seed = model_seed + local_get(ce, 'reservoir_seed_offset', 2000);

    if isfield(options, 'inject_candidates')
        inj = options.inject_candidates;
        if ~isempty(inj)
            if ~isfield(options, 'allow_test_fixture') || ~logical(options.allow_test_fixture)
                error('fit_conventional_memory_curve:FixtureFlagRequired', ...
                    'inject_candidates requires allow_test_fixture=true.');
            end
            [cand, meta, n_cand, n_simulations] = pack_injected(inj);
            provenance = 'synthetic_injected_candidates';
            is_fixture = true;
        else
            [cand, meta, n_cand, n_simulations] = simulate_grid( ...
                splits, mesn_Win, rhos, leaks, scales, reservoir_seed);
            provenance = 'production';
            is_fixture = false;
        end
    else
        [cand, meta, n_cand, n_simulations] = simulate_grid( ...
            splits, mesn_Win, rhos, leaks, scales, reservoir_seed);
        provenance = 'production';
        is_fixture = false;
    end
    if ~is_fixture
        expected_n = numel(rhos) * numel(leaks) * numel(scales);
        if n_cand ~= expected_n
            error('fit_conventional_memory_curve:CandidateCount', ...
                'Expected %d candidates, got %d.', expected_n, n_cand);
        end
    end

    n_lags = numel(lags);
    n_sel = numel(selection_lags);
    val_nrmse = nan(n_cand, n_sel);
    per_cand_lambda = nan(n_cand, n_lags);
    per_cand_sel = cell(n_cand, n_lags);

    for ic = 1:n_cand
        if ~meta(ic).finite
            continue;
        end
        for li = 1:n_lags
            try
                sel = select_ridge_lambda(cand{ic}.Htr, Ytr{li}, ...
                    cand{ic}.Hva, Yva{li}, lambda_grid);
            catch
                continue;
            end
            if isfinite(sel.selected_val_score)
                per_cand_lambda(ic, li) = sel.selected_lambda;
                per_cand_sel{ic, li} = sel;
            end
        end
        for si = 1:n_sel
            li = sel_idx(si);
            if ~isempty(per_cand_sel{ic, li})
                val_nrmse(ic, si) = per_cand_sel{ic, li}.selected_val_score;
            end
        end
    end

    aggregate = mean(val_nrmse, 2);
    finite_mask = isfinite(aggregate);
    if ~any(finite_mask)
        error('fit_conventional_memory_curve:NoValidCandidate', ...
            'No candidate produced finite aggregate validation NRMSE.');
    end
    best = min(aggregate(finite_mask));
    tied = finite_mask & (abs(aggregate - best) <= tie_tol);
    selected_ic = find(tied, 1, 'first');

    table_rows = repmat(struct( ...
        'candidate_index', NaN, ...
        'spectral_radius', NaN, ...
        'leak_rate', NaN, ...
        'input_scaling', NaN, ...
        'achieved_spectral_radius', NaN, ...
        'aggregate_validation_nrmse', NaN, ...
        'finite', false, ...
        'accepted', false, ...
        'selected_candidate', false, ...
        'per_lag_validation_nrmse_hash', ''), n_cand, 1);
    for ic = 1:n_cand
        table_rows(ic).candidate_index = ic;
        table_rows(ic).spectral_radius = meta(ic).spectral_radius;
        table_rows(ic).leak_rate = meta(ic).leak_rate;
        table_rows(ic).input_scaling = meta(ic).input_scaling;
        table_rows(ic).achieved_spectral_radius = meta(ic).achieved_spectral_radius;
        table_rows(ic).aggregate_validation_nrmse = aggregate(ic);
        table_rows(ic).finite = meta(ic).finite && isfinite(aggregate(ic));
        table_rows(ic).accepted = table_rows(ic).finite;
        table_rows(ic).selected_candidate = (ic == selected_ic);
        table_rows(ic).per_lag_validation_nrmse_hash = ...
            hash_numeric_array(val_nrmse(ic, :));
    end

    selected = cand{selected_ic};
    hyp = meta(selected_ic);
    per_lag = repmat(struct( ...
        'lag', NaN, ...
        'selected_candidate_index', selected_ic, ...
        'selected_lambda', NaN, ...
        'hyperparameters', hyp, ...
        'model', struct(), ...
        'numerical_rank', NaN, ...
        'coefficient_norm', NaN, ...
        'intercept', NaN, ...
        'coefficients', [], ...
        'feature_mean', [], ...
        'feature_scale', []), n_lags, 1);

    for li = 1:n_lags
        lam = per_cand_lambda(selected_ic, li);
        if ~isfinite(lam)
            error('fit_conventional_memory_curve:MissingLambda', ...
                'Selected candidate lacks lambda at lag %d.', lags(li));
        end
        model = fit_ridge_readout( ...
            [selected.Htr; selected.Hva], ...
            [Ytr{li}(:); Yva{li}(:)], lam);
        per_lag(li).lag = lags(li);
        per_lag(li).selected_candidate_index = selected_ic;
        per_lag(li).selected_lambda = lam;
        per_lag(li).hyperparameters = hyp;
        per_lag(li).model = model;
        per_lag(li).numerical_rank = model.numerical_rank;
        per_lag(li).coefficient_norm = model.coefficient_norm;
        per_lag(li).intercept = model.intercept;
        per_lag(li).coefficients = model.coefficients;
        per_lag(li).feature_mean = model.feature_mean;
        per_lag(li).feature_scale = model.feature_scale;
    end

    selected_candidate_content_hash = canonical_sha256(struct( ...
        'Wres_hash', hash_numeric_array(selected.Wres), ...
        'Win_hash', hash_numeric_array(selected.Win), ...
        'leak_rate', hyp.leak_rate, ...
        'spectral_radius', hyp.spectral_radius, ...
        'input_scaling', hyp.input_scaling, ...
        'reservoir_seed', reservoir_seed, ...
        'selected_candidate_index', selected_ic));

    bundle = struct();
    bundle.name = 'conventional_leaky_esn';
    bundle.status = 'fitted';
    bundle.protocol_version = 'matched_conventional_memory_curve_v1';
    bundle.engine = 'run_conventional_leaky_esn';
    bundle.candidate_grid_source = 'build_matched_task_baselines_config';
    bundle.n_candidates = n_cand;
    bundle.n_reservoir_simulations = n_simulations;
    bundle.reservoir_seed = reservoir_seed;
    bundle.model_seed = model_seed;
    bundle.lags = lags;
    bundle.lambda_grid = lambda_grid;
    bundle.selected_candidate_index = selected_ic;
    bundle.selected_hyperparameters = hyp;
    bundle.selected_candidate_content_hash = selected_candidate_content_hash;
    bundle.candidate_selection_table = table_rows;
    bundle.aggregate_validation_nrmse = aggregate;
    bundle.per_candidate_per_lag_validation_nrmse = val_nrmse;
    bundle.selection_metric = policy.reservoir_selection_metric;
    bundle.selection_lags = selection_lags;
    bundle.tie_tolerance = tie_tol;
    bundle.tie_break = policy.tie_break;
    bundle.per_lag = per_lag;
    bundle.same_reservoir_for_all_lags = true;
    bundle.test_targets_used_for_selection = false;
    bundle.test_targets_used_for_fitting = false;
    bundle.used_narma_orchestrator = false;
    bundle.used_mackey_glass_orchestrator = false;
    bundle.X_test = selected.Hte;
    bundle.Wres = selected.Wres;
    bundle.Win = selected.Win;
    bundle.provenance = provenance;
    bundle.is_test_fixture = is_fixture;
    if is_fixture
        bundle.synthetic_provenance = true;
    end
    bundle.execution_scope = policy.execution_scope;
    bundle.reusable_across_cells = true;
end

function policy = default_policy(options, lags)
    policy = struct();
    policy.protocol_version = 'matched_conventional_memory_curve_v1';
    policy.reservoir_selection_metric = 'mean_validation_nrmse_over_all_preregistered_lags';
    policy.selection_lags = lags(:);
    policy.tie_tolerance = 1e-12;
    policy.tie_break = 'earliest_candidate_in_frozen_order';
    policy.execution_scope = 'once_per_model_seed_shared_across_all_diagnostic_cells';
    if isfield(options, 'selection_lags')
        policy.selection_lags = options.selection_lags;
    end
    if isfield(options, 'tie_tolerance')
        policy.tie_tolerance = options.tie_tolerance;
    end
    if isfield(options, 'conventional_memory_baseline')
        cmb = options.conventional_memory_baseline;
        if isfield(cmb, 'selection_lags'); policy.selection_lags = cmb.selection_lags; end
        if isfield(cmb, 'tie_tolerance'); policy.tie_tolerance = cmb.tie_tolerance; end
        if isfield(cmb, 'reservoir_selection_metric')
            policy.reservoir_selection_metric = cmb.reservoir_selection_metric;
        end
        if isfield(cmb, 'tie_break'); policy.tie_break = cmb.tie_break; end
        if isfield(cmb, 'execution_scope'); policy.execution_scope = cmb.execution_scope; end
    end
end

function [cand, meta, n_cand, n_simulations] = pack_injected(inject)
    n_cand = numel(inject);
    cand = inject;
    meta = repmat(struct('spectral_radius', NaN, 'leak_rate', NaN, ...
        'input_scaling', NaN, 'achieved_spectral_radius', NaN, ...
        'finite', true, 'candidate_index', NaN), n_cand, 1);
    for ic = 1:n_cand
        meta(ic).candidate_index = ic;
        meta(ic).spectral_radius = ic;
        meta(ic).leak_rate = 1;
        meta(ic).input_scaling = 1;
        meta(ic).achieved_spectral_radius = ic;
        meta(ic).finite = true;
        if ~isfield(cand{ic}, 'Wres'); cand{ic}.Wres = eye(size(cand{ic}.Htr, 2)); end
        if ~isfield(cand{ic}, 'Win'); cand{ic}.Win = ones(size(cand{ic}.Htr, 2), 1); end
    end
    n_simulations = 0;
end

function [cand, meta, n_cand, n_simulations] = simulate_grid( ...
        splits, mesn_Win, rhos, leaks, scales, reservoir_seed)
    n_cand = numel(rhos) * numel(leaks) * numel(scales);
    cand = cell(n_cand, 1);
    meta = repmat(struct('spectral_radius', NaN, 'leak_rate', NaN, ...
        'input_scaling', NaN, 'achieved_spectral_radius', NaN, ...
        'finite', false, 'candidate_index', NaN), n_cand, 1);
    ic = 0;
    n_simulations = 0;
    for ir = 1:numel(rhos)
        for il = 1:numel(leaks)
            for isc = 1:numel(scales)
                ic = ic + 1;
                [Wres, winfo] = build_conventional_leaky_esn_Wres( ...
                    size(mesn_Win, 1), rhos(ir), reservoir_seed);
                [Win, ~] = build_conventional_leaky_esn_Win(mesn_Win, scales(isc));
                Htr = []; Hva = []; Hte = [];
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
                meta(ic).candidate_index = ic;
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
end

function v = local_get(S, name, default)
    if isstruct(S) && isfield(S, name) && ~isempty(S.(name))
        v = S.(name);
    else
        v = default;
    end
end
