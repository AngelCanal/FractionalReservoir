function tests = test_fractional_mesn_v2_engine
%TEST_FRACTIONAL_MESN_V2_ENGINE Unit tests for isolated Fractional MESN v2 engine.
%
% Numerical alpha values in this file are deterministic engineering fixtures,
% not scientific candidates.
this_file = mfilename('fullpath');
repo_root = fileparts(fileparts(fileparts(this_file)));
addpath(genpath(fullfile(repo_root, 'src')));
addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
tests = functiontests({ ...
    @testValidInputOnlyConfig, ...
    @testValidLinearConfig, ...
    @testRecurrenceModeCanonicalization, ...
    @testInputOnlyWNormalization, ...
    @testInvalidOrMissingConfigFields, ...
    @testInvalidN, ...
    @testInvalidAlpha, ...
    @testInvalidDt, ...
    @testInvalidTauX, ...
    @testInvalidWin, ...
    @testInvalidWPerMode, ...
    @testInvalidRecurrenceMode, ...
    @testInvalidU, ...
    @testInvalidX0, ...
    @testScalarX0Broadcast, ...
    @testRowAndColumnX0Normalization, ...
    @testN0OutputAndMetadata, ...
    @testAlphaOneSingleNeuronInputOnlyExactRecurrence, ...
    @testAlphaOneMultiNeuronInputOnlyExactRecurrence, ...
    @testAlphaOneSingleNeuronLinearExactRecurrence, ...
    @testAlphaOneMultiNeuronLinearExactRecurrence, ...
    @testAlphaLessThanOneInputOnlyMatchesManualCore, ...
    @testAlphaLessThanOneLinearMatchesManualCore, ...
    @testEarlyHistoryPerturbationChangesLaterFractionalState, ...
    @testFutureInputPerturbationLeavesEarlierStatesUnchanged, ...
    @testFullHistoryAndNoTruncationMetadata, ...
    @testBitwiseDeterministicReplay, ...
    @testCallerRngUnchanged, ...
    @testValueClassObjectUnchangedAfterSimulate, ...
    @testRepeatedSimulationsDoNotLeakState, ...
    @testZeroInputAndZeroX0RemainZero, ...
    @testConstantEquilibriumFixture, ...
    @testZeroLinearRecurrenceMatchesInputOnly, ...
    @testAlphaOneZeroDriveGeometricDecay, ...
    @testEngineSchemaAndHash, ...
    @testCoreSchemaAndHashPropagated, ...
    @testMechanismDeclarationsPoliciesAndMetadata, ...
    @testStableFractionalMesnErrorIdentifiers});
end

function testValidInputOnlyConfig(testCase)
    cfg = validate_fractional_mesn_v2_config(base_cfg('input_only'));
    testCase.verifyEqual(cfg.n, 3);
    testCase.verifyEqual(cfg.recurrence_mode, 'input_only');
    testCase.verifyEqual(cfg.W, zeros(3, 3), 'AbsTol', 0);
end

function testValidLinearConfig(testCase)
    cfg_in = base_cfg('linear');
    cfg = validate_fractional_mesn_v2_config(cfg_in);
    testCase.verifyEqual(cfg.recurrence_mode, 'linear');
    testCase.verifyEqual(cfg.W, cfg_in.W, 'AbsTol', 0);
end

function testRecurrenceModeCanonicalization(testCase)
    cfg_in = base_cfg("input_only");
    cfg = validate_fractional_mesn_v2_config(cfg_in);
    testCase.verifyClass(cfg.recurrence_mode, 'char');
    testCase.verifyEqual(cfg.recurrence_mode, 'input_only');
end

function testInputOnlyWNormalization(testCase)
    cfg_in = base_cfg('input_only');
    cfg_in.W = [];
    cfg = validate_fractional_mesn_v2_config(cfg_in);
    testCase.verifyEqual(cfg.W, zeros(cfg.n, cfg.n), 'AbsTol', 0);
end

