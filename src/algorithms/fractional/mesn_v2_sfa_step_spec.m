function spec = mesn_v2_sfa_step_spec()
%MESN_V2_SFA_STEP_SPEC Frozen MESN v2 SFA-step module contract.
%
%   spec = mesn_v2_sfa_step_spec()
%
% Fixed-contract identity for mesn_v2_sfa_step_v1. Excludes content_hash
% from the hashed payload and excludes all runtime a/r/dt/tau values.

    SCHEMA_VERSION = 'mesn_v2_sfa_step_v1';

    payload = struct();
    payload.schema_version = SCHEMA_VERSION;
    payload.continuous_equation = 'tau_a_m * da_i_m_dt = r_i - a_i_m';
    payload.discrete_update = [ ...
        'a_next = a_previous .* exp(-dt ./ tau_a) + ', ...
        'r_previous(:) * (1 - exp(-dt ./ tau_a))'];
    payload.update_scheme = 'exact_exponential_zero_order_hold';
    payload.rate_index = 'n_minus_1';
    payload.input_layout = 'a_n_population_by_n_channels_r_vector_dt_scalar_tau_vector';
    payload.output_layout = 'a_next_same_size_as_a_previous';
    payload.rate_normalization = 'column_n_population_by_1';
    payload.tau_normalization = 'row_1_by_n_channels';
    payload.zero_channel_policy = 'empty_tau_identity_copy_no_update';
    payload.zero_population_policy = 'preserve_zero_by_n_channels';
    payload.clipping_policy = 'none';
    payload.unit_interval_invariant = 'conditional_on_a_and_r_in_unit_interval';
    payload.integer_order = true;
    payload.adaptation_memory = 'markovian_a_previous_only';
    payload.fractional_history_used = false;
    payload.delay_history_used = false;
    payload.included_scope = {'exact_exponential_sfa_step'};
    payload.excluded_scope = { ...
        'sfa_engine', 'fractional_x_history', 'std', 'delays', ...
        'recurrence', 'rate_map', 'readout', 'clipping', 'benchmark'};
    payload.state_semantics = 'stateless_pure_function';

    content_hash = canonical_sha256(payload);

    spec = struct();
    spec.schema_version = payload.schema_version;
    spec.content_hash = content_hash;
    spec.continuous_equation = payload.continuous_equation;
    spec.discrete_update = payload.discrete_update;
    spec.update_scheme = payload.update_scheme;
    spec.rate_index = payload.rate_index;
    spec.input_layout = payload.input_layout;
    spec.output_layout = payload.output_layout;
    spec.rate_normalization = payload.rate_normalization;
    spec.tau_normalization = payload.tau_normalization;
    spec.zero_channel_policy = payload.zero_channel_policy;
    spec.zero_population_policy = payload.zero_population_policy;
    spec.clipping_policy = payload.clipping_policy;
    spec.unit_interval_invariant = payload.unit_interval_invariant;
    spec.integer_order = payload.integer_order;
    spec.adaptation_memory = payload.adaptation_memory;
    spec.fractional_history_used = payload.fractional_history_used;
    spec.delay_history_used = payload.delay_history_used;
    spec.included_scope = payload.included_scope;
    spec.excluded_scope = payload.excluded_scope;
    spec.state_semantics = payload.state_semantics;
end
