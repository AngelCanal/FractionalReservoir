function tests = test_fractional_mesn_v2_mechanistic_engine
%TEST_FRACTIONAL_MESN_V2_MECHANISTIC_ENGINE Unit tests for no-delay mechanistic engine.
%
% Numerical alpha values in this file are deterministic engineering fixtures,
% not scientific candidates. No governed seeds.
this_file = mfilename('fullpath');
repo_root = fileparts(fileparts(fileparts(this_file)));
addpath(genpath(fullfile(repo_root, 'src')));
addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
tests = functiontests({ ...
    @testValidPiecewiseAndIdentityConfig, ...
    @testNormalizedFieldOrderAndNoDefaults, ...
    @testSignAndActivationNormalization, ...
    @testMissingAndInvalidConfigFields, ...
    @testInvalidAlphaDtTauAndMatrices, ...
    @testDaleSignViolationUnderMechanisticPrefix, ...
    @testInvalidActivationAndStableErrorIds, ...
    @testCfgInUnchanged, ...
    @testInvalidUAndX0, ...
    @testX0BroadcastAndNormalization, ...
    @testN0ShapesValuesAndMetadata, ...
    @testPhysicalTimeRowAlignment, ...
    @testAlphaOneIndependentIdentitySingleAndMulti, ...
    @testAlphaOneIndependentPiecewiseSingleAndMulti, ...
    @testAlphaLessThanOneManualCoreIdentityAndPiecewise, ...
    @testRecurrenceUsesRNotXAndRateRecomputed, ...
    @testCausalityFutureInputAndEarlyHistory, ...
    @testCompleteHistoryMetadataAndSingleCorePath, ...
    @testDeterminismRngValueObjectAndNoMutation, ...
    @testE2InputOnlyLimitingControls, ...
    @testE2LinearLimitingControlsAndIdentityQR, ...
    @testZeroStateConstantAndAlphaOneDecay, ...
    @testEngineSchemaHashDependenciesAndBoundedInfo, ...
    @testNoProductionCallerIntegration});
end

function testValidPiecewiseAndIdentityConfig(testCase)
    cfg_pw = validate_fractional_mesn_v2_mechanistic_config( ...
        base_cfg('piecewise_sigmoid'));
    testCase.verifyEqual(cfg_pw.n, 3);
    testCase.verifyEqual(cfg_pw.activation.mode, 'piecewise_sigmoid');
    testCase.verifyEqual(cfg_pw.activation.S_a, 0.7);
    testCase.verifyEqual(cfg_pw.activation.S_c, 0.2);

    cfg_id = validate_fractional_mesn_v2_mechanistic_config( ...
        base_cfg('identity'));
    testCase.verifyEqual(cfg_id.activation.mode, 'identity');
    testCase.verifyEqual(cfg_id.activation.S_a, []);
    testCase.verifyEqual(cfg_id.activation.S_c, []);
end

function testNormalizedFieldOrderAndNoDefaults(testCase)
    cfg = validate_fractional_mesn_v2_mechanistic_config(base_cfg('identity'));
    testCase.verifyEqual(fieldnames(cfg), { ...
        'n'; 'alpha'; 'dt'; 'tau_x'; 'W_in'; 'W'; ...
        'presynaptic_signs'; 'activation'});
    testCase.verifyEqual(fieldnames(cfg.activation), {'mode'; 'S_a'; 'S_c'});

    bare = struct();
    bare.n = 2;
    bare.alpha = 0.5;
    bare.dt = 0.1;
    bare.tau_x = 1;
    bare.W_in = [1; 0];
    bare.W = [0.1, -0.2; 0.0, -0.1];
    bare.presynaptic_signs = [1, -1];
    bare.activation = struct('mode', 'identity', 'S_a', [], 'S_c', []);
    cfg2 = validate_fractional_mesn_v2_mechanistic_config(bare);
    testCase.verifyEqual(cfg2.alpha, 0.5);
    testCase.verifyFalse(isfield(cfg2, 'recurrence_mode'));
end

function testSignAndActivationNormalization(testCase)
    cfg_in = base_cfg('identity');
    cfg_in.presynaptic_signs = [1; 1; -1];
    cfg = validate_fractional_mesn_v2_mechanistic_config(cfg_in);
    testCase.verifyEqual(size(cfg.presynaptic_signs), [1, 3]);
    testCase.verifyEqual(cfg.presynaptic_signs, [1, 1, -1]);

    cfg_in = base_cfg('identity');
    cfg_in.activation.mode = "identity";
    cfg_in.activation = rmfield(cfg_in.activation, 'S_a');
    cfg_in.activation = rmfield(cfg_in.activation, 'S_c');
    cfg = validate_fractional_mesn_v2_mechanistic_config(cfg_in);
    testCase.verifyClass(cfg.activation.mode, 'char');
    testCase.verifyEqual(cfg.activation.mode, 'identity');
    testCase.verifyEqual(cfg.activation.S_a, []);
    testCase.verifyEqual(cfg.activation.S_c, []);
