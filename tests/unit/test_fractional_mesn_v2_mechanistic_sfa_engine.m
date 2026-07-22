function tests = test_fractional_mesn_v2_mechanistic_sfa_engine
%TEST_FRACTIONAL_MESN_V2_MECHANISTIC_SFA_ENGINE Unit tests for SFA-enabled engine.
%
% Deterministic fixtures only; no governed seeds. Independent alpha==1
% references do not call Caputo or SFA-step modules.
this_file = mfilename('fullpath');
repo_root = fileparts(fileparts(fileparts(this_file)));
addpath(genpath(fullfile(repo_root, 'src')));
addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
tests = functiontests({ ...
    @testValidConfigsPopulationsAndOrdering, ...
    @testSfaNormalizationFieldOrderAndNoDefaults, ...
    @testMissingLegacyInvalidSfaAndBaseRethrow, ...
    @testCfgInUnchangedAndStableErrorIds, ...
    @testA0ValidationShapesAndZeroSizeNormalization, ...
    @testUX0ValidationAndBroadcast, ...
    @testInitialRowsLayoutsAndPhysicalTime, ...
    @testN0ShapesValuesAndMetadata, ...
    @testDimensionEdgeCasesSingletonZeroChannelZeroPop, ...
    @testAlphaOneIndependentMixedAndOrdering, ...
    @testAlphaOneIdentityAndPiecewise, ...
    @testAlphaLessThanOneManualReference, ...
    @testCausalityRkm1Ukm1QkAndNoAlgebraicLoop, ...
    @testHistorySensitivityAndCompleteHistoryMetadata, ...
    @testDeterminismRngValueObjectAndNoMutation, ...
    @testZeroChannelEqualsNoSfaEngine, ...
    @testZeroCouplingEqualsNoSfaAndAEvolves, ...
    @testWZeroEqualsE2InputOnly, ...
    @testIdentityZeroCouplingEqualsE2Linear, ...
    @testPiecewiseInvariantAndSfaLimitingFixtures, ...
    @testEngineSchemaHashDependenciesBoundedInfo, ...
    @testNoProductionCallerIntegration});
end

function testValidConfigsPopulationsAndOrdering(testCase)
    cfg = validate_fractional_mesn_v2_mechanistic_sfa_config( ...
        base_sfa_cfg('piecewise_sigmoid'));
    testCase.verifyEqual(cfg.n, 3);
    testCase.verifyEqual(cfg.activation.mode, 'piecewise_sigmoid');
    testCase.verifyEqual(numel(cfg.sfa.tau_a_E), 2);
    testCase.verifyEqual(numel(cfg.sfa.tau_a_I), 1);

    cfg_id = validate_fractional_mesn_v2_mechanistic_sfa_config( ...
        base_sfa_cfg('identity'));
    testCase.verifyEqual(cfg_id.activation.mode, 'identity');

    cfg_E = base_sfa_cfg('identity');
    cfg_E.n = 2;
    cfg_E.W_in = [1; 0.5];
    cfg_E.W = [0.1, 0.0; 0.2, 0.0];
    cfg_E.presynaptic_signs = [1, 1];
    cfg_E.sfa.tau_a_I = zeros(1, 0);
    cfg_E.sfa.c_a_I = zeros(1, 0);
    cfg_E = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_E);
    testCase.verifyEqual(sum(cfg_E.presynaptic_signs == 1), 2);

    cfg_I = base_sfa_cfg('identity');
    cfg_I.n = 2;
    cfg_I.W_in = [1; -0.5];
    cfg_I.W = [0, -0.2; 0, -0.1];
    cfg_I.presynaptic_signs = [-1, -1];
    cfg_I.sfa.tau_a_E = zeros(1, 0);
    cfg_I.sfa.c_a_E = zeros(1, 0);
    cfg_I = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_I);
    testCase.verifyEqual(sum(cfg_I.presynaptic_signs == -1), 2);

    cfg_ord = base_sfa_cfg('identity');
    cfg_ord.presynaptic_signs = [-1, 1, 1];
    cfg_ord.W = [-0.2, 0.1, 0.05; -0.1, 0.0, 0.1; -0.15, 0.05, 0.0];
    cfg_ord = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_ord);
    testCase.verifyEqual(cfg_ord.presynaptic_signs, [-1, 1, 1]);

    engine = FractionalMESN_v2_mechanistic_sfa(cfg_ord);
    a0 = a0_for_cfg(cfg_ord, 0.2);
    [~, ~, ~, A_E, A_I, info] = simulate(engine, [0.1; 0.2], 0.1, a0);
    testCase.verifyEqual(info.n_E, 2);
    testCase.verifyEqual(info.n_I, 1);
    testCase.verifyEqual(size(A_E, 2), 2);
    testCase.verifyEqual(size(A_I, 2), 1);
end

function testSfaNormalizationFieldOrderAndNoDefaults(testCase)
    cfg_in = base_sfa_cfg('identity');
    cfg_in.sfa.tau_a_E = [0.2; 0.4];
    cfg_in.sfa.c_a_E = [0.1; 0.05];
    cfg_in.sfa.tau_a_I = 0.3;
    cfg_in.sfa.c_a_I = 0.0;
    cfg = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_in);
    testCase.verifyEqual(fieldnames(cfg), { ...
        'n'; 'alpha'; 'dt'; 'tau_x'; 'W_in'; 'W'; ...
        'presynaptic_signs'; 'activation'; 'sfa'});
    testCase.verifyEqual(fieldnames(cfg.sfa), { ...
        'tau_a_E'; 'c_a_E'; 'tau_a_I'; 'c_a_I'});
    testCase.verifyEqual(size(cfg.sfa.tau_a_E), [1, 2]);
    testCase.verifyEqual(size(cfg.sfa.c_a_E), [1, 2]);
    testCase.verifyEqual(size(cfg.sfa.tau_a_I), [1, 1]);
    testCase.verifyEqual(cfg.sfa.c_a_I, 0);

    cfg_zc = base_sfa_cfg('identity');
    cfg_zc.sfa.tau_a_E = [];
    cfg_zc.sfa.c_a_E = [];
    cfg_zc.sfa.tau_a_I = zeros(0, 1);
    cfg_zc.sfa.c_a_I = zeros(1, 0);
    cfg_zc = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_zc);
    testCase.verifyEqual(cfg_zc.sfa.tau_a_E, zeros(1, 0));
    testCase.verifyEqual(cfg_zc.sfa.c_a_I, zeros(1, 0));

    cfg_ze = base_sfa_cfg('identity');
    cfg_ze.sfa.tau_a_E = zeros(1, 0);
    cfg_ze.sfa.c_a_E = zeros(1, 0);
    cfg_ze = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_ze);
    testCase.verifyEqual(numel(cfg_ze.sfa.tau_a_E), 0);
    testCase.verifyEqual(numel(cfg_ze.sfa.tau_a_I), 1);

    cfg_zi = base_sfa_cfg('identity');
    cfg_zi.sfa.tau_a_I = zeros(1, 0);
    cfg_zi.sfa.c_a_I = zeros(1, 0);
    cfg_zi = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_zi);
    testCase.verifyEqual(numel(cfg_zi.sfa.tau_a_I), 0);