function testInvalidOrMissingConfigFields(testCase)
    cfg = base_cfg('input_only');
    cfg = rmfield(cfg, 'alpha');
    testCase.verifyError(@() validate_fractional_mesn_v2_config(cfg), ...
        'FractionalMESN_v2:missingField');
    testCase.verifyError(@() validate_fractional_mesn_v2_config([]), ...
        'FractionalMESN_v2:invalidConfig');
end

function testInvalidN(testCase)
    bad = {0, -1, 1.5, [1 2], NaN, Inf, 1+1i};
    for i = 1:numel(bad)
        cfg = base_cfg('input_only');
        cfg.n = bad{i};
        testCase.verifyError(@() validate_fractional_mesn_v2_config(cfg), ...
            'FractionalMESN_v2:invalidN');
    end
end

function testInvalidAlpha(testCase)
    bad = {0, -0.1, 1.1, NaN, Inf, 0.5+1i, [0.5 0.6]};
    for i = 1:numel(bad)
        cfg = base_cfg('input_only');
        cfg.alpha = bad{i};
        testCase.verifyError(@() validate_fractional_mesn_v2_config(cfg), ...
            'FractionalMESN_v2:invalidAlpha');
    end
end

function testInvalidDt(testCase)
    bad = {0, -0.1, NaN, Inf, 0.1+1i, [0.1 0.2]};
    for i = 1:numel(bad)
        cfg = base_cfg('input_only');
        cfg.dt = bad{i};
        testCase.verifyError(@() validate_fractional_mesn_v2_config(cfg), ...
            'FractionalMESN_v2:invalidDt');
    end
end

function testInvalidTauX(testCase)
    bad = {0, -1, NaN, Inf, 1+1i, [1 2]};
    for i = 1:numel(bad)
        cfg = base_cfg('input_only');
        cfg.tau_x = bad{i};
        testCase.verifyError(@() validate_fractional_mesn_v2_config(cfg), ...
            'FractionalMESN_v2:invalidTauX');
    end
end

function testInvalidWin(testCase)
    bad = {[], ones(2, 1), ones(3, 1, 2), [1; NaN; 3], [1; 2+1i; 3], 'x'};
    for i = 1:numel(bad)
        cfg = base_cfg('input_only');
        cfg.W_in = bad{i};
        testCase.verifyError(@() validate_fractional_mesn_v2_config(cfg), ...
            'FractionalMESN_v2:invalidWin');
    end
end

function testInvalidWPerMode(testCase)
    cfg = base_cfg('input_only');
    cfg.W = eye(cfg.n);
    testCase.verifyError(@() validate_fractional_mesn_v2_config(cfg), ...
        'FractionalMESN_v2:invalidW');

    cfg = base_cfg('linear');
    cfg.W = [];
    testCase.verifyError(@() validate_fractional_mesn_v2_config(cfg), ...
        'FractionalMESN_v2:invalidW');

    cfg = base_cfg('linear');
    cfg.W = eye(cfg.n + 1);
    testCase.verifyError(@() validate_fractional_mesn_v2_config(cfg), ...
        'FractionalMESN_v2:invalidW');
end

function testInvalidRecurrenceMode(testCase)
    bad = {42, "LINEAR", 'input-only', 'linear '};
    for i = 1:numel(bad)
        cfg = base_cfg('input_only');
        cfg.recurrence_mode = bad{i};
        testCase.verifyError(@() validate_fractional_mesn_v2_config(cfg), ...
            'FractionalMESN_v2:invalidRecurrenceMode');
    end
end

function testInvalidU(testCase)
    engine = FractionalMESN_v2(base_cfg('input_only'));
    bad = {[1 2], [1; NaN], [1; 2+1i], ones(3, 2, 1)};
    for i = 1:numel(bad)
        testCase.verifyError(@() simulate(engine, bad{i}, 0), ...
            'FractionalMESN_v2:invalidU');
    end
end

function testInvalidX0(testCase)
    engine = FractionalMESN_v2(base_cfg('input_only'));
    bad = {[1 2], [1; 2], ones(2, 2), NaN, Inf, 1+1i};
    for i = 1:numel(bad)
        testCase.verifyError(@() simulate(engine, zeros(0, 1), bad{i}), ...
            'FractionalMESN_v2:invalidX0');
    end