end

function testMissingAndInvalidConfigFields(testCase)
    cfg = base_cfg('identity');
    cfg = rmfield(cfg, 'alpha');
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_config(cfg), ...
        'FractionalMESN_v2_mechanistic:missingField');
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_config([]), ...
        'FractionalMESN_v2_mechanistic:invalidConfig');

    bad_n = {0, -1, 1.5, [1 2], NaN, Inf, 1+1i};
    for i = 1:numel(bad_n)
        cfg = base_cfg('identity');
        cfg.n = bad_n{i};
        testCase.verifyError( ...
            @() validate_fractional_mesn_v2_mechanistic_config(cfg), ...
            'FractionalMESN_v2_mechanistic:invalidN');
    end
end

function testInvalidAlphaDtTauAndMatrices(testCase)
    bad_alpha = {0, -0.1, 1.1, NaN, Inf, 0.5+1i, [0.5 0.6]};
    for i = 1:numel(bad_alpha)
        cfg = base_cfg('identity');
        cfg.alpha = bad_alpha{i};
        testCase.verifyError( ...
            @() validate_fractional_mesn_v2_mechanistic_config(cfg), ...
            'FractionalMESN_v2_mechanistic:invalidAlpha');
    end

    bad_pos = {0, -0.1, NaN, Inf, 0.1+1i, [0.1 0.2]};
    for i = 1:numel(bad_pos)
        cfg = base_cfg('identity');
        cfg.dt = bad_pos{i};
        testCase.verifyError( ...
            @() validate_fractional_mesn_v2_mechanistic_config(cfg), ...
            'FractionalMESN_v2_mechanistic:invalidDt');
        cfg = base_cfg('identity');
        cfg.tau_x = bad_pos{i};
        testCase.verifyError( ...
            @() validate_fractional_mesn_v2_mechanistic_config(cfg), ...
            'FractionalMESN_v2_mechanistic:invalidTauX');
    end

    bad_win = {[], ones(2, 1), ones(3, 1, 2), [1; NaN; 3], [1; 2+1i; 3], 'x'};
    for i = 1:numel(bad_win)
        cfg = base_cfg('identity');
        cfg.W_in = bad_win{i};
        testCase.verifyError( ...
            @() validate_fractional_mesn_v2_mechanistic_config(cfg), ...
            'FractionalMESN_v2_mechanistic:invalidWin');
    end

    bad_w = {[], ones(2, 2), ones(3, 3, 1), [NaN, 0, 0; 0, 0, 0; 0, 0, 0], ...
        [1+1i, 0, 0; 0, 0, 0; 0, 0, 0], 'W'};
    for i = 1:numel(bad_w)
        cfg = base_cfg('identity');
        cfg.W = bad_w{i};
        testCase.verifyError( ...
            @() validate_fractional_mesn_v2_mechanistic_config(cfg), ...
            'FractionalMESN_v2_mechanistic:invalidW');
    end

    cfg = base_cfg('identity');
    cfg.presynaptic_signs = [1, 0, -1];
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_config(cfg), ...
        'FractionalMESN_v2_mechanistic:invalidPresynapticSigns');
    cfg = base_cfg('identity');
    cfg.presynaptic_signs = [1, 1];
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_config(cfg), ...
        'FractionalMESN_v2_mechanistic:invalidPresynapticSigns');
end

function testDaleSignViolationUnderMechanisticPrefix(testCase)
    cfg = base_cfg('identity');
    cfg.W(1, 1) = -0.5;  % excitatory column negative entry
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_config(cfg), ...
        'FractionalMESN_v2_mechanistic:invalidW');

    cfg = base_cfg('identity');
    cfg.W(2, 3) = 0.4;  % inhibitory column positive entry
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_config(cfg), ...
        'FractionalMESN_v2_mechanistic:invalidW');
end

function testInvalidActivationAndStableErrorIds(testCase)
    cfg = base_cfg('identity');
    cfg.activation.mode = 'relu';
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_config(cfg), ...
        'FractionalMESN_v2_mechanistic:invalidActivation');

    cfg = base_cfg('piecewise_sigmoid');
    cfg.activation.S_a = 1.5;
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_config(cfg), ...
        'FractionalMESN_v2_mechanistic:invalidActivation');

    cfg = base_cfg('identity');
    cfg.activation.S_a = 0.1;
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_config(cfg), ...
        'FractionalMESN_v2_mechanistic:invalidActivation');

    testCase.verifyError(@() FractionalMESN_v2_mechanistic(), ...
        'FractionalMESN_v2_mechanistic:missingConfig');
