function result = lyapunov_spectrum_qr_ode(options)
% lyapunov_spectrum_qr_ode  ODE-only QR Lyapunov spectrum (clean API).
%
% Co-integrates fiducial state and tangent matrix over each QR interval,
% evaluating jacobian_fun along the evolving state. Uses positive-diagonal
% QR sign convention. Accumulation starts at T_interval(1) (washout).
%
% Required options:
%   .odefun        - @(t,x) RHS
%   .jacobian_fun  - @(t,x) Jacobian matrix
%   .x0            - state at T_interval(1)
%   .T_interval    - [T_start, T_end]
%
% Optional:
%   .lya_dt, .ode_solver, .ode_options, .params, .seed
%   .compute_benettin (default true) — also return Benettin LLE for comparison
%
% Output fields:
%   .LE_spectrum, .local_LE_spectrum_t, .finite_LE_spectrum_t
%   .t_lya, .segment_durations, .LLE_qr, .LLE_benettin, .status

    if nargin < 1 || isempty(options)
        error('lyapunov_spectrum_qr_ode:MissingOptions', 'options required');
    end
    if isfield(options, 'params') && isfield(options.params, 'lags') && ...
            ~isempty(options.params.lags)
        error('MESN:DelayedLyapunovUnsupported', ...
            'QR Lyapunov spectrum is ODE-only; nonempty delays are unsupported.');
    end

    odefun = options.odefun;
    jacfun = options.jacobian_fun;
    x0 = options.x0(:);
    T_interval = options.T_interval(:).';
    if numel(T_interval) ~= 2 || ~(T_interval(2) > T_interval(1))
        error('lyapunov_spectrum_qr_ode:InvalidInterval', ...
            'T_interval must be [T_start, T_end] with T_end > T_start');
    end

    lya_dt = get_opt(options, 'lya_dt', 0.5);
    ode_solver = get_opt(options, 'ode_solver', @ode45);
    ode_options = get_opt(options, 'ode_options', odeset('RelTol', 1e-8, 'AbsTol', 1e-10));
    do_ben = get_opt(options, 'compute_benettin', true);
    seed = get_opt(options, 'seed', 1);

    n = numel(x0);
    T_start = T_interval(1);
    T_end = T_interval(2);

    Q = eye(n);
    x = x0;
    t = T_start;
    sum_log = zeros(n, 1);
    total_time = 0;

    local_LE = [];
    finite_LE = [];
    t_lya = [];
    segment_durations = [];

    while t + 0.5 * lya_dt < T_end
        t_end_seg = min(t + lya_dt, T_end);
        actual_dt_nom = t_end_seg - t;
        if actual_dt_nom <= 0
            break;
        end

        y0 = [x; Q(:)];
        aug = @(tt, yy) aug_rhs(tt, yy, n, odefun, jacfun);
        [tt, YY] = ode_solver(aug, [t, t_end_seg], y0, ode_options);
        actual_dt = tt(end) - t;
        if actual_dt <= 0
            error('lyapunov_spectrum_qr_ode:NumericalFailure', ...
                'Non-positive segment duration at t=%g', t);
        end

        y_end = YY(end, :).';
        if any(~isfinite(y_end))
            error('lyapunov_spectrum_qr_ode:NumericalFailure', ...
                'Nonfinite state/tangent at t=%g', t);
        end
        x = y_end(1:n);
        Psi = reshape(y_end(n+1:end), [n, n]);

        [Q_new, R] = qr_positive_diag(Psi);
        diag_R = diag(R);
        if any(~isfinite(diag_R)) || any(abs(diag_R) <= 0)
            error('lyapunov_spectrum_qr_ode:NumericalFailure', ...
                'Nonfinite or nonpositive R diagonal at t=%g', t);
        end
        log_abs = log(abs(diag_R));

        % Washout: only accumulate for segments starting at/after T_start
        sum_log = sum_log + log_abs;
        total_time = total_time + actual_dt;
        finite = sum_log / total_time;
        local = log_abs / actual_dt;

        local_LE(end+1, :) = local.'; %#ok<AGROW>
        finite_LE(end+1, :) = finite.'; %#ok<AGROW>
        t_lya(end+1, 1) = t; %#ok<AGROW>
        segment_durations(end+1, 1) = actual_dt; %#ok<AGROW>

        Q = Q_new;
        t = t + actual_dt;
    end

    if total_time <= 0
        error('lyapunov_spectrum_qr_ode:EmptyWindow', ...
            'No QR segments inside T_interval');
    end

    LE_spectrum = sum_log / total_time;
    [LE_sorted, sort_idx] = sort(LE_spectrum, 'descend');

    result = struct();
    result.LE_spectrum = LE_sorted;
    result.LE_spectrum_unsorted = LE_spectrum;
    result.sort_idx = sort_idx;
    result.local_LE_spectrum_t = local_LE(:, sort_idx);
    result.finite_LE_spectrum_t = finite_LE(:, sort_idx);
    result.t_lya = t_lya;
    result.segment_durations = segment_durations;
    result.total_time = total_time;
    result.LLE_qr = LE_sorted(1);
    result.T_interval = T_interval;
    result.status = 'ok';

    result.LLE_benettin = NaN;
    if do_ben
        ben = benettin_lle_ode(struct( ...
            'odefun', odefun, ...
            'x0', x0, ...
            'T_interval', T_interval, ...
            'lya_dt', lya_dt, ...
            'd0', get_opt(options, 'd0', 1e-6), ...
            'seed', seed, ...
            'ode_solver', ode_solver, ...
            'ode_options', ode_options, ...
            'params', get_opt(options, 'params', struct())));
        result.LLE_benettin = ben.LLE;
        result.benettin = ben;
    end
end

function dy = aug_rhs(tt, yy, n, odefun, jacfun)
    x = yy(1:n);
    Psi = reshape(yy(n+1:end), [n, n]);
    dx = odefun(tt, x);
    J = jacfun(tt, x);
    dPsi = J * Psi;
    dy = [dx(:); dPsi(:)];
end

function [Q, R] = qr_positive_diag(Psi)
    [Q, R] = qr(Psi, 0);
    d = sign(diag(R));
    d(d == 0) = 1;
    D = diag(d);
    Q = Q * D;
    R = D * R;
end

function v = get_opt(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