end

function testMissingLegacyInvalidSfaAndBaseRethrow(testCase)
    cfg = base_sfa_cfg('identity');
    cfg = rmfield(cfg, 'sfa');
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_sfa_config(cfg), ...
        'FractionalMESN_v2_mechanistic_sfa:missingField');

    cfg = base_sfa_cfg('identity');
    cfg.sfa = rmfield(cfg.sfa, 'c_a_E');
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_sfa_config(cfg), ...
        'FractionalMESN_v2_mechanistic_sfa:missingField');

    cfg = base_sfa_cfg('identity');
    cfg.c_E = 0.1;
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_sfa_config(cfg), ...
        'FractionalMESN_v2_mechanistic_sfa:invalidSfa');
    cfg = base_sfa_cfg('identity');
    cfg.sfa.c_I = 0.1;
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_sfa_config(cfg), ...
        'FractionalMESN_v2_mechanistic_sfa:invalidSfa');

    cfg = base_sfa_cfg('identity');
    cfg.sfa.c_a_E = [0.1];
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_sfa_config(cfg), ...
        'FractionalMESN_v2_mechanistic_sfa:invalidCouplingE');

    bad_tau = {0, -0.1, NaN, Inf, 0.1+1i, [0.1, 0.2; 0.3, 0.4], 't'};
    for i = 1:numel(bad_tau)
        cfg = base_sfa_cfg('identity');
        cfg.sfa.tau_a_E = bad_tau{i};
        testCase.verifyError( ...
            @() validate_fractional_mesn_v2_mechanistic_sfa_config(cfg), ...
            'FractionalMESN_v2_mechanistic_sfa:invalidTauE');
    end

    bad_c = {-0.1, NaN, Inf, 0.1+1i, [0.1, 0.2; 0.3, 0.4], 'c'};
    for i = 1:numel(bad_c)
        cfg = base_sfa_cfg('identity');
        cfg.sfa.c_a_I = bad_c{i};
        if isnumeric(bad_c{i}) && isvector(bad_c{i}) && numel(bad_c{i}) == 1
            % length may match; still invalid for negative/nan/inf/complex
        end
        testCase.verifyError( ...
            @() validate_fractional_mesn_v2_mechanistic_sfa_config(cfg), ...
            'FractionalMESN_v2_mechanistic_sfa:invalidCouplingI');
    end

    cfg = base_sfa_cfg('identity');
    cfg.alpha = -0.2;
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_sfa_config(cfg), ...
        'FractionalMESN_v2_mechanistic_sfa:invalidAlpha');

    cfg = base_sfa_cfg('identity');
    cfg.W(1, 1) = -0.5;
    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_sfa_config(cfg), ...
        'FractionalMESN_v2_mechanistic_sfa:invalidW');
end

function testCfgInUnchangedAndStableErrorIds(testCase)
    cfg_in = base_sfa_cfg('identity');
    cfg_copy = cfg_in;
    validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_in);
    testCase.verifyEqual(cfg_in, cfg_copy);

    testCase.verifyError( ...
        @() validate_fractional_mesn_v2_mechanistic_sfa_config([]), ...
        'FractionalMESN_v2_mechanistic_sfa:invalidConfig');
    testCase.verifyError(@() FractionalMESN_v2_mechanistic_sfa(), ...
        'FractionalMESN_v2_mechanistic_sfa:missingConfig');
end

function testA0ValidationShapesAndZeroSizeNormalization(testCase)
    cfg = validate_fractional_mesn_v2_mechanistic_sfa_config( ...
        base_sfa_cfg('identity'));
    engine = FractionalMESN_v2_mechanistic_sfa(cfg);
    a0 = a0_for_cfg(cfg, 0.25);
    [~, ~, ~, A_E, A_I, ~] = simulate(engine, zeros(0, 1), 0, a0);
    testCase.verifyEqual(size(A_E, 2), 2);
    testCase.verifyEqual(size(A_E, 3), 2);
    testCase.verifyEqual(size(A_I, 2), 1);
    testCase.verifyEqual(size(A_I, 3), 1);

    bad = a0;
    bad.a_E = 0.1;
    testCase.verifyError(@() simulate(engine, zeros(0, 1), 0, bad), ...
        'FractionalMESN_v2_mechanistic_sfa:invalidA0');

    bad = a0;
    bad.a_E = ones(1, 4);
    testCase.verifyError(@() simulate(engine, zeros(0, 1), 0, bad), ...
        'FractionalMESN_v2_mechanistic_sfa:invalidA0');

    bad = a0;
    bad.a_I = 1+1i;
    testCase.verifyError(@() simulate(engine, zeros(0, 1), 0, bad), ...
        'FractionalMESN_v2_mechanistic_sfa:invalidA0');

    cfg_zc = base_sfa_cfg('identity');
    cfg_zc.sfa.tau_a_E = zeros(1, 0);
    cfg_zc.sfa.c_a_E = zeros(1, 0);
    cfg_zc.sfa.tau_a_I = zeros(1, 0);
    cfg_zc.sfa.c_a_I = zeros(1, 0);
    cfg_zc = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_zc);
    engine_zc = FractionalMESN_v2_mechanistic_sfa(cfg_zc);
    a0_zc = struct('a_E', [], 'a_I', []);
    [~, ~, ~, A_E, A_I, info] = simulate(engine_zc, zeros(0, 1), 0, a0_zc);
    testCase.verifyEqual(size(A_E, 1), 1);
    testCase.verifyEqual(size(A_E, 2), 2);
    testCase.verifyEqual(size(A_E, 3), 0);
    testCase.verifyEqual(size(A_I, 3), 0);
    testCase.verifyEqual(info.n_a_E, 0);
    testCase.verifyEqual(info.n_a_I, 0);

    cfg_E = base_sfa_cfg('identity');
    cfg_E.n = 2;
    cfg_E.W_in = [1; 0];
    cfg_E.W = [0.1, 0; 0.2, 0];
    cfg_E.presynaptic_signs = [1, 1];
    cfg_E.sfa.tau_a_I = zeros(1, 0);
    cfg_E.sfa.c_a_I = zeros(1, 0);
    cfg_E = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_E);
    engine_E = FractionalMESN_v2_mechanistic_sfa(cfg_E);
    a0_E = struct('a_E', [0.1, 0.2; 0.3, 0.4], 'a_I', []);
    [~, ~, ~, ~, A_I, info] = simulate(engine_E, zeros(0, 1), 0, a0_E);
    testCase.verifyEqual(size(A_I, 2), 0);
    testCase.verifyEqual(info.n_I, 0);

    a0_copy = a0;
    simulate(engine, [0.1], 0.2, a0);
    testCase.verifyEqual(a0, a0_copy);
end

