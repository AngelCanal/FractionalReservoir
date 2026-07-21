function spec = fractional_mesn_v2_engine_spec()
%FRACTIONAL_MESN_V2_ENGINE_SPEC Frozen isolated Fractional MESN v2 engine contract.
%
%   spec = fractional_mesn_v2_engine_spec()

    ENGINE_VERSION = 'fractional_mesn_v2_engine_v1';
    CORE_VERSION = 'fractional_mesn_v2_caputo_l1_core_v1';
    CORE_HASH = '3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f';

    core_spec = fractional_l1_core_spec();
    if ~strcmp(core_spec.schema_version, CORE_VERSION)
        error('FractionalMESN_v2:coreSchemaMismatch', ...
            'Unexpected core schema version: %s.', core_spec.schema_version);
    end
    if ~strcmp(core_spec.content_hash, CORE_HASH)
        error('FractionalMESN_v2:coreHashMismatch', ...
            'Unexpected core content hash: %s.', core_spec.content_hash);
    end

    payload = struct();
    payload.schema_version = ENGINE_VERSION;
    payload.core_schema_version = CORE_VERSION;
    payload.core_content_hash = CORE_HASH;
    payload.state_operator = 'caputo_l1_full_history';
    payload.integration_scheme = 'semiimplicit_linear_leak_explicit_drive';
    payload.drive_index = 'n_minus_1';
    payload.input_index = 'n_minus_1';
    payload.recurrence_index = 'n_minus_1';
    payload.history_policy = 'full_history_no_truncation';
    payload.alpha_one_policy = 'core_exact_backward_euler_branch';
    payload.object_semantics = 'value_class_stateless_simulate';
    payload.continuation_policy = ...
        'not_supported_in_e2_requires_separate_preregistration';
    payload.included_mechanisms = { ...
        'input_plumbing', 'linear_recurrence', 'caputo_l1_stepping'};
    payload.excluded_mechanisms = { ...
        'nonlinear_rate_map', 'sfa', 'std', 'dale_law', 'delays', ...
        'bias', 'noise', 'readout', 'fast_convolution', 'continuation'};

    content_hash = canonical_sha256(payload);

    spec = struct();
    spec.schema_version = payload.schema_version;
    spec.content_hash = content_hash;
    spec.core_schema_version = payload.core_schema_version;
    spec.core_content_hash = payload.core_content_hash;
    spec.state_operator = payload.state_operator;
    spec.integration_scheme = payload.integration_scheme;
    spec.drive_index = payload.drive_index;
    spec.input_index = payload.input_index;
    spec.recurrence_index = payload.recurrence_index;
    spec.history_policy = payload.history_policy;
    spec.alpha_one_policy = payload.alpha_one_policy;
    spec.object_semantics = payload.object_semantics;
    spec.continuation_policy = payload.continuation_policy;
    spec.included_mechanisms = payload.included_mechanisms;
    spec.excluded_mechanisms = payload.excluded_mechanisms;
end
