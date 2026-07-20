function [X, info] = simulate_caputo_l1_reference(drive, x0, dt, alpha, tau_x)
%SIMULATE_CAPUTO_L1_REFERENCE Full-history Caputo-L1 reference trajectory.
%
%   [X, info] = simulate_caputo_l1_reference(drive, x0, dt, alpha, tau_x)
%
% Conventions:
%   - drive has N rows representing d_0, ..., d_{N-1}
%   - X has N+1 rows representing x_0, ..., x_N
%   - x0 is scalar-expandable or one row matching drive columns
%   - each step calls caputo_l1_semiimplicit_step with full state history
%   - no truncation, randomness, globals, or persistent state
%
% Standalone linear problem only:
%   tau_x^alpha * C_D^alpha x(t) = -x(t) + d(t)
% with causal forcing d_{n-1} at each step.

    CORE_VERSION = 'fractional_mesn_v2_caputo_l1_core_v1';

    if ~isnumeric(drive) || ~ismatrix(drive) || isempty(drive)
        error('simulate_caputo_l1_reference:InvalidDrive', ...
            'drive must be a nonempty numeric matrix.');
    end
    if ~isreal(drive) || ~all(isfinite(drive(:)))
        error('simulate_caputo_l1_reference:NonFiniteDrive', ...
            'drive must be finite and real.');
    end

    N = size(drive, 1);
    n_state = size(drive, 2);
    x0_row = expand_x0(x0, n_state);

    X = zeros(N + 1, n_state);
    X(1, :) = x0_row;

    alpha_one_any = (alpha == 1);
    for n = 1:N
        [X(n + 1, :), step_info] = caputo_l1_semiimplicit_step( ...
            X(1:n, :), drive(n, :), dt, alpha, tau_x);
        alpha_one_any = alpha_one_any || step_info.alpha_one_branch_used;
    end

    info = struct();
    info.core_version = CORE_VERSION;
    info.schema_version = CORE_VERSION;
    info.alpha = alpha;
    info.dt = dt;
    info.tau_x = tau_x;
    info.step_count = N;
    info.state_dimension = n_state;
    info.full_history_used = true;
    info.truncated = false;
    info.alpha_one_branch_used = alpha_one_any;
    info.deterministic = true;
end

function x0_row = expand_x0(x0, n_state)
    if ~isnumeric(x0) || ~isreal(x0) || ~all(isfinite(x0(:)))
        error('simulate_caputo_l1_reference:InvalidX0', ...
            'x0 must be finite and real.');
    end
    if isscalar(x0)
        x0_row = x0 * ones(1, n_state);
    elseif isvector(x0) && numel(x0) == n_state
        x0_row = reshape(x0, 1, n_state);
    elseif isequal(size(x0), [1, n_state])
        x0_row = x0;
    else
        error('simulate_caputo_l1_reference:X0DimensionMismatch', ...
            'x0 must be scalar or match drive column dimension.');
    end
end
