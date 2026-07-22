function tests = test_mesn_v2_sfa_step
%TEST_MESN_V2_SFA_STEP Unit tests for standalone MESN v2 SFA-step module.
%
% Deterministic hand-constructed fixtures only; no governed seeds.
% Does not call ODE/DDE solvers or the future SFA-enabled engine.
this_file = mfilename('fullpath');
repo_root = fileparts(fileparts(fileparts(this_file)));
addpath(genpath(fullfile(repo_root, 'src')));
tests = functiontests({ ...
    @testScalarPopulationOneChannelFormula, ...
    @testMultipleNeuronsOneChannelFormula, ...
    @testOneNeuronMultipleChannelsFormula, ...
    @testMultipleNeuronsMultipleChannelsMatrixFormula, ...
    @testRowAndColumnRateNormalization, ...
    @testRowAndColumnTauNormalization, ...
    @testOutputSizeAndSingletonPreservation, ...
    @testZeroChannelNonzeroPopulation, ...
    @testZeroPopulationNonzeroChannels, ...
    @testZeroPopulationZeroChannels, ...
    @testRejectNonemptyRateForZeroPopulation, ...
    @testRejectNonemptyTauForZeroChannels, ...
    @testZeroRateExactDecay, ...
    @testFixedPointWhenAEqualsR, ...
    @testConstantRateTwoStepSemigroup, ...
    @testConditionalUnitIntervalInvariant, ...
    @testOutsideRangeNoClipping, ...
    @testSmallDtApproachesPrevious, ...
    @testInvalidAdaptationRejected, ...
    @testInvalidRateRejected, ...
    @testInvalidDtRejected, ...
    @testInvalidTauRejected, ...
    @testDeterminismRngAndInputsUnchanged, ...
    @testSchemaHashInfoAndStableErrors});
end

function testScalarPopulationOneChannelFormula(testCase)
    a_previous = 0.25;
    r_previous = 0.80;
    dt = 0.05;
    tau_a = 0.20;
    expected = hand_update(a_previous, r_previous, dt, tau_a);
    [a_next, info] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_a);
    testCase.verifyEqual(a_next, expected, 'AbsTol', 0);
    testCase.verifyEqual(info.n_population, 1);
    testCase.verifyEqual(info.n_channels, 1);
end

function testMultipleNeuronsOneChannelFormula(testCase)
    a_previous = [0.10; 0.40; 0.70];
    r_previous = [0.20; 0.50; 0.90];
    dt = 0.02;
    tau_a = 0.15;
    expected = hand_update(a_previous, r_previous, dt, tau_a);
    [a_next, info] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_a);
    testCase.verifyEqual(a_next, expected, 'AbsTol', 0);
    testCase.verifyEqual(size(a_next, 1), 3);
    testCase.verifyEqual(size(a_next, 2), 1);
    testCase.verifyEqual(info.n_population, 3);
    testCase.verifyEqual(info.n_channels, 1);
end

function testOneNeuronMultipleChannelsFormula(testCase)
    a_previous = [0.10, 0.30, 0.50];
    r_previous = 0.70;
    dt = 0.01;
    tau_a = [0.05, 0.10, 0.25];
    expected = hand_update(a_previous, r_previous, dt, tau_a);
    [a_next, info] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_a);
    testCase.verifyEqual(a_next, expected, 'AbsTol', 0);
    testCase.verifyEqual(size(a_next, 1), 1);
    testCase.verifyEqual(size(a_next, 2), 3);
    testCase.verifyEqual(info.n_population, 1);
    testCase.verifyEqual(info.n_channels, 3);
end

function testMultipleNeuronsMultipleChannelsMatrixFormula(testCase)
    a_previous = [0.10, 0.20; 0.30, 0.40; 0.50, 0.60];
    r_previous = [0.15; 0.45; 0.75];
    dt = 0.03;
    tau_a = [0.08, 0.16];
    expected = hand_update(a_previous, r_previous, dt, tau_a);
    [a_next, info] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_a);
    testCase.verifyEqual(a_next, expected, 'AbsTol', 0);
    testCase.verifyEqual(size(a_next, 1), 3);
    testCase.verifyEqual(size(a_next, 2), 2);
    testCase.verifyEqual(info.n_population, 3);
    testCase.verifyEqual(info.n_channels, 2);
