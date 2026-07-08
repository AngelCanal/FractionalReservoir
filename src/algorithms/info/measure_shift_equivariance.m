function se = measure_shift_equivariance(esn_or_params, options)
% measure_shift_equivariance
% Empirically test temporal (time-shift) invariance of the reservoir map.
%
% A time-invariant, fading-memory system F obeys shift-equivariance:
%   F[u(. - s)](t)  ==  F[u](t - s)     for large t (after transients).
% This is the operational content of "temporal invariance" for a driven
% reservoir: the representation of an input does not depend on absolute time,
% only on the input history relative to now. We verify it by driving the same
% reservoir with an input and with a time-shifted copy of that input, then
% comparing the feature trajectories on their overlapping, post-washout window.
%
% Usage:
%   se = measure_shift_equivariance(esn);
%   se = measure_shift_equivariance(params, struct('shifts', [5 10 20]));
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct
%   options - struct (optional)
%       .T          (default 3000)  base input length
%       .washout    (default 800)
%       .shifts     (default [5 10 20 40])  shifts in samples
%       .seed       (default 11)
%       .input_scale(default 0.2)
%       .feature_mode (default 'x')
%
% Output:
%   se - struct
%       .shifts
%       .nrmse_per_shift   (numel(shifts) x 1) normalised RMSE of the
%                          equivariance mismatch (0 = perfect invariance)
%       .options

    if nargin < 2 || isempty(options)
        options = struct();
    end
    T = getFieldOrDefault(options, 'T', 3000);
    washout = getFieldOrDefault(options, 'washout', 800);
    shifts = getFieldOrDefault(options, 'shifts', [5 10 20 40]);
    seed = getFieldOrDefault(options, 'seed', 11);
    input_scale = getFieldOrDefault(options, 'input_scale', 0.2);
    feature_mode = getFieldOrDefault(options, 'feature_mode', 'x');

    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
    else
        esn = SRNN_ESN(esn_or_params);
    end
    esn.which_states = feature_mode;

    max_shift = max(shifts);
    rng(seed);
    % Build a long base input; the shifted input is the same signal read from
    % an earlier point, so both share identical local history for large t.
    u_full = input_scale * randn(T + max_shift, 1);

    % Reference run on the tail (indices max_shift+1 : end)
    u_ref = u_full((max_shift + 1):end);
    esn.resetState();
    X_ref = esn.runReservoir(u_ref);

    nrmse = zeros(numel(shifts), 1);
    for si = 1:numel(shifts)
        s = shifts(si);
        % Shifted input starts s samples earlier -> its sample t equals
        % u_ref(t - s) for t > s.
        u_shift = u_full((max_shift - s + 1):(end - s));
        esn.resetState();
        X_shift = esn.runReservoir(u_shift);

        % Compare X_shift(t) with X_ref(t - s) on the post-washout overlap
        t0 = washout + 1;
        idx_shift = t0:size(X_shift, 1);
        idx_ref = idx_shift - s;
        valid = idx_ref >= 1;
        idx_shift = idx_shift(valid);
        idx_ref = idx_ref(valid);

        D = X_shift(idx_shift, :) - X_ref(idx_ref, :);
        rmse = sqrt(mean(D(:).^2));
        scale = std(X_ref(idx_ref, :), 0, 'all');
        nrmse(si) = rmse / max(scale, eps);
    end

    se = struct();
    se.shifts = shifts(:);
    se.nrmse_per_shift = nrmse;
    se.options = options;
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end
