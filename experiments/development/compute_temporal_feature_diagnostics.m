function fd = compute_temporal_feature_diagnostics(X_train, activity)
%COMPUTE_TEMPORAL_FEATURE_DIAGNOSTICS  Train-only feature and activity diagnostics.
%
%   fd = compute_temporal_feature_diagnostics(X_train)
%   fd = compute_temporal_feature_diagnostics(X_train, activity)
%
% Uses training features after washout only. Numerical rank uses the Phase 4A
% geometric tolerance: tol = max(size(Z)) * eps(max(s)).
%
% Participation ratio on covariance singular values:
%   (sum(s))^2 / sum(s.^2)
%
% Activity summaries must come from neuronal rates (passed in activity), never
% from packed-state width.

    if nargin < 1 || isempty(X_train)
        error('compute_temporal_feature_diagnostics:Empty', ...
            'X_train must be nonempty.');
    end
    if any(~isfinite(X_train(:)))
        error('compute_temporal_feature_diagnostics:NonFinite', ...
            'X_train must be finite.');
    end
    if nargin < 2
        activity = struct();
    end

    [n_rows, n_features] = size(X_train);
    feature_mean = mean(X_train, 1);
    feature_std = std(X_train, 0, 1);
    near_const = feature_std < sqrt(eps);

    Xc = X_train - feature_mean;
    if n_features == 0 || n_rows == 0
        s_data = zeros(0, 1);
        tol = 0;
        numerical_rank = 0;
        s_cov = zeros(0, 1);
    else
        [~, Smat, ~] = svd(Xc, 'econ');
        s_data = diag(Smat);
        if isempty(s_data) || ~(isfinite(max(s_data)) && max(s_data) > 0)
            tol = max(size(Xc)) * eps(1);
            numerical_rank = 0;
        else
            tol = max(size(Xc)) * eps(max(s_data));
            numerical_rank = nnz(s_data > tol);
        end
        C = (Xc' * Xc) / n_rows;
        [~, Sc, ~] = svd(C);
        s_cov = diag(Sc);
    end

    if isempty(s_cov) || sum(s_cov.^2) == 0
        participation_ratio = 0;
    else
        participation_ratio = (sum(s_cov))^2 / sum(s_cov.^2);
    end

    if n_features >= 2
        R = corrcoef(X_train);
        off = abs(R(~eye(n_features)));
        off = off(isfinite(off));
        if isempty(off)
            median_abs_offdiag_corr = NaN;
            max_abs_offdiag_corr = NaN;
        else
            median_abs_offdiag_corr = median(off);
            max_abs_offdiag_corr = max(off);
        end
    else
        median_abs_offdiag_corr = NaN;
        max_abs_offdiag_corr = NaN;
    end

    fd = struct();
    fd.n_rows = n_rows;
    fd.n_features = n_features;
    fd.numerical_rank = numerical_rank;
    fd.feature_covariance_effective_rank = numerical_rank;
    fd.rank_tolerance = tol;
    fd.rank_tolerance_policy = 'max(size(Z))*eps(max(s))';
    fd.data_singular_values = s_data(:)';
    fd.covariance_singular_values = s_cov(:)';
    fd.participation_ratio = participation_ratio;
    fd.feature_participation_ratio = participation_ratio;
    fd.fraction_numerically_near_constant_features = mean(near_const);
    fd.near_constant_mask = near_const;
    fd.mean_feature_standard_deviation = mean(feature_std);
    fd.median_feature_standard_deviation = median(feature_std);
    fd.median_absolute_offdiag_feature_correlation = median_abs_offdiag_corr;
    fd.maximum_absolute_offdiag_feature_correlation = max_abs_offdiag_corr;

    fd.mean_firing_rate = local_get(activity, 'mean_rate', NaN);
    fd.saturation_fraction = local_get(activity, 'saturation_fraction', NaN);
    fd.silence_fraction = local_get(activity, 'silence_fraction', ...
        local_get(activity, 'silent_fraction', NaN));
    fd.n_neurons = local_get(activity, 'n_neurons', NaN);
    fd.packed_state_dimension = local_get(activity, 'packed_state_dimension', NaN);
    fd.activity_from_neuronal_rates = local_get(activity, 'rates_are_neuronal', false);
    fd.packed_states_counted_as_neurons = local_get(activity, ...
        'packed_states_counted_as_neurons', false);
end

function v = local_get(S, name, default)
    if isstruct(S) && isfield(S, name) && ~isempty(S.(name))
        v = S.(name);
    else
        v = default;
    end
end
