function esp = verify_echo_state_property(esn_or_params, U, options)
% verify_echo_state_property
% Empirical state-convergence rate experiment under a shared driven input.
%
% This is a diagnostic on a finite test set. It does NOT prove the Echo State
% Property. Returned classifications are only:
%   'empirically_contracting_on_test_set'
%   'not_contracting_on_test_set'
%   'inconclusive'
%
% Primary distances use the complete packed S_history (not X_features):
%   dist = ||S_a - S_b||_2 / sqrt(n_state)
% Slopes are fit to log(distance) versus physical time in seconds
% (units: slope_per_time). Distance-floor-saturated samples are excluded.
%
% IC-pair slopes are dependent descriptive measurements within one
% network/input trial. They are summarized by median/mean; they are NOT
% treated as independent experimental replicates for inferential CIs.
%
% Usage:
%   esp = verify_echo_state_property(esn, U);
%   esp = verify_echo_state_property(params, U, opts);
%
% Canonical fields:
%   pair_slopes, median_pair_slope, mean_pair_slope, slope_per_time_units,
%   final_max_spread, final_median_spread, convergence_ratio,
%   classification, classification_reason
%
% DDE results set history_space_sampled=true and dde_empirical_only=true.
% Never returns esp_holds.

    if nargin < 3 || isempty(options)
        options = struct();
    end

    n_ic = getFieldOrDefault(options, 'n_ic', 8);
    n_input_seeds = getFieldOrDefault(options, 'n_input_seeds', 1);
    input_seed = getFieldOrDefault(options, 'input_seed', 1);
    ic_seed = getFieldOrDefault(options, 'ic_seed', 1000);
    ic_scale = getFieldOrDefault(options, 'ic_scale', 0.1);
    washout_steps = getFieldOrDefault(options, 'washout_steps', 200);
    tail_window = getFieldOrDefault(options, 'tail_window', [0.7, 1.0]);
    distance_floor = getFieldOrDefault(options, 'distance_floor', 1e-12);
    slope_contracting_max = getFieldOrDefault(options, 'slope_contracting_max', -1e-3);
    slope_expanding_min = getFieldOrDefault(options, 'slope_expanding_min', 1e-3);
    min_tail_points = getFieldOrDefault(options, 'min_tail_points', 20);
    verbose = getFieldOrDefault(options, 'verbose', true);
    dde_history_mode = getFieldOrDefault(options, 'dde_history_mode', 'constant');
    has_sim = isfield(options, 'simulate_fn') && isa(options.simulate_fn, 'function_handle');

    if washout_steps < 0
        error('verify_echo_state_property:InvalidWashout', 'washout_steps must be >= 0');
    end
    if size(U, 1) <= washout_steps + 1
        error('verify_echo_state_property:ShortInput', ...
            'U is too short for washout_steps=%d', washout_steps);
    end

    esn = [];
    params = struct();
    is_dde = false;
    dt = getFieldOrDefault(options, 'dt', 1.0);
    if has_sim
        simulate_fn = options.simulate_fn;
        if isfield(options, 'n_state')
            n_state = options.n_state;
        else
            X0 = simulate_fn(U(1:min(5, size(U,1)), :), 0);
            n_state = size(X0, 2);
        end
        S0 = zeros(n_state, 1);
        idx_b_E = [];
        idx_b_I = [];
        idx_a_E = [];
        idx_a_I = [];
        idx_x = 1:n_state;
        layout = struct();
    else
        if isa(esn_or_params, 'SRNN_ESN')
            esn = esn_or_params;
        else
            esn = SRNN_ESN(esn_or_params);
        end
        params = esn.params;
        dt = esn.dt;
        esn.resetState();
        S0 = esn.getState();
        n_state = numel(S0);
        layout = state_layout(params);
        idx_b_E = layout.idx_b_E;
        idx_b_I = layout.idx_b_I;
        idx_a_E = layout.idx_a_E;
        idx_a_I = layout.idx_a_I;
        idx_x = layout.idx_x;
        is_dde = isfield(params, 'lags') && ~isempty(params.lags);
        simulate_fn = [];
    end

    T = size(U, 1);
    input_stream = RandStream('mt19937ar', 'Seed', input_seed);
    ic_stream = RandStream('mt19937ar', 'Seed', ic_seed);

    pair_slopes = [];
    pair_slopes_per_sample_compat = [];
    pair_meta = struct( ...
        'input_seed_index', {}, 'pair', {}, 'slope_per_time', {}, ...
        'n_usable_tail_points', {}, 'fraction_at_floor', {}, ...
        'fit_interval_seconds', {}, 'fit_quality_r2', {});

    dist_max_all = [];
    dist_med_all = [];
    dist_p90_all = [];
    t_idx = (washout_steps + 1):T;
    n_t = numel(t_idx);
    t_sec_all = ((0:T-1)') * dt;
    initial_states = zeros(n_state, n_ic);
    initial_state_summaries = struct([]);

    for s = 1:n_input_seeds
        if n_input_seeds == 1
            U_s = U;
        else
            U_s = randn(input_stream, T, size(U, 2));
            if isfield(options, 'input_scale')
                U_s = options.input_scale * U_s;
            else
                U_s = 0.2 * U_s;
            end
        end

        S_all = zeros(T, n_state, n_ic);
        for k = 1:n_ic
            S_k = perturb_packed_state(S0, ic_scale, ic_stream, ...
                idx_x, idx_a_E, idx_a_I, idx_b_E, idx_b_I);
            initial_states(:, k) = S_k;
            if has_sim
                S_traj = simulate_fn(U_s, S_k);
                if size(S_traj, 2) ~= n_state
                    error('verify_echo_state_property:SimulateWidth', ...
                        'simulate_fn must return packed-state width %d.', n_state);
                end
            elseif is_dde
                hist_fn = make_dde_history_fn(S_k, S0, dde_history_mode, ...
                    max(params.lags(:)), ic_scale, k, ic_seed);
                [~, S_traj] = esn.runReservoir(U_s, struct( ...
                    'reset_before', false, ...
                    'update_internal_state', false, ...
                    'history_fn', hist_fn));
            else
                [~, S_traj] = esn.runReservoir(U_s, struct( ...
                    'reset_before', false, ...
                    'update_internal_state', false, ...
                    'initial_state', S_k));
            end
            if size(S_traj, 1) ~= T
                error('verify_echo_state_property:TrajectoryLength', ...
                    'Expected T=%d rows in S_history, got %d.', T, size(S_traj, 1));
            end
            S_all(:, :, k) = S_traj;
        end

        if n_ic >= 2
            d01 = norm(initial_states(:, 1) - initial_states(:, 2));
            if ~(isfinite(d01) && d01 > 0)
                error('verify_echo_state_property:IdenticalInitialStates', ...
                    'Generated initial states/histories are not numerically distinct.');
            end
        end

        [d_max, d_med, d_p90] = pairwise_distance_stats(S_all(t_idx, :, :), n_state);
        dist_max_all = [dist_max_all, d_max]; %#ok<AGROW>
        dist_med_all = [dist_med_all, d_med]; %#ok<AGROW>
        dist_p90_all = [dist_p90_all, d_p90]; %#ok<AGROW>

        i0 = max(1, floor(tail_window(1) * n_t));
        i1 = min(n_t, max(i0 + 1, ceil(tail_window(2) * n_t)));
        tail_local = i0:i1;
        if numel(tail_local) < min_tail_points
            continue;
        end
        t_tail = t_sec_all(t_idx(tail_local));
        sample_tail = (0:numel(tail_local)-1)';  % compatibility diagnostic only
        pairs = nchoosek(1:n_ic, 2);
        for p = 1:size(pairs, 1)
            a = pairs(p, 1);
            b = pairs(p, 2);
            diff_ab = S_all(t_idx(tail_local), :, a) - S_all(t_idx(tail_local), :, b);
            dist = sqrt(sum(diff_ab.^2, 2)) / sqrt(n_state);
            usable = isfinite(dist) & (dist > distance_floor);
            frac_floor = mean(~usable);
            n_usable = sum(usable);
            fit = struct( ...
                'slope_per_time', NaN, ...
                'slope_per_sample_compat', NaN, ...
                'n_usable_tail_points', n_usable, ...
                'fraction_at_floor', frac_floor, ...
                'fit_interval_seconds', [NaN, NaN], ...
                'fit_quality_r2', NaN);
            if n_usable >= min_tail_points
                t_u = t_tail(usable);
                y = log(dist(usable));
                if all(isfinite(y))
                    P = polyfit(t_u - t_u(1), y, 1);
                    fit.slope_per_time = P(1);
                    yhat = polyval(P, t_u - t_u(1));
                    ss_res = sum((y - yhat).^2);
                    ss_tot = sum((y - mean(y)).^2);
                    if ss_tot > 0
                        fit.fit_quality_r2 = 1 - ss_res / ss_tot;
                    else
                        fit.fit_quality_r2 = 1;
                    end
                    fit.fit_interval_seconds = [t_u(1), t_u(end)];
                    % Compatibility diagnostic only (sample-index slope).
                    P_s = polyfit(sample_tail(usable), y, 1);
                    fit.slope_per_sample_compat = P_s(1);
                end
            end
            if isfinite(fit.slope_per_time)
                pair_slopes(end+1, 1) = fit.slope_per_time; %#ok<AGROW>
                pair_slopes_per_sample_compat(end+1, 1) = fit.slope_per_sample_compat; %#ok<AGROW>
            end
            pair_meta(end+1).input_seed_index = s; %#ok<AGROW>
            pair_meta(end).pair = pairs(p, :);
            pair_meta(end).slope_per_time = fit.slope_per_time;
            pair_meta(end).n_usable_tail_points = fit.n_usable_tail_points;
            pair_meta(end).fraction_at_floor = fit.fraction_at_floor;
            pair_meta(end).fit_interval_seconds = fit.fit_interval_seconds;
            pair_meta(end).fit_quality_r2 = fit.fit_quality_r2;
        end
    end

    for k = 1:n_ic
        initial_state_summaries(k).norm = norm(initial_states(:, k));
        initial_state_summaries(k).hash = state_digest(initial_states(:, k));
        if k > 1
            initial_state_summaries(k).distance_from_first = ...
                norm(initial_states(:, k) - initial_states(:, 1));
        else
            initial_state_summaries(k).distance_from_first = 0;
        end
    end

    % Block-normalized diagnostic (documented fixed scales).
    block_scales = struct('x', 1.0, 'a', 1.0, 'b', 1.0);
    block_diag = struct('enabled', ~has_sim, 'scales', block_scales);
    if ~has_sim && n_ic >= 2
        diff12 = S_all(t_idx, :, 1) - S_all(t_idx, :, 2);
        block_diag.distance_curve = block_normalized_distance( ...
            diff12, layout, block_scales);
    end

    esp = struct();
    esp.options = options;
    esp.n_ic = n_ic;
    esp.n_input_seeds = n_input_seeds;
    esp.dt = dt;
    esp.t_idx = t_idx(:);
    esp.n_state = n_state;
    esp.distance_floor = distance_floor;
    esp.tail_window = tail_window;
    esp.distance_max = dist_max_all;
    esp.distance_median = dist_med_all;
    esp.distance_p90 = dist_p90_all;
    esp.primary_norm = 'euclidean_over_sqrt_n_state';
    esp.block_normalized_diagnostic = block_diag;
    esp.initial_state_summaries = initial_state_summaries;
    esp.slope_per_time_units = 'per_second';
    esp.pair_slopes = pair_slopes;
    esp.pair_slopes_per_sample_compat = pair_slopes_per_sample_compat;
    esp.pair_meta = pair_meta;

    if ~isempty(dist_max_all)
        esp.convergence_curve = mean(dist_max_all, 2);
        esp.final_max_spread = esp.convergence_curve(end);
        esp.final_median_spread = mean(dist_med_all(end, :));
        if isfinite(esp.convergence_curve(1)) && esp.convergence_curve(1) > 0
            esp.convergence_ratio = esp.final_max_spread / esp.convergence_curve(1);
        else
            esp.convergence_ratio = NaN;
        end
    else
        esp.convergence_curve = [];
        esp.final_max_spread = NaN;
        esp.final_median_spread = NaN;
        esp.convergence_ratio = NaN;
    end

    if isempty(pair_meta)
        n_usable_med = 0;
        frac_floor_med = 1;
    else
        n_usable_med = median([pair_meta.n_usable_tail_points]);
        frac_floor_med = median([pair_meta.fraction_at_floor]);
    end
    esp.n_usable_tail_points = n_usable_med;
    esp.fraction_at_floor = frac_floor_med;
    if ~isempty(pair_meta) && isfield(pair_meta, 'fit_interval_seconds')
        intervals = reshape([pair_meta.fit_interval_seconds], 2, [])';
        finite_rows = all(isfinite(intervals), 2);
        if any(finite_rows)
            esp.fit_interval_seconds = [min(intervals(finite_rows, 1)), ...
                max(intervals(finite_rows, 2))];
        else
            esp.fit_interval_seconds = [NaN, NaN];
        end
        esp.fit_quality_r2 = median([pair_meta.fit_quality_r2], 'omitnan');
    else
        esp.fit_interval_seconds = [NaN, NaN];
        esp.fit_quality_r2 = NaN;
    end

    if isempty(pair_slopes) || n_t < min_tail_points
        esp.median_pair_slope = NaN;
        esp.mean_pair_slope = NaN;
        esp.classification = 'inconclusive';
        if n_t < min_tail_points
            esp.classification_reason = 'insufficient_duration_or_pairs';
        else
            esp.classification_reason = 'insufficient_usable_tail_points_above_distance_floor';
        end
    else
        % Descriptive within-trial summaries only; not independent-replicate CIs.
        esp.median_pair_slope = median(pair_slopes);
        esp.mean_pair_slope = mean(pair_slopes);
        if esp.median_pair_slope < slope_contracting_max
            esp.classification = 'empirically_contracting_on_test_set';
            esp.classification_reason = 'median_pair_slope_below_contracting_threshold';
        elseif esp.median_pair_slope > slope_expanding_min
            esp.classification = 'not_contracting_on_test_set';
            esp.classification_reason = 'median_pair_slope_above_expanding_threshold';
        else
            esp.classification = 'inconclusive';
            esp.classification_reason = 'median_pair_slope_within_inconclusive_band';
        end
    end

    esp.dde_empirical_only = is_dde;
    esp.history_space_sampled = is_dde;
    esp.dde_constant_history_limitation = is_dde && strcmp(dde_history_mode, 'constant');
    if is_dde
        esp.dde_limitation_note = [ ...
            'DDE mode: only sampled history-space empirical convergence was evaluated; ', ...
            'this does not exhaust the infinite-dimensional history space and is not ', ...
            'an ESP theorem.'];
        esp.dde_history_mode = dde_history_mode;
    end

    esp.sensitivity = struct( ...
        'washout_steps', washout_steps, ...
        'ic_scale', ic_scale, ...
        'input_seed', input_seed, ...
        'ic_seed', ic_seed, ...
        'norm', esp.primary_norm, ...
        'duration_steps', T, ...
        'post_washout_steps', n_t, ...
        'dt', dt);

    if verbose
        fprintf(['Empirical convergence: class=%s  median_pair_slope=%.3e %s\n'], ...
            esp.classification, esp.median_pair_slope, esp.slope_per_time_units);
    end
end

function S_k = perturb_packed_state(S0, ic_scale, stream, ...
        idx_x, idx_a_E, idx_a_I, idx_b_E, idx_b_I)
    S_k = S0(:);
    if ~isempty(idx_x)
        S_k(idx_x) = S_k(idx_x) + ic_scale * randn(stream, numel(idx_x), 1);
    end
    idx_a = [idx_a_E(:); idx_a_I(:)];
    if ~isempty(idx_a)
        S_k(idx_a) = S_k(idx_a) + ic_scale * randn(stream, numel(idx_a), 1);
    end
    idx_b = [idx_b_E(:); idx_b_I(:)];
    if ~isempty(idx_b)
        % Perturb resources and clip to [0,1]; do not reset every resource to 1.
        S_k(idx_b) = S_k(idx_b) + ic_scale * randn(stream, numel(idx_b), 1);
        S_k(idx_b) = min(max(S_k(idx_b), 0), 1);
    end
end

function hist_fn = make_dde_history_fn(S_k, S0, mode, lag_max, ic_scale, k, ic_seed)
    mode = char(mode);
    switch lower(mode)
        case 'constant'
            hist_fn = @(t) S_k(:);
        case {'smooth', 'nonconstant', 'smooth_nonconstant'}
            % Deterministic smooth bounded perturbation around constant history.
            amp = 0.25 * ic_scale;
            phase = 0.7 * k + 0.01 * ic_seed;
            omega = 2 * pi / max(lag_max, eps);
            hist_fn = @(t) smooth_history(t, S_k(:), S0(:), amp, omega, phase, lag_max);
        otherwise
            error('verify_echo_state_property:InvalidDDEHistoryMode', ...
                'dde_history_mode must be ''constant'' or ''smooth''.');
    end
end

function S = smooth_history(t, S_k, S0, amp, omega, phase, lag_max)
    w = amp * sin(omega * t + phase);
    % Bound perturbation; keep resources feasible after clip in runReservoir.
    S = S_k + w * (S_k - S0 + 0.1);
    % Soft clamp towards history endpoints magnitude.
    if t < -lag_max
        S = S_k;
    end
end

function d = block_normalized_distance(diff_rows, layout, scales)
    n_t = size(diff_rows, 1);
    d = zeros(n_t, 1);
    for ti = 1:n_t
        v = diff_rows(ti, :)';
        acc = 0;
        n_terms = 0;
        if ~isempty(layout.idx_x)
            acc = acc + sum((v(layout.idx_x) / scales.x).^2);
            n_terms = n_terms + numel(layout.idx_x);
        end
        idx_a = [layout.idx_a_E(:); layout.idx_a_I(:)];
        if ~isempty(idx_a)
            acc = acc + sum((v(idx_a) / scales.a).^2);
            n_terms = n_terms + numel(idx_a);
        end
        idx_b = [layout.idx_b_E(:); layout.idx_b_I(:)];
        if ~isempty(idx_b)
            acc = acc + sum((v(idx_b) / scales.b).^2);
            n_terms = n_terms + numel(idx_b);
        end
        d(ti) = sqrt(acc) / sqrt(max(n_terms, 1));
    end
end

function [d_max, d_med, d_p90] = pairwise_distance_stats(Xw, n_state)
    n_t = size(Xw, 1);
    n_ic = size(Xw, 3);
    d_max = zeros(n_t, 1);
    d_med = zeros(n_t, 1);
    d_p90 = zeros(n_t, 1);
    pairs = nchoosek(1:n_ic, 2);
    for ti = 1:n_t
        dists = zeros(size(pairs, 1), 1);
        for p = 1:size(pairs, 1)
            da = Xw(ti, :, pairs(p, 1)) - Xw(ti, :, pairs(p, 2));
            dists(p) = norm(da) / sqrt(n_state);
        end
        d_max(ti) = max(dists);
        d_med(ti) = median(dists);
        d_p90(ti) = prctile(dists, 90);
    end
end

function h = state_digest(S)
    bytes = typecast(double(S(:)), 'uint8');
    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(bytes);
    digest = typecast(md.digest(), 'uint8');
    h = lower(sprintf('%02x', digest(1:8)));
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end
