function stats = compute_coding_statistics(esn_or_params, S_history, options)
% compute_coding_statistics
% Compute biologically-inspired coding statistics from a reservoir trajectory.
%
% Usage:
%   stats = compute_coding_statistics(esn, S_history);
%   stats = compute_coding_statistics(params, S_history);
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct
%   S_history     - (T x N_state) SRNN state history
%   options       - struct (optional)
%       .time_stride     (default 1)  subsample time for expensive computations
%       .silent_thresh   (default 1e-3)
%
% Output:
%   stats - struct with rate distributions, silence fractions, E/I balance metrics

    if nargin < 3 || isempty(options)
        options = struct();
    end

    time_stride = getFieldOrDefault(options, 'time_stride', 1);
    silent_thresh = getFieldOrDefault(options, 'silent_thresh', 1e-3);

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
    n = params.n;

    rates = zeros(nT, n);
    b_all = zeros(nT, n);

    for ii = 1:nT
        S = S_history(t_idx(ii), :)';
        r = esn.computeRates(S);
        rates(ii, :) = r(:)';

        % Extract b vector from state (for currents)
        [~, b] = extract_b_from_state(S, params);
        b_all(ii, :) = b(:)';
    end

    % Firing rate distributions
    mean_rate = mean(rates, 1);
    stats = struct();
    stats.options = options;
    stats.mean_rate_all = mean_rate(:);
    stats.mean_rate_E = mean_rate(params.E_indices(:));
    stats.mean_rate_I = mean_rate(params.I_indices(:));

    stats.silent_fraction_all = mean(mean_rate < silent_thresh);
    stats.silent_fraction_E = mean(stats.mean_rate_E < silent_thresh);
    stats.silent_fraction_I = mean(stats.mean_rate_I < silent_thresh);

    stats.rate_mean_population = mean(mean_rate);
    stats.rate_std_population = std(mean_rate);

    % E/I balance at input-current level (recurrent contribution only)
    % current(t) = W * (b .* r)
    W = params.W;
    E = params.E_indices(:);
    I = params.I_indices(:);

    curr_E = zeros(nT, n);
    curr_I = zeros(nT, n);
    for ii = 1:nT
        br = (b_all(ii, :)' .* rates(ii, :)');
        curr_E(ii, :) = (W(:, E) * br(E))';
        curr_I(ii, :) = (W(:, I) * br(I))';
    end

    mean_curr_E = mean(curr_E, 1);
    mean_curr_I = mean(curr_I, 1);
    stats.mean_recurrent_current_E = mean_curr_E(:);
    stats.mean_recurrent_current_I = mean_curr_I(:);

    denom = abs(mean_curr_I) + eps;
    stats.EI_balance_ratio = (abs(mean_curr_E) ./ denom).';

    % Sparseness (population)
    % Treves-Rolls sparseness per time, then average
    a_t = zeros(nT, 1);
    for ii = 1:nT
        r = rates(ii, :);
        if all(r == 0)
            a_t(ii) = 1;
        else
            a_t(ii) = (mean(r)^2) / mean(r.^2 + eps);
        end
    end
    stats.population_sparseness = mean(a_t);
end

function params = exportParams(esn)
    params = struct();
    params.n = esn.n;
    params.n_E = esn.n_E;
    params.n_I = esn.n_I;
    params.E_indices = esn.E_indices;
    params.I_indices = esn.I_indices;
    params.n_a_E = esn.n_a_E;
    params.n_a_I = esn.n_a_I;
    params.n_b_E = esn.n_b_E;
    params.n_b_I = esn.n_b_I;
    params.tau_d = esn.tau_d;
    params.W = esn.W;
end

function [b_EI, b] = extract_b_from_state(S, params)
    current_idx = 0;
    len_a_E = params.n_E * params.n_a_E;
    len_a_I = params.n_I * params.n_a_I;
    len_b_E = params.n_E * params.n_b_E;
    len_b_I = params.n_I * params.n_b_I;
    current_idx = current_idx + len_a_E + len_a_I;

    b_E = [];
    b_I = [];
    if len_b_E > 0
        b_E = S(current_idx + (1:len_b_E));
    end
    current_idx = current_idx + len_b_E;
    if len_b_I > 0
        b_I = S(current_idx + (1:len_b_I));
    end

    b = ones(params.n, 1);
    if ~isempty(b_E)
        b(params.E_indices) = b_E;
    end
    if ~isempty(b_I)
        b(params.I_indices) = b_I;
    end

    b_EI = struct('b_E', b_E, 'b_I', b_I);
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

