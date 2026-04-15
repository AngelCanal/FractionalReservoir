function stats = compute_adaptation_STD_statistics(esn_or_params, S_history, options)
% compute_adaptation_STD_statistics
% Analyse adaptation (a) and short-term depression (b) state variables over time.
%
% Usage:
%   stats = compute_adaptation_STD_statistics(esn, S_history);
%   stats = compute_adaptation_STD_statistics(params, S_history);
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct
%   S_history     - (T x N_state) SRNN state history
%   options       - struct (optional)
%       .time_stride     (default 1)
%       .smooth_win      (default 50)   for transition detection
%       .transition_z    (default 3.0)  threshold in std units
%
% Output:
%   stats - struct with summary distributions, autocorrs, coupling and transitions

    if nargin < 3 || isempty(options)
        options = struct();
    end

    time_stride = getFieldOrDefault(options, 'time_stride', 1);
    smooth_win = getFieldOrDefault(options, 'smooth_win', 50);
    transition_z = getFieldOrDefault(options, 'transition_z', 3.0);

    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
        params = exportParams(esn);
    else
        params = esn_or_params;
        esn = SRNN_ESN(params);
    end

    T = size(S_history, 1);
    t_idx = 1:time_stride:T;
    nT = numel(t_idx);

    % Dimensions
    len_a_E = params.n_E * params.n_a_E;
    len_a_I = params.n_I * params.n_a_I;
    len_b_E = params.n_E * params.n_b_E;
    len_b_I = params.n_I * params.n_b_I;
    n = params.n;

    aE_mean = zeros(nT, 1);
    aI_mean = zeros(nT, 1);
    bE_mean = zeros(nT, 1);
    bI_mean = zeros(nT, 1);
    r_mean = zeros(nT, 1);

    % Collect time series of means (and optionally full distributions later)
    for ii = 1:nT
        S = S_history(t_idx(ii), :)';
        [a_E, a_I, b_E, b_I] = unpack_a_b(S, params, len_a_E, len_a_I, len_b_E, len_b_I, n);

        if ~isempty(a_E)
            aE_mean(ii) = mean(a_E, 'all');
        end
        if ~isempty(a_I)
            aI_mean(ii) = mean(a_I, 'all');
        end
        if ~isempty(b_E)
            bE_mean(ii) = mean(b_E, 'all');
        else
            bE_mean(ii) = 1;
        end
        if ~isempty(b_I)
            bI_mean(ii) = mean(b_I, 'all');
        else
            bI_mean(ii) = 1;
        end

        r = esn.computeRates(S);
        r_mean(ii) = mean(r);
    end

    stats = struct();
    stats.options = options;
    stats.time_indices = t_idx(:);
    stats.aE_mean_t = aE_mean;
    stats.aI_mean_t = aI_mean;
    stats.bE_mean_t = bE_mean;
    stats.bI_mean_t = bI_mean;
    stats.r_mean_t = r_mean;

    % Summary statistics
    stats.aE_mean = mean(aE_mean);
    stats.aE_std = std(aE_mean);
    stats.aI_mean = mean(aI_mean);
    stats.aI_std = std(aI_mean);
    stats.bE_mean = mean(bE_mean);
    stats.bE_std = std(bE_mean);
    stats.bI_mean = mean(bI_mean);
    stats.bI_std = std(bI_mean);

    % Depression-rate coupling (correlation)
    stats.corr_bE_r = corr(bE_mean, r_mean, 'Rows', 'complete');
    stats.corr_bI_r = corr(bI_mean, r_mean, 'Rows', 'complete');

    % Autocorrelation of b (coarse)
    maxLag = min(1000, max(10, floor(nT/4)));
    stats.autocorr_bE = autocorr_safe(bE_mean, maxLag);
    stats.autocorr_bI = autocorr_safe(bI_mean, maxLag);

    % Transition detection on smoothed population rate
    r_s = smoothdata(r_mean, 'movmean', max(3, smooth_win));
    dr = [0; diff(r_s)];
    thr = transition_z * std(dr);
    trans_idx = find(abs(dr) > thr);
    stats.transition_indices = trans_idx(:);
    stats.transition_times = t_idx(trans_idx(:));

    if ~isempty(trans_idx)
        stats.bE_at_transitions = bE_mean(trans_idx);
        stats.bI_at_transitions = bI_mean(trans_idx);
        stats.r_at_transitions = r_mean(trans_idx);
    else
        stats.bE_at_transitions = [];
        stats.bI_at_transitions = [];
        stats.r_at_transitions = [];
    end
end

function params = exportParams(esn)
    params = struct();
    params.n = esn.n;
    params.n_E = esn.n_E;
    params.n_I = esn.n_I;
    params.n_a_E = esn.n_a_E;
    params.n_a_I = esn.n_a_I;
    params.n_b_E = esn.n_b_E;
    params.n_b_I = esn.n_b_I;
end

function [a_E, a_I, b_E, b_I] = unpack_a_b(S, params, len_a_E, len_a_I, len_b_E, len_b_I, n)
    current_idx = 0;
    if len_a_E > 0
        a_E = reshape(S(current_idx + (1:len_a_E)), params.n_E, params.n_a_E);
    else
        a_E = [];
    end
    current_idx = current_idx + len_a_E;

    if len_a_I > 0
        a_I = reshape(S(current_idx + (1:len_a_I)), params.n_I, params.n_a_I);
    else
        a_I = [];
    end
    current_idx = current_idx + len_a_I;

    if len_b_E > 0
        b_E = S(current_idx + (1:len_b_E));
    else
        b_E = [];
    end
    current_idx = current_idx + len_b_E;

    if len_b_I > 0
        b_I = S(current_idx + (1:len_b_I));
    else
        b_I = [];
    end
    current_idx = current_idx + len_b_I;

    %#ok<NASGU>
    x = S(current_idx + (1:n)); %#ok<NASGU>
end

function ac = autocorr_safe(x, maxLag)
    x = x(:);
    x = x - mean(x, 'omitnan');
    ac = zeros(maxLag+1, 1);
    denom = sum(x.^2) + eps;
    for k = 0:maxLag
        ac(k+1) = sum(x(1:end-k) .* x(1+k:end)) / denom;
    end
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