end

function testScalarX0Broadcast(testCase)
    engine = FractionalMESN_v2(base_cfg('input_only'));
    [X, ~] = simulate(engine, zeros(0, 1), 2.5);
    testCase.verifyEqual(X, 2.5 * ones(1, 3), 'AbsTol', 0);
end

function testRowAndColumnX0Normalization(testCase)
    engine = FractionalMESN_v2(base_cfg('input_only'));
    [Xr, ~] = simulate(engine, zeros(0, 1), [1 2 3]);
    [Xc, ~] = simulate(engine, zeros(0, 1), [1; 2; 3]);
    testCase.verifyEqual(Xr, Xc, 'AbsTol', 0);
end

function testN0OutputAndMetadata(testCase)
    engine = FractionalMESN_v2(base_cfg('input_only'));
    [X, info] = simulate(engine, zeros(0, 1), [1 2 3]);
    testCase.verifyEqual(X, [1 2 3], 'AbsTol', 0);
    testCase.verifyEqual(size(X), [1, 3]);
    testCase.verifyEqual(info.n_steps, 0);
    verify_common_info(testCase, info, engine.Config, 0);
end

function testAlphaOneSingleNeuronInputOnlyExactRecurrence(testCase)
    cfg = base_cfg('input_only');
    cfg.n = 1;
    cfg.alpha = 1;
    cfg.W_in = 2;
    cfg.W = [];
    engine = FractionalMESN_v2(cfg);
    U = [0.1; -0.2; 0.4; 0.0];
    x0 = 0.3;
    [X, info] = simulate(engine, U, x0);
    expected = manual_alpha_one(engine.Config, U, x0);
    testCase.verifyEqual(X, expected, 'AbsTol', 0);
    verify_common_info(testCase, info, engine.Config, size(U, 1));
end

function testAlphaOneMultiNeuronInputOnlyExactRecurrence(testCase)
    cfg = base_cfg('input_only');
    cfg.alpha = 1;
    cfg.n = 2;
    cfg.W_in = [1, 2; -1, 0.5];
    cfg.W = [];
    engine = FractionalMESN_v2(cfg);
    U = [0.2, 0.1; -0.1, 0.3; 0.0, -0.2];
    x0 = [0.5, -0.25];
    [X, ~] = simulate(engine, U, x0);
    expected = manual_alpha_one(engine.Config, U, x0);
    testCase.verifyEqual(X, expected, 'AbsTol', 0);
end

function testAlphaOneSingleNeuronLinearExactRecurrence(testCase)
    cfg = base_cfg('linear');
    cfg.n = 1;
    cfg.alpha = 1;
    cfg.W_in = 0.75;
    cfg.W = 0.4;
    engine = FractionalMESN_v2(cfg);
    U = [0.2; 0.0; -0.1; 0.3];
    x0 = 0.6;
    [X, ~] = simulate(engine, U, x0);
    expected = manual_alpha_one(engine.Config, U, x0);
    testCase.verifyEqual(X, expected, 'AbsTol', 0);
end

function testAlphaOneMultiNeuronLinearExactRecurrence(testCase)
    cfg = base_cfg('linear');
    cfg.alpha = 1;
    cfg.n = 2;
    cfg.W_in = [1, 0; 0.5, -1];
    cfg.W = [0.25, -0.1; 0.2, 0.3];
    engine = FractionalMESN_v2(cfg);
    U = [0.1, 0.2; -0.2, 0.0; 0.3, -0.4];
    x0 = [0.2, -0.1];
    [X, info] = simulate(engine, U, x0);
    expected = manual_alpha_one(engine.Config, U, x0);
    testCase.verifyEqual(X, expected, 'AbsTol', 0);
    testCase.verifyTrue(info.alpha_one_branch_used);
end