end

function testRowAndColumnRateNormalization(testCase)
    a_previous = [0.2, 0.3; 0.4, 0.5];
    dt = 0.01;
    tau_a = [0.1, 0.2];
    r_row = [0.6, 0.7];
    r_col = [0.6; 0.7];
    [a_row, ~] = mesn_v2_sfa_step(a_previous, r_row, dt, tau_a);
    [a_col, ~] = mesn_v2_sfa_step(a_previous, r_col, dt, tau_a);
    expected = hand_update(a_previous, r_col, dt, tau_a);
    testCase.verifyEqual(a_row, expected, 'AbsTol', 0);
    testCase.verifyEqual(a_col, expected, 'AbsTol', 0);
    testCase.verifyEqual(a_row, a_col, 'AbsTol', 0);
end

function testRowAndColumnTauNormalization(testCase)
    a_previous = [0.2, 0.3; 0.4, 0.5];
    r_previous = [0.6; 0.7];
    dt = 0.01;
    tau_row = [0.1, 0.2];
    tau_col = [0.1; 0.2];
    [a_from_row, ~] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_row);
    [a_from_col, ~] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_col);
    expected = hand_update(a_previous, r_previous, dt, tau_row);
    testCase.verifyEqual(a_from_row, expected, 'AbsTol', 0);
    testCase.verifyEqual(a_from_col, expected, 'AbsTol', 0);
    testCase.verifyEqual(a_from_row, a_from_col, 'AbsTol', 0);
end

function testOutputSizeAndSingletonPreservation(testCase)
    a_previous = zeros(4, 1);
    r_previous = [0.1; 0.2; 0.3; 0.4];
    [a_next, ~] = mesn_v2_sfa_step(a_previous, r_previous, 0.01, 0.2);
    testCase.verifyEqual(size(a_next, 1), 4);
    testCase.verifyEqual(size(a_next, 2), 1);
    testCase.verifyEqual(ndims(a_next), 2);

    a_row = [0.1, 0.2, 0.3];
    [a_next_row, ~] = mesn_v2_sfa_step(a_row, 0.5, 0.01, [0.1, 0.2, 0.3]);
    testCase.verifyEqual(size(a_next_row, 1), 1);
    testCase.verifyEqual(size(a_next_row, 2), 3);
end

function testZeroChannelNonzeroPopulation(testCase)
    a_previous = zeros(3, 0);
    r_previous = [0.1; 0.2; 0.3];
    dt = 0.05;
    tau_a = [];
    [a_next, info] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_a);
    testCase.verifyEqual(size(a_next, 1), 3);
    testCase.verifyEqual(size(a_next, 2), 0);
    testCase.verifyEqual(a_next, a_previous);
    testCase.verifyEqual(info.n_population, 3);
    testCase.verifyEqual(info.n_channels, 0);

    [a_next2, ~] = mesn_v2_sfa_step(a_previous, r_previous, dt, zeros(1, 0));
    testCase.verifyEqual(size(a_next2, 2), 0);
    [a_next3, ~] = mesn_v2_sfa_step(a_previous, r_previous, dt, zeros(0, 1));
    testCase.verifyEqual(size(a_next3, 2), 0);
end

function testZeroPopulationNonzeroChannels(testCase)
    a_previous = zeros(0, 2);
    r_previous = zeros(0, 1);
    dt = 0.02;
    tau_a = [0.1, 0.25];
    [a_next, info] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_a);
    testCase.verifyEqual(size(a_next, 1), 0);
    testCase.verifyEqual(size(a_next, 2), 2);
    testCase.verifyEqual(info.n_population, 0);
    testCase.verifyEqual(info.n_channels, 2);

    [a_next2, ~] = mesn_v2_sfa_step(a_previous, zeros(1, 0), dt, tau_a);
    testCase.verifyEqual(size(a_next2, 1), 0);
    testCase.verifyEqual(size(a_next2, 2), 2);
    [a_next3, ~] = mesn_v2_sfa_step(a_previous, [], dt, tau_a);
    testCase.verifyEqual(size(a_next3, 1), 0);
    testCase.verifyEqual(size(a_next3, 2), 2);
end

