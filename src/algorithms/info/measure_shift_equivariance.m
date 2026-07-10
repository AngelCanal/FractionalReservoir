function se = measure_shift_equivariance(esn_or_params, options)
% measure_shift_equivariance
% Empirically test temporal (time-shift) equivariance of the reservoir map.
%
% A time-invariant, fading-memory system F obeys:
%   F[u(. - s)](t)  ==  F[u](t - s)     after washout.
% The shifted drive is built by delaying the same waveform and padding with a
% constant baseline (not a circular shift). Both simulations are independently
% reset. Only overlapping post-washout windows are compared after an exact
% integer sample shift of state indices.
%
% Usage:
%   se = measure_shift_equivariance(esn);
%   se = measure_shift_equivariance(params, struct('shifts', [5 10 20]));
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct
%   options - struct (optional)
%       .T            (default 3000)  waveform length (excluding prefix/pad)
%       .washout      (default 800)
%       .shifts       (default [5 10 20 40])  integer shifts in samples
%       .seed         (default 11)
%       .input_scale  (default 0.2)
%       .feature_mode (default 'x')
%       .baseline     (default 0)     pad value for zero prefix / trailing pad
%       .ode_reltol / .ode_abstol / .dde_reltol / .dde_abstol  solver opts
%
% Output:
%   se - struct
%       .shifts
%       .abs_error_per_shift   RMSE of aligned state mismatch
%       .rel_error_per_shift   RMSE / (RMS(ref) + eps)
%       .nrmse_per_shift       alias of rel_error_per_shift (compat)
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
    baseline = getFieldOrDefault(options, 'baseline', 0);

    shifts = shifts(:);
    if isempty(shifts) || any(shifts ~= floor(shifts)) || any(shifts < 0)
        error('measure_shift_equivariance:NonIntegerShift', ...
            'shifts must be nonnegative integers (exact sample counts).');
    end
    max_shift = max(shifts);

    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
    else
        esn = SRNN_ESN(esn_or_params);
    end
    esn.which_states = feature_mode;

    run_opts = struct();
    if isfield(options, 'ode_reltol'); run_opts.ode_reltol = options.ode_reltol; end
    if isfield(options, 'ode_abstol'); run_opts.ode_abstol = options.ode_abstol; end
    if isfield(options, 'dde_reltol'); run_opts.dde_reltol = options.dde_reltol; end
    if isfield(options, 'dde_abstol'); run_opts.dde_abstol = options.dde_abstol; end
    run_opts.reset_before = true;

    % Zero (baseline) prefix longer than washout + max shift, then waveform,
    % then trailing baseline pad so delayed copies keep a common length.
    prefix = washout + max_shift + 1;
    rng(seed);
    waveform = input_scale * randn(T, 1);
    u_ref = [baseline * ones(prefix, 1); waveform; baseline * ones(max_shift, 1)];

    esn.resetState();
    X_ref = esn.runReservoir(u_ref, run_opts);

    abs_err = zeros(numel(shifts), 1);
    rel_err = zeros(numel(shifts), 1);

    for si = 1:numel(shifts)
        s = shifts(si);
        % Move the same waveform later by s samples; pad with baseline (no wrap).
        u_shift = [baseline * ones(prefix + s, 1); waveform; ...
            baseline * ones(max_shift - s, 1)];

        esn.resetState();
        X_shift = esn.runReservoir(u_shift, run_opts);

        % Overlapping post-washout windows: X_shift(t) vs X_ref(t - s)
        t0 = washout + 1;
        idx_shift = t0:size(X_shift, 1);
        idx_ref = idx_shift - s;
        valid = idx_ref >= t0;
        idx_shift = idx_shift(valid);
        idx_ref = idx_ref(valid);
        if isempty(idx_shift)
            error('measure_shift_equivariance:EmptyOverlap', ...
                'No post-washout overlap for shift=%d; increase T.', s);
        end

        D = X_shift(idx_shift, :) - X_ref(idx_ref, :);
        rmse = sqrt(mean(D(:).^2));
        ref_rms = sqrt(mean(X_ref(idx_ref, :).^2, 'all'));
        abs_err(si) = rmse;
        rel_err(si) = rmse / (ref_rms + eps);
    end

    se = struct();
    se.shifts = shifts;
    se.abs_error_per_shift = abs_err;
    se.rel_error_per_shift = rel_err;
    se.nrmse_per_shift = rel_err; % backward-compatible alias
    se.options = options;
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end