function testAlphaLessThanOneInputOnlyMatchesManualCore(testCase)
    cfg = base_cfg('input_only');
    cfg.alpha = 0.6;
    cfg.n = 2;
    cfg.W_in = [1; -0.5];
    cfg.W = [];
    engine = FractionalMESN_v2(cfg);
    U = [0.1; 0.0; -0.2; 0.3];
    x0 = [0.4, -0.1];
    [X, ~] = simulate(engine, U, x0);
    expected = manual_fractional(engine.Config, U, x0);
    testCase.verifyEqual(X, expected, 'AbsTol', 0);
end

function testAlphaLessThanOneLinearMatchesManualCore(testCase)
    cfg = base_cfg('linear');
    cfg.alpha = 0.7;
    cfg.n = 2;
    cfg.W_in = [1, 0; 0.5, -1];
    cfg.W = [0.1, 0.2; -0.3, 0.4];
    engine = FractionalMESN_v2(cfg);
    U = [0.2, -0.1; 0.1, 0.0; -0.3, 0.4; 0.0, 0.2];
    x0 = [0.2, -0.2];
    [X, ~] = simulate(engine, U, x0);
    expected = manual_fractional(engine.Config, U, x0);
    testCase.verifyEqual(X, expected, 'AbsTol', 0);
end

function testEarlyHistoryPerturbationChangesLaterFractionalState(testCase)
    cfg = base_cfg('input_only');
    cfg.alpha = 0.65;
    engine = FractionalMESN_v2(cfg);
    U = [0.1; 0.2; -0.1; 0.0; 0.4];
    [Xa, ~] = simulate(engine, U, 0.2);
    [Xb, ~] = simulate(engine, U, 0.25);
    testCase.verifyNotEqual(Xa(end), Xb(end));
end

function testFutureInputPerturbationLeavesEarlierStatesUnchanged(testCase)
    cfg = base_cfg('linear');
    cfg.alpha = 0.55;
    cfg.n = 2;
    cfg.W_in = [1; -1];
    cfg.W = [0.1, 0.2; 0.0, 0.15];
    engine = FractionalMESN_v2(cfg);
    U1 = [0.1; 0.2; 0.3; 0.4; 0.5];
    U2 = U1;
    U2(5) = 10;
    x0 = [0.2, -0.2];
    [X1, ~] = simulate(engine, U1, x0);
    [X2, ~] = simulate(engine, U2, x0);
    testCase.verifyEqual(X1(1:5, :), X2(1:5, :), 'AbsTol', 0);
end

function testFullHistoryAndNoTruncationMetadata(testCase)
    cfg = base_cfg('input_only');
    cfg.alpha = 0.6;
    engine = FractionalMESN_v2(cfg);
    [~, info] = simulate(engine, [0.1; 0.2; 0.3], 0);
    testCase.verifyTrue(info.full_history_used);
    testCase.verifyFalse(info.truncated);
end

function testBitwiseDeterministicReplay(testCase)
    engine = FractionalMESN_v2(base_cfg('linear'));
    U = [0.1; -0.2; 0.3; 0.0];
    x0 = [0.5, -0.5, 0.25];
    [X1, info1] = simulate(engine, U, x0);
    [X2, info2] = simulate(engine, U, x0);
    testCase.verifyEqual(X1, X2, 'AbsTol', 0);
    testCase.verifyEqual(info1, info2);
end

function testCallerRngUnchanged(testCase)
    rng(2468, 'twister');
    s0 = rng;
    engine = FractionalMESN_v2(base_cfg('input_only'));
    simulate(engine, [0.1; -0.2; 0.3], 0.4);
    s1 = rng;
    testCase.verifyEqual(s0.Type, s1.Type);
    testCase.verifyEqual(s0.Seed, s1.Seed);
    testCase.verifyEqual(s0.State, s1.State);
end

function testValueClassObjectUnchangedAfterSimulate(testCase)
    engine = FractionalMESN_v2(base_cfg('linear'));
    before = engine;
    simulate(engine, [0.1; 0.2], [0.3, -0.1, 0.2]);
    testCase.verifyTrue(isequaln(before, engine));
end

