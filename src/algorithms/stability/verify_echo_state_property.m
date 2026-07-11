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
% Usage:
%   esp = verify_echo_state_property(esn, U);
%   esp = verify_echo_state_property(params, U, opts);
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct (ignored if simulate_fn set)
%   U             - (T x n_inputs) input sequence
%   options       - struct (optional)
%       .n_ic              (default 8) initial conditions / histories per input
%       .n_input_seeds     (default 1) number of input realizations
%       .input_seed        (default 1) base seed for input stream
%       .ic_seed           (default 1000) base seed for IC stream
%       .ic_scale          (default 0.1)
%       .washout_steps     (default 200) discarded before distance stats
%       .tail_window       (default [0.7 1.0]) fraction of post-washout time
%       .distance_floor    (default 1e-12) added inside log(distance+floor)
%       .slope_contracting_max (default -1e-3) upper bound for contracting slope
%       .slope_expanding_min   (default 1e-3)
%       .ci_level          (default 0.95)
%       .min_tail_points   (default 20) below this => inconclusive
%       .feature_mode      (default 'x')
%       .verbose           (default true)
%       .simulate_fn       optional @(U,S0)->X (T x n_state) override
%       .n_state           required with simulate_fn if not inferable
%
% DDE note: when params.lags is nonempty, each IC is a constant history only;
% that limitation is recorded in esp.dde_constant_history_limitation.

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
    ci_level = getFieldOrDefault(options, 'ci_level', 0.95);
    min_tail_points = getFieldOrDefault(options, 'min_tail_points', 20);
    feature_mode = getFieldOrDefault(options, 'feature_mode', 'x');
    verbose = getFieldOrDefault(options, 'verbose', true);
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
    dde_limitation = false;
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
    else
        if isa(esn_or_params, 'SRNN_ESN')
            esn = esn_or_params;
        else
            esn = SRNN_ESN(esn_or_params);
        end
        params = esn.params;
        esn.which_states = feature_mode;
        esn.resetState();
        S0 = esn.getState();
        n_state = numel(S0);
        layout = state_layout(params);
        idx_b_E = layout.idx_b_E;
        idx_b_I = layout.idx_b_I;
        dde_limitation = isfield(params, 'lags') && ~isempty(params.lags);
        simulate_fn = [];
    end

    T = size(U, 1);
    input_stream = RandStream('mt19937ar', 'Seed', input_seed);
    ic_stream = RandStream('mt19937ar', 'Seed', ic_seed);

    slopes = [];
    pair_meta = struct('input_seed_index', {}, 'pair', {}, 'slope', {});
    dist_max_all = [];
    dist_med_all = [];
    dist_p90_all = [];
    t_idx = (washout_steps + 1):T;
    n_t = numel(t_idx);

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

        X_all = zeros(T, n_state, n_ic);
        for k = 1:n_ic
            S_k = S0 + ic_scale * randn(ic_stream, size(S0));
            if ~isempty(idx_b_E)
                S_k(idx_b_E) = 1;
            end
            if ~isempty(idx_b_I)
                S_k(idx_b_I) = 1;
            end
            if has_sim
                X_feat = simulate_fn(U_s, S_k);
            else
                esn.setState(S_k);
                [X_feat, ~] = esn.runReservoir(U_s);
            end
            if size(X_feat, 2) ~= n_state
                % Feature width may differ from packed state; use returned width
                if k == 1 && s == 1
                    n_state = size(X_feat, 2);
                    X_all = zeros(T, n_state, n_ic);
                end
            end
            X_all(:, 1:size(X_feat, 2), k) = X_feat;
        end

        [d_max, d_med, d_p90] = pairwise_distance_stats(X_all(t_idx, :, :), n_state);
        dist_max_all = [dist_max_all, d_max]; %#ok<AGROW>
        dist_med_all = [dist_med_all, d_med]; %#ok<AGROW>
        dist_p90_all = [dist_p90_all, d_p90]; %#ok<AGROW>

        % Pairwise slopes over the preregistered tail window
        i0 = max(1, floor(tail_window(1) * n_t));
        i1 = min(n_t, max(i0 + 1, ceil(tail_window(2) * n_t)));
        tail_idx = i0:i1;
        if numel(tail_idx) < min_tail_points
            continue;
        end
        tt = (0:numel(tail_idx)-1)';
        pairs = nchoosek(1:n_ic, 2);
        for p = 1:size(pairs, 1)
            a = pairs(p, 1);
            b = pairs(p, 2);
            diff_ab = X_all(t_idx(tail_idx), :, a) - X_all(t_idx(tail_idx), :, b);
            dist = sqrt(sum(diff_ab.^2, 2)) / sqrt(n_state);
            y = log(dist + distance_floor);
            if ~all(isfinite(y))
                continue;
            end
            P = polyfit(tt, y, 1);
            slopes(end+1, 1) = P(1); %#ok<AGROW>
            pair_meta(end+1).input_seed_index = s; %#ok<AGROW>
            pair_meta(end).pair = pairs(p, :);
            pair_meta(end).slope = P(1);
        end
    end

    esp = struct();
    esp.options = options;
    esp.n_ic = n_ic;
    esp.n_input_seeds = n_input_seeds;
    esp.t_idx = t_idx(:);
    esp.n_state = n_state;
    esp.distance_floor = distance_floor;
    esp.tail_window = tail_window;
    esp.distance_max = dist_max_all;
    esp.distance_median = dist_med_all;
    esp.distance_p90 = dist_p90_all;
    if ~isempty(dist_max_all)
        esp.convergence_curve = mean(dist_max_all, 2);
        esp.final_spread = esp.convergence_curve(end);
    else
        esp.convergence_curve = [];
        esp.final_spread = nan;
    end
    esp.slopes = slopes;
    esp.pair_meta = pair_meta;
    esp.dde_constant_history_limitation = dde_limitation;
    if dde_limitation
        esp.dde_limitation_note = [ ...
            'DDE mode: each initial condition denotes a constant history only; ', ...
            'this does not exhaust the infinite-dimensional history space.'];
    end

    if numel(slopes) < 1 || n_t < min_tail_points
        esp.slope_mean = nan;
        esp.slope_ci = [nan, nan];
        esp.classification = 'inconclusive';
        esp.classification_reason = 'insufficient_duration_or_pairs';
    else
        esp.slope_mean = mean(slopes);
        esp.slope_std = std(slopes);
        n_s = numel(slopes);
        % Normal approx CI across input/IC pairs
        z = sqrt(2) * erfinv(ci_level);
        half = z * esp.slope_std / max(sqrt(n_s), 1);
        esp.slope_ci = [esp.slope_mean - half, esp.slope_mean + half];
        ci = esp.slope_ci;
        if ci(2) < slope_contracting_max
            esp.classification = 'empirically_contracting_on_test_set';
            esp.classification_reason = 'slope_ci_above_contracting_threshold';
        elseif ci(1) > slope_expanding_min
            esp.classification = 'not_contracting_on_test_set';
            esp.classification_reason = 'slope_ci_above_expanding_threshold';
        else
            esp.classification = 'inconclusive';
            esp.classification_reason = 'slope_ci_straddles_zero_or_weak';
        end
        % Fix reason string for contracting
        if strcmp(esp.classification, 'empirically_contracting_on_test_set')
            esp.classification_reason = 'slope_ci_below_contracting_threshold';
        end
    end

    % Sensitivity diagnostics (vary duration / IC scale / seed / norm)
    esp.sensitivity = struct( ...
        'washout_steps', washout_steps, ...
        'ic_scale', ic_scale, ...
        'input_seed', input_seed, ...
        'ic_seed', ic_seed, ...
        'norm', 'euclidean_over_sqrt_n_state', ...
        'duration_steps', T, ...
        'post_washout_steps', n_t);

    if verbose
        fprintf('Empirical convergence: class=%s  slope_mean=%.3e  CI=[%.3e, %.3e]\n', ...
            esp.classification, esp.slope_mean, esp.slope_ci(1), esp.slope_ci(2));
    end
end

function [d_max, d_med, d_p90] = pairwise_distance_stats(Xw, n_state)
    % Xw: n_t x n_feat x n_ic
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

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end
