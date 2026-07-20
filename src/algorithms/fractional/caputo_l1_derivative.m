function [D, info] = caputo_l1_derivative(X, dt, alpha)
%CAPUTO_L1_DERIVATIVE Full-history L1 Caputo derivative at the final sample.
%
%   [D, info] = caputo_l1_derivative(X, dt, alpha)
%
% Conventions:
%   - rows of X are time samples x_0, ..., x_n
%   - columns are independent state dimensions
%   - D is 1 x n_state at the final sample
%   - every increment from x_0 through x_n is used (no truncation)
%
% For 0 < alpha < 1:
%
%   D_L1^alpha x_n
%     = 1 / (Gamma(2-alpha) * dt^alpha)
%       * sum_{k=0}^{n-1} w_k (x_{n-k} - x_{n-k-1})
%
% so w_0 multiplies (x_n - x_{n-1}), w_1 multiplies (x_{n-1} - x_{n-2}), etc.
%
% For alpha == 1:
%
%   D = (X(end,:) - X(end-1,:)) / dt

    CORE_VERSION = 'fractional_mesn_v2_caputo_l1_core_v1';

    validate_X(X);
    validate_dt(dt);
    validate_alpha(alpha);

    n_rows = size(X, 1);
    n_state = size(X, 2);
    if n_rows < 2
        error('caputo_l1_derivative:InsufficientHistory', ...
            'X must have at least two rows (x_0 and x_1).');
    end

    n_increments = n_rows - 1;
    alpha_one = (alpha == 1);

    if alpha_one
        D = (X(end, :) - X(end - 1, :)) / dt;
        weights = caputo_l1_weights(1, n_increments);
        denominator = dt;
    else
        increments = diff(X, 1, 1);
        weights = caputo_l1_weights(alpha, n_increments);
        % Reverse so w_0 multiplies latest increment
        rev = flipud(increments);
        denominator = gamma(2 - alpha) * (dt ^ alpha);
        D = (weights.' * rev) / denominator;
    end

    info = struct();
    info.schema_version = CORE_VERSION;
    info.core_version = CORE_VERSION;
    info.alpha = alpha;
    info.dt = dt;
    info.n_history_increments_used = n_increments;
    info.full_history_used = true;
    info.truncated = false;
    info.weights = weights;
    info.denominator = denominator;
    info.alpha_one_branch_used = alpha_one;
    info.n_state = n_state;
end

function validate_X(X)
    if ~isnumeric(X) || ~ismatrix(X) || isempty(X)
        error('caputo_l1_derivative:InvalidX', ...
            'X must be a nonempty numeric matrix.');
    end
    if ~isreal(X) || ~all(isfinite(X(:)))
        error('caputo_l1_derivative:NonFiniteX', ...
            'X must be finite and real.');
    end
end

function validate_dt(dt)
    if ~isnumeric(dt) || ~isscalar(dt) || ~isreal(dt) || ~isfinite(dt) || ~(dt > 0)
        error('caputo_l1_derivative:InvalidDt', ...
            'dt must be a finite positive real scalar.');
    end
end

function validate_alpha(alpha)
    if ~isnumeric(alpha) || ~isscalar(alpha) || ~isreal(alpha) || ~isfinite(alpha)
        error('caputo_l1_derivative:InvalidAlpha', ...
            'alpha must be a finite real scalar.');
    end
    if ~(alpha > 0 && alpha <= 1)
        error('caputo_l1_derivative:AlphaOutOfRange', ...
            'alpha must satisfy 0 < alpha <= 1.');
    end
end
