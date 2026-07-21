function tests = test_mesn_v2_rate_map
%TEST_MESN_V2_RATE_MAP Unit tests for MESN v2 rate-map module.
%
% Deterministic engineering fixtures only; no governed seeds.
this_file = mfilename('fullpath');
repo_root = fileparts(fileparts(fileparts(this_file)));
addpath(genpath(fullfile(repo_root, 'src')));
tests = functiontests({ ...
    @testIdentityScalarExactness, ...
    @testIdentityVectorAndMatrixExactness, ...
    @testIdentityEmptyInput, ...
    @testIdentityCanonicalEmptyParameters, ...
    @testIdentityRejectsNonemptyParameters, ...
    @testPiecewiseMatchesPiecewiseSigmoid, ...
    @testPiecewiseInteriorAndBoundaryValues, ...
    @testPiecewiseSaBoundaryValues, ...
    @testPiecewiseOutputRange, ...
    @testInvalidActivationCfgTypeAndShape, ...
    @testMissingActivationFields, ...
    @testUnsupportedMode, ...
    @testInvalidSaValues, ...
    @testInvalidScValues, ...
    @testInvalidQValues, ...
    @testDeterministicReplayAndRngUnchanged, ...
    @testActivationCfgUnchanged, ...
    @testSchemaAndContentHash, ...
    @testBoundedInfoWithoutDataCopies, ...
    @testStableErrorIdentifiers});
end

function testIdentityScalarExactness(testCase)
    cfg = identity_cfg();
    q = -0.25;
    [r, info] = mesn_v2_rate_map(q, cfg);
    testCase.verifyEqual(r, q);
    testCase.verifyEqual(info.mode, 'identity');
end

function testIdentityVectorAndMatrixExactness(testCase)
    cfg = identity_cfg();
    q_row = [-1, 0, 0.5, 2];
    [r_row, ~] = mesn_v2_rate_map(q_row, cfg);
    testCase.verifyEqual(r_row, q_row);
    testCase.verifyEqual(size(r_row), size(q_row));

    q_col = q_row.';
    [r_col, ~] = mesn_v2_rate_map(q_col, cfg);
    testCase.verifyEqual(r_col, q_col);
    testCase.verifyEqual(size(r_col), size(q_col));

    q_mat = reshape(-1:6, 2, 4);
    [r_mat, ~] = mesn_v2_rate_map(q_mat, cfg);
    testCase.verifyEqual(r_mat, q_mat);
    testCase.verifyEqual(size(r_mat), size(q_mat));
end

function testIdentityEmptyInput(testCase)
    cfg = identity_cfg();
    q = zeros(0, 0);
    [r, ~] = mesn_v2_rate_map(q, cfg);
    testCase.verifyEqual(r, q);
    testCase.verifyEqual(size(r), [0, 0]);
end

function testIdentityCanonicalEmptyParameters(testCase)
    cfg = struct('mode', 'identity', 'S_a', [], 'S_c', []);
    q = 0.3;
    [r, info] = mesn_v2_rate_map(q, cfg);
    testCase.verifyEqual(r, q);
    testCase.verifyEqual(info.mode, 'identity');
end

function testIdentityRejectsNonemptyParameters(testCase)
    cfg = identity_cfg();
    cfg.S_a = 0.5;
    testCase.verifyError(@() mesn_v2_rate_map(0, cfg), ...
        'mesn_v2_rate_map:identityParametersNotEmpty');
    cfg = identity_cfg();
    cfg.S_c = 0.1;
    testCase.verifyError(@() mesn_v2_rate_map(0, cfg), ...
        'mesn_v2_rate_map:identityParametersNotEmpty');
end

function testPiecewiseMatchesPiecewiseSigmoid(testCase)
    cfg = piecewise_cfg(0.85, 0.4);
    q = linspace(-2, 2, 17);
    [r, ~] = mesn_v2_rate_map(q, cfg);
    expected = piecewiseSigmoid(q, cfg.S_a, cfg.S_c);
    testCase.verifyEqual(r, expected, 'AbsTol', 0);
end

function testPiecewiseInteriorAndBoundaryValues(testCase)
    cfg = piecewise_cfg(0.6, 0.2);
    q = [-1000, cfg.S_c - 1, cfg.S_c, cfg.S_c + 0.25, 1000];
    [r, ~] = mesn_v2_rate_map(q, cfg);
    expected = piecewiseSigmoid(q, cfg.S_a, cfg.S_c);
    testCase.verifyEqual(r, expected, 'AbsTol', 0);
    testCase.verifyEqual(r(1), 0, 'AbsTol', 0);
    testCase.verifyEqual(r(end), 1, 'AbsTol', 0);
end

function testPiecewiseSaBoundaryValues(testCase)
    for sa = [0, 1, 0.5]
        cfg = piecewise_cfg(sa, 0.0);
        q = linspace(-1.5, 1.5, 9);
        [r, ~] = mesn_v2_rate_map(q, cfg);
        expected = piecewiseSigmoid(q, sa, cfg.S_c);
        testCase.verifyEqual(r, expected, 'AbsTol', 0);
    end
end

function testPiecewiseOutputRange(testCase)
    cfg = piecewise_cfg(0.75, -0.3);
    q = linspace(-4, 4, 41);
    [r, ~] = mesn_v2_rate_map(q, cfg);
    testCase.verifyGreaterThanOrEqual(min(r(:)), 0);
    testCase.verifyLessThanOrEqual(max(r(:)), 1);
end