end

function testCfgInUnchanged(testCase)
    cfg_in = base_cfg('piecewise_sigmoid');
    cfg_in.presynaptic_signs = [1; 1; -1];
    snapshot = cfg_in;
    validate_fractional_mesn_v2_mechanistic_config(cfg_in);
    testCase.verifyTrue(isequaln(cfg_in, snapshot));
end

function testInvalidUAndX0(testCase)
    engine = FractionalMESN_v2_mechanistic(base_cfg('identity'));
    bad_u = {[1 2], [1; NaN], [1; 2+1i], ones(3, 2, 1)};
    for i = 1:numel(bad_u)
        testCase.verifyError(@() simulate(engine, bad_u{i}, 0), ...
            'FractionalMESN_v2_mechanistic:invalidU');
    end

    bad_x0 = {[1 2], ones(2, 2), NaN, Inf, 1+1i};
    for i = 1:numel(bad_x0)
        testCase.verifyError( ...
            @() simulate(engine, zeros(0, 1), bad_x0{i}), ...
            'FractionalMESN_v2_mechanistic:invalidX0');
    end
end

function testX0BroadcastAndNormalization(testCase)
    engine = FractionalMESN_v2_mechanistic(base_cfg('identity'));
    [X, Q, R, ~] = simulate(engine, zeros(0, 1), 2.5);
    testCase.verifyEqual(X, 2.5 * ones(1, 3), 'AbsTol', 0);
    testCase.verifyEqual(Q, X, 'AbsTol', 0);
    testCase.verifyEqual(R, X, 'AbsTol', 0);

    [Xr, ~, ~, ~] = simulate(engine, zeros(0, 1), [1 2 3]);
    [Xc, ~, ~, ~] = simulate(engine, zeros(0, 1), [1; 2; 3]);
    testCase.verifyEqual(Xr, Xc, 'AbsTol', 0);
end

function testN0ShapesValuesAndMetadata(testCase)
    cfg = base_cfg('piecewise_sigmoid');
    engine = FractionalMESN_v2_mechanistic(cfg);
    x0 = [0.1, -0.2, 0.3];
    [X, Q, R, info] = simulate(engine, zeros(0, 1), x0);
    testCase.verifyEqual(size(X), [1, 3]);
    testCase.verifyEqual(size(Q), [1, 3]);
    testCase.verifyEqual(size(R), [1, 3]);
    testCase.verifyEqual(X, x0, 'AbsTol', 0);
    testCase.verifyEqual(Q, X, 'AbsTol', 0);
    expected_r = mesn_v2_rate_map(x0, engine.Config.activation);
    testCase.verifyEqual(R, expected_r, 'AbsTol', 0);
    testCase.verifyEqual(info.n_steps, 0);
    testCase.verifyEqual(info.alpha_one_branch_used, false);
    testCase.verifyTrue(info.full_history_used);
    testCase.verifyFalse(info.truncated);
    verify_common_info(testCase, info, engine.Config, 0);
end

function testPhysicalTimeRowAlignment(testCase)
    cfg = base_cfg('identity');
    cfg.alpha = 1;
    cfg.n = 1;
    cfg.W_in = 1;
    cfg.W = 0;
    cfg.presynaptic_signs = 1;
    engine = FractionalMESN_v2_mechanistic(cfg);
    U = [0.5; -0.25; 0.1];
    x0 = 0.2;
    [X, Q, R, ~] = simulate(engine, U, x0);
    testCase.verifyEqual(size(X), [4, 1]);
    testCase.verifyEqual(X(1), x0, 'AbsTol', 0);
    testCase.verifyEqual(Q, X, 'AbsTol', 0);
    testCase.verifyEqual(R, X, 'AbsTol', 0);
    ratio = cfg.tau_x / cfg.dt;
    x1 = (ratio * x0 + cfg.W_in * U(1)) / (ratio + 1);
    testCase.verifyEqual(X(2), x1, 'AbsTol', 0);
end

