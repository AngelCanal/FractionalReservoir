function result = validate_seed_effect_vector(seed_ids, effects, expected_seed_ids, ...
        protocol_tier, inference_action)
%VALIDATE_SEED_EFFECT_VECTOR  Fail-closed seed-effect vector checks.
%
%   result = validate_seed_effect_vector(seed_ids, effects, expected_seed_ids, ...
%       protocol_tier, inference_action)

    if nargin < 5
        inference_action = 'test_and_holm';
    end
    if nargin < 4
        protocol_tier = 'publication';
    end

    seed_ids = seed_ids(:);
    effects = effects(:);

    if numel(seed_ids) ~= numel(effects)
        error('validate_seed_effect_vector:LengthMismatch', ...
            'seed_ids and effects must have equal length.');
    end

    if ~all(isfinite(seed_ids))
        error('validate_seed_effect_vector:NonFiniteSeed', ...
            'seed_ids must be finite integers.');
    end
    if ~all(abs(seed_ids - round(seed_ids)) < 1e-12)
        error('validate_seed_effect_vector:NonIntegerSeed', ...
            'seed_ids must be integers.');
    end

    if numel(unique(seed_ids)) ~= numel(seed_ids)
        error('validate_seed_effect_vector:DuplicateSeed', ...
            'seed_ids must be unique (one effect per seed).');
    end

    if ~all(isfinite(effects))
        error('validate_seed_effect_vector:NonFiniteEffect', ...
            'effects must be finite (no pairwise deletion or imputation).');
    end

    expected_seed_ids = expected_seed_ids(:);
    if numel(unique(expected_seed_ids)) ~= numel(expected_seed_ids)
        error('validate_seed_effect_vector:DuplicateExpectedSeed', ...
            'expected_seed_ids must be unique.');
    end

    missing = setdiff(expected_seed_ids, seed_ids);
    if ~isempty(missing)
        error('validate_seed_effect_vector:MissingSeed', ...
            'Missing %d expected seed(s); first missing: %d.', ...
            numel(missing), missing(1));
    end

    extra = setdiff(seed_ids, expected_seed_ids);
    if ~isempty(extra)
        error('validate_seed_effect_vector:ExtraSeed', ...
            'Found %d unexpected seed(s); first extra: %d.', ...
            numel(extra), extra(1));
    end

    if strcmp(protocol_tier, 'publication') && strcmp(inference_action, 'test_and_holm')
        if numel(expected_seed_ids) ~= 30
            error('validate_seed_effect_vector:PublicationSeedCount', ...
                'Publication inference requires exactly 30 publication seeds.');
        end
    end

    result = struct();
    result.valid = true;
    result.n_seeds = numel(seed_ids);
    result.protocol_tier = protocol_tier;
    result.inference_action = inference_action;
end