function testInvalidActivationCfgTypeAndShape(testCase)
    testCase.verifyError(@() mesn_v2_rate_map(0, []), ...
        'mesn_v2_rate_map:invalidActivationCfg');
    testCase.verifyError(@() mesn_v2_rate_map(0, {1, 2}), ...
        'mesn_v2_rate_map:invalidActivationCfg');
    bad = [identity_cfg(), identity_cfg()];
    testCase.verifyError(@() mesn_v2_rate_map(0, bad), ...
        'mesn_v2_rate_map:invalidActivationCfg');
end

function testMissingActivationFields(testCase)
    cfg = identity_cfg();
    cfg = rmfield(cfg, 'mode');
    testCase.verifyError(@() mesn_v2_rate_map(0, cfg), ...
        'mesn_v2_rate_map:missingField');
    cfg = identity_cfg();
    cfg = rmfield(cfg, 'S_a');
    testCase.verifyError(@() mesn_v2_rate_map(0, cfg), ...
        'mesn_v2_rate_map:missingField');
end

function testUnsupportedMode(testCase)
    cfg = identity_cfg();
    cfg.mode = 'logistic';
    testCase.verifyError(@() mesn_v2_rate_map(0, cfg), ...
        'mesn_v2_rate_map:unsupportedMode');
    cfg = identity_cfg();
    cfg.mode = 1;
    testCase.verifyError(@() mesn_v2_rate_map(0, cfg), ...
        'mesn_v2_rate_map:unsupportedMode');
end

function testInvalidSaValues(testCase)
    cfg = piecewise_cfg(0.5, 0.0);
    bad = {-0.1, 1.1, [0.5 0.6], NaN, Inf, 0.5+1i, 'a'};
    for i = 1:numel(bad)
        cfg.S_a = bad{i};
        testCase.verifyError(@() mesn_v2_rate_map(0, cfg), ...
            'mesn_v2_rate_map:invalidSa');
    end
end

function testInvalidScValues(testCase)
    cfg = piecewise_cfg(0.5, 0.0);
    bad = {[0 0], NaN, Inf, 0.1+1i, 'b'};
    for i = 1:numel(bad)
        cfg.S_c = bad{i};
        testCase.verifyError(@() mesn_v2_rate_map(0, cfg), ...
            'mesn_v2_rate_map:invalidSc');
    end
end

function testInvalidQValues(testCase)
    cfg = identity_cfg();
    bad = {'x', NaN, Inf, 1+1i};
    for i = 1:numel(bad)
        testCase.verifyError(@() mesn_v2_rate_map(bad{i}, cfg), ...
            'mesn_v2_rate_map:invalidQ');
    end
end

function testDeterministicReplayAndRngUnchanged(testCase)
    cfg = piecewise_cfg(0.85, 0.4);
    q = [-0.5, 0, 0.5, 1.2];
    rng(2468, 'twister');
    s0 = rng;
    [r1, info1] = mesn_v2_rate_map(q, cfg);
    [r2, info2] = mesn_v2_rate_map(q, cfg);
    s1 = rng;
    testCase.verifyEqual(r1, r2, 'AbsTol', 0);
    testCase.verifyEqual(info1, info2);
    testCase.verifyEqual(s0.Type, s1.Type);
    testCase.verifyEqual(s0.Seed, s1.Seed);
    testCase.verifyEqual(s0.State, s1.State);
end

function testActivationCfgUnchanged(testCase)
    cfg = piecewise_cfg(0.7, 0.1);
    cfg_copy = cfg;
    mesn_v2_rate_map(0.2, cfg);
    testCase.verifyEqual(cfg, cfg_copy);
end

function testSchemaAndContentHash(testCase)
    spec = mesn_v2_rate_map_spec();
    testCase.verifyEqual(spec.schema_version, 'mesn_v2_rate_map_v1');
    payload = rmfield(spec, 'content_hash');
    testCase.verifyEqual(spec.content_hash, canonical_sha256(payload));
    testCase.verifyEqual(spec.content_hash, ...
        '483b6192099426b1c22f29a35e04d9e22c508826a9d334f8da8b0134b94fe257');
    spec2 = mesn_v2_rate_map_spec();
    testCase.verifyEqual(spec, spec2);
end

function testBoundedInfoWithoutDataCopies(testCase)
    cfg = piecewise_cfg(0.5, 0.0);
    q = [0.1, 0.9];
    [~, info] = mesn_v2_rate_map(q, cfg);
    testCase.verifyTrue(isfield(info, 'schema_version'));
    testCase.verifyTrue(isfield(info, 'content_hash'));
    testCase.verifyTrue(isfield(info, 'mode'));
    testCase.verifyTrue(isfield(info, 'shape_preserved'));
    testCase.verifyFalse(isfield(info, 'q'));
    testCase.verifyFalse(isfield(info, 'r'));
end

function testStableErrorIdentifiers(testCase)
    testCase.verifyError(@() mesn_v2_rate_map(NaN, identity_cfg()), ...
        'mesn_v2_rate_map:invalidQ');
    testCase.verifyError(@() mesn_v2_rate_map(0, []), ...
        'mesn_v2_rate_map:invalidActivationCfg');
    cfg = identity_cfg();
    cfg.mode = 'unknown';
    testCase.verifyError(@() mesn_v2_rate_map(0, cfg), ...
        'mesn_v2_rate_map:unsupportedMode');
end

function cfg = identity_cfg()
    cfg = struct();
    cfg.mode = 'identity';
    cfg.S_a = [];
    cfg.S_c = [];
end

function cfg = piecewise_cfg(S_a, S_c)
    cfg = struct();
    cfg.mode = 'piecewise_sigmoid';
    cfg.S_a = S_a;
    cfg.S_c = S_c;
end
