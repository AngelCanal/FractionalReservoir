function spec = fractional_mesn_v2_mechanistic_sfa_engine_spec()
%FRACTIONAL_MESN_V2_MECHANISTIC_SFA_ENGINE_SPEC Frozen SFA-enabled engine contract.
%
%   spec = fractional_mesn_v2_mechanistic_sfa_engine_spec()

    ENGINE_VERSION = 'fractional_mesn_v2_mechanistic_sfa_engine_v1';
    CORE_VERSION = 'fractional_mesn_v2_caputo_l1_core_v1';
    CORE_HASH = '3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f';
    RATE_MAP_VERSION = 'mesn_v2_rate_map_v1';
    RATE_MAP_HASH = '483b6192099426b1c22f29a35e04d9e22c508826a9d334f8da8b0134b94fe257';
    DALE_VERSION = 'mesn_v2_dale_validator_v1';
    DALE_HASH = 'dba675ded7b3f3f8e91ceb93185171a6fbedc42bba5050a97cca8d830bc3f081';
    FOUNDATION_VERSION = 'fractional_mesn_v2_mechanistic_engine_v1';
    FOUNDATION_HASH = ...
        'fe9691184cc22a4b4e9afe8d5740badf9442ed535e848f6fbbe94d6c2539fc69';
    SFA_STEP_VERSION = 'mesn_v2_sfa_step_v1';
    SFA_STEP_HASH = ...
        '7bec90a56bc1df144848b5857eb9bd3565719a4905de4ca9ec7967124eee5fa0';

    core_spec = fractional_l1_core_spec();
    assert_identity(core_spec.schema_version, CORE_VERSION, ...
        'FractionalMESN_v2_mechanistic_sfa:dependencyIdentityMismatch', ...
        'core schema');
    assert_identity(core_spec.content_hash, CORE_HASH, ...
        'FractionalMESN_v2_mechanistic_sfa:dependencyIdentityMismatch', ...
        'core hash');

    rate_spec = mesn_v2_rate_map_spec();
    assert_identity(rate_spec.schema_version, RATE_MAP_VERSION, ...
        'FractionalMESN_v2_mechanistic_sfa:dependencyIdentityMismatch', ...
        'rate-map schema');
    assert_identity(rate_spec.content_hash, RATE_MAP_HASH, ...
        'FractionalMESN_v2_mechanistic_sfa:dependencyIdentityMismatch', ...
        'rate-map hash');

    dale_spec = mesn_v2_dale_validator_spec();
    assert_identity(dale_spec.schema_version, DALE_VERSION, ...
        'FractionalMESN_v2_mechanistic_sfa:dependencyIdentityMismatch', ...
        'Dale-validator schema');
    assert_identity(dale_spec.content_hash, DALE_HASH, ...
        'FractionalMESN_v2_mechanistic_sfa:dependencyIdentityMismatch', ...
        'Dale-validator hash');

    foundation_spec = fractional_mesn_v2_mechanistic_engine_spec();
    assert_identity(foundation_spec.schema_version, FOUNDATION_VERSION, ...
        'FractionalMESN_v2_mechanistic_sfa:dependencyIdentityMismatch', ...
        'foundation-engine schema');
    assert_identity(foundation_spec.content_hash, FOUNDATION_HASH, ...
        'FractionalMESN_v2_mechanistic_sfa:dependencyIdentityMismatch', ...
        'foundation-engine hash');

    sfa_spec = mesn_v2_sfa_step_spec();
    assert_identity(sfa_spec.schema_version, SFA_STEP_VERSION, ...
        'FractionalMESN_v2_mechanistic_sfa:dependencyIdentityMismatch', ...
        'SFA-step schema');
    assert_identity(sfa_spec.content_hash, SFA_STEP_HASH, ...
        'FractionalMESN_v2_mechanistic_sfa:dependencyIdentityMismatch', ...
        'SFA-step hash');

    payload = struct();
    payload.schema_version = ENGINE_VERSION;
    payload.foundation_engine_schema_version = FOUNDATION_VERSION;
    payload.foundation_engine_content_hash = FOUNDATION_HASH;
    payload.core_schema_version = CORE_VERSION;
    payload.core_content_hash = CORE_HASH;
    payload.rate_map_schema_version = RATE_MAP_VERSION;
    payload.rate_map_content_hash = RATE_MAP_HASH;
    payload.dale_validator_schema_version = DALE_VERSION;
    payload.dale_validator_content_hash = DALE_HASH;
    payload.sfa_step_schema_version = SFA_STEP_VERSION;
    payload.sfa_step_content_hash = SFA_STEP_HASH;
    payload.state_operator = 'caputo_l1_full_history';
    payload.integration_scheme = 'semiimplicit_linear_leak_explicit_drive';
    payload.trajectory_layout = 'X_Q_R_A_E_A_I_row_aligned';
    payload.adaptation_ordering = 'population_local_ascending_E_idx_I_idx';
    payload.global_qr_ordering = 'original_neuronal_order';
    payload.physical_time_index = [ ...
        'U_k_is_u_km1_X_jp1_is_x_j_Q_jp1_is_q_j_R_jp1_is_r_j_', ...
        'A_jp1_is_a_at_t_j'];
    payload.drive_index = 'n_minus_1';
    payload.rate_index = 'n_minus_1';
    payload.input_index = 'n_minus_1';
    payload.sfa_rate_index = 'n_minus_1';
    payload.q_policy = 'q_k_equals_x_k_minus_adaptation_k';
    payload.sfa_update = 'exact_exponential_zero_order_hold';
    payload.sfa_memory = 'first_order_markov_a_previous_only';
    payload.history_policy = 'full_fractional_x_history_no_truncation';
    payload.alpha_one_policy = 'core_exact_backward_euler_branch';
    payload.clipping_policy = 'none';
    payload.mechanism_off_limits = [ ...
        'zero_channel_equals_no_sfa_engine;', ...
        'zero_coupling_equals_no_sfa_engine_Q_equals_X;', ...
        'W_zero_X_equals_E2_input_only;', ...
        'identity_zero_coupling_equals_E2_linear'];
    payload.object_semantics = 'value_class_stateless_simulate';
    payload.public_api = 'simulate_returns_X_Q_R_A_E_A_I_info';
    payload.continuation_policy = ...
        'not_supported_in_e3c3_requires_separate_preregistration';
    payload.included_mechanisms = { ...
        'input_plumbing', 'nonlinear_rate_map', 'dale_validation', ...
        'linear_w_recurrence_on_r', 'caputo_l1_stepping', ...
        'sfa_integer_order'};
    payload.excluded_mechanisms = { ...
        'std', 'delays', 'delay_prehistory', 'bias', 'noise', 'readout', ...
        'weight_construction', 'spectral_scaling', 'fast_convolution', ...
        'continuation', 'sfa_clipping'};

    content_hash = canonical_sha256(payload);

    spec = struct();
    spec.schema_version = payload.schema_version;
    spec.content_hash = content_hash;
    spec.foundation_engine_schema_version = ...
        payload.foundation_engine_schema_version;
    spec.foundation_engine_content_hash = payload.foundation_engine_content_hash;
    spec.core_schema_version = payload.core_schema_version;
    spec.core_content_hash = payload.core_content_hash;
    spec.rate_map_schema_version = payload.rate_map_schema_version;
    spec.rate_map_content_hash = payload.rate_map_content_hash;
    spec.dale_validator_schema_version = payload.dale_validator_schema_version;
    spec.dale_validator_content_hash = payload.dale_validator_content_hash;
    spec.sfa_step_schema_version = payload.sfa_step_schema_version;
    spec.sfa_step_content_hash = payload.sfa_step_content_hash;
    spec.state_operator = payload.state_operator;
    spec.integration_scheme = payload.integration_scheme;
    spec.trajectory_layout = payload.trajectory_layout;
    spec.adaptation_ordering = payload.adaptation_ordering;
    spec.global_qr_ordering = payload.global_qr_ordering;
    spec.physical_time_index = payload.physical_time_index;
    spec.drive_index = payload.drive_index;
    spec.rate_index = payload.rate_index;
    spec.input_index = payload.input_index;
    spec.sfa_rate_index = payload.sfa_rate_index;
    spec.q_policy = payload.q_policy;
    spec.sfa_update = payload.sfa_update;
    spec.sfa_memory = payload.sfa_memory;
    spec.history_policy = payload.history_policy;
    spec.alpha_one_policy = payload.alpha_one_policy;
    spec.clipping_policy = payload.clipping_policy;
    spec.mechanism_off_limits = payload.mechanism_off_limits;
    spec.object_semantics = payload.object_semantics;
    spec.public_api = payload.public_api;
    spec.continuation_policy = payload.continuation_policy;
    spec.included_mechanisms = payload.included_mechanisms;
    spec.excluded_mechanisms = payload.excluded_mechanisms;
end

function assert_identity(actual, expected, err_id, label)
    if ~strcmp(actual, expected)
        error(err_id, 'Unexpected %s: %s.', label, actual);
    end
end
