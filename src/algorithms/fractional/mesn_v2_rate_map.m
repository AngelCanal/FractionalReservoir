function [r, info] = mesn_v2_rate_map(q, activation_cfg)
%MESN_V2_RATE_MAP MESN v2 rate map from effective state q.
%
%   [r, info] = mesn_v2_rate_map(q, activation_cfg)
%
% Maps effective state q to firing-rate output r. Does not compute adaptation.
% Supported activation modes: piecewise_sigmoid, identity.

    q = validate_q(q);
    cfg = validate_activation_cfg(activation_cfg);

    switch cfg.mode
        case 'identity'
            r = q;
        case 'piecewise_sigmoid'
            r = piecewiseSigmoid(q, cfg.S_a, cfg.S_c);
    end

    spec = mesn_v2_rate_map_spec();
    info = struct();
    info.schema_version = spec.schema_version;
    info.content_hash = spec.content_hash;
    info.mode = cfg.mode;
    info.shape_preserved = true;
end

function q = validate_q(value)
    if ~isnumeric(value) || ~isreal(value) || ~all(isfinite(value(:)))
        error('mesn_v2_rate_map:invalidQ', ...
            'q must be a finite real numeric array.');
    end
    q = value;
end

function cfg = validate_activation_cfg(value)
    if nargin < 1 || ~isstruct(value) || ~isscalar(value)
        error('mesn_v2_rate_map:invalidActivationCfg', ...
            'activation_cfg must be a scalar struct.');
    end

    required = {'mode', 'S_a', 'S_c'};
    missing = required(~isfield(value, required));
    if ~isempty(missing)
        error('mesn_v2_rate_map:missingField', ...
            'Missing required activation_cfg field: %s.', missing{1});
    end

    mode = validate_mode(value.mode);

    if strcmp(mode, 'identity')
        S_a = validate_identity_parameter(value.S_a, 'S_a');
        S_c = validate_identity_parameter(value.S_c, 'S_c');
    else
        S_a = validate_piecewise_sa(value.S_a);
        S_c = validate_piecewise_sc(value.S_c);
    end

    cfg = struct();
    cfg.mode = mode;
    cfg.S_a = S_a;
    cfg.S_c = S_c;
end

function mode = validate_mode(value)
    if isstring(value) && isscalar(value)
        mode = char(value);
    elseif ischar(value) && isrow(value)
        mode = value;
    else
        error('mesn_v2_rate_map:unsupportedMode', ...
            'activation_cfg.mode must be a scalar string or char.');
    end

    allowed = {'piecewise_sigmoid', 'identity'};
    if ~any(strcmp(mode, allowed))
        error('mesn_v2_rate_map:unsupportedMode', ...
            'Unsupported activation mode: %s.', mode);
    end
end

function x = validate_identity_parameter(value, name)
    if isempty(value)
        x = [];
        return;
    end
    error('mesn_v2_rate_map:identityParametersNotEmpty', ...
        '%s must be empty for identity mode.', name);
end

function S_a = validate_piecewise_sa(value)
    if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
            ~isfinite(value) || value < 0 || value > 1
        error('mesn_v2_rate_map:invalidSa', ...
            'S_a must be a finite real scalar with 0 <= S_a <= 1.');
    end
    S_a = double(value);
end

function S_c = validate_piecewise_sc(value)
    if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
            ~isfinite(value)
        error('mesn_v2_rate_map:invalidSc', ...
            'S_c must be a finite real scalar.');
    end
    S_c = double(value);
end
