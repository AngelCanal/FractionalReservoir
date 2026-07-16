function result = evaluate_dimension_control_equivalence(treatment_values, ...
        control_values, seed_ids, endpoint_id, cfg_equiv)
%EVALUATE_DIMENSION_CONTROL_EQUIVALENCE  Numerical dimension-control diagnostic.
%
%   result = evaluate_dimension_control_equivalence(treatment_values, ...
%       control_values, seed_ids, endpoint_id, cfg_equiv)
%
% Not statistical equivalence. Autonomous endpoints are excluded from gating.

    if nargin < 5 || isempty(cfg_equiv)
        cfg_equiv = struct( ...
            'absolute_tolerance', 1e-8, ...
            'relative_tolerance', 1e-6, ...
            'gated_endpoint_ids', {{ ...
                'mc_total', 'narma_test_nrmse', 'mg_onestep_test_nrmse'}}, ...
            'label', 'numerical_dimension_control_check_not_statistical_equivalence');
    end

    treatment_values = treatment_values(:);
    control_values = control_values(:);
    seed_ids = seed_ids(:);

    if numel(treatment_values) ~= numel(control_values) || ...
            numel(treatment_values) ~= numel(seed_ids)
        error('evaluate_dimension_control_equivalence:LengthMismatch', ...
            'treatment, control, and seed_ids must have equal length.');
    end

    if ~all(isfinite(treatment_values))
        error('evaluate_dimension_control_equivalence:NonFiniteTreatment', ...
            'treatment_values must be finite.');
    end
    if ~all(isfinite(control_values))
        error('evaluate_dimension_control_equivalence:NonFiniteControl', ...
            'control_values must be finite.');
    end
    if ~all(isfinite(seed_ids))
        error('evaluate_dimension_control_equivalence:NonFiniteSeed', ...
            'seed_ids must be finite.');
    end
    if ~all(abs(seed_ids - round(seed_ids)) < 1e-12)
        error('evaluate_dimension_control_equivalence:NonIntegerSeed', ...
            'seed_ids must be integers.');
    end
    if numel(unique(seed_ids)) ~= numel(seed_ids)
        error('evaluate_dimension_control_equivalence:DuplicateSeed', ...
            'seed_ids must be unique.');
    end

    abs_tol = cfg_equiv.absolute_tolerance;
    rel_tol = cfg_equiv.relative_tolerance;
    if ~(isscalar(abs_tol) && isfinite(abs_tol) && abs_tol >= 0)
        error('evaluate_dimension_control_equivalence:InvalidAbsTol', ...
            'absolute_tolerance must be finite and nonnegative.');
    end
    if ~(isscalar(rel_tol) && isfinite(rel_tol) && rel_tol >= 0)
        error('evaluate_dimension_control_equivalence:InvalidRelTol', ...
            'relative_tolerance must be finite and nonnegative.');
    end

    delta_raw = treatment_values - control_values;

    allowed_error = abs_tol + rel_tol * max(abs(treatment_values), abs(control_values));
    abs_delta = abs(delta_raw);
    rel_delta = abs_delta ./ max(max(abs(treatment_values), abs(control_values)), eps);

    pass_mask = abs_delta <= allowed_error + eps(abs_tol);
    n_checked = numel(seed_ids);
    n_exceed = sum(~pass_mask);

    gated = ismember(endpoint_id, cfg_equiv.gated_endpoint_ids);
    if gated
        pass = (n_exceed == 0);
        status = 'gated_check';
    else
        pass = true;  % not gated; autonomous etc. excluded
        status = 'not_gated_endpoint';
    end

    result = struct();
    result.label = cfg_equiv.label;
    result.endpoint_id = endpoint_id;
    result.gated = gated;
    result.absolute_tolerance = abs_tol;
    result.relative_tolerance = rel_tol;
    result.seed_ids = seed_ids;
    result.delta_raw = delta_raw;
    result.allowed_error = allowed_error;
    result.max_absolute_discrepancy = max(abs_delta);
    result.max_relative_discrepancy = max(rel_delta);
    result.n_seeds_checked = n_checked;
    result.n_seeds_exceeding_tolerance = n_exceed;
    result.pass = pass;
    result.status = status;
    result.prohibited_interpretations = { ...
        'failure_to_reject_zero', ...
        'tost', ...
        'post_hoc_sesoi', ...
        'p_greater_than_alpha_as_equivalence'};
end