function testAlphaOneIndependentIdentitySingleAndMulti(testCase)
    cfg = base_cfg('identity');
    cfg.n = 1;
    cfg.alpha = 1;
    cfg.W_in = 0.75;
    cfg.W = 0.4;
    cfg.presynaptic_signs = 1;
    engine = FractionalMESN_v2_mechanistic(cfg);
    U = [0.2; 0.0; -0.1; 0.3];
    x0 = 0.6;
    [X, Q, R, info] = simulate(engine, U, x0);
    [Xe, Qe, Re] = independent_alpha_one(engine.Config, U, x0);
    testCase.verifyEqual(X, Xe, 'AbsTol', 0);
    testCase.verifyEqual(Q, Qe, 'AbsTol', 0);
    testCase.verifyEqual(R, Re, 'AbsTol', 0);
    testCase.verifyTrue(info.alpha_one_branch_used);

    cfg = base_cfg('identity');
    cfg.alpha = 1;
    cfg.n = 2;
    cfg.W_in = [1, 0; 0.5, -1];
    cfg.W = [0.25, -0.1; 0.2, -0.3];
    cfg.presynaptic_signs = [1, -1];
    engine = FractionalMESN_v2_mechanistic(cfg);
    U = [0.1, 0.2; -0.2, 0.0; 0.3, -0.4];
    x0 = [0.2, -0.1];
    [X, Q, R, ~] = simulate(engine, U, x0);
    [Xe, Qe, Re] = independent_alpha_one(engine.Config, U, x0);
    testCase.verifyEqual(X, Xe, 'AbsTol', 0);
    testCase.verifyEqual(Q, Qe, 'AbsTol', 0);
    testCase.verifyEqual(R, Re, 'AbsTol', 0);
end

function testAlphaOneIndependentPiecewiseSingleAndMulti(testCase)
    cfg = base_cfg('piecewise_sigmoid');
    cfg.n = 1;
    cfg.alpha = 1;
    cfg.W_in = 0.8;
    cfg.W = 0.35;
    cfg.presynaptic_signs = 1;
    engine = FractionalMESN_v2_mechanistic(cfg);
    U = [0.15; -0.05; 0.2; 0.0];
    x0 = 0.4;
    [X, Q, R, ~] = simulate(engine, U, x0);
    [Xe, Qe, Re] = independent_alpha_one(engine.Config, U, x0);
    testCase.verifyEqual(X, Xe, 'AbsTol', 0);
    testCase.verifyEqual(Q, Qe, 'AbsTol', 0);
    testCase.verifyEqual(R, Re, 'AbsTol', 0);

    cfg = base_cfg('piecewise_sigmoid');
    cfg.alpha = 1;
    cfg.n = 2;
    cfg.W_in = [1, 0; 0.5, -1];
    cfg.W = [0.2, -0.15; 0.1, -0.25];
    cfg.presynaptic_signs = [1, -1];
    engine = FractionalMESN_v2_mechanistic(cfg);
    U = [0.1, 0.2; -0.2, 0.0; 0.3, -0.1];
    x0 = [0.2, 0.1];
    [X, Q, R, ~] = simulate(engine, U, x0);
    [Xe, Qe, Re] = independent_alpha_one(engine.Config, U, x0);
    testCase.verifyEqual(X, Xe, 'AbsTol', 0);
    testCase.verifyEqual(Q, Qe, 'AbsTol', 0);
    testCase.verifyEqual(R, Re, 'AbsTol', 0);
end

function testAlphaLessThanOneManualCoreIdentityAndPiecewise(testCase)
    cfg = base_cfg('identity');
    cfg.alpha = 0.7;
    cfg.n = 2;
    cfg.W_in = [1, 0; 0.5, -1];
    cfg.W = [0.1, -0.2; 0.05, -0.15];
    cfg.presynaptic_signs = [1, -1];
    engine = FractionalMESN_v2_mechanistic(cfg);
    U = [0.2, -0.1; 0.1, 0.0; -0.3, 0.4; 0.0, 0.2];
    x0 = [0.2, -0.2];
    [X, Q, R, ~] = simulate(engine, U, x0);
    [Xe, Qe, Re] = manual_fractional_reference(engine.Config, U, x0);
    testCase.verifyEqual(X, Xe, 'AbsTol', 0);
    testCase.verifyEqual(Q, Qe, 'AbsTol', 0);
    testCase.verifyEqual(R, Re, 'AbsTol', 0);

    cfg = base_cfg('piecewise_sigmoid');
    cfg.alpha = 0.65;
    cfg.n = 2;
    cfg.W_in = [1; -0.5];
    cfg.W = [0.15, -0.2; 0.05, -0.1];
    cfg.presynaptic_signs = [1, -1];
    engine = FractionalMESN_v2_mechanistic(cfg);
    U = [0.1; 0.0; -0.2; 0.3];
    x0 = [0.4, -0.1];
    [X, Q, R, ~] = simulate(engine, U, x0);
    [Xe, Qe, Re] = manual_fractional_reference(engine.Config, U, x0);
    testCase.verifyEqual(X, Xe, 'AbsTol', 0);
    testCase.verifyEqual(Q, Qe, 'AbsTol', 0);
    testCase.verifyEqual(R, Re, 'AbsTol', 0);
end