function testZeroPopulationZeroChannels(testCase)
    a_previous = zeros(0, 0);
    [a_next, info] = mesn_v2_sfa_step(a_previous, [], 0.01, []);
    testCase.verifyEqual(size(a_next, 1), 0);
    testCase.verifyEqual(size(a_next, 2), 0);
    testCase.verifyEqual(info.n_population, 0);
    testCase.verifyEqual(info.n_channels, 0);
    testCase.verifyEqual(info.clipped, false);
    testCase.verifyEqual(info.integer_order, true);
    testCase.verifyEqual(info.fractional_history_used, false);
    testCase.verifyEqual(info.delay_history_used, false);
end

function testRejectNonemptyRateForZeroPopulation(testCase)
    a_previous = zeros(0, 2);
    tau_a = [0.1, 0.2];
    testCase.verifyError( ...
        @() mesn_v2_sfa_step(a_previous, 0.5, 0.01, tau_a), ...
        'mesn_v2_sfa_step:invalidRate');
    testCase.verifyError( ...
        @() mesn_v2_sfa_step(a_previous, zeros(0, 2), 0.01, tau_a), ...
        'mesn_v2_sfa_step:invalidRate');
end

function testRejectNonemptyTauForZeroChannels(testCase)
    a_previous = zeros(2, 0);
    r_previous = [0.1; 0.2];
    testCase.verifyError( ...
        @() mesn_v2_sfa_step(a_previous, r_previous, 0.01, 0.2), ...
        'mesn_v2_sfa_step:invalidTau');
    testCase.verifyError( ...
        @() mesn_v2_sfa_step(a_previous, r_previous, 0.01, zeros(0, 2)), ...
        'mesn_v2_sfa_step:invalidTau');
end

function testZeroRateExactDecay(testCase)
    a_previous = [0.2, 0.5; 0.4, 0.8];
    r_previous = [0; 0];
    dt = 0.07;
    tau_a = [0.1, 0.3];
    expected = a_previous .* exp(-dt ./ tau_a);
    [a_next, ~] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_a);
    testCase.verifyEqual(a_next, expected, 'AbsTol', 0);
end

function testFixedPointWhenAEqualsR(testCase)
    r_previous = [0.2; 0.55; 0.9];
    a_previous = [r_previous, r_previous];
    dt = 0.04;
    tau_a = [0.12, 0.35];
    [a_next, ~] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_a);
    testCase.verifyEqual(a_next, a_previous, 'AbsTol', 0);
end

function testConstantRateTwoStepSemigroup(testCase)
    a0 = [0.15, 0.35; 0.55, 0.75];
    r = [0.25; 0.65];
    dt = 0.03;
    tau_a = [0.09, 0.18];
    [a1, ~] = mesn_v2_sfa_step(a0, r, dt, tau_a);
    [a2, ~] = mesn_v2_sfa_step(a1, r, dt, tau_a);
    a_direct = hand_update(a0, r, 2 * dt, tau_a);
    testCase.verifyEqual(a2, a_direct, 'AbsTol', 1e-15);
end

function testConditionalUnitIntervalInvariant(testCase)
    a_previous = [0.0, 0.25, 1.0; 0.5, 0.75, 0.1];
    r_previous = [0.0; 1.0];
    dt = 0.11;
    tau_a = [0.05, 0.2, 0.4];
    [a_next, info] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_a);
    testCase.verifyGreaterThanOrEqual(a_next, 0 - 1e-15);
    testCase.verifyLessThanOrEqual(a_next, 1 + 1e-15);
    testCase.verifyEqual(info.clipped, false);
end

function testOutsideRangeNoClipping(testCase)
    a_previous = [-0.5, 1.7; 2.3, -1.1];
    r_previous = [-2.0; 3.5];
    dt = 0.05;
    tau_a = [0.1, 0.25];
    expected = hand_update(a_previous, r_previous, dt, tau_a);
    [a_next, info] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_a);
    testCase.verifyEqual(a_next, expected, 'AbsTol', 0);
    testCase.verifyEqual(info.clipped, false);
    testCase.verifyTrue(any(a_next(:) < 0) || any(a_next(:) > 1));
end

