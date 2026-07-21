function dale_info = validate_mesn_v2_dale_matrix(W, presynaptic_signs)
%VALIDATE_MESN_V2_DALE_MATRIX Validate Dale-law presynaptic-column signs.
%
%   dale_info = validate_mesn_v2_dale_matrix(W, presynaptic_signs)
%
% Validates that W obeys presynaptic-column Dale sign constraints. Does not
% modify W or construct/scaled/alter weights.

    W = validate_w(W);
    n = size(W, 1);
    signs = validate_presynaptic_signs(presynaptic_signs, n);
    validate_column_signs(W, signs);

    spec = mesn_v2_dale_validator_spec();
    dale_info = struct();
    dale_info.schema_version = spec.schema_version;
    dale_info.content_hash = spec.content_hash;
    dale_info.n = n;
    dale_info.n_excitatory = sum(signs == 1);
    dale_info.n_inhibitory = sum(signs == -1);
    dale_info.signs_by = 'presynaptic_columns';
    dale_info.signs_valid = true;
end

function W = validate_w(value)
    if ~isnumeric(value) || ~ismatrix(value) || ~isreal(value) || ...
            ~all(isfinite(value(:))) || isempty(value) || ...
            size(value, 1) ~= size(value, 2)
        error('mesn_v2_dale_validator:invalidW', ...
            'W must be a finite real nonempty square numeric matrix.');
    end
    W = value;
end

function signs = validate_presynaptic_signs(value, n)
    if ~isnumeric(value) || ~isvector(value) || ~isreal(value) || ...
            ~all(isfinite(value(:))) || numel(value) ~= n
        error('mesn_v2_dale_validator:invalidSigns', ...
            'presynaptic_signs must be a finite real numeric vector with n elements.');
    end

    if ~all(value == 1 | value == -1)
        error('mesn_v2_dale_validator:invalidSigns', ...
            'Each presynaptic sign must be exactly +1 or -1.');
    end

    signs = reshape(double(value), 1, n);
end

function validate_column_signs(W, signs)
    excitatory = find(signs == 1);
    inhibitory = find(signs == -1);

    if ~isempty(excitatory) && any(W(:, excitatory) < 0, 'all')
        error('mesn_v2_dale_validator:daleSignViolation', ...
            'Excitatory presynaptic column contains negative entries.');
    end

    if ~isempty(inhibitory) && any(W(:, inhibitory) > 0, 'all')
        error('mesn_v2_dale_validator:daleSignViolation', ...
            'Inhibitory presynaptic column contains positive entries.');
    end
end
