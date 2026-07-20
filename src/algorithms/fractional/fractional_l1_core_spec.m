function spec = fractional_l1_core_spec()
%FRACTIONAL_L1_CORE_SPEC Frozen Caputo-L1 numerical core method identity.
%
%   spec = fractional_l1_core_spec()
%
% Returns a scalar struct describing protocol
% fractional_mesn_v2_caputo_l1_core_v1. No runtime alpha belongs here; a
% future scientific protocol must fingerprint its chosen alpha separately.
%
% Content hash excludes the self-hash field and uses canonical_sha256.

    CORE_VERSION = 'fractional_mesn_v2_caputo_l1_core_v1';

    spec = struct();
    spec.schema_version = CORE_VERSION;
    spec.operator = 'Caputo';
    spec.alpha_domain = '0<alpha<=1';
    spec.grid = 'uniform';
    spec.fractional_scheme = 'L1_full_history';
    spec.leak_index = 'semi_implicit_at_n';
    spec.drive_index = 'explicit_at_n_minus_1';
    spec.alpha_one_scheme = 'backward_euler_leak_explicit_previous_drive';
    spec.fractional_lower_terminal = 't0';
    spec.fractional_prehistory = 'none_standard_caputo';
    spec.delay_history = 'separate_future_module';
    spec.history_truncation = 'forbidden';
    spec.precision = 'double';
    spec.deterministic = true;

    payload = spec;
    spec.content_hash = canonical_sha256(payload);
end
