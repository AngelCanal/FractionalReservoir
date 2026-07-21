function spec = mesn_v2_dale_validator_spec()
%MESN_V2_DALE_VALIDATOR_SPEC Frozen MESN v2 Dale-matrix validator contract.
%
%   spec = mesn_v2_dale_validator_spec()

    SCHEMA_VERSION = 'mesn_v2_dale_validator_v1';

    payload = struct();
    payload.schema_version = SCHEMA_VERSION;
    payload.signs_by = 'presynaptic_columns';
    payload.zero_entry_policy = 'allowed';
    payload.zero_column_policy = 'allowed';
    payload.row_sign_enforcement = 'none';
    payload.w_mutation = 'forbidden';
    payload.w_construction = 'excluded';
    payload.spectral_constraints = 'excluded';

    content_hash = canonical_sha256(payload);

    spec = struct();
    spec.schema_version = payload.schema_version;
    spec.content_hash = content_hash;
    spec.signs_by = payload.signs_by;
    spec.zero_entry_policy = payload.zero_entry_policy;
    spec.zero_column_policy = payload.zero_column_policy;
    spec.row_sign_enforcement = payload.row_sign_enforcement;
    spec.w_mutation = payload.w_mutation;
    spec.w_construction = payload.w_construction;
    spec.spectral_constraints = payload.spectral_constraints;
end