function testUX0ValidationAndBroadcast(testCase)
    cfg = validate_fractional_mesn_v2_mechanistic_sfa_config( ...
        base_sfa_cfg('identity'));
    engine = FractionalMESN_v2_mechanistic_sfa(cfg);
    a0 = a0_for_cfg(cfg, 0);
    [X, ~, ~, ~, ~, ~] = simulate(engine, zeros(0, 1), 0.7, a0);
    testCase.verifyEqual(X(1, :), [0.7, 0.7, 0.7]);

    [X, ~, ~, ~, ~, ~] = simulate(engine, zeros(0, 1), [0.1; 0.2; 0.3], a0);
    testCase.verifyEqual(X(1, :), [0.1, 0.2, 0.3]);

    testCase.verifyError(@() simulate(engine, ones(2, 2), 0, a0), ...
        'FractionalMESN_v2_mechanistic_sfa:invalidU');
    testCase.verifyError(@() simulate(engine, [NaN; 0], 0, a0), ...
        'FractionalMESN_v2_mechanistic_sfa:invalidU');
    testCase.verifyError(@() simulate(engine, zeros(0, 1), [1, 2], a0), ...
        'FractionalMESN_v2_mechanistic_sfa:invalidX0');
    testCase.verifyError(@() simulate(engine, zeros(0, 1), Inf, a0), ...
        'FractionalMESN_v2_mechanistic_sfa:invalidX0');
end

function testInitialRowsLayoutsAndPhysicalTime(testCase)
    cfg = validate_fractional_mesn_v2_mechanistic_sfa_config( ...
        base_sfa_cfg('identity'));
    engine = FractionalMESN_v2_mechanistic_sfa(cfg);
    a0 = struct('a_E', [0.10, 0.20; 0.30, 0.40], 'a_I', 0.50);
    x0 = [0.9, 0.8, 0.7];
    U = [0.1; -0.2];
    [X, Q, R, A_E, A_I, ~] = simulate(engine, U, x0, a0);

    testCase.verifyEqual(X(1, :), x0);
    testCase.verifyEqual(reshape(A_E(1, :, :), [2, 2]), a0.a_E, 'AbsTol', 0);
    testCase.verifyEqual(reshape(A_I(1, :, :), [1, 1]), a0.a_I, 'AbsTol', 0);

    adapt = zeros(1, 3);
    adapt([1, 2]) = (a0.a_E * cfg.sfa.c_a_E(:)).';
    adapt(3) = a0.a_I * cfg.sfa.c_a_I;
    testCase.verifyEqual(Q(1, :), X(1, :) - adapt, 'AbsTol', 0);
    testCase.verifyEqual(R(1, :), Q(1, :), 'AbsTol', 0);

    testCase.verifyEqual(size(X, 1), 3);
    testCase.verifyEqual(size(Q, 1), 3);
    testCase.verifyEqual(size(R, 1), 3);
    testCase.verifyEqual(size(A_E, 1), 3);
    testCase.verifyEqual(size(A_I, 1), 3);
    testCase.verifyEqual(size(U, 1) + 1, size(X, 1));
end

function testN0ShapesValuesAndMetadata(testCase)
    cfg = validate_fractional_mesn_v2_mechanistic_sfa_config( ...
        base_sfa_cfg('piecewise_sigmoid'));
    engine = FractionalMESN_v2_mechanistic_sfa(cfg);
    a0 = a0_for_cfg(cfg, 0.4);
    [X, Q, R, A_E, A_I, info] = simulate(engine, zeros(0, 1), 0.2, a0);
    testCase.verifyEqual(size(X, 1), 1);
    testCase.verifyEqual(size(Q, 1), 1);
    testCase.verifyEqual(size(R, 1), 1);
    testCase.verifyEqual(size(A_E, 1), 1);
    testCase.verifyEqual(size(A_I, 1), 1);
    testCase.verifyEqual(info.n_steps, 0);
    testCase.verifyEqual(info.full_fractional_history_used, true);
    testCase.verifyEqual(info.sfa_integer_order, true);
    testCase.verifyEqual(X(1, :), [0.2, 0.2, 0.2]);
end

function testDimensionEdgeCasesSingletonZeroChannelZeroPop(testCase)
    cfg = base_sfa_cfg('identity');
    cfg.sfa.tau_a_E = 0.25;
    cfg.sfa.c_a_E = 0.1;
    cfg = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg);
    engine = FractionalMESN_v2_mechanistic_sfa(cfg);
    a0 = struct('a_E', [0.1; 0.2], 'a_I', 0.3);
    [~, ~, ~, A_E, A_I, info] = simulate(engine, [0.1], 0, a0);
    testCase.verifyEqual(size(A_E, 3), 1);
    testCase.verifyEqual(size(A_I, 3), 1);
    testCase.verifyEqual(info.n_a_E, 1);

    cfg_zc = base_sfa_cfg('identity');
    cfg_zc.sfa.tau_a_E = zeros(1, 0);
    cfg_zc.sfa.c_a_E = zeros(1, 0);
    cfg_zc.sfa.tau_a_I = zeros(1, 0);
    cfg_zc.sfa.c_a_I = zeros(1, 0);
    cfg_zc = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_zc);
    engine = FractionalMESN_v2_mechanistic_sfa(cfg_zc);
    a0 = struct('a_E', zeros(2, 0), 'a_I', zeros(1, 0));
    [~, ~, ~, A_E, A_I, ~] = simulate(engine, [0.1; 0.2], 0, a0);
    testCase.verifyEqual(size(A_E, 3), 0);
    testCase.verifyEqual(size(A_I, 3), 0);
end

