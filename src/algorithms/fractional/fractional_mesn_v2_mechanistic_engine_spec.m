function spec = fractional_mesn_v2_mechanistic_engine_spec()
%FRACTIONAL_MESN_V2_MECHANISTIC_ENGINE_SPEC Frozen no-delay mechanistic engine contract.
%
%   spec = fractional_mesn_v2_mechanistic_engine_spec()

    ENGINE_VERSION = 'fractional_mesn_v2_mechanistic_engine_v1';
    CORE_VERSION = 'fractional_mesn_v2_caputo_l1_core_v1';
    CORE_HASH = '3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f';
    RATE_MAP_VERSION = 'mesn_v2_rate_map_v1';
    RATE_MAP_HASH = '483b6192099426b1c22f29a35e04d9e22c508826a9d334f8da8b0134b94fe257';
    DALE_VERSION = 'mesn_v2_dale_validator_v1';
    DALE_HASH = 'dba675ded7b3f3f8e91ceb93185171a6fbedc42bba5050a97cca8d830bc3f081';

    core_spec = fractional_l1_core_spec();
    if ~strcmp(core_spec.schema_version, CORE_VERSION)
        error('FractionalMESN_v2_mechanistic:coreSchemaMismatch', ...
            'Unexpected core schema version: %s.', core_spec.schema_version);
    end
    if ~strcmp(core_spec.content_hash, CORE_HASH)
        error('FractionalMESN_v2_mechanistic:coreHashMismatch', ...
            'Unexpected core content hash: %s.', core_spec.content_hash);
    end

    rate_spec = mesn_v2_rate_map_spec();
    if ~strcmp(rate_spec.schema_version, RATE_MAP_VERSION)
        error('FractionalMESN_v2_mechanistic:rateMapSchemaMismatch', ...
            'Unexpected rate-map schema version: %s.', rate_spec.schema_version);
    end
    if ~strcmp(rate_spec.content_hash, RATE_MAP_HASH)
        error('FractionalMESN_v2_mechanistic:rateMapHashMismatch', ...
            'Unexpected rate-map content hash: %s.', rate_spec.content_hash);
    end

    dale_spec = mesn_v2_dale_validator_spec();
    if ~strcmp(dale_spec.schema_version, DALE_VERSION)
        error('FractionalMESN_v2_mechanistic:daleSchemaMismatch', ...
            'Unexpected Dale-validator schema version: %s.', ...
            dale_spec.schema_version);
    end
    if ~strcmp(dale_spec.content_hash, DALE_HASH)
        error('FractionalMESN_v2_mechanistic:daleHashMismatch', ...
            'Unexpected Dale-validator content hash: %s.', ...
            dale_spec.content_hash);
    end

    payload = struct();
    payload.schema_version = ENGINE_VERSION;
    payload.core_schema_version = CORE_VERSION;
    payload.core_content_hash = CORE_HASH;
    payload.rate_map_schema_version = RATE_MAP_VERSION;
    payload.rate_map_content_hash = RATE_MAP_HASH;
    payload.dale_validator_schema_version = DALE_VERSION;
    payload.dale_validator_content_hash = DALE_HASH;
    payload.state_operator = 'caputo_l1_full_history';
    payload.integration_scheme = 'semiimplicit_linear_leak_explicit_drive';
    payload.trajectory_layout = 'X_Q_R_row_aligned_N_plus_1_by_n';
    payload.physical_time_index = ...
        'U_k_is_u_km1_X_jp1_is_x_j_Q_jp1_is_q_j_R_jp1_is_r_j';
    payload.drive_index = 'n_minus_1';
    payload.rate_index = 'n_minus_1';
    payload.input_index = 'n_minus_1';
    payload.recurrence_formula = 'W_times_r_plus_Win_times_u';
    payload.q_policy = 'q_equals_x_no_sfa_in_e3b2';
    payload.history_policy = 'full_history_no_truncation';
    payload.alpha_one_policy = 'core_exact_backward_euler_branch';
    payload.object_semantics = 'value_class_stateless_simulate';
    payload.continuation_policy = ...
        'not_supported_in_e3b2_requires_separate_preregistration';
    payload.included_mechanisms = { ...
        'input_plumbing', 'nonlinear_rate_map', 'dale_validation', ...
        'linear_w_recurrence_on_r', 'caputo_l1_stepping'};
    payload.excluded_mechanisms = { ...
        'sfa', 'std', 'delays', 'delay_prehistory', 'bias', 'noise', ...
        'readout', 'weight_construction', 'spectral_scaling', ...
        'fast_convolution', 'continuation'};

    content_hash = canonical_sha256(payload);

    spec = struct();
    spec.schema_version = payload.schema_version;
    spec.content_hash = content_hash;
    spec.core_schema_version = payload.core_schema_version;
    spec.core_content_hash = payload.core_content_hash;
    spec.rate_map_schema_version = payload.rate_map_schema_version;
    spec.rate_map_content_hash = payload.rate_map_content_hash;
    spec.dale_validator_schema_version = payload.dale_validator_schema_version;
    spec.dale_validator_content_hash = payload.dale_validator_content_hash;
    spec.state_operator = payload.state_operator;
    spec.integration_scheme = payload.integration_scheme;
    spec.trajectory_layout = payload.trajectory_layout;
    spec.physical_time_index = payload.physical_time_index;
    spec.drive_index = payload.drive_index;
    spec.rate_index = payload.rate_index;
    spec.input_index = payload.input_index;
    spec.recurrence_formula = payload.recurrence_formula;
    spec.q_policy = payload.q_policy;
    spec.history_policy = payload.history_policy;
    spec.alpha_one_policy = payload.alpha_one_policy;
    spec.object_semantics = payload.object_semantics;
    spec.continuation_policy = payload.continuation_policy;
    spec.included_mechanisms = payload.included_mechanisms;
    spec.excluded_mechanisms = payload.excluded_mechanisms;
end