function testRecurrenceUsesRNotXAndRateRecomputed(testCase)
    cfg = base_cfg('piecewise_sigmoid');
    cfg.alpha = 1;
    cfg.n = 2;
    cfg.W_in = [0; 0];
    cfg.W = [0.5, -0.3; 0.2, -0.4];
    cfg.presynaptic_signs = [1, -1];
    cfg.activation.S_a = 0.6;
    cfg.activation.S_c = 0.0;
    engine = FractionalMESN_v2_mechanistic(cfg);
    U = zeros(4, 1);
    x0 = [1.0, -0.5];
    [X, Q, R, ~] = simulate(engine, U, x0);

    [Xe_r, ~, ~] = independent_alpha_one(engine.Config, U, x0);
    testCase.verifyEqual(X, Xe_r, 'AbsTol', 0);
    testCase.verifyEqual(Q, X, 'AbsTol', 0);
    for j = 1:size(X, 1)
        testCase.verifyEqual(R(j, :), ...
            mesn_v2_rate_map(Q(j, :), engine.Config.activation), 'AbsTol', 0);
    end

    % Independent W*x path must differ when R ~= X.
    Xe_x = independent_alpha_one_on_x(engine.Config, U, x0);
    testCase.verifyFalse(isequal(X, Xe_x));
    testCase.verifyFalse(isequal(R, X));
end

function testCausalityFutureInputAndEarlyHistory(testCase)
    cfg = base_cfg('piecewise_sigmoid');
    cfg.alpha = 0.55;
    cfg.n = 2;
    cfg.W_in = [1; -1];
    cfg.W = [0.1, -0.2; 0.0, -0.15];
    cfg.presynaptic_signs = [1, -1];
    engine = FractionalMESN_v2_mechanistic(cfg);
    U1 = [0.1; 0.2; 0.3; 0.4; 0.5];
    U2 = U1;
    U2(5) = 10;
    x0 = [0.2, -0.2];
    [X1, Q1, R1, ~] = simulate(engine, U1, x0);
    [X2, Q2, R2, ~] = simulate(engine, U2, x0);
    testCase.verifyEqual(X1(1:5, :), X2(1:5, :), 'AbsTol', 0);
    testCase.verifyEqual(Q1(1:5, :), Q2(1:5, :), 'AbsTol', 0);
    testCase.verifyEqual(R1(1:5, :), R2(1:5, :), 'AbsTol', 0);

    [Xa, ~, ~, ~] = simulate(engine, U1, 0.2);
    [Xb, ~, ~, ~] = simulate(engine, U1, 0.25);
    testCase.verifyNotEqual(Xa(end, :), Xb(end, :));
end

function testCompleteHistoryMetadataAndSingleCorePath(testCase)
    cfg = base_cfg('identity');
    cfg.alpha = 0.6;
    engine = FractionalMESN_v2_mechanistic(cfg);
    [~, ~, ~, info] = simulate(engine, [0.1; 0.2; 0.3], 0);
    testCase.verifyTrue(info.full_history_used);
    testCase.verifyFalse(info.truncated);
    testCase.verifyEqual(info.drive_index, 'n_minus_1');
    testCase.verifyEqual(info.rate_index, 'n_minus_1');
    testCase.verifyEqual(info.input_index, 'n_minus_1');
    testCase.verifyEqual(info.alpha_one_branch_used, false);

    cfg.alpha = 1;
    engine = FractionalMESN_v2_mechanistic(cfg);
    [~, ~, ~, info1] = simulate(engine, [0.1; 0.2], 0);
    testCase.verifyTrue(info1.alpha_one_branch_used);
    testCase.verifyTrue(info1.full_history_used);
end

function testDeterminismRngValueObjectAndNoMutation(testCase)
    engine = FractionalMESN_v2_mechanistic(base_cfg('piecewise_sigmoid'));
    U = [0.1; -0.2; 0.3; 0.0];
    x0 = [0.5, -0.5, 0.25];
    U_snap = U;
    x0_snap = x0;
    before = engine;

    rng(2468, 'twister');
    s0 = rng;
    [X1, Q1, R1, info1] = simulate(engine, U, x0);
    s1 = rng;
    [X2, Q2, R2, info2] = simulate(engine, U, x0);

    testCase.verifyEqual(X1, X2, 'AbsTol', 0);
    testCase.verifyEqual(Q1, Q2, 'AbsTol', 0);
    testCase.verifyEqual(R1, R2, 'AbsTol', 0);
    testCase.verifyEqual(info1, info2);
    testCase.verifyEqual(s0.Type, s1.Type);
    testCase.verifyEqual(s0.Seed, s1.Seed);
    testCase.verifyEqual(s0.State, s1.State);
    testCase.verifyTrue(isequaln(before, engine));
    testCase.verifyEqual(U, U_snap, 'AbsTol', 0);
    testCase.verifyEqual(x0, x0_snap, 'AbsTol', 0);

    [X3, ~, ~, ~] = simulate(engine, U, x0);
    testCase.verifyEqual(X1, X3, 'AbsTol', 0);