function testAlphaOneIndependentMixedAndOrdering(testCase)
    cfg = base_sfa_cfg('identity');
    cfg.alpha = 1;
    cfg = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg);
    engine = FractionalMESN_v2_mechanistic_sfa(cfg);
    U = [0.2; -0.1; 0.05];
    x0 = [0.1, 0.2, 0.3];
    a0 = struct('a_E', [0.15, 0.25; 0.35, 0.45], 'a_I', 0.55);
    [X, Q, R, A_E, A_I, ~] = simulate(engine, U, x0, a0);
    [Xe, Qe, Re, AEe, AIe] = independent_alpha_one_sfa(cfg, U, x0, a0);
    testCase.verifyEqual(X, Xe, 'AbsTol', 1e-14);
    testCase.verifyEqual(Q, Qe, 'AbsTol', 1e-14);
    testCase.verifyEqual(R, Re, 'AbsTol', 1e-14);
    testCase.verifyEqual(A_E, AEe, 'AbsTol', 1e-14);
    testCase.verifyEqual(A_I, AIe, 'AbsTol', 1e-14);

    cfg1 = base_sfa_cfg('identity');
    cfg1.alpha = 1;
    cfg1.n = 1;
    cfg1.W_in = 1;
    cfg1.W = 0.2;
    cfg1.presynaptic_signs = 1;
    cfg1.sfa.tau_a_E = 0.3;
    cfg1.sfa.c_a_E = 0.1;
    cfg1.sfa.tau_a_I = zeros(1, 0);
    cfg1.sfa.c_a_I = zeros(1, 0);
    cfg1 = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg1);
    engine1 = FractionalMESN_v2_mechanistic_sfa(cfg1);
    a01 = struct('a_E', 0.2, 'a_I', []);
    [X1, Q1, R1, AE1, ~, ~] = simulate(engine1, [0.5; 0.1], 0.4, a01);
    [X1e, Q1e, R1e, AE1e, ~] = independent_alpha_one_sfa(cfg1, [0.5; 0.1], 0.4, a01);
    testCase.verifyEqual(X1, X1e, 'AbsTol', 1e-14);
    testCase.verifyEqual(Q1, Q1e, 'AbsTol', 1e-14);
    testCase.verifyEqual(R1, R1e, 'AbsTol', 1e-14);
    testCase.verifyEqual(AE1, AE1e, 'AbsTol', 1e-14);

    cfg_ord = base_sfa_cfg('identity');
    cfg_ord.alpha = 1;
    cfg_ord.presynaptic_signs = [-1, 1, 1];
    cfg_ord.W = [-0.2, 0.1, 0.05; -0.1, 0.0, 0.1; -0.15, 0.05, 0.0];
    cfg_ord = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_ord);
    engine_ord = FractionalMESN_v2_mechanistic_sfa(cfg_ord);
    a0o = a0_for_cfg(cfg_ord, 0.2);
    Uo = [0.1; 0.2];
    [Xo, Qo, Ro, AEo, AIo, ~] = simulate(engine_ord, Uo, 0.1, a0o);
    [Xoe, Qoe, Roe, AEoe, AIoe] = independent_alpha_one_sfa(cfg_ord, Uo, 0.1, a0o);
    testCase.verifyEqual(Xo, Xoe, 'AbsTol', 1e-14);
    testCase.verifyEqual(Qo, Qoe, 'AbsTol', 1e-14);
    testCase.verifyEqual(Ro, Roe, 'AbsTol', 1e-14);
    testCase.verifyEqual(AEo, AEoe, 'AbsTol', 1e-14);
    testCase.verifyEqual(AIo, AIoe, 'AbsTol', 1e-14);
end

function testAlphaOneIdentityAndPiecewise(testCase)
    for modes = {'identity', 'piecewise_sigmoid'}
        cfg = base_sfa_cfg(modes{1});
        cfg.alpha = 1;
        cfg = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg);
        engine = FractionalMESN_v2_mechanistic_sfa(cfg);
        U = [0.15; -0.05; 0.2];
        x0 = [0.2, 0.1, 0.05];
        a0 = a0_for_cfg(cfg, 0.3);
        [X, Q, R, A_E, A_I, ~] = simulate(engine, U, x0, a0);
        [Xe, Qe, Re, AEe, AIe] = independent_alpha_one_sfa(cfg, U, x0, a0);
        testCase.verifyEqual(X, Xe, 'AbsTol', 1e-13);
        testCase.verifyEqual(Q, Qe, 'AbsTol', 1e-13);
        testCase.verifyEqual(R, Re, 'AbsTol', 1e-13);
        testCase.verifyEqual(A_E, AEe, 'AbsTol', 1e-13);
        testCase.verifyEqual(A_I, AIe, 'AbsTol', 1e-13);
    end
end

function testAlphaLessThanOneManualReference(testCase)
    for modes = {'identity', 'piecewise_sigmoid'}
        cfg = base_sfa_cfg(modes{1});
        cfg.alpha = 0.7;
        cfg = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg);
        engine = FractionalMESN_v2_mechanistic_sfa(cfg);
        U = [0.1; 0.2; -0.05];
        x0 = [0.05, 0.1, 0.15];
        a0 = a0_for_cfg(cfg, 0.25);
        [X, Q, R, A_E, A_I, ~] = simulate(engine, U, x0, a0);
        [Xe, Qe, Re, AEe, AIe] = manual_fractional_sfa_reference(cfg, U, x0, a0);
        testCase.verifyEqual(X, Xe, 'AbsTol', 0);
        testCase.verifyEqual(Q, Qe, 'AbsTol', 0);
        testCase.verifyEqual(R, Re, 'AbsTol', 0);
        testCase.verifyEqual(A_E, AEe, 'AbsTol', 0);
        testCase.verifyEqual(A_I, AIe, 'AbsTol', 0);
    end

    cfg_ord = base_sfa_cfg('identity');
    cfg_ord.alpha = 0.8;
    cfg_ord.presynaptic_signs = [-1, 1, 1];
    cfg_ord.W = [-0.2, 0.1, 0.05; -0.1, 0.0, 0.1; -0.15, 0.05, 0.0];
    cfg_ord = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_ord);
    engine = FractionalMESN_v2_mechanistic_sfa(cfg_ord);
    a0 = a0_for_cfg(cfg_ord, 0.2);
    U = [0.05; 0.1];
    [X, Q, R, A_E, A_I, ~] = simulate(engine, U, 0.1, a0);
    [Xe, Qe, Re, AEe, AIe] = manual_fractional_sfa_reference(cfg_ord, U, 0.1, a0);
    testCase.verifyEqual(X, Xe, 'AbsTol', 0);
    testCase.verifyEqual(Q, Qe, 'AbsTol', 0);
    testCase.verifyEqual(R, Re, 'AbsTol', 0);
    testCase.verifyEqual(A_E, AEe, 'AbsTol', 0);
    testCase.verifyEqual(A_I, AIe, 'AbsTol', 0);
end

