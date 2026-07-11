function [LLE, local_lya, finite_lya, t_lya] = benettin_algorithm(X, t, dt, fs, d0, T, lya_dt, params, ode_options, dynamics_func, t_ex, u_ex, ode_solver)
% benettin_algorithm  Legacy wrapper around benettin_lle_ode (ODE-only).
%
% Prefer benettin_lle_ode with an options struct for new code.
% This wrapper extracts the fiducial state at T(1) from the precomputed
% trajectory X(t), then evolves fiducial and perturbed trajectories with
% the same dynamics_func over [T(1), T(2)].

    %#ok<INUSD>  % dt, fs, t_ex, u_ex retained for signature compatibility

    if isfield(params, 'lags') && ~isempty(params.lags)
        error('MESN:DelayedLyapunovUnsupported', ...
            'Benettin Lyapunov analysis is ODE-only; nonempty delays are unsupported.');
    end

    T_interval = T(:).';
    if numel(T_interval) ~= 2
        error('benettin_algorithm:InvalidT', 'T must be [T_start, T_end]');
    end

    % State at or after analysis start
    idx0 = find(t >= T_interval(1) - 10*eps(T_interval(1)), 1, 'first');
    if isempty(idx0)
        error('benettin_algorithm:StartNotInTrajectory', ...
            'No trajectory sample at or after T_interval(1)=%g', T_interval(1));
    end
    if t(end) < T_interval(2) - 1e-12 * max(1, abs(T_interval(2)))
        error('benettin_algorithm:EndBeyondTrajectory', ...
            'Trajectory ends before T_interval(2)');
    end

    x0 = X(idx0, :).';
    t0_actual = t(idx0);
    % Honor requested start: analysis begins at max(T(1), first available sample)
    T_use = [t0_actual, T_interval(2)];

    opts = struct();
    opts.odefun = dynamics_func;
    opts.x0 = x0;
    opts.T_interval = T_use;
    opts.lya_dt = lya_dt;
    opts.d0 = d0;
    opts.seed = 1;
    opts.ode_solver = ode_solver;
    opts.ode_options = ode_options;
    opts.params = params;

    result = benettin_lle_ode(opts);
    LLE = result.LLE;
    local_lya = result.local_lya;
    finite_lya = result.finite_lya;
    t_lya = result.t_lya;
end
