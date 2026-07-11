function mi = compute_MI_lag_curve(x_history, u, options)
% compute_MI_lag_curve
% Lag-resolved mutual information curve between reservoir state and past input.
%
% For each lag k, computes MI(x_i(t), u(t-k)) for a subset of neurons and
% averages across neurons. Uses mutual_info_SISO (histogram plug-in with
% train-fitted bin edges and a deterministic permutation null).
%
% Usage:
%   mi = compute_MI_lag_curve(x_history, u);
%
% Inputs:
%   x_history - (T x n) state features (typically x or r)
%   u         - (T x 1) input sequence aligned with x_history
%   options   - struct (optional)
%       .K_max       (default 200)
%       .washout     (default 200)
%       .n_bins_u    (default 16)
%       .n_bins_x    (default 16)
%       .max_neurons (default 50)
%       .seed        (default 1)
%       .n_null      (default 10)
%       .train_fraction (default 0.5)
%
% Output:
%   mi - struct
%       .lags
%       .MI_corrected_mean
%       .MI_uncorrected_mean
%       .MI_null_mean
%       .status_per_lag
%       .options

    if nargin < 3 || isempty(options)
        options = struct();
    end

    K_max = getFieldOrDefault(options, 'K_max', 200);
    washout = getFieldOrDefault(options, 'washout', 200);
    n_bins_u = getFieldOrDefault(options, 'n_bins_u', 16);
    n_bins_x = getFieldOrDefault(options, 'n_bins_x', 16);
    max_neurons = getFieldOrDefault(options, 'max_neurons', 50);
    seed = getFieldOrDefault(options, 'seed', 1);
    n_null = getFieldOrDefault(options, 'n_null', 10);
    train_fraction = getFieldOrDefault(options, 'train_fraction', 0.5);
    min_expected_occupancy = getFieldOrDefault(options, 'min_expected_occupancy', 1);

    T = size(x_history, 1);
    n = size(x_history, 2);
    if size(u, 1) ~= T
        error('compute_MI_lag_curve:SizeMismatch', 'u and x_history must have the same length');
    end

    if T <= washout + K_max + 5
        error('compute_MI_lag_curve:ShortT', 'Trajectory too short for washout and K_max');
    end

    stream = RandStream('mt19937ar', 'Seed', seed);
    n_use = min(max_neurons, n);
    idx = randperm(stream, n, n_use);

    % Post-washout signals
    x = x_history((washout+1):end, idx);
    u2 = u((washout+1):end, 1);
    T2 = size(x, 1);

    MIc = zeros(K_max, 1);
    MIu = zeros(K_max, 1);
    MIn = zeros(K_max, 1);
    status_per_lag = strings(K_max, 1);

    warn_state = warning('off', 'mutual_info_SISO:LowOccupancy');
    cleanup = onCleanup(@() warning(warn_state));

    for k = 1:K_max
        % Align: x(t) with u(t-k)
        xk = x((k+1):end, :);
        uk = u2(1:(end-k));

        mi_c_neur = zeros(n_use, 1);
        mi_u_neur = zeros(n_use, 1);
        mi_n_neur = zeros(n_use, 1);
        statuses = strings(n_use, 1);
        for j = 1:n_use
            mi_opts = struct( ...
                'n_bins_in', n_bins_u, ...
                'n_bins_out', n_bins_x, ...
                'n_null', n_null, ...
                'seed', seed + 1000 * k + j, ...
                'train_fraction', train_fraction, ...
                'min_expected_occupancy', min_expected_occupancy);
            mi_res = mutual_info_SISO(uk, xk(:, j), mi_opts);
            mi_c_neur(j) = mi_res.corrected;
            mi_u_neur(j) = mi_res.raw;
            mi_n_neur(j) = mi_res.null_mean;
            statuses(j) = string(mi_res.status);
        end

        MIc(k) = mean(mi_c_neur);
        MIu(k) = mean(mi_u_neur);
        MIn(k) = mean(mi_n_neur);
        if any(statuses ~= "ok")
            status_per_lag(k) = "unsupported";
        else
            status_per_lag(k) = "ok";
        end
    end

    mi = struct();
    mi.options = options;
    mi.lags = (1:K_max)';
    mi.MI_corrected_mean = MIc;
    mi.MI_uncorrected_mean = MIu;
    mi.MI_null_mean = MIn;
    mi.status_per_lag = status_per_lag;
    mi.n_neurons_used = n_use;
    mi.neuron_indices = idx(:);
    mi.T_effective = T2;
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end