end

function testE2InputOnlyLimitingControls(testCase)
    for modes = {'identity', 'piecewise_sigmoid'}
        mode = modes{1};
        cfg_m = base_cfg(mode);
        cfg_m.W = zeros(cfg_m.n);
        cfg_m.alpha = 0.72;
        engine_m = FractionalMESN_v2_mechanistic(cfg_m);

        cfg_e2 = struct();
        cfg_e2.n = cfg_m.n;
        cfg_e2.alpha = cfg_m.alpha;
        cfg_e2.dt = cfg_m.dt;
        cfg_e2.tau_x = cfg_m.tau_x;
        cfg_e2.W_in = cfg_m.W_in;
        cfg_e2.W = [];
        cfg_e2.recurrence_mode = 'input_only';
        engine_e2 = FractionalMESN_v2(cfg_e2);

        U = [0.1; 0.0; -0.2; 0.3; 0.15];
        x0 = [0.4, -0.2, 0.1];
        [Xm, ~, ~, ~] = simulate(engine_m, U, x0);
        [Xe, ~] = simulate(engine_e2, U, x0);
        testCase.verifyEqual(Xm, Xe, 'AbsTol', 0);
    end
end

function testE2LinearLimitingControlsAndIdentityQR(testCase)
    alphas = [1, 0.68];
    for ia = 1:numel(alphas)
        cfg_m = base_cfg('identity');
        cfg_m.alpha = alphas(ia);
        cfg_m.n = 2;
        cfg_m.W_in = [1, 0; 0.5, -1];
        cfg_m.W = [0.1, -0.2; 0.05, -0.15];
        cfg_m.presynaptic_signs = [1, -1];
        engine_m = FractionalMESN_v2_mechanistic(cfg_m);

        cfg_e2 = struct();
        cfg_e2.n = cfg_m.n;
        cfg_e2.alpha = cfg_m.alpha;
        cfg_e2.dt = cfg_m.dt;
        cfg_e2.tau_x = cfg_m.tau_x;
        cfg_e2.W_in = cfg_m.W_in;
        cfg_e2.W = cfg_m.W;
        cfg_e2.recurrence_mode = 'linear';
        engine_e2 = FractionalMESN_v2(cfg_e2);

        U = [0.2, -0.1; 0.1, 0.0; -0.3, 0.4; 0.0, 0.2];
        x0 = [0.2, -0.2];
        [Xm, Qm, Rm, ~] = simulate(engine_m, U, x0);
        [Xe, ~] = simulate(engine_e2, U, x0);
        testCase.verifyEqual(Xm, Xe, 'AbsTol', 0);
        testCase.verifyEqual(Qm, Xm, 'AbsTol', 0);
        testCase.verifyEqual(Rm, Xm, 'AbsTol', 0);
    end
end

function testZeroStateConstantAndAlphaOneDecay(testCase)
    cfg = base_cfg('identity');
    cfg.W = zeros(cfg.n);
    engine = FractionalMESN_v2_mechanistic(cfg);
    [X, Q, R, ~] = simulate(engine, zeros(5, 1), 0);
    testCase.verifyEqual(X, zeros(6, 3), 'AbsTol', 0);
    testCase.verifyEqual(Q, X, 'AbsTol', 0);
    testCase.verifyEqual(R, X, 'AbsTol', 0);

    cfg = base_cfg('identity');
    cfg.n = 2;
    cfg.W = zeros(2);
    cfg.W_in = eye(2);
    cfg.presynaptic_signs = [1, 1];
    cfg.alpha = 0.6;
    engine = FractionalMESN_v2_mechanistic(cfg);
    c = [1.5, -0.5];
    U = repmat(c, 4, 1);
    [X, Q, R, ~] = simulate(engine, U, c);
    testCase.verifyEqual(X, repmat(c, 5, 1), 'AbsTol', 1e-14);
    testCase.verifyEqual(Q, X, 'AbsTol', 0);
    testCase.verifyEqual(R, X, 'AbsTol', 0);

    cfg = base_cfg('identity');
    cfg.alpha = 1;
    cfg.n = 1;
    cfg.W_in = 0;
    cfg.W = 0;
    cfg.presynaptic_signs = 1;
    engine = FractionalMESN_v2_mechanistic(cfg);
    U = zeros(6, 1);
    x0 = 2;
    [X, ~, ~, ~] = simulate(engine, U, x0);
    ratio = (cfg.tau_x / cfg.dt) / ((cfg.tau_x / cfg.dt) + 1);
    expected = x0 * ratio .^ (0:6).';
    testCase.verifyEqual(X, expected, 'AbsTol', 0);
