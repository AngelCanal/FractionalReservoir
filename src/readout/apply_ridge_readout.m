function Y_hat = apply_ridge_readout(model, X)
% APPLY_RIDGE_READOUT  Apply a fitted standardized ridge readout model.
%
% Uses stored training feature_mean / feature_scale (aliases mu / sigma)
% exactly once. Does not inspect or refit against targets.

    if ~isstruct(model) || ~isfield(model, 'coefficients')
        error('apply_ridge_readout:InvalidModel', 'model must be a fitted ridge struct.');
    end
    if ~isfield(model, 'n_features')
        error('apply_ridge_readout:InvalidModel', 'model.n_features is required.');
    end
    if size(X, 2) ~= model.n_features
        error('apply_ridge_readout:FeatureCount', ...
            'Expected %d features, got %d.', model.n_features, size(X, 2));
    end
    if any(~isfinite(X(:)))
        error('apply_ridge_readout:NonFinite', 'X must be finite.');
    end

    mu = get_preprocess_field(model, 'feature_mean', 'mu');
    scale = get_preprocess_field(model, 'feature_scale', 'sigma');
    intercept = model.intercept;
    coefficients = model.coefficients;

    if any(~isfinite(mu(:))) || any(~isfinite(scale(:))) || ...
            any(~isfinite(coefficients(:))) || any(~isfinite(intercept(:)))
        error('apply_ridge_readout:NonFiniteModel', ...
            'Model parameters must be finite.');
    end
    if any(scale(:) <= 0)
        error('apply_ridge_readout:InvalidScale', ...
            'feature_scale / sigma must be positive.');
    end

    Z = (X - mu) ./ scale;
    Y_hat = Z * coefficients + intercept;

    if any(~isfinite(Y_hat(:)))
        error('apply_ridge_readout:NonFinitePrediction', ...
            'Predictions are nonfinite.');
    end
end

function value = get_preprocess_field(model, primary, legacy)
    if isfield(model, primary)
        value = model.(primary);
    elseif isfield(model, legacy)
        value = model.(legacy);
    else
        error('apply_ridge_readout:InvalidModel', ...
            'model must contain %s or %s.', primary, legacy);
    end
end
