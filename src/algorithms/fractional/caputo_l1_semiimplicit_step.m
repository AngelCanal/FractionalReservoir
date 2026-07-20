function [x_next, info] = caputo_l1_semiimplicit_step( ...
        X_history, drive_previous, dt, alpha, tau_x)
%CAPUTO_L1_SEMIIMPLICIT_STEP One full-history Caputo-L1 semi-implicit step.
%
%   [x_next, info] = caputo_l1_semiimplicit_step( ...
%       X_history, drive_previous, dt, alpha, tau_x)
%
% Conventions:
%   - X_history rows are x_0, ..., x_{n-1}
%   - this function computes x_n
%   - drive_previous is d_{n-1} (causal; never future)
%   - columns are independent state dimensions
%
% For 0 < alpha < 1:
%
%   kappa = tau_x^alpha / (Gamma(2-alpha) * dt^alpha)
%   H_n   = sum_{k=1}^{n-1} w_k (x_{n-k} - x_{n-k-1})   (H_1 = 0)
%   x_n   = (kappa * x_{n-1} - kappa * H_n + d_{n-1}) / (kappa + 1)
%
% For alpha == 1 (exact comparison; history before x_{n-1} ignored):
%
%   ratio = tau_x / dt
%   x_n   = (ratio * x_{n-1} + d_{n-1}) / (ratio + 1)

    CORE_VERSION = 'fractional_mesn_v2_caputo_l1_core_v1';

    validate_history(X_history);
    validate_dt(dt);
    validate_alpha(alpha);
    validate_tau_x(tau_x);

    n_previous = size(X_history, 1);
    n_state = size(X_history, 2);
    drive_previous = expand_drive(drive_previous, n_state);

    alpha_one = (alpha == 1);

    if alpha_one
        ratio = tau_x / dt;
        history_term = zeros(1, n_state);
        x_next = (ratio * X_history(end, :) + drive_previous) / (ratio + 1);
        kappa_or_ratio = ratio;
        n_frac_hist = 0;
        full_history_used = false;
    else
        if n_previous == 1
            H_n = zeros(1, n_state);
            n_frac_hist = 0;
        else
            increments = diff(X_history, 1, 1);
            % Need w_1,...,w_{n_previous-1}; allocate n_previous weights (w_0..w_{n-1})
            all_w = caputo_l1_weights(alpha, n_previous);
            history_weights = all_w(2:end);
            rev = flipud(increments);
            H_n = (history_weights.' * rev);
            n_frac_hist = n_previous - 1;
        end
        history_term = H_n;
        kappa = (tau_x ^ alpha) / (gamma(2 - alpha) * (dt ^ alpha));
        x_next = (kappa * X_history(end, :) - kappa * H_n + drive_previous) ...
            / (kappa + 1);
        kappa_or_ratio = kappa;
        full_history_used = true;
    end

    info = struct();
    info.core_version = CORE_VERSION;
    info.schema_version = CORE_VERSION;
    info.alpha = alpha;
    info.dt = dt;
    info.tau_x = tau_x;
    if alpha_one
        info.ratio = kappa_or_ratio;
        info.kappa = [];
    else
        info.kappa = kappa_or_ratio;
        info.ratio = [];
    end
    info.history_term = history_term;
    info.n_fractional_history_increments_used = n_frac_hist;
    info.full_history_used = full_history_used;
    info.alpha_one_branch_used = alpha_one;
    info.drive_index = 'n_minus_1';
    info.leak_index = 'n';
end

function drive = expand_drive(drive_previous, n_state)
    if ~isnumeric(drive_previous) || ~isreal(drive_previous) || ~all(isfinite(drive_previous(:)))
        error('caputo_l1_semiimplicit_step:InvalidDrive', ...
            'drive_previous must be finite and real.');
    end
    drive = double(drive_previous);
    if isscalar(drive)
        drive = drive * ones(1, n_state);
    elseif isvector(drive) && numel(drive) == n_state
        drive = reshape(drive, 1, n_state);
    elseif isequal(size(drive), [1, n_state])
        % already ok
    else
        error('caputo_l1_semiimplicit_step:DriveDimensionMismatch', ...
            'drive_previous must be scalar or match state dimension.');
    end
end

function validate_history(X_history)
    if ~isnumeric(X_history) || ~ismatrix(X_history) || isempty(X_history)
        error('caputo_l1_semiimplicit_step:InvalidHistory', ...
            'X_history must be a nonempty numeric matrix.');
    end
    if ~isreal(X_history) || ~all(isfinite(X_history(:)))
        error('caputo_l1_semiimplicit_step:NonFiniteHistory', ...
            'X_history must be finite and real.');
    end
end

function validate_dt(dt)
    if ~isnumeric(dt) || ~isscalar(dt) || ~isreal(dt) || ~isfinite(dt) || ~(dt > 0)
        error('caputo_l1_semiimplicit_step:InvalidDt', ...
            'dt must be a finite positive real scalar.');
    end
end

function validate_alpha(alpha)
    if ~isnumeric(alpha) || ~isscalar(alpha) || ~isreal(alpha) || ~isfinite(alpha)
        error('caputo_l1_semiimplicit_step:InvalidAlpha', ...
            'alpha must be a finite real scalar.');
    end
    if ~(alpha > 0 && alpha <= 1)
        error('caputo_l1_semiimplicit_step:AlphaOutOfRange', ...
            'alpha must satisfy 0 < alpha <= 1.');
    end
end

function validate_tau_x(tau_x)
    if ~isnumeric(tau_x) || ~isscalar(tau_x) || ~isreal(tau_x) || ~isfinite(tau_x) || ~(tau_x > 0)
        error('caputo_l1_semiimplicit_step:InvalidTau', ...
            'tau_x must be a finite positive real scalar.');
    end
end