function testCausalityRkm1Ukm1QkAndNoAlgebraicLoop(testCase)
    cfg = base_sfa_cfg('piecewise_sigmoid');
    cfg.alpha = 1;
    cfg = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg);
    engine = FractionalMESN_v2_mechanistic_sfa(cfg);
    U = [0.2; 0.3; 0.4];
    x0 = [0.1, 0.2, 0.3];
    a0 = a0_for_cfg(cfg, 0.2);
    [X, Q, R, A_E, A_I, ~] = simulate(engine, U, x0, a0);

    % After first step, a uses R(1,:), x uses R(1,:) and U(1,:), q uses X(2,:) and A(2)
    E_idx = find(cfg.presynaptic_signs == 1);
    I_idx = find(cfg.presynaptic_signs == -1);
    decay_E = exp(-cfg.dt ./ cfg.sfa.tau_a_E);
    a_E1 = reshape(A_E(1, :, :), [2, 2]);
    a_E2_expected = a_E1 .* decay_E + R(1, E_idx).' * (1 - decay_E);
    testCase.verifyEqual(reshape(A_E(2, :, :), [2, 2]), a_E2_expected, ...
        'AbsTol', 1e-14);

    ratio = cfg.tau_x / cfg.dt;
    d0 = (cfg.W_in * U(1, :).').' + (cfg.W * R(1, :).').';
    x1_expected = ((ratio * X(1, :)) + d0) / (ratio + 1);
    testCase.verifyEqual(X(2, :), x1_expected, 'AbsTol', 1e-14);

    adapt = zeros(1, 3);
    adapt(E_idx) = (reshape(A_E(2, :, :), [2, 2]) * cfg.sfa.c_a_E(:)).';
    adapt(I_idx) = reshape(A_I(2, :, :), [1, 1]) * cfg.sfa.c_a_I;
    testCase.verifyEqual(Q(2, :), X(2, :) - adapt, 'AbsTol', 1e-14);
    testCase.verifyEqual(R(2, :), mesn_v2_rate_map(Q(2, :), cfg.activation), ...
        'AbsTol', 0);

    % Nonlinear recurrence uses r not x: compare against W*x path
    Xx = independent_alpha_one_on_x_ignore_sfa(cfg, U, x0);
    testCase.verifyGreaterThan(max(abs(X(:) - Xx(:))), 1e-8);
end

function testHistorySensitivityAndCompleteHistoryMetadata(testCase)
    cfg = base_sfa_cfg('identity');
    cfg.alpha = 0.75;
    cfg = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg);
    engine = FractionalMESN_v2_mechanistic_sfa(cfg);
    U = [0.1; 0.2; 0.3; 0.4; 0.5];
    a0 = a0_for_cfg(cfg, 0.1);
    [X, Q, R, A_E, ~, info] = simulate(engine, U, 0.2, a0);

    U2 = U;
    U2(5) = U2(5) + 1;
    [X2, Q2, R2, A_E2, ~, ~] = simulate(engine, U2, 0.2, a0);
    testCase.verifyEqual(X(1:5, :), X2(1:5, :), 'AbsTol', 0);
    testCase.verifyEqual(Q(1:5, :), Q2(1:5, :), 'AbsTol', 0);
    testCase.verifyEqual(R(1:5, :), R2(1:5, :), 'AbsTol', 0);
    testCase.verifyEqual(A_E(1:5, :, :), A_E2(1:5, :, :), 'AbsTol', 0);

    [X3, ~, ~, ~, ~, ~] = simulate(engine, U, 0.2 + 0.5, a0);
    testCase.verifyGreaterThan(max(abs(X(end, :) - X3(end, :))), 1e-10);

    a0b = a0;
    a0b.a_E = a0.a_E + 0.2;
    [X4, Q4, ~, ~, ~, ~] = simulate(engine, U, 0.2, a0b);
    testCase.verifyGreaterThan(max(abs(Q(1, :) - Q4(1, :))), 1e-12);
    testCase.verifyGreaterThan(max(abs(X(end, :) - X4(end, :))), 1e-12);

    testCase.verifyTrue(info.full_fractional_history_used);
    testCase.verifyFalse(info.fractional_history_truncated);
    testCase.verifyEqual(info.sfa_rate_index, 'n_minus_1');
    testCase.verifyEqual(info.drive_index, 'n_minus_1');
    testCase.verifyEqual(info.input_index, 'n_minus_1');
    testCase.verifyEqual(info.rate_index, 'n_minus_1');
end

function testDeterminismRngValueObjectAndNoMutation(testCase)
    cfg = validate_fractional_mesn_v2_mechanistic_sfa_config( ...
        base_sfa_cfg('piecewise_sigmoid'));
    engine = FractionalMESN_v2_mechanistic_sfa(cfg);
    engine_before = engine;
    U = [0.1; 0.2; 0.0];
    U_copy = U;
    x0 = [0.1, 0.0, -0.1];
    x0_copy = x0;
    a0 = a0_for_cfg(cfg, 0.2);
    a0_copy = a0;

    rng(7777, 'twister');
    s0 = rng;
    [X1, Q1, R1, AE1, AI1, info1] = simulate(engine, U, x0, a0);
    [X2, Q2, R2, AE2, AI2, info2] = simulate(engine, U, x0, a0);
    s1 = rng;

    testCase.verifyEqual(X1, X2, 'AbsTol', 0);
    testCase.verifyEqual(Q1, Q2, 'AbsTol', 0);
    testCase.verifyEqual(R1, R2, 'AbsTol', 0);
    testCase.verifyEqual(AE1, AE2, 'AbsTol', 0);
    testCase.verifyEqual(AI1, AI2, 'AbsTol', 0);
    testCase.verifyEqual(info1, info2);
    testCase.verifyEqual(s0.Type, s1.Type);
    testCase.verifyEqual(s0.Seed, s1.Seed);
    testCase.verifyEqual(s0.State, s1.State);
    testCase.verifyEqual(engine, engine_before);
    testCase.verifyEqual(U, U_copy);
    testCase.verifyEqual(x0, x0_copy);
    testCase.verifyEqual(a0, a0_copy);
end

function testZeroChannelEqualsNoSfaEngine(testCase)
    for item = { ...
            struct('mode', 'identity', 'alpha', 1), ...
            struct('mode', 'piecewise_sigmoid', 'alpha', 0.7)}
        cfg_sfa = base_sfa_cfg(item{1}.mode);
        cfg_sfa.alpha = item{1}.alpha;
        cfg_sfa.sfa.tau_a_E = zeros(1, 0);
        cfg_sfa.sfa.c_a_E = zeros(1, 0);
        cfg_sfa.sfa.tau_a_I = zeros(1, 0);
        cfg_sfa.sfa.c_a_I = zeros(1, 0);
        cfg_sfa = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_sfa);

        cfg_ns = strip_sfa(cfg_sfa);
        engine_sfa = FractionalMESN_v2_mechanistic_sfa(cfg_sfa);
        engine_ns = FractionalMESN_v2_mechanistic(cfg_ns);
        U = [0.1; -0.2; 0.05; 0.0];
        x0 = [0.2, -0.1, 0.05];
        a0 = struct('a_E', zeros(2, 0), 'a_I', zeros(1, 0));
        [X, Q, R, ~, ~, ~] = simulate(engine_sfa, U, x0, a0);
        [Xn, Qn, Rn, ~] = simulate(engine_ns, U, x0);
        testCase.verifyEqual(X, Xn, 'AbsTol', 0);
        testCase.verifyEqual(Q, Qn, 'AbsTol', 0);
        testCase.verifyEqual(R, Rn, 'AbsTol', 0);
    end
end

function testZeroCouplingEqualsNoSfaAndAEvolves(testCase)
    for alphas = [1, 0.8]
        cfg_sfa = base_sfa_cfg('identity');
        cfg_sfa.alpha = alphas;
        cfg_sfa.sfa.c_a_E = [0, 0];
        cfg_sfa.sfa.c_a_I = 0;
        cfg_sfa = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_sfa);
        cfg_ns = strip_sfa(cfg_sfa);
        engine_sfa = FractionalMESN_v2_mechanistic_sfa(cfg_sfa);
        engine_ns = FractionalMESN_v2_mechanistic(cfg_ns);
        U = [0.2; 0.1; -0.05];
        x0 = [0.1, 0.2, 0.3];
        a0 = a0_for_cfg(cfg_sfa, 0.4);
        [X, Q, R, A_E, A_I, ~] = simulate(engine_sfa, U, x0, a0);
        [Xn, Qn, Rn, ~] = simulate(engine_ns, U, x0);
        testCase.verifyEqual(Q, X, 'AbsTol', 0);
        testCase.verifyEqual(X, Xn, 'AbsTol', 0);
        testCase.verifyEqual(Q, Qn, 'AbsTol', 0);
        testCase.verifyEqual(R, Rn, 'AbsTol', 0);
        testCase.verifyGreaterThan( ...
            max(abs(reshape(A_E(end, :, :), [], 1) - a0.a_E(:))), 1e-12);
        testCase.verifyGreaterThan( ...
            abs(reshape(A_I(end, :, :), [], 1) - a0.a_I), 1e-12);
    end