end

function testEngineSchemaHashDependenciesAndBoundedInfo(testCase)
    ENGINE_HASH = ...
        'fe9691184cc22a4b4e9afe8d5740badf9442ed535e848f6fbbe94d6c2539fc69';
    CORE_HASH = ...
        '3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f';
    RATE_HASH = ...
        '483b6192099426b1c22f29a35e04d9e22c508826a9d334f8da8b0134b94fe257';
    DALE_HASH = ...
        'dba675ded7b3f3f8e91ceb93185171a6fbedc42bba5050a97cca8d830bc3f081';

    spec = fractional_mesn_v2_mechanistic_engine_spec();
    testCase.verifyEqual(spec.schema_version, ...
        'fractional_mesn_v2_mechanistic_engine_v1');
    payload = rmfield(spec, 'content_hash');
    testCase.verifyEqual(spec.content_hash, canonical_sha256(payload));
    testCase.verifyEqual(spec.content_hash, ENGINE_HASH);
    testCase.verifyEqual(spec.core_schema_version, ...
        'fractional_mesn_v2_caputo_l1_core_v1');
    testCase.verifyEqual(spec.core_content_hash, CORE_HASH);
    testCase.verifyEqual(spec.rate_map_schema_version, 'mesn_v2_rate_map_v1');
    testCase.verifyEqual(spec.rate_map_content_hash, RATE_HASH);
    testCase.verifyEqual(spec.dale_validator_schema_version, ...
        'mesn_v2_dale_validator_v1');
    testCase.verifyEqual(spec.dale_validator_content_hash, DALE_HASH);
    testCase.verifyEqual(spec.included_mechanisms, { ...
        'input_plumbing', 'nonlinear_rate_map', 'dale_validation', ...
        'linear_w_recurrence_on_r', 'caputo_l1_stepping'});
    testCase.verifyEqual(spec.excluded_mechanisms, { ...
        'sfa', 'std', 'delays', 'delay_prehistory', 'bias', 'noise', ...
        'readout', 'weight_construction', 'spectral_scaling', ...
        'fast_convolution', 'continuation'});

    engine = FractionalMESN_v2_mechanistic(base_cfg('piecewise_sigmoid'));
    [~, ~, ~, info0] = simulate(engine, zeros(0, 1), 0);
    [~, ~, ~, infoN] = simulate(engine, [0.1; 0.2], [0.1, 0, -0.1]);
    for infos = {info0, infoN}
        info = infos{1};
        verify_common_info(testCase, info, engine.Config, info.n_steps);
        testCase.verifyEqual(info.engine_content_hash, ENGINE_HASH);
        testCase.verifyFalse(isfield(info, 'W'));
        testCase.verifyFalse(isfield(info, 'W_in'));
        testCase.verifyFalse(isfield(info, 'presynaptic_signs'));
        testCase.verifyFalse(isfield(info, 'X'));
        testCase.verifyFalse(isfield(info, 'Q'));
        testCase.verifyFalse(isfield(info, 'R'));
        testCase.verifyFalse(isfield(info, 'activation'));
        testCase.verifyFalse(isfield(info, 'step_infos'));
    end
    testCase.verifyEqual(info0.n_steps, 0);
    testCase.verifyEqual(infoN.n_steps, 2);
end

