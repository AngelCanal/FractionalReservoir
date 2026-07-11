function [LE_spectrum, local_LE_spectrum_t, finite_LE_spectrum_t, t_lya_vec] = lyapunov_spectrum_qr(X_fid_traj, t_fid_traj, lya_dt_interval, params, ode_solver, ode_options_main, jacobian_func_handle, T_full_interval, N_states_sys, fs_fid)
% lyapunov_spectrum_qr  Legacy wrapper around lyapunov_spectrum_qr_ode.
%
% Prefer lyapunov_spectrum_qr_ode. This wrapper takes the fiducial state at
% T_full_interval(1) from X_fid_traj and co-integrates state + tangent with
% the provided Jacobian handle. dynamics RHS is reconstructed as autonomous
% only when a full odefun is not available; callers should prefer the clean API.

    %#ok<INUSD>  % fs_fid retained for signature compatibility

    if isfield(params, 'lags') && ~isempty(params.lags)
        error('MESN:DelayedLyapunovUnsupported', ...
            'QR Lyapunov spectrum is ODE-only; nonempty delays are unsupported.');
    end

    T_interval = T_full_interval(:).';
    idx0 = find(t_fid_traj >= T_interval(1) - 10*eps(T_interval(1)), 1, 'first');
    if isempty(idx0)
        error('lyapunov_spectrum_qr:StartNotInTrajectory', ...
            'No sample at or after T_interval(1)');
    end
    x0 = X_fid_traj(idx0, :).';
    t0 = t_fid_traj(idx0);

    % Reconstruct an approximate RHS via Jacobian*x is wrong for nonlinear systems.
    % Use finite-difference-free approach: integrate using Jacobian along
    % co-evolved state requires true odefun. For legacy MESN callers,
    % compute_lyapunov_exponents passes through the clean API instead.
    % Here we build odefun from the Jacobian linearization about the
    % instantaneous state only if params contains a marker; otherwise error.
    if isfield(params, 'legacy_qr_odefun') && ~isempty(params.legacy_qr_odefun)
        odefun = params.legacy_qr_odefun;
    else
        error('lyapunov_spectrum_qr:UseCleanAPI', ...
            ['lyapunov_spectrum_qr legacy path requires params.legacy_qr_odefun. ', ...
             'Use lyapunov_spectrum_qr_ode or compute_lyapunov_exponents.']);
    end

    jacfun = @(tt, xx) jacobian_func_handle(tt, xx, params);

    opts = struct( ...
        'odefun', odefun, ...
        'jacobian_fun', jacfun, ...
        'x0', x0, ...
        'T_interval', [t0, T_interval(2)], ...
        'lya_dt', lya_dt_interval, ...
        'ode_solver', ode_solver, ...
        'ode_options', ode_options_main, ...
        'params', params, ...
        'compute_benettin', false);
    result = lyapunov_spectrum_qr_ode(opts);

    % Unsort to original order expected by some callers, then match old outputs
    LE_spectrum = result.LE_spectrum_unsorted;
    local_LE_spectrum_t = result.local_LE_spectrum_t;
    % Re-map local/finite back to unsorted column order for legacy
    inv_sort = empty_inv_sort(result.sort_idx);
    local_LE_spectrum_t = result.local_LE_spectrum_t(:, inv_sort);
    finite_LE_spectrum_t = result.finite_LE_spectrum_t(:, inv_sort);
    t_lya_vec = result.t_lya;
    %#ok<NASGU>
    N_states_sys = N_states_sys;
end

function inv_sort = empty_inv_sort(sort_idx)
    inv_sort = zeros(size(sort_idx));
    inv_sort(sort_idx) = 1:numel(sort_idx);
end