end

function testWZeroEqualsE2InputOnly(testCase)
    for modes = {'identity', 'piecewise_sigmoid'}
        cfg_sfa = base_sfa_cfg(modes{1});
        cfg_sfa.alpha = 0.85;
        cfg_sfa.W = zeros(3, 3);
        cfg_sfa = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_sfa);
        engine_sfa = FractionalMESN_v2_mechanistic_sfa(cfg_sfa);

        cfg_e2 = struct();
        cfg_e2.n = cfg_sfa.n;
        cfg_e2.alpha = cfg_sfa.alpha;
        cfg_e2.dt = cfg_sfa.dt;
        cfg_e2.tau_x = cfg_sfa.tau_x;
        cfg_e2.W_in = cfg_sfa.W_in;
        cfg_e2.W = [];
        cfg_e2.recurrence_mode = 'input_only';
        engine_e2 = FractionalMESN_v2(cfg_e2);

        U = [0.2; -0.1; 0.3];
        x0 = [0.5, 0.0, -0.2];
        a0 = a0_for_cfg(cfg_sfa, 0.3);
        [X, Q, R, A_E, ~, ~] = simulate(engine_sfa, U, x0, a0);
        [Xe2, ~] = simulate(engine_e2, U, x0);
        testCase.verifyEqual(X, Xe2, 'AbsTol', 0);
        testCase.verifyGreaterThan(max(abs(Q(:) - X(:))), 1e-12);
        testCase.verifyGreaterThan( ...
            max(abs(reshape(A_E(end, :, :), [], 1) - a0.a_E(:))), 1e-12);
        testCase.verifyFalse(isequal(R, X));
    end
end

function testIdentityZeroCouplingEqualsE2Linear(testCase)
    for alphas = [1, 0.7]
        cfg_sfa = base_sfa_cfg('identity');
        cfg_sfa.alpha = alphas;
        cfg_sfa.sfa.c_a_E = [0, 0];
        cfg_sfa.sfa.c_a_I = 0;
        cfg_sfa = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_sfa);
        engine_sfa = FractionalMESN_v2_mechanistic_sfa(cfg_sfa);

        cfg_e2 = struct();
        cfg_e2.n = cfg_sfa.n;
        cfg_e2.alpha = cfg_sfa.alpha;
        cfg_e2.dt = cfg_sfa.dt;
        cfg_e2.tau_x = cfg_sfa.tau_x;
        cfg_e2.W_in = cfg_sfa.W_in;
        cfg_e2.W = cfg_sfa.W;
        cfg_e2.recurrence_mode = 'linear';
        engine_e2 = FractionalMESN_v2(cfg_e2);

        U = [0.1; 0.2; -0.05];
        x0 = [0.2, 0.1, 0.0];
        a0 = a0_for_cfg(cfg_sfa, 0.4);
        [X, Q, R, ~, ~, ~] = simulate(engine_sfa, U, x0, a0);
        [Xe2, ~] = simulate(engine_e2, U, x0);
        testCase.verifyEqual(Q, X, 'AbsTol', 0);
        testCase.verifyEqual(R, X, 'AbsTol', 0);
        testCase.verifyEqual(X, Xe2, 'AbsTol', 0);
    end
end

function testPiecewiseInvariantAndSfaLimitingFixtures(testCase)
    cfg = base_sfa_cfg('piecewise_sigmoid');
    cfg.alpha = 1;
    cfg = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg);
    engine = FractionalMESN_v2_mechanistic_sfa(cfg);
    a0 = struct('a_E', [0.1, 0.2; 0.3, 0.4], 'a_I', 0.5);
    U = [0.2; 0.1; 0.0; -0.1];
    [~, ~, R, A_E, A_I, info] = simulate(engine, U, 0.2, a0);
    testCase.verifyGreaterThanOrEqual(R, 0 - 1e-15);
    testCase.verifyLessThanOrEqual(R, 1 + 1e-15);
    testCase.verifyGreaterThanOrEqual(A_E, 0 - 1e-15);
    testCase.verifyLessThanOrEqual(A_E, 1 + 1e-15);
    testCase.verifyGreaterThanOrEqual(A_I, 0 - 1e-15);
    testCase.verifyLessThanOrEqual(A_I, 1 + 1e-15);
    testCase.verifyFalse(info.sfa_clipped);

    % Zero-rate adaptation decay: zero coupling so R=X; x0=0 keeps R=0
    cfg_d = base_sfa_cfg('identity');
    cfg_d.alpha = 1;
    cfg_d.W = zeros(3, 3);
    cfg_d.W_in = zeros(3, 1);
    cfg_d.sfa.c_a_E = [0, 0];
    cfg_d.sfa.c_a_I = 0;
    cfg_d = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_d);
    engine_d = FractionalMESN_v2_mechanistic_sfa(cfg_d);
    a0d = a0_for_cfg(cfg_d, 0.6);
    [~, ~, R0, A_E0, ~, ~] = simulate(engine_d, zeros(3, 1), 0, a0d);
    testCase.verifyEqual(R0, zeros(4, 3), 'AbsTol', 0);
    decay = exp(-cfg_d.dt ./ cfg_d.sfa.tau_a_E);
    expected = a0d.a_E;
    for k = 1:3
        expected = expected .* decay;
    end
    testCase.verifyEqual(reshape(A_E0(end, :, :), [2, 2]), expected, ...
        'AbsTol', 1e-14);

    % Adaptation one-step fixed point when a0 equals r_0
    cfg_f = base_sfa_cfg('identity');
    cfg_f.alpha = 1;
    cfg_f.sfa.c_a_E = [0, 0];
    cfg_f.sfa.c_a_I = 0;
    cfg_f = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_f);
    engine_f = FractionalMESN_v2_mechanistic_sfa(cfg_f);
    x0f = [0.2, 0.4, 0.6];
    a0f = struct('a_E', [0.2, 0.2; 0.4, 0.4], 'a_I', 0.6);
    [~, ~, ~, A_Ef, A_If, ~] = simulate(engine_f, zeros(1, 1), x0f, a0f);
    testCase.verifyEqual(reshape(A_Ef(2, :, :), [2, 2]), a0f.a_E, ...
        'AbsTol', 1e-14);
    testCase.verifyEqual(reshape(A_If(2, :, :), [1, 1]), a0f.a_I, ...
        'AbsTol', 1e-14);

    % Alpha==1 zero-drive x decay
    cfg_z = base_sfa_cfg('identity');
    cfg_z.alpha = 1;
    cfg_z.n = 1;
    cfg_z.W_in = 0;
    cfg_z.W = 0;
    cfg_z.presynaptic_signs = 1;
    cfg_z.sfa.tau_a_E = 0.2;
    cfg_z.sfa.c_a_E = 0;
    cfg_z.sfa.tau_a_I = zeros(1, 0);
    cfg_z.sfa.c_a_I = zeros(1, 0);
    cfg_z = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_z);
    engine_z = FractionalMESN_v2_mechanistic_sfa(cfg_z);
    a0z = struct('a_E', 0, 'a_I', []);
    [Xz, ~, ~, ~, ~, ~] = simulate(engine_z, zeros(5, 1), 2, a0z);
    ratio = (cfg_z.tau_x / cfg_z.dt) / ((cfg_z.tau_x / cfg_z.dt) + 1);
    expected = 2 * ratio .^ (0:5).';
    testCase.verifyEqual(Xz, expected, 'AbsTol', 0);
