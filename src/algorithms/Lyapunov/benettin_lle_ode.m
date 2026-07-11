function result = benettin_lle_ode(options)
% benettin_lle_ode  ODE-only Benettin largest Lyapunov exponent (clean API).
%
% result = benettin_lle_ode(options)
%
% Required options:
%   .odefun       - RHS @(t,x) matching the fiducial and perturbed trajectories
%   .x0           - column state at analysis start (T_interval(1))
%   .T_interval   - [T_start, T_end]; first rescaling at/after T_start;
%                   log-growth accumulation excludes times before T_start
%
% Optional:
%   .lya_dt       - nominal rescaling interval (default 0.5)
%   .d0           - perturbation magnitude (default 1e-6)
%   .seed         - local RNG seed for initial perturbation direction (default 1)
%   .ode_solver   - function handle (default @ode45)
%   .ode_options  - odeset struct (default RelTol/AbsTol 1e-8)
%   .params       - if present with nonempty .lags, errors (ODE-only)
%
% Output struct:
%   .LLE, .local_lya, .finite_lya, .t_lya, .segment_durations
%   .sum_log_growth, .total_time, .status ('ok' or named failure)

    if nargin < 1 || isempty(options)
        error('benettin_lle_ode:MissingOptions', 'options struct is required');
    end

    if isfield(options, 'params') && isfield(options.params, 'lags') && ...
            ~isempty(options.params.lags)
        error('MESN:DelayedLyapunovUnsupported', ...
            'Benettin Lyapunov analysis is ODE-only; nonempty delays are unsupported.');
    end

    odefun = options.odefun;
    x0 = options.x0(:);
    T_interval = options.T_interval(:).';
    if numel(T_interval) ~= 2 || ~(T_interval(2) > T_interval(1))
        error('benettin_lle_ode:InvalidInterval', ...
            'T_interval must be [T_start, T_end] with T_end > T_start');
    end

    lya_dt = get_opt(options, 'lya_dt', 0.5);
    d0 = get_opt(options, 'd0', 1e-6);
    seed = get_opt(options, 'seed', 1);
    ode_solver = get_opt(options, 'ode_solver', @ode45);
    ode_options = get_opt(options, 'ode_options', odeset('RelTol', 1e-8, 'AbsTol', 1e-10));

    if ~(isscalar(lya_dt) && isfinite(lya_dt) && lya_dt > 0)
        error('benettin_lle_ode:InvalidLyaDt', 'lya_dt must be a positive scalar');
    end
    if ~(isscalar(d0) && isfinite(d0) && d0 > 0)
        error('benettin_lle_ode:InvalidD0', 'd0 must be a positive scalar');
    end

    n = numel(x0);
    stream = RandStream('mt19937ar', 'Seed', seed);
    dir0 = randn(stream, n, 1);
    nrm = norm(dir0);
    if ~(isfinite(nrm) && nrm > 0)
        error('benettin_lle_ode:NumericalFailure', ...
            'Initial perturbation direction is zero or nonfinite');
    end
    pert_dir = dir0 / nrm;

    T_start = T_interval(1);
    T_end = T_interval(2);

    % First rescaling time at or after requested start
    t = T_start;
    x_fid = x0;

    local_lya = [];
    finite_lya = [];
    t_lya = [];
    segment_durations = [];
    sum_log = 0;
    total_time = 0;

    while t + 0.5 * lya_dt < T_end
        t_seg_end = min(t + lya_dt, T_end);
        actual_dt = t_seg_end - t;
        if actual_dt <= 0
            break;
        end

        x_pert0 = x_fid + d0 * pert_dir;

        t_span = [t, t_seg_end];
        [tf, Xf] = ode_solver(odefun, t_span, x_fid, ode_options);
        [tp, Xp] = ode_solver(odefun, t_span, x_pert0, ode_options);
        %#ok<ASGLU>

        x_fid_end = Xf(end, :).';
        x_pert_end = Xp(end, :).';
        % Prefer solver-reported end times for duration bookkeeping
        actual_dt = min(tf(end), tp(end)) - t;
        if actual_dt <= 0
            error('benettin_lle_ode:NumericalFailure', ...
                'Non-positive segment duration at t=%g', t);
        end

        delta = x_pert_end - x_fid_end;
        d_k = norm(delta);
        if ~(isfinite(d_k) && d_k > 0)
            error('benettin_lle_ode:NumericalFailure', ...
                'Benettin numerical failure: zero_or_nonfinite_separation_at_t_%g', t);
        end

        stretch = log(d_k / d0);
        loc = stretch / actual_dt;

        % Accumulation excludes washout: only segments with start >= T_start
        % (all segments here start at/after T_start by construction)
        sum_log = sum_log + stretch;
        total_time = total_time + actual_dt;
        finite = sum_log / total_time;

        local_lya(end+1, 1) = loc; %#ok<AGROW>
        finite_lya(end+1, 1) = finite; %#ok<AGROW>
        t_lya(end+1, 1) = t; %#ok<AGROW>
        segment_durations(end+1, 1) = actual_dt; %#ok<AGROW>

        pert_dir = delta / d_k;
        x_fid = x_fid_end;
        t = t + actual_dt;
    end

    if total_time <= 0 || isempty(finite_lya)
        error('benettin_lle_ode:EmptyWindow', ...
            'No Lyapunov segments inside T_interval=[%g,%g]', T_start, T_end);
    end

    result = struct();
    result.LLE = finite_lya(end);
    result.local_lya = local_lya;
    result.finite_lya = finite_lya;
    result.t_lya = t_lya;
    result.segment_durations = segment_durations;
    result.sum_log_growth = sum_log;
    result.total_time = total_time;
    result.T_interval = T_interval;
    result.status = 'ok';
end

function v = get_opt(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
