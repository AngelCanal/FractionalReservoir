function tests = test_mesn_v2_dale_validator
%TEST_MESN_V2_DALE_VALIDATOR Unit tests for MESN v2 Dale-matrix validator.
%
% Deterministic hand-constructed fixtures only; no governed seeds.
this_file = mfilename('fullpath');
repo_root = fileparts(fileparts(fileparts(this_file)));
addpath(genpath(fullfile(repo_root, 'src')));
tests = functiontests({ ...
    @testValidMixedEIColumns, ...
    @testArbitraryExplicitOrdering, ...
    @testSignVectorNormalization, ...
    @testZeroEntriesAndZeroColumns, ...
    @testExcitatoryNegativeEntryRejection, ...
    @testInhibitoryPositiveEntryRejection, ...
    @testColumnNotRowSignValidation, ...
    @testInvalidWValues, ...
    @testInvalidSignValues, ...
    @testInputsUnchanged, ...
    @testBoundedInfoCounts, ...
    @testDeterministicReplayAndRngUnchanged, ...
    @testSchemaAndContentHash, ...
    @testStableErrorIdentifiers});
end

function testValidMixedEIColumns(testCase)
    W = [1.0, 0.0, -0.5; ...
         0.2, -0.3, 0.0; ...
         0.0, -0.1, -0.4];
    signs = [1, -1, -1];
    info = validate_mesn_v2_dale_matrix(W, signs);
    testCase.verifyEqual(info.n, 3);
    testCase.verifyEqual(info.n_excitatory, 1);
    testCase.verifyEqual(info.n_inhibitory, 2);
    testCase.verifyEqual(info.signs_valid, true);
end

function testArbitraryExplicitOrdering(testCase)
    W = [0.0, 0.2, -0.5; ...
         -0.1, 0.3, 0.0; ...
         -0.4, 0.0, -0.6];
    signs = [-1, 1, -1];
    info = validate_mesn_v2_dale_matrix(W, signs);
    testCase.verifyEqual(info.n_excitatory, 1);
    testCase.verifyEqual(info.n_inhibitory, 2);
end

function testSignVectorNormalization(testCase)
    W = [1, 0; 0, -1];
    info_row = validate_mesn_v2_dale_matrix(W, [1, -1]);
    info_col = validate_mesn_v2_dale_matrix(W, [1; -1]);
    testCase.verifyEqual(info_row.n, 2);
    testCase.verifyEqual(info_col.n, 2);
    testCase.verifyEqual(info_row.n_excitatory, 1);
    testCase.verifyEqual(info_col.n_inhibitory, 1);
end

function testZeroEntriesAndZeroColumns(testCase)
    W = [0, 0, 0; ...
         0, 0.5, -0.2; ...
         0, 0.0, -0.1];
    signs = [1, 1, -1];
    info = validate_mesn_v2_dale_matrix(W, signs);
    testCase.verifyEqual(info.signs_valid, true);

    W_zero_col = [0, 0; 0, -0.3];
    info2 = validate_mesn_v2_dale_matrix(W_zero_col, [1, -1]);
    testCase.verifyEqual(info2.signs_valid, true);
end

function testExcitatoryNegativeEntryRejection(testCase)
    W = [1.0, 0.0; -0.2, -0.3];
    signs = [1, -1];
    testCase.verifyError(@() validate_mesn_v2_dale_matrix(W, signs), ...
        'mesn_v2_dale_validator:daleSignViolation');
end

function testInhibitoryPositiveEntryRejection(testCase)
    W = [1.0, 0.1; 0.2, -0.3];
    signs = [1, -1];
    testCase.verifyError(@() validate_mesn_v2_dale_matrix(W, signs), ...
        'mesn_v2_dale_validator:daleSignViolation');
end

function testColumnNotRowSignValidation(testCase)
    % Row signs would fail if enforced, but column signs are valid.
    W = [0.5, -0.2; ...
         0.3, -0.4];
    signs = [1, -1];
    info = validate_mesn_v2_dale_matrix(W, signs);
    testCase.verifyEqual(info.signs_valid, true);

    W_bad_col = [1.0, 0.5; 0.2, -0.3];
    testCase.verifyError(@() validate_mesn_v2_dale_matrix(W_bad_col, signs), ...
        'mesn_v2_dale_validator:daleSignViolation');
end