end

function testEngineSchemaHashDependenciesBoundedInfo(testCase)
    ENGINE_HASH = ...
        'c51bc46648b17eb1b32b112665874dc565c49b9678480f58fbd8b4a95bf4ef13';
    CORE_HASH = ...
        '3ee28c939b113d89e55693777f52786c8e7cdee4b5df629d97ccd40e926bda6f';
    RATE_HASH = ...
        '483b6192099426b1c22f29a35e04d9e22c508826a9d334f8da8b0134b94fe257';
    DALE_HASH = ...
        'dba675ded7b3f3f8e91ceb93185171a6fbedc42bba5050a97cca8d830bc3f081';
    FOUNDATION_HASH = ...
        'fe9691184cc22a4b4e9afe8d5740badf9442ed535e848f6fbbe94d6c2539fc69';
    SFA_HASH = ...
        '7bec90a56bc1df144848b5857eb9bd3565719a4905de4ca9ec7967124eee5fa0';
    E2_HASH = ...
        '38414814b75f35c997e695347ec8f9979660108e053d8f676329758e4fc6971d';

    spec = fractional_mesn_v2_mechanistic_sfa_engine_spec();
    testCase.verifyEqual(spec.schema_version, ...
        'fractional_mesn_v2_mechanistic_sfa_engine_v1');
    payload = rmfield(spec, 'content_hash');
    testCase.verifyEqual(spec.content_hash, canonical_sha256(payload));
    testCase.verifyEqual(spec.content_hash, ENGINE_HASH);
    testCase.verifyEqual(spec, fractional_mesn_v2_mechanistic_sfa_engine_spec());
    testCase.verifyEqual(spec.core_content_hash, CORE_HASH);
    testCase.verifyEqual(spec.rate_map_content_hash, RATE_HASH);
    testCase.verifyEqual(spec.dale_validator_content_hash, DALE_HASH);
    testCase.verifyEqual(spec.foundation_engine_content_hash, FOUNDATION_HASH);
    testCase.verifyEqual(spec.sfa_step_content_hash, SFA_HASH);
    testCase.verifyEqual(fractional_mesn_v2_engine_spec().content_hash, E2_HASH);
    testCase.verifyEqual(mesn_v2_sfa_step_spec().content_hash, SFA_HASH);
    testCase.verifyEqual( ...
        fractional_mesn_v2_mechanistic_engine_spec().content_hash, FOUNDATION_HASH);

    cfg = validate_fractional_mesn_v2_mechanistic_sfa_config( ...
        base_sfa_cfg('piecewise_sigmoid'));
    engine = FractionalMESN_v2_mechanistic_sfa(cfg);
    a0 = a0_for_cfg(cfg, 0.1);
    [~, ~, ~, ~, ~, info0] = simulate(engine, zeros(0, 1), 0, a0);
    [~, ~, ~, ~, ~, infoN] = simulate(engine, [0.1; 0.2], 0.1, a0);
    for infos = {info0, infoN}
        info = infos{1};
        testCase.verifyEqual(info.engine_schema_version, ...
            'fractional_mesn_v2_mechanistic_sfa_engine_v1');
        testCase.verifyEqual(info.engine_content_hash, ENGINE_HASH);
        testCase.verifyEqual(info.foundation_engine_content_hash, FOUNDATION_HASH);
        testCase.verifyEqual(info.core_content_hash, CORE_HASH);
        testCase.verifyEqual(info.rate_map_content_hash, RATE_HASH);
        testCase.verifyEqual(info.dale_validator_content_hash, DALE_HASH);
        testCase.verifyEqual(info.sfa_step_content_hash, SFA_HASH);
        testCase.verifyEqual(info.sfa_rate_index, 'n_minus_1');
        testCase.verifyEqual(info.drive_index, 'n_minus_1');
        testCase.verifyEqual(info.rate_index, 'n_minus_1');
        testCase.verifyEqual(info.input_index, 'n_minus_1');
        testCase.verifyTrue(info.full_fractional_history_used);
        testCase.verifyFalse(info.fractional_history_truncated);
        testCase.verifyTrue(info.sfa_integer_order);
        testCase.verifyFalse(info.sfa_clipped);
        testCase.verifyTrue(info.dale_signs_valid);
        testCase.verifyEqual(info.n_E, 2);
        testCase.verifyEqual(info.n_I, 1);
        testCase.verifyEqual(info.n_a_E, 2);
        testCase.verifyEqual(info.n_a_I, 1);
        testCase.verifyEqual(info.included_mechanisms, spec.included_mechanisms);
        testCase.verifyEqual(info.excluded_mechanisms, spec.excluded_mechanisms);
        testCase.verifyFalse(isfield(info, 'W'));
        testCase.verifyFalse(isfield(info, 'W_in'));
        testCase.verifyFalse(isfield(info, 'presynaptic_signs'));
        testCase.verifyFalse(isfield(info, 'tau_a_E'));
        testCase.verifyFalse(isfield(info, 'c_a_E'));
        testCase.verifyFalse(isfield(info, 'X'));
        testCase.verifyFalse(isfield(info, 'A_E'));
        testCase.verifyFalse(isfield(info, 'a0'));
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
    own = { ...
        'FractionalMESN_v2_mechanistic_sfa', ...
        'validate_fractional_mesn_v2_mechanistic_sfa_config', ...
        'fractional_mesn_v2_mechanistic_sfa_engine_spec'};
    for i = 1:numel(listing)
        path = fullfile(listing(i).folder, listing(i).name);
        [~, name, ~] = fileparts(path);
        if any(strcmp(name, own))
            continue;
        end
        txt = fileread(path);
        if contains(txt, 'FractionalMESN_v2_mechanistic_sfa')
            hits{end + 1} = path; %#ok<AGROW>
        end
    end
    testCase.verifyEmpty(hits);
end

function cfg = base_sfa_cfg(mode)
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
    cfg.sfa = struct();
    cfg.sfa.tau_a_E = [0.2, 0.4];
    cfg.sfa.c_a_E = [0.10, 0.05];
    cfg.sfa.tau_a_I = 0.3;
    cfg.sfa.c_a_I = 0.2;
end

function cfg_ns = strip_sfa(cfg_sfa)
    cfg_ns = rmfield(cfg_sfa, 'sfa');
end

