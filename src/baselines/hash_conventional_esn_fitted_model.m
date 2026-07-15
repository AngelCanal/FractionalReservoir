function hex = hash_conventional_esn_fitted_model(fitted)
% HASH_CONVENTIONAL_ESN_FITTED_MODEL  Compact identity for frozen leaky ESN.
%
%   hex = hash_conventional_esn_fitted_model(fitted)

    if ~isstruct(fitted)
        error('hash_conventional_esn_fitted_model:BadModel', 'fitted must be a struct.');
    end
    id = struct();
    id.W_res_hash = hash_numeric_array(fitted.W_res);
    id.W_in_hash = hash_numeric_array(fitted.W_in);
    id.leak_rate = fitted.leak_rate;
    id.spectral_radius = fitted.spectral_radius;
    id.input_scaling = fitted.input_scaling;
    id.reservoir_seed = fitted.reservoir_seed;
    id.selected_candidate_index = fitted.selected_candidate_index;
    id.readout_hash = hash_fitted_ridge_model(fitted.readout_model);
    id.zero_initial_state_hash = hash_numeric_array(fitted.zero_initial_state);
    hex = canonical_sha256(id);
end