function testNoProductionCallerIntegration(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    src_root = fullfile(repo_root, 'src');
    listing = dir(fullfile(src_root, '**', '*.m'));
    hits = {};
    for i = 1:numel(listing)
        path = fullfile(listing(i).folder, listing(i).name);
        [~, name, ~] = fileparts(path);
        if any(strcmp(name, { ...
                'FractionalMESN_v2_mechanistic', ...
                'validate_fractional_mesn_v2_mechanistic_config', ...
                'fractional_mesn_v2_mechanistic_engine_spec'}))
            continue;
        end
        txt = fileread(path);
        if contains(txt, 'FractionalMESN_v2_mechanistic')
            hits{end + 1} = path; %#ok<AGROW>
        end
    end
    testCase.verifyEmpty(hits);
end

function cfg = base_cfg(mode)
    if nargin < 1
        mode = 'identity';
    end
    cfg = struct();
    cfg.n = 3;
    cfg.alpha = 0.75;
    cfg.dt = 0.1;
    cfg.tau_x = 1.5;
    cfg.W_in = [1; -0.5; 0.25];
    cfg.W = [0.10, 0.05, -0.20; ...
             0.00, 0.10, -0.10; ...
             0.05, 0.00, -0.15];
    cfg.presynaptic_signs = [1, 1, -1];
    if strcmp(char(mode), 'piecewise_sigmoid')
        cfg.activation = struct('mode', 'piecewise_sigmoid', ...
            'S_a', 0.7, 'S_c', 0.2);
    else
        cfg.activation = struct('mode', 'identity', 'S_a', [], 'S_c', []);
    end
end

function [X, Q, R] = independent_alpha_one(cfg, U, x0)
    % Independent alpha==1 reference: no Caputo core, no engine calls.
    x_prev = normalize_x0_for_test(x0, cfg.n);
    N = size(U, 1);
    X = zeros(N + 1, cfg.n);
    Q = zeros(N + 1, cfg.n);
    R = zeros(N + 1, cfg.n);
    X(1, :) = x_prev;
    Q(1, :) = X(1, :);
    R(1, :) = mesn_v2_rate_map(Q(1, :), cfg.activation);
    ratio = cfg.tau_x / cfg.dt;
    for k = 1:N
        u_prev = U(k, :);
        r_prev = R(k, :);
        d_prev = (cfg.W_in * u_prev.').' + (cfg.W * r_prev.').';
        x_prev = ((ratio * x_prev) + d_prev) / (ratio + 1);
        X(k + 1, :) = x_prev;
        Q(k + 1, :) = X(k + 1, :);
        R(k + 1, :) = mesn_v2_rate_map(Q(k + 1, :), cfg.activation);
    end
end

function X = independent_alpha_one_on_x(cfg, U, x0)
    % Contrast path using W*x instead of W*r (must differ under piecewise).
    x_prev = normalize_x0_for_test(x0, cfg.n);
    N = size(U, 1);
    X = zeros(N + 1, cfg.n);
    X(1, :) = x_prev;
    ratio = cfg.tau_x / cfg.dt;
    for k = 1:N
        u_prev = U(k, :);
        d_prev = (cfg.W_in * u_prev.').' + (cfg.W * x_prev.').';
        x_prev = ((ratio * x_prev) + d_prev) / (ratio + 1);
        X(k + 1, :) = x_prev;
    end
end

function [X, Q, R] = manual_fractional_reference(cfg, U, x0)
    % Manual growing-history Caputo + rate-map reference (not the engine).
    x0_row = normalize_x0_for_test(x0, cfg.n);
    N = size(U, 1);
    X = zeros(N + 1, cfg.n);
    Q = zeros(N + 1, cfg.n);
    R = zeros(N + 1, cfg.n);
    X(1, :) = x0_row;
    Q(1, :) = X(1, :);
    R(1, :) = mesn_v2_rate_map(Q(1, :), cfg.activation);
    for k = 1:N
        u_previous = U(k, :);
        r_previous = R(k, :);
        drive_previous = (cfg.W_in * u_previous.').' + (cfg.W * r_previous.').';
        X(k + 1, :) = caputo_l1_semiimplicit_step( ...
            X(1:k, :), drive_previous, cfg.dt, cfg.alpha, cfg.tau_x);
        Q(k + 1, :) = X(k + 1, :);
        R(k + 1, :) = mesn_v2_rate_map(Q(k + 1, :), cfg.activation);
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
        'fractional_mesn_v2_mechanistic_engine_v1');
    testCase.verifyEqual(info.core_schema_version, ...
        'fractional_mesn_v2_caputo_l1_core_v1');
    testCase.verifyEqual(info.core_content_hash, ...
        '3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f');
    testCase.verifyEqual(info.rate_map_schema_version, 'mesn_v2_rate_map_v1');
    testCase.verifyEqual(info.rate_map_content_hash, ...
        '483b6192099426b1c22f29a35e04d9e22c508826a9d334f8da8b0134b94fe257');
    testCase.verifyEqual(info.dale_validator_schema_version, ...
        'mesn_v2_dale_validator_v1');
    testCase.verifyEqual(info.dale_validator_content_hash, ...
        'dba675ded7b3f3f8e91ceb93185171a6fbedc42bba5050a97cca8d830bc3f081');
    testCase.verifyEqual(info.alpha, cfg.alpha);
    testCase.verifyEqual(info.alpha_one_branch_used, cfg.alpha == 1);
    testCase.verifyEqual(info.n_steps, N);
    testCase.verifyEqual(info.drive_index, 'n_minus_1');
    testCase.verifyEqual(info.rate_index, 'n_minus_1');
    testCase.verifyEqual(info.input_index, 'n_minus_1');
    testCase.verifyTrue(info.full_history_used);
    testCase.verifyFalse(info.truncated);
    testCase.verifyEqual(info.activation_mode, cfg.activation.mode);
    testCase.verifyTrue(info.dale_signs_valid);
end
