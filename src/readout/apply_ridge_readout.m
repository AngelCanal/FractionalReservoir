function Y_hat = apply_ridge_readout(model, X)
% APPLY_RIDGE_READOUT  Apply a fitted standardized ridge readout model.

    if ~isstruct(model) || ~isfield(model, 'coefficients') || ~isfield(model, 'mu')
        error('apply_ridge_readout:InvalidModel', 'model must be a fitted ridge struct.');
    end
    if size(X, 2) ~= model.n_features
        error('apply_ridge_readout:FeatureCount', ...
            'Expected %d features, got %d.', model.n_features, size(X, 2));
    end
    if any(~isfinite(X(:)))
        error('apply_ridge_readout:NonFinite', 'X must be finite.');
    end

    Z = (X - model.mu) ./ model.sigma;
    Y_hat = Z * model.coefficients + model.intercept;
end