function testSmallDtApproachesPrevious(testCase)
    a_previous = [0.33, 0.66; 0.11, 0.88];
    r_previous = [0.9; 0.2];
    tau_a = [0.15, 0.4];
    dts = [1e-2, 1e-3, 1e-4, 1e-5];
    errs = zeros(size(dts));
    for i = 1:numel(dts)
        [a_next, ~] = mesn_v2_sfa_step(a_previous, r_previous, dts(i), tau_a);
        errs(i) = max(abs(a_next(:) - a_previous(:)));
    end
    testCase.verifyTrue(all(diff(errs) < 0));
    testCase.verifyLessThan(errs(end), 1e-4);
end

function testInvalidAdaptationRejected(testCase)
    r = [0.1; 0.2];
    dt = 0.01;
    tau = [0.1, 0.2];
    testCase.verifyError(@() mesn_v2_sfa_step('bad', r, dt, tau), ...
        'mesn_v2_sfa_step:invalidAdaptation');
    testCase.verifyError(@() mesn_v2_sfa_step([1+2i, 0; 0, 1], r, dt, tau), ...
        'mesn_v2_sfa_step:invalidAdaptation');
    testCase.verifyError(@() mesn_v2_sfa_step([NaN, 0; 0, 1], r, dt, tau), ...
        'mesn_v2_sfa_step:invalidAdaptation');
    testCase.verifyError(@() mesn_v2_sfa_step([Inf, 0; 0, 1], r, dt, tau), ...
        'mesn_v2_sfa_step:invalidAdaptation');
    testCase.verifyError(@() mesn_v2_sfa_step(ones(2, 2, 2), r, dt, tau), ...
        'mesn_v2_sfa_step:invalidAdaptation');
end

function testInvalidRateRejected(testCase)
    a = [0.1, 0.2; 0.3, 0.4];
    dt = 0.01;
    tau = [0.1, 0.2];
    testCase.verifyError(@() mesn_v2_sfa_step(a, 'bad', dt, tau), ...
        'mesn_v2_sfa_step:invalidRate');
    testCase.verifyError(@() mesn_v2_sfa_step(a, [1+1i; 0], dt, tau), ...
        'mesn_v2_sfa_step:invalidRate');
    testCase.verifyError(@() mesn_v2_sfa_step(a, [NaN; 0.2], dt, tau), ...
        'mesn_v2_sfa_step:invalidRate');
    testCase.verifyError(@() mesn_v2_sfa_step(a, [Inf; 0.2], dt, tau), ...
        'mesn_v2_sfa_step:invalidRate');
    testCase.verifyError(@() mesn_v2_sfa_step(a, [0.1; 0.2; 0.3], dt, tau), ...
        'mesn_v2_sfa_step:invalidRate');
    testCase.verifyError(@() mesn_v2_sfa_step(a, [0.1, 0.2; 0.3, 0.4], dt, tau), ...
        'mesn_v2_sfa_step:invalidRate');
end

function testInvalidDtRejected(testCase)
    a = 0.2;
    r = 0.5;
    tau = 0.1;
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, 0, tau), ...
        'mesn_v2_sfa_step:invalidDt');
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, -0.01, tau), ...
        'mesn_v2_sfa_step:invalidDt');
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, NaN, tau), ...
        'mesn_v2_sfa_step:invalidDt');
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, Inf, tau), ...
        'mesn_v2_sfa_step:invalidDt');
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, 1+1i, tau), ...
        'mesn_v2_sfa_step:invalidDt');
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, [0.01, 0.02], tau), ...
        'mesn_v2_sfa_step:invalidDt');
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, 'dt', tau), ...
        'mesn_v2_sfa_step:invalidDt');
end

function testInvalidTauRejected(testCase)
    a = [0.1, 0.2; 0.3, 0.4];
    r = [0.1; 0.2];
    dt = 0.01;
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, dt, 0.1), ...
        'mesn_v2_sfa_step:invalidTau');
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, dt, [0.1, 0]), ...
        'mesn_v2_sfa_step:invalidTau');
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, dt, [0.1, -0.2]), ...
        'mesn_v2_sfa_step:invalidTau');
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, dt, [0.1, NaN]), ...
        'mesn_v2_sfa_step:invalidTau');
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, dt, [0.1, Inf]), ...
        'mesn_v2_sfa_step:invalidTau');
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, dt, [0.1, 1+1i]), ...
        'mesn_v2_sfa_step:invalidTau');
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, dt, [0.1, 0.2; 0.3, 0.4]), ...
        'mesn_v2_sfa_step:invalidTau');
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, dt, 'tau'), ...
        'mesn_v2_sfa_step:invalidTau');
    testCase.verifyError(@() mesn_v2_sfa_step(a, r, dt, []), ...
        'mesn_v2_sfa_step:invalidTau');
