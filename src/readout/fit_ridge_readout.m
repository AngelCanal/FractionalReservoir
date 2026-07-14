function model = fit_ridge_readout(X_train, Y_train, lambda)
% FIT_RIDGE_READOUT  Standardized ridge regression via economy SVD.
%
%   model = fit_ridge_readout(X_train, Y_train, lambda)
%
% Objective (lambda is the absolute ridge strength; it is NOT scaled by n):
%   min_B ||Z*B - Yc||_F^2 + lambda * ||B||_F^2
% where Z is training-standardized features and Yc is training-centered
% targets. The intercept is recovered as target_mean and is unregularized.
%
% Solves with thin SVD (never via (X'X + lambda I) \ X'Y). For lambda == 0,
% uses a deterministic numerical-rank tolerance
%   tol = max(size(Z)) * eps(max(s))
% and the minimum-norm pseudoinverse on singular values above tol.

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

    feature_mean = mean(X_train, 1);
    feature_scale = std(X_train, 0, 1);
    zero_variance_mask = feature_scale < sqrt(eps);
    feature_scale(zero_variance_mask) = 1;

    Z = (X_train - feature_mean) ./ feature_scale;
    target_mean = mean(Y_train, 1);
    Yc = Y_train - target_mean;

    [coefficients, solve_info] = svd_ridge_solve(Z, Yc, lambda);

    intercept = target_mean;
    if any(~isfinite(coefficients(:))) || any(~isfinite(intercept(:)))
        error('fit_ridge_readout:NonFiniteSolution', ...
            'Fitted coefficients or intercept are nonfinite.');
    end

    model = struct();
    model.intercept = intercept;
    model.coefficients = coefficients;
    % Backward-compatible aliases used by apply / SRNN_ESN mirrors
    model.mu = feature_mean;
    model.sigma = feature_scale;
    model.constant_feature = zero_variance_mask;
    model.feature_mean = feature_mean;
    model.feature_scale = feature_scale;
    model.target_mean = target_mean;
    model.zero_variance_mask = zero_variance_mask;
    model.n_zero_variance_features = nnz(zero_variance_mask);
    model.lambda = lambda;
    model.n_samples = n_rows;
    model.n_features = n_features;
    model.n_outputs = n_outputs;
    model.solver_method = solve_info.solver_method;
    model.numerical_rank = solve_info.numerical_rank;
    model.rank_tolerance = solve_info.rank_tolerance;
    model.singular_values = solve_info.singular_values;
    model.largest_singular_value = solve_info.largest_singular_value;
    model.smallest_retained_singular_value = solve_info.smallest_retained_singular_value;
    model.raw_condition_estimate = solve_info.raw_condition_estimate;
    model.regularized_condition_estimate = solve_info.regularized_condition_estimate;
    model.coefficient_norm = norm(coefficients, 'fro');
    model.conditioning_status = solve_info.conditioning_status;
end

function [B, info] = svd_ridge_solve(Z, Yc, lambda)
    [n_rows, n_features] = size(Z);
    n_outputs = size(Yc, 2);
    B = zeros(n_features, n_outputs);

    if n_features == 0
        info = empty_solve_info(lambda);
        return;
    end

    [U, S, V] = svd(Z, 'econ');
    s = diag(S);
    if isempty(s)
        info = empty_solve_info(lambda);
        info.solver_method = 'svd_econ_empty';
        info.conditioning_status = 'numerically_degenerate';
        return;
    end

    s_max = max(s);
    if ~(isfinite(s_max) && s_max > 0)
        tol = max(size(Z)) * eps(1);
        keep = false(size(s));
        s_max = 0;
    else
        tol = max(size(Z)) * eps(s_max);
        keep = s > tol;
    end
    numerical_rank = nnz(keep);

    if lambda > 0
        gain = s ./ (s.^2 + lambda);
        solver_method = 'svd_econ_ridge';
    else
        gain = zeros(size(s));
        gain(keep) = 1 ./ s(keep);
        solver_method = 'svd_econ_min_norm';
    end

    UY = U' * Yc;
    B = V * (gain .* UY);

    if numerical_rank == 0
        smallest_retained = NaN;
    else
        smallest_retained = min(s(keep));
    end

    has_nullspace = (numerical_rank < n_features) || (numel(s) < n_features);
    if numerical_rank == 0 || ~isfinite(s_max) || s_max <= 0
        raw_cond = Inf;
    elseif has_nullspace
        raw_cond = Inf;
    else
        raw_cond = s_max / min(s);
    end

    if lambda > 0
        max_eig = s_max^2 + lambda;
        if has_nullspace || numerical_rank == 0
            min_eig = lambda;
        else
            min_eig = min(s)^2 + lambda;
        end
        reg_cond = max_eig / min_eig;
    else
        if has_nullspace || numerical_rank == 0
            reg_cond = Inf;
        else
            reg_cond = (s_max / min(s))^2;
        end
    end

    if any(~isfinite(B(:)))
        status = 'failed_nonfinite';
    elseif numerical_rank == 0 && n_features > 0
        status = 'numerically_degenerate';
    elseif lambda == 0 && has_nullspace
        status = 'rank_deficient_minimum_norm';
    elseif lambda > 0 && has_nullspace
        status = 'rank_deficient_stable_ridge';
    else
        status = 'well_conditioned';
    end

    info = struct();
    info.solver_method = solver_method;
    info.numerical_rank = numerical_rank;
    info.rank_tolerance = tol;
    info.singular_values = s(:)';
    info.largest_singular_value = s_max;
    info.smallest_retained_singular_value = smallest_retained;
    info.raw_condition_estimate = raw_cond;
    info.regularized_condition_estimate = reg_cond;
    info.conditioning_status = status;
end

function info = empty_solve_info(lambda)
    info = struct();
    if lambda > 0
        info.solver_method = 'svd_econ_ridge';
    else
        info.solver_method = 'svd_econ_min_norm';
    end
    info.numerical_rank = 0;
    info.rank_tolerance = 0;
    info.singular_values = zeros(1, 0);
    info.largest_singular_value = 0;
    info.smallest_retained_singular_value = NaN;
    info.raw_condition_estimate = Inf;
    info.regularized_condition_estimate = Inf;
    info.conditioning_status = 'numerically_degenerate';
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