function testRepeatedSimulationsDoNotLeakState(testCase)
    engine = FractionalMESN_v2(base_cfg('linear'));
    U = [0.1; 0.2; 0.0];
    x0 = [0.5, 0.1, -0.2];
    [X1, ~] = simulate(engine, U, x0);
    [X2, ~] = simulate(engine, U, x0);
    testCase.verifyEqual(X1, X2, 'AbsTol', 0);
end

function testZeroInputAndZeroX0RemainZero(testCase)
    engine = FractionalMESN_v2(base_cfg('input_only'));
    [X, ~] = simulate(engine, zeros(5, 1), 0);
    testCase.verifyEqual(X, zeros(6, 3), 'AbsTol', 0);
end

function testConstantEquilibriumFixture(testCase)
    cfg = base_cfg('input_only');
    cfg.n = 2;
    cfg.W_in = eye(2);
    cfg.alpha = 0.6;
    engine = FractionalMESN_v2(cfg);
    c = [1.5, -0.5];
    U = repmat(c, 4, 1);
    [X, ~] = simulate(engine, U, c);
    testCase.verifyEqual(X, repmat(c, 5, 1), 'AbsTol', 1e-14);
end

function testZeroLinearRecurrenceMatchesInputOnly(testCase)
    cfg_input = base_cfg('input_only');
    cfg_input.n = 2;
    cfg_input.W_in = [1; -0.5];
    cfg_input.alpha = 0.65;
    cfg_linear = cfg_input;
    cfg_linear.recurrence_mode = 'linear';
    cfg_linear.W = zeros(2, 2);
    engine_input = FractionalMESN_v2(cfg_input);
    engine_linear = FractionalMESN_v2(cfg_linear);
    U = [0.1; 0.0; -0.2; 0.3];
    x0 = [0.4, -0.2];
    [Xi, ~] = simulate(engine_input, U, x0);
    [Xl, ~] = simulate(engine_linear, U, x0);
    testCase.verifyEqual(Xi, Xl, 'AbsTol', 0);
end

function testAlphaOneZeroDriveGeometricDecay(testCase)
    cfg = base_cfg('input_only');
    cfg.alpha = 1;
    cfg.n = 1;
    cfg.W_in = 0;
    engine = FractionalMESN_v2(cfg);
    U = zeros(6, 1);
    x0 = 2;
    [X, ~] = simulate(engine, U, x0);
    ratio = (cfg.tau_x / cfg.dt) / ((cfg.tau_x / cfg.dt) + 1);
    expected = x0 * ratio .^ (0:6).';
    testCase.verifyEqual(X, expected, 'AbsTol', 0);
end

function testEngineSchemaAndHash(testCase)
    spec = fractional_mesn_v2_engine_spec();
    testCase.verifyEqual(spec.schema_version, 'fractional_mesn_v2_engine_v1');
    payload = rmfield(spec, 'content_hash');
    testCase.verifyEqual(spec.content_hash, canonical_sha256(payload));
    testCase.verifyEqual(spec.content_hash, ...
        '38414814b75f35c997e695347ec8f9979660108e053d8f676329758e4fc6971d');
end

function testCoreSchemaAndHashPropagated(testCase)
    spec = fractional_mesn_v2_engine_spec();
    engine = FractionalMESN_v2(base_cfg('input_only'));
    [~, info] = simulate(engine, zeros(0, 1), 0);
    testCase.verifyEqual(spec.core_schema_version, ...
        'fractional_mesn_v2_caputo_l1_core_v1');
    testCase.verifyEqual(spec.core_content_hash, ...
        '3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f');
    testCase.verifyEqual(info.core_schema_version, ...
        'fractional_mesn_v2_caputo_l1_core_v1');
    testCase.verifyEqual(info.core_content_hash, ...
        '3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f');
end

function testMechanismDeclarationsPoliciesAndMetadata(testCase)
    spec = fractional_mesn_v2_engine_spec();
    testCase.verifyEqual(spec.included_mechanisms, ...
        {'input_plumbing', 'linear_recurrence', 'caputo_l1_stepping'});
    testCase.verifyEqual(spec.excluded_mechanisms, ...
        {'nonlinear_rate_map', 'sfa', 'std', 'dale_law', 'delays', ...
         'bias', 'noise', 'readout', 'fast_convolution', 'continuation'});
    testCase.verifyEqual(spec.object_semantics, 'value_class_stateless_simulate');
    testCase.verifyEqual(spec.continuation_policy, ...
        'not_supported_in_e2_requires_separate_preregistration');
