function hex = hash_fitted_ridge_model(model)
% HASH_FITTED_RIDGE_MODEL  Compact identity hash for a frozen ridge readout.
%
%   hex = hash_fitted_ridge_model(model)
%
% Hashes coefficients / intercept / feature normalization via hash_numeric_array
% rather than serializing full numeric arrays as JSON.

    if ~isstruct(model)
        error('hash_fitted_ridge_model:BadModel', 'model must be a struct.');
    end
    id = struct();
    id.lambda = local_get(model, 'lambda', NaN);
    id.n_features = local_get(model, 'n_features', NaN);
    id.intercept_hash = hash_numeric_array(local_get(model, 'intercept', []));
    id.coefficients_hash = hash_numeric_array(local_get(model, 'coefficients', []));
    mu = local_preprocess(model, 'feature_mean', 'mu');
    sc = local_preprocess(model, 'feature_scale', 'sigma');
    id.feature_mean_hash = hash_numeric_array(mu);
    id.feature_scale_hash = hash_numeric_array(sc);
    hex = canonical_sha256(id);
end

function v = local_preprocess(model, primary, legacy)
    if isfield(model, primary)
        v = model.(primary);
    elseif isfield(model, legacy)
        v = model.(legacy);
    else
        v = [];
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