function a0 = a0_for_cfg(cfg, fill)
    E_idx = find(cfg.presynaptic_signs == 1);
    I_idx = find(cfg.presynaptic_signs == -1);
    n_E = numel(E_idx);
    n_I = numel(I_idx);
    n_a_E = numel(cfg.sfa.tau_a_E);
    n_a_I = numel(cfg.sfa.tau_a_I);
    a0 = struct();
    a0.a_E = fill * ones(n_E, n_a_E);
    a0.a_I = fill * ones(n_I, n_a_I);
end

function [X, Q, R, A_E, A_I] = independent_alpha_one_sfa(cfg, U, x0, a0)
    % Independent alpha==1 reference: no Caputo core, no SFA-step, no engines.
    E_idx = find(cfg.presynaptic_signs == 1);
    I_idx = find(cfg.presynaptic_signs == -1);
    n_E = numel(E_idx);
    n_I = numel(I_idx);
    n_a_E = numel(cfg.sfa.tau_a_E);
    n_a_I = numel(cfg.sfa.tau_a_I);
    a_E = normalize_a_for_test(a0.a_E, n_E, n_a_E);
    a_I = normalize_a_for_test(a0.a_I, n_I, n_a_I);
    x_prev = normalize_x0_for_test(x0, cfg.n);
    N = size(U, 1);
    X = zeros(N + 1, cfg.n);
    Q = zeros(N + 1, cfg.n);
    R = zeros(N + 1, cfg.n);
    A_E = zeros(N + 1, n_E, n_a_E);
    A_I = zeros(N + 1, n_I, n_a_I);
    X(1, :) = x_prev;
    A_E(1, :, :) = reshape(a_E, [1, n_E, n_a_E]);
    A_I(1, :, :) = reshape(a_I, [1, n_I, n_a_I]);
    adapt = zeros(1, cfg.n);
    if n_E > 0
        adapt(E_idx) = (a_E * cfg.sfa.c_a_E(:)).';
    end
    if n_I > 0
        adapt(I_idx) = (a_I * cfg.sfa.c_a_I(:)).';
    end
    Q(1, :) = X(1, :) - adapt;
    R(1, :) = mesn_v2_rate_map(Q(1, :), cfg.activation);
    ratio = cfg.tau_x / cfg.dt;
    decay_E = exp(-cfg.dt ./ cfg.sfa.tau_a_E);
    decay_I = exp(-cfg.dt ./ cfg.sfa.tau_a_I);
    for k = 1:N
        u_prev = U(k, :);
        r_prev = R(k, :);
        d_prev = (cfg.W_in * u_prev.').' + (cfg.W * r_prev.').';
        x_prev = ((ratio * x_prev) + d_prev) / (ratio + 1);
        if n_a_E == 0
            a_E_next = a_E;
        else
            a_E_next = a_E .* decay_E + r_prev(E_idx).' * (1 - decay_E);
        end
        if n_a_I == 0
            a_I_next = a_I;
        else
            a_I_next = a_I .* decay_I + r_prev(I_idx).' * (1 - decay_I);
        end
        X(k + 1, :) = x_prev;
        A_E(k + 1, :, :) = reshape(a_E_next, [1, n_E, n_a_E]);
        A_I(k + 1, :, :) = reshape(a_I_next, [1, n_I, n_a_I]);
        adapt = zeros(1, cfg.n);
        if n_E > 0
            adapt(E_idx) = (a_E_next * cfg.sfa.c_a_E(:)).';
        end
        if n_I > 0
            adapt(I_idx) = (a_I_next * cfg.sfa.c_a_I(:)).';
        end
        Q(k + 1, :) = X(k + 1, :) - adapt;
        R(k + 1, :) = mesn_v2_rate_map(Q(k + 1, :), cfg.activation);
        a_E = a_E_next;
        a_I = a_I_next;
    end
end

function [X, Q, R, A_E, A_I] = manual_fractional_sfa_reference(cfg, U, x0, a0)
    % Manual Caputo + SFA-step + rate-map reference (not the SFA engine).
    E_idx = find(cfg.presynaptic_signs == 1);
    I_idx = find(cfg.presynaptic_signs == -1);
    n_E = numel(E_idx);
    n_I = numel(I_idx);
    n_a_E = numel(cfg.sfa.tau_a_E);
    n_a_I = numel(cfg.sfa.tau_a_I);
    a_E = normalize_a_for_test(a0.a_E, n_E, n_a_E);
    a_I = normalize_a_for_test(a0.a_I, n_I, n_a_I);
    x0_row = normalize_x0_for_test(x0, cfg.n);
    N = size(U, 1);
    X = zeros(N + 1, cfg.n);
    Q = zeros(N + 1, cfg.n);
    R = zeros(N + 1, cfg.n);
    A_E = zeros(N + 1, n_E, n_a_E);
    A_I = zeros(N + 1, n_I, n_a_I);
    X(1, :) = x0_row;
    A_E(1, :, :) = reshape(a_E, [1, n_E, n_a_E]);
    A_I(1, :, :) = reshape(a_I, [1, n_I, n_a_I]);
    adapt = zeros(1, cfg.n);
    if n_E > 0
        adapt(E_idx) = (a_E * cfg.sfa.c_a_E(:)).';
    end
    if n_I > 0
        adapt(I_idx) = (a_I * cfg.sfa.c_a_I(:)).';
    end
    Q(1, :) = X(1, :) - adapt;
    R(1, :) = mesn_v2_rate_map(Q(1, :), cfg.activation);
    for k = 1:N
        u_previous = U(k, :);
        r_previous = R(k, :);
        drive_previous = (cfg.W_in * u_previous.').' + (cfg.W * r_previous.').';
        X(k + 1, :) = caputo_l1_semiimplicit_step( ...
            X(1:k, :), drive_previous, cfg.dt, cfg.alpha, cfg.tau_x);
        a_E = mesn_v2_sfa_step(a_E, r_previous(E_idx), cfg.dt, cfg.sfa.tau_a_E);
        a_I = mesn_v2_sfa_step(a_I, r_previous(I_idx), cfg.dt, cfg.sfa.tau_a_I);
        A_E(k + 1, :, :) = reshape(a_E, [1, n_E, n_a_E]);
        A_I(k + 1, :, :) = reshape(a_I, [1, n_I, n_a_I]);
        adapt = zeros(1, cfg.n);
        if n_E > 0
            adapt(E_idx) = (a_E * cfg.sfa.c_a_E(:)).';
        end
        if n_I > 0
            adapt(I_idx) = (a_I * cfg.sfa.c_a_I(:)).';
        end
        Q(k + 1, :) = X(k + 1, :) - adapt;
        R(k + 1, :) = mesn_v2_rate_map(Q(k + 1, :), cfg.activation);
    end
end

function X = independent_alpha_one_on_x_ignore_sfa(cfg, U, x0)
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

function A = normalize_a_for_test(value, n_pop, n_chan)
    if isempty(value) && (n_pop == 0 || n_chan == 0)
        A = zeros(n_pop, n_chan);
    else
        A = double(value);
    end
end

function x0_row = normalize_x0_for_test(x0, n)
    if isscalar(x0)
        x0_row = repmat(double(x0), 1, n);
    else
        x0_row = reshape(double(x0), 1, n);
    end
end