end

function testStableFractionalMesnErrorIdentifiers(testCase)
    testCase.verifyError(@() FractionalMESN_v2(), ...
        'FractionalMESN_v2:missingConfig');

    cfg = base_cfg('input_only');
    cfg.alpha = 0;
    testCase.verifyError(@() FractionalMESN_v2(cfg), ...
        'FractionalMESN_v2:invalidAlpha');
end

function cfg = base_cfg(mode)
    if nargin < 1
        mode = 'input_only';
    end
    cfg = struct();
    cfg.n = 3;
    cfg.alpha = 0.75;
    cfg.dt = 0.1;
    cfg.tau_x = 1.5;
    cfg.W_in = [1; -0.5; 0.25];
    if strcmp(char(mode), 'linear')
        cfg.W = [0.1, 0.0, -0.2; 0.05, 0.1, 0.0; -0.1, 0.2, 0.15];
        cfg.recurrence_mode = 'linear';
    else
        cfg.W = [];
        cfg.recurrence_mode = char(mode);
    end
end

function X = manual_alpha_one(cfg, U, x0)
    x_prev = normalize_x0_for_test(x0, cfg.n);
    N = size(U, 1);
    X = zeros(N + 1, cfg.n);
    X(1, :) = x_prev;
    ratio = cfg.tau_x / cfg.dt;
    for k = 1:N
        u_prev = U(k, :);
        input_prev = (cfg.W_in * u_prev.').';
        if strcmp(cfg.recurrence_mode, 'input_only')
            recurrent_prev = zeros(1, cfg.n);
        else
            recurrent_prev = (cfg.W * x_prev.').';
        end
        drive_prev = input_prev + recurrent_prev;
        x_prev = ((ratio * x_prev) + drive_prev) / (ratio + 1);
        X(k + 1, :) = x_prev;
    end
end

function X = manual_fractional(cfg, U, x0)
    x0_row = normalize_x0_for_test(x0, cfg.n);
    N = size(U, 1);
    X = zeros(N + 1, cfg.n);
    X(1, :) = x0_row;
    for k = 1:N
        x_previous = X(k, :);
        u_previous = U(k, :);
        input_previous = (cfg.W_in * u_previous.').';
        if strcmp(cfg.recurrence_mode, 'input_only')
            recurrent_previous = zeros(1, cfg.n);
        else
            recurrent_previous = (cfg.W * x_previous.').';
        end
        drive_previous = input_previous + recurrent_previous;
        X(k + 1, :) = caputo_l1_semiimplicit_step( ...
            X(1:k, :), drive_previous, cfg.dt, cfg.alpha, cfg.tau_x);
    end
end

function x0_row = normalize_x0_for_test(x0, n)
    if isscalar(x0)
        x0_row = repmat(double(x0), 1, n);
    else
        x0_row = reshape(double(x0), 1, n);
    end
end

function verify_common_info(testCase, info, cfg, N)
    testCase.verifyEqual(info.engine_schema_version, ...
        'fractional_mesn_v2_engine_v1');
    testCase.verifyEqual(info.core_schema_version, ...
        'fractional_mesn_v2_caputo_l1_core_v1');
    testCase.verifyEqual(info.core_content_hash, ...
        '3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f');
    testCase.verifyEqual(info.alpha, cfg.alpha);
    testCase.verifyEqual(info.alpha_one_branch_used, cfg.alpha == 1);
    testCase.verifyEqual(info.n_steps, N);
    testCase.verifyEqual(info.recurrence_mode, cfg.recurrence_mode);
    testCase.verifyTrue(info.full_history_used);
    testCase.verifyFalse(info.truncated);
    testCase.verifyEqual(info.input_index, 'n_minus_1');
    testCase.verifyEqual(info.recurrence_index, 'n_minus_1');
end
