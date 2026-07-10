function params = validate_MESN_params(params)
% validate_MESN_params  Validate MESN parameter struct and supported modes.

    if ~isstruct(params)
        error('MESN:InvalidParams', 'params must be a struct.');
    end

    params = fill_missing_indices(params);

    assert_positive_integer(params, 'n');
    assert_nonnegative_integer(params, 'n_E');
    assert_nonnegative_integer(params, 'n_I');

    if params.n_E + params.n_I ~= params.n
        error('MESN:InvalidPopulationSize', 'n_E + n_I must equal n.');
    end

    if ~isequal(params.E_indices(:)', 1:params.n_E)
        error('MESN:InvalidIndices', 'E_indices must be 1:n_E in order.');
    end
    if ~isequal(params.I_indices(:)', (params.n_E + 1):params.n)
        error('MESN:InvalidIndices', 'I_indices must follow E_indices contiguously.');
    end

    assert_matrix_finite(params, 'W', [params.n, params.n]);
    assert_matrix_finite(params, 'W_in', [params.n, NaN]);
    if size(params.W_in, 2) < 1
        error('MESN:InvalidWIn', 'W_in must have at least one column.');
    end

    assert_positive_scalar(params, 'tau_d');
    assert_positive_scalar(params, 'dt');

    validate_adaptation(params, 'E');
    validate_adaptation(params, 'I');
    validate_std(params, 'E');
    validate_std(params, 'I');

    if isfield(params, 'c_E') && ~isfinite(params.c_E)
        error('MESN:InvalidCoupling', 'c_E must be finite.');
    end
    if isfield(params, 'c_I') && ~isfinite(params.c_I)
        error('MESN:InvalidCoupling', 'c_I must be finite.');
    end
    if isfield(params, 'c_E') && params.c_E < 0
        error('MESN:InvalidCoupling', 'c_E must be nonnegative.');
    end
    if isfield(params, 'c_I') && params.c_I < 0
        error('MESN:InvalidCoupling', 'c_I must be nonnegative.');
    end

    validate_lags(params);

    if ~isfield(params, 'activation_function') || ~isa(params.activation_function, 'function_handle')
        error('MESN:InvalidActivation', 'activation_function must be a function handle.');
    end
    if ~isfield(params, 'activation_function_derivative') || ...
            ~isa(params.activation_function_derivative, 'function_handle')
        error('MESN:InvalidActivation', 'activation_function_derivative must be a function handle.');
    end

    which_states = getfield_or_error(params, 'which_states');
    if ~any(strcmp(which_states, {'x', 'r', 'all'}))
        error('MESN:InvalidWhichStates', 'which_states must be x, r, or all.');
    end

    if ~isfield(params, 'lambda') || ~isfinite(params.lambda) || params.lambda < 0
        error('MESN:InvalidLambda', 'lambda must be finite and nonnegative.');
    end
end

function params = fill_missing_indices(params)
    if ~isfield(params, 'n_E') || ~isfield(params, 'n_I')
        return;
    end
    if ~isfield(params, 'E_indices')
        params.E_indices = 1:params.n_E;
    end
    if ~isfield(params, 'I_indices')
        params.I_indices = (params.n_E + 1):params.n;
    end
end

function validate_adaptation(params, pop)
    n_field = sprintf('n_a_%s', pop);
    tau_field = sprintf('tau_a_%s', pop);
    n_pop = params.(sprintf('n_%s', pop));
    n_a = params.(n_field);

    assert_nonnegative_integer_scalar(n_a, n_field);
    if n_a == 0
        if isfield(params, tau_field) && ~isempty(params.(tau_field))
            if numel(params.(tau_field)) ~= 0
                error('MESN:InvalidTauA', '%s must be empty when %s is zero.', tau_field, n_field);
            end
        else
            params.(tau_field) = zeros(1, 0);
        end
        return;
    end

    tau = params.(tau_field);
    if ~isvector(tau) || numel(tau) ~= n_a || size(tau, 1) ~= 1
        error('MESN:InvalidTauA', '%s must be a 1 x n_a row vector.', tau_field);
    end
    if any(~isfinite(tau)) || any(tau <= 0)
        error('MESN:InvalidTauA', '%s must contain finite positive values.', tau_field);
    end
end

function validate_std(params, pop)
    n_field = sprintf('n_b_%s', pop);
    n_b = params.(n_field);
    if ~(n_b == 0 || n_b == 1)
        error('MESN:MultipleSTDUnsupported', ...
            '%s must be exactly 0 or 1.', n_field);
    end
    if n_b == 0
        return;
    end
    rec_field = sprintf('tau_b_%s_rec', pop);
    rel_field = sprintf('tau_b_%s_rel', pop);
    assert_positive_scalar(params, rec_field);
    assert_positive_scalar(params, rel_field);
end

function validate_lags(params)
    if ~isfield(params, 'lags')
        params.lags = [];
        return;
    end
    lags = params.lags;
    if isempty(lags)
        return;
    end
    if ~isscalar(lags) || ~isfinite(lags) || lags <= 0
        if ~isscalar(lags)
            error('MESN:VectorDelayUnsupported', ...
                'Vector delays are unsupported; provide one positive scalar lag.');
        end
        error('MESN:InvalidLags', 'lags must be empty or one strictly positive scalar.');
    end
end

function assert_positive_integer(params, field)
    if ~isfield(params, field) || ~isscalar(params.(field)) || params.(field) <= 0 || ...
            abs(params.(field) - round(params.(field))) > 0
        error('MESN:InvalidN', '%s must be a positive integer.', field);
    end
end

function assert_nonnegative_integer(params, field)
    if ~isfield(params, field) || ~isscalar(params.(field)) || params.(field) < 0 || ...
            abs(params.(field) - round(params.(field))) > 0
        error('MESN:InvalidPopulationCount', '%s must be a nonnegative integer.', field);
    end
end

function assert_nonnegative_integer_scalar(value, name)
    if ~isscalar(value) || value < 0 || abs(value - round(value)) > 0
        error('MESN:InvalidCount', '%s must be a nonnegative integer.', name);
    end
end

function assert_positive_scalar(params, field)
    if ~isfield(params, field) || ~isscalar(params.(field)) || ~isfinite(params.(field)) || params.(field) <= 0
        error('MESN:InvalidScalar', '%s must be a finite positive scalar.', field);
    end
end

function assert_matrix_finite(params, field, expected_size)
    if ~isfield(params, field)
        error('MESN:MissingField', 'Missing required field %s.', field);
    end
    M = params.(field);
    if ndims(M) ~= 2
        error('MESN:InvalidMatrix', '%s must be two-dimensional.', field);
    end
    if size(M, 1) ~= expected_size(1)
        error('MESN:InvalidMatrix', '%s has invalid row dimension.', field);
    end
    if numel(expected_size) >= 2 && ~isnan(expected_size(2)) && size(M, 2) ~= expected_size(2)
        error('MESN:InvalidMatrix', '%s has invalid column dimension.', field);
    end
    if any(~isfinite(M(:)))
        error('MESN:InvalidMatrix', '%s must be finite.', field);
    end
end

function value = getfield_or_error(params, field)
    if ~isfield(params, field)
        error('MESN:MissingField', 'Missing required field %s.', field);
    end
    value = params.(field);
end
