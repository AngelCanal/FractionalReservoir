function spec = mesn_v2_rate_map_spec()
%MESN_V2_RATE_MAP_SPEC Frozen MESN v2 rate-map module contract.
%
%   spec = mesn_v2_rate_map_spec()

    SCHEMA_VERSION = 'mesn_v2_rate_map_v1';

    payload = struct();
    payload.schema_version = SCHEMA_VERSION;
    payload.activation_modes = {'identity', 'piecewise_sigmoid'};
    payload.piecewise_dependency = 'piecewiseSigmoid';
    payload.shape_policy = 'preserve_input_shape';
    payload.identity_policy = 'engineering_limiting_control';
    payload.default_parameters = 'none';
    payload.adaptation_computation = 'excluded';

    content_hash = canonical_sha256(payload);

    spec = struct();
    spec.schema_version = payload.schema_version;
    spec.content_hash = content_hash;
    spec.activation_modes = payload.activation_modes;
    spec.piecewise_dependency = payload.piecewise_dependency;
    spec.shape_policy = payload.shape_policy;
    spec.identity_policy = payload.identity_policy;
    spec.default_parameters = payload.default_parameters;
    spec.adaptation_computation = payload.adaptation_computation;
end
