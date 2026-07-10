function model = fit_ridge_readout(X_train, Y_train, lambda)
% FIT_RIDGE_READOUT  Standardized ridge regression with unpenalized intercept.
%
%   model = fit_ridge_readout(X_train, Y_train, lambda)
%
% Feature mean/std from training rows only. Scales below sqrt(eps) become 1
% and are recorded in constant_feature. Intercept column is unpenalized.

    if nargin < 3
        error('fit_ridge_readout:MissingLambda', 'lambda is required.');
    end
    validate_xy(X_train, Y_train, 'train');
    if ~isscalar(lambda) || ~isfinite(lambda) || lambda < 0
        error('fit_ridge_readout:InvalidLambda', ...
            'lambda must be a finite nonnegative scalar.');
    end

    [n_rows, n_features] = size(X_train);
    n_outputs = size(Y_train, 2);

    mu = mean(X_train, 1);
    sigma = std(X_train, 0, 1);
    constant_feature = sigma < sqrt(eps);
    sigma(constant_feature) = 1;

    Z = (X_train - mu) ./ sigma;
    % Constant columns are identically zero after centering; exclude them from
    % the design so lambda=0 remains well-posed, then expand coefficients.
    active = ~constant_feature;
    Z_active = Z(:, active);
    D = [ones(n_rows, 1), Z_active];
    P = diag([0, ones(1, size(Z_active, 2))]);
    coef_active = (D' * D + lambda * P) \ (D' * Y_train);

    coefficients = zeros(n_features, n_outputs);
    coefficients(active, :) = coef_active(2:end, :);

    model = struct();
    model.intercept = coef_active(1, :);
    model.coefficients = coefficients;
    model.mu = mu;
    model.sigma = sigma;
    model.lambda = lambda;
    model.n_features = n_features;
    model.n_outputs = n_outputs;
    model.constant_feature = constant_feature;
end

function validate_xy(X, Y, tag)
    if isempty(X) || isempty(Y)
        error('fit_ridge_readout:EmptyInput', '%s arrays must be nonempty.', tag);
    end
    if ~ismatrix(X) || ~ismatrix(Y)
        error('fit_ridge_readout:InvalidShape', '%s arrays must be 2-D.', tag);
    end
    if size(X, 1) ~= size(Y, 1)
        error('fit_ridge_readout:RowMismatch', ...
            '%s feature/target row counts must match.', tag);
    end
    if any(~isfinite(X(:))) || any(~isfinite(Y(:)))
        error('fit_ridge_readout:NonFinite', '%s arrays must be finite.', tag);
    end
end