end

function testDeterminismRngAndInputsUnchanged(testCase)
    a_previous = [0.1, 0.2; 0.3, 0.4];
    r_previous = [0.5; 0.6];
    dt = 0.02;
    tau_a = [0.1, 0.2];
    a_copy = a_previous;
    r_copy = r_previous;
    tau_copy = tau_a;

    rng(4242, 'twister');
    s0 = rng;
    [a1, info1] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_a);
    [a2, info2] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_a);
    s1 = rng;

    testCase.verifyEqual(a1, a2, 'AbsTol', 0);
    testCase.verifyEqual(info1, info2);
    testCase.verifyEqual(s0.Type, s1.Type);
    testCase.verifyEqual(s0.Seed, s1.Seed);
    testCase.verifyEqual(s0.State, s1.State);
    testCase.verifyEqual(a_previous, a_copy);
    testCase.verifyEqual(r_previous, r_copy);
    testCase.verifyEqual(tau_a, tau_copy);
end

function testSchemaHashInfoAndStableErrors(testCase)
    frozen_hash = ...
        '7bec90a56bc1df144848b5857eb9bd3565719a4905de4ca9ec7967124eee5fa0';

    spec = mesn_v2_sfa_step_spec();
    testCase.verifyEqual(spec.schema_version, 'mesn_v2_sfa_step_v1');
    payload = rmfield(spec, 'content_hash');
    testCase.verifyEqual(spec.content_hash, canonical_sha256(payload));
    testCase.verifyEqual(spec.content_hash, frozen_hash);
    spec2 = mesn_v2_sfa_step_spec();
    testCase.verifyEqual(spec, spec2);

    [~, info] = mesn_v2_sfa_step([0.2, 0.3], 0.4, 0.01, [0.1, 0.2]);
    testCase.verifyEqual(info.schema_version, 'mesn_v2_sfa_step_v1');
    testCase.verifyEqual(info.content_hash, frozen_hash);
    testCase.verifyEqual(info.update_scheme, 'exact_exponential_zero_order_hold');
    testCase.verifyEqual(info.rate_index, 'n_minus_1');
    testCase.verifyEqual(info.clipped, false);
    testCase.verifyEqual(info.integer_order, true);
    testCase.verifyEqual(info.fractional_history_used, false);
    testCase.verifyEqual(info.delay_history_used, false);
    testCase.verifyEqual(info.n_population, 1);
    testCase.verifyEqual(info.n_channels, 2);

    testCase.verifyFalse(isfield(info, 'a_previous'));
    testCase.verifyFalse(isfield(info, 'a_next'));
    testCase.verifyFalse(isfield(info, 'r_previous'));
    testCase.verifyFalse(isfield(info, 'tau_a'));
    testCase.verifyFalse(isfield(info, 'decay'));
    testCase.verifyFalse(isfield(info, 'trajectories'));

    testCase.verifyError(@() mesn_v2_sfa_step(NaN, 0.1, 0.01, 0.1), ...
        'mesn_v2_sfa_step:invalidAdaptation');
    testCase.verifyError(@() mesn_v2_sfa_step(0.1, NaN, 0.01, 0.1), ...
        'mesn_v2_sfa_step:invalidRate');
    testCase.verifyError(@() mesn_v2_sfa_step(0.1, 0.1, 0, 0.1), ...
        'mesn_v2_sfa_step:invalidDt');
    testCase.verifyError(@() mesn_v2_sfa_step(0.1, 0.1, 0.01, -1), ...
        'mesn_v2_sfa_step:invalidTau');
end

function expected = hand_update(a_previous, r_previous, dt, tau_a)
    decay = exp(-dt ./ tau_a(:).');
    expected = a_previous .* decay + r_previous(:) * (1 - decay);
end
