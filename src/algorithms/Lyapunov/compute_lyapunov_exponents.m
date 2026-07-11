function lya_results = compute_lyapunov_exponents(Lya_method, S_out, t_out, dt, fs, T_interval, params, opts, ode_solver, rhs_func, t_ex, u_ex)
% compute_lyapunov_exponents - Compute Lyapunov exponents using various methods
%
% Syntax:
%   lya_results = compute_lyapunov_exponents(Lya_method, S_out, t_out, dt, fs, T_interval, params, opts, ode_solver, rhs_func, t_ex, u_ex)
%
% Description:
%   Computes Lyapunov exponents using either Benettin's algorithm (single
%   largest exponent) or QR decomposition method (full spectrum). Returns
%   an empty struct if method is 'none'.
%
% Inputs:
%   Lya_method  - 'benettin', 'qr', or 'none'
%   S_out       - State trajectory (nt x N_sys_eqs)
%   t_out       - Time vector (nt x 1)
%   dt          - Integration time step (seconds)
%   fs          - Sampling frequency (Hz)
%   T_interval  - [T_start, T_end] time interval for analysis
%   params      - SRNN parameters struct
%   opts        - ODE solver options
%   ode_solver  - ODE solver function handle (e.g., @ode45)
%   rhs_func    - Right-hand side function handle for integration
%   t_ex        - External input time vector
%   u_ex        - External input matrix
%
% Outputs:
%   lya_results - Struct containing Lyapunov analysis results:
%                 For 'benettin': LLE, local_lya, finite_lya, t_lya
%                 For 'qr': LE_spectrum, local_LE_spectrum_t, finite_LE_spectrum_t,
%                           t_lya, sort_idx, params.N_sys_eqs
%                 For 'none': empty struct
%
% Example:
%   lya_results = compute_lyapunov_exponents('benettin', S_out, t_out, ...
%       dt, fs, [3, 150], params, opts, @ode45, @SRNN_reservoir, t_ex, u_ex);

    lya_results = struct();

    if isfield(params, 'lags') && ~isempty(params.lags)
        error('MESN:DelayedLyapunovUnsupported', ...
            'Lyapunov analysis is ODE-only; nonempty delays are unsupported.');
    end
    
    if strcmpi(Lya_method, 'none')
        return;
    end
    
    % Choose a target renormalisation interval (seconds) then snap it to an
    % integer number of simulation steps so it is compatible with dt.
    if strcmpi(Lya_method, 'qr')
        lya_dt_target = 0.1;   % QR typically benefits from longer intervals
    elseif strcmpi(Lya_method, 'benettin')
        lya_dt_target = 0.02;  % Standard interval for Benettin (when dt allows)
    else
        lya_dt_target = 0.1;
    end

    if ~(isscalar(dt) && isfinite(dt) && dt > 0)
        error('dt must be a positive, finite scalar');
    end

    n_steps = max(1, round(lya_dt_target / dt));
    lya_dt = n_steps * dt;
    
    lya_fs = 1 / lya_dt;
    
    switch lower(Lya_method)
        case 'benettin'
            fprintf('Computing largest Lyapunov exponent using Benettin''s algorithm...\n');
            d0 = 1e-3;
            tic
            idx0 = find(t_out >= T_interval(1) - 10*eps(T_interval(1)), 1, 'first');
            if isempty(idx0)
                error('compute_lyapunov_exponents:StartNotInTrajectory', ...
                    'No sample at or after T_interval(1)');
            end
            ben_opts = struct( ...
                'odefun', rhs_func, ...
                'x0', S_out(idx0, :).', ...
                'T_interval', [t_out(idx0), T_interval(2)], ...
                'lya_dt', lya_dt, ...
                'd0', d0, ...
                'seed', 1, ...
                'ode_solver', ode_solver, ...
                'ode_options', opts, ...
                'params', params);
            ben = benettin_lle_ode(ben_opts);
            toc
            LLE = ben.LLE;
            fprintf('Largest Lyapunov Exponent: %.4f\n', LLE);
            lya_results.LLE = LLE;
            lya_results.local_lya = ben.local_lya;
            lya_results.finite_lya = ben.finite_lya;
            lya_results.t_lya = ben.t_lya;
            lya_results.segment_durations = ben.segment_durations;
            lya_results.lya_dt = lya_dt;
            lya_results.lya_fs = lya_fs;
            lya_results.status = ben.status;
            
        case 'qr'
            fprintf('Computing full Lyapunov spectrum using QR decomposition method...\n');
            tic
            idx0 = find(t_out >= T_interval(1) - 10*eps(T_interval(1)), 1, 'first');
            if isempty(idx0)
                error('compute_lyapunov_exponents:StartNotInTrajectory', ...
                    'No sample at or after T_interval(1)');
            end
            qr_opts = struct( ...
                'odefun', rhs_func, ...
                'jacobian_fun', @(tt, S) SRNN_Jacobian_wrapper(tt, S, params), ...
                'x0', S_out(idx0, :).', ...
                'T_interval', [t_out(idx0), T_interval(2)], ...
                'lya_dt', lya_dt, ...
                'ode_solver', ode_solver, ...
                'ode_options', opts, ...
                'params', params, ...
                'compute_benettin', true, ...
                'd0', 1e-3, ...
                'seed', 1);
            qr = lyapunov_spectrum_qr_ode(qr_opts);
            toc
            fprintf('Lyapunov Dimension: %.2f\n', compute_kaplan_yorke_dimension(qr.LE_spectrum));
            lya_results.LE_spectrum = qr.LE_spectrum;
            lya_results.local_LE_spectrum_t = qr.local_LE_spectrum_t;
            lya_results.finite_LE_spectrum_t = qr.finite_LE_spectrum_t;
            lya_results.t_lya = qr.t_lya;
            lya_results.segment_durations = qr.segment_durations;
            lya_results.sort_idx = qr.sort_idx;
            lya_results.params.N_sys_eqs = params.N_sys_eqs;
            lya_results.lya_dt = lya_dt;
            lya_results.lya_fs = lya_fs;
            lya_results.LLE_qr = qr.LLE_qr;
            lya_results.LLE_benettin = qr.LLE_benettin;
            lya_results.LLE = qr.LLE_qr;
            lya_results.status = qr.status;
            fprintf('Largest Lyapunov Exponent (QR): %.4f  (Benettin): %.4f\n', ...
                qr.LLE_qr, qr.LLE_benettin);
            
        otherwise
            error('Unknown Lyapunov method: %s. Use ''benettin'', ''qr'', or ''none''.', Lya_method);
    end
end

%% Helper function to compute Kaplan-Yorke dimension
function D_KY = compute_kaplan_yorke_dimension(lambda)
    % Compute Kaplan-Yorke (Lyapunov) dimension from spectrum
    % lambda: sorted Lyapunov exponents (descending order)
    
    lambda = sort(lambda, 'descend');
    cumsum_lambda = cumsum(lambda);
    
    % Find largest j such that sum of first j exponents is non-negative
    j = find(cumsum_lambda >= 0, 1, 'last');
    
    if isempty(j)
        D_KY = 0;
    elseif j == length(lambda)
        D_KY = length(lambda);
    else
        D_KY = j + cumsum_lambda(j) / abs(lambda(j+1));
    end
end

%% Jacobian wrapper for lyapunov_spectrum_qr
function J_jac = SRNN_Jacobian_wrapper(tt, S, params)
    J_jac = compute_Jacobian_fast(S, params);
end