function testInvalidWValues(testCase)
    signs = [1, -1];
    testCase.verifyError(@() validate_mesn_v2_dale_matrix([1 2; 3 4; 5 6], signs), ...
        'mesn_v2_dale_validator:invalidW');
    testCase.verifyError(@() validate_mesn_v2_dale_matrix([], signs), ...
        'mesn_v2_dale_validator:invalidW');
    testCase.verifyError(@() validate_mesn_v2_dale_matrix([NaN 0; 0 -1], signs), ...
        'mesn_v2_dale_validator:invalidW');
    testCase.verifyError(@() validate_mesn_v2_dale_matrix([Inf 0; 0 -1], signs), ...
        'mesn_v2_dale_validator:invalidW');
    testCase.verifyError(@() validate_mesn_v2_dale_matrix([1+1i 0; 0 -1], signs), ...
        'mesn_v2_dale_validator:invalidW');
    testCase.verifyError(@() validate_mesn_v2_dale_matrix('abc', signs), ...
        'mesn_v2_dale_validator:invalidW');
    testCase.verifyError(@() validate_mesn_v2_dale_matrix(ones(2, 2, 2), signs), ...
        'mesn_v2_dale_validator:invalidW');
end

function testInvalidSignValues(testCase)
    W = eye(2);
    testCase.verifyError(@() validate_mesn_v2_dale_matrix(W, [1]), ...
        'mesn_v2_dale_validator:invalidSigns');
    testCase.verifyError(@() validate_mesn_v2_dale_matrix(W, [1 1; -1 -1]), ...
        'mesn_v2_dale_validator:invalidSigns');
    testCase.verifyError(@() validate_mesn_v2_dale_matrix(W, [1, 0]), ...
        'mesn_v2_dale_validator:invalidSigns');
    testCase.verifyError(@() validate_mesn_v2_dale_matrix(W, [1, 2]), ...
        'mesn_v2_dale_validator:invalidSigns');
    testCase.verifyError(@() validate_mesn_v2_dale_matrix(W, [NaN, -1]), ...
        'mesn_v2_dale_validator:invalidSigns');
    testCase.verifyError(@() validate_mesn_v2_dale_matrix(W, [Inf, -1]), ...
        'mesn_v2_dale_validator:invalidSigns');
    testCase.verifyError(@() validate_mesn_v2_dale_matrix(W, [1+1i, -1]), ...
        'mesn_v2_dale_validator:invalidSigns');
    testCase.verifyError(@() validate_mesn_v2_dale_matrix(W, {'a', 'b'}), ...
        'mesn_v2_dale_validator:invalidSigns');
end

function testInputsUnchanged(testCase)
    W = [1.0, 0.0; 0.2, -0.3];
    W_copy = W;
    signs = [1, -1];
    signs_copy = signs;
    validate_mesn_v2_dale_matrix(W, signs);
    testCase.verifyEqual(W, W_copy, 'AbsTol', 0);
    testCase.verifyEqual(signs, signs_copy);
end

function testBoundedInfoCounts(testCase)
    W = [1, 0, -0.2; 0, -0.1, 0; 0.3, 0, -0.4];
    info = validate_mesn_v2_dale_matrix(W, [1, -1, -1]);
    testCase.verifyEqual(info.schema_version, 'mesn_v2_dale_validator_v1');
    testCase.verifyEqual(info.signs_by, 'presynaptic_columns');
    testCase.verifyEqual(info.n, 3);
    testCase.verifyEqual(info.n_excitatory, 1);
    testCase.verifyEqual(info.n_inhibitory, 2);
    testCase.verifyFalse(isfield(info, 'W'));
    testCase.verifyFalse(isfield(info, 'presynaptic_signs'));
end

function testDeterministicReplayAndRngUnchanged(testCase)
    W = [0.5, -0.2; 0.1, -0.3];
    signs = [1, -1];
    rng(2468, 'twister');
    s0 = rng;
    info1 = validate_mesn_v2_dale_matrix(W, signs);
    info2 = validate_mesn_v2_dale_matrix(W, signs);
    s1 = rng;
    testCase.verifyEqual(info1, info2);
    testCase.verifyEqual(s0.Type, s1.Type);
    testCase.verifyEqual(s0.Seed, s1.Seed);
    testCase.verifyEqual(s0.State, s1.State);
end

function testSchemaAndContentHash(testCase)
    spec = mesn_v2_dale_validator_spec();
    testCase.verifyEqual(spec.schema_version, 'mesn_v2_dale_validator_v1');
    payload = rmfield(spec, 'content_hash');
    testCase.verifyEqual(spec.content_hash, canonical_sha256(payload));
    testCase.verifyEqual(spec.content_hash, ...
        'dba675ded7b3f3f8e91ceb93185171a6fbedc42bba5050a97cca8d830bc3f081');
    spec2 = mesn_v2_dale_validator_spec();
    testCase.verifyEqual(spec, spec2);
end

function testStableErrorIdentifiers(testCase)
    testCase.verifyError(@() validate_mesn_v2_dale_matrix([], 1), ...
        'mesn_v2_dale_validator:invalidW');
    testCase.verifyError(@() validate_mesn_v2_dale_matrix(eye(2), [0, 1]), ...
        'mesn_v2_dale_validator:invalidSigns');
    W = [1, 0.1; 0, -1];
    testCase.verifyError(@() validate_mesn_v2_dale_matrix(W, [1, -1]), ...
        'mesn_v2_dale_validator:daleSignViolation');
end
