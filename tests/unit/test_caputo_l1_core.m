function tests = test_caputo_l1_core
%TEST_CAPUTO_L1_CORE Unit tests for Caputo-L1 numerical core v1.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'scripts')));
    testCase.TestData.repo_root = repo_root;
    testCase.TestData.core_version = 'fractional_mesn_v2_caputo_l1_core_v1';
end

%% --- 1. Core specification ---
function testCoreSpecFrozenFieldsAndHash(testCase)
    spec = fractional_l1_core_spec();
    testCase.verifyEqual(spec.schema_version, testCase.TestData.core_version);
    testCase.verifyEqual(spec.operator, 'Caputo');
    testCase.verifyEqual(spec.alpha_domain, '0<alpha<=1');
    testCase.verifyEqual(spec.grid, 'uniform');
    testCase.verifyEqual(spec.fractional_scheme, 'L1_full_history');
    testCase.verifyEqual(spec.leak_index, 'semi_implicit_at_n');
    testCase.verifyEqual(spec.drive_index, 'explicit_at_n_minus_1');
    testCase.verifyEqual(spec.alpha_one_scheme, ...
        'backward_euler_leak_explicit_previous_drive');
    testCase.verifyEqual(spec.fractional_lower_terminal, 't0');
    testCase.verifyEqual(spec.fractional_prehistory, 'none_standard_caputo');
    testCase.verifyEqual(spec.delay_history, 'separate_future_module');
    testCase.verifyEqual(spec.history_truncation, 'forbidden');
    testCase.verifyEqual(spec.precision, 'double');
    testCase.verifyTrue(spec.deterministic);

    payload = rmfield(spec, 'content_hash');
    recomputed = canonical_sha256(payload);
    testCase.verifyEqual(spec.content_hash, recomputed);
    spec2 = fractional_l1_core_spec();
    testCase.verifyEqual(spec.content_hash, spec2.content_hash);
end

%% --- 2-6. Weights ---
function testWeightsNTermsZero(testCase)
    w = caputo_l1_weights(0.5, 0);
    testCase.verifyEqual(size(w), [0, 1]);
    testCase.verifyClass(w, 'double');
end

function testWeightW0ExactOne(testCase)
    for alpha = [0.25, 0.5, 0.75, 0.99, 1]
        w = caputo_l1_weights(alpha, 8);
        testCase.verifyEqual(w(1), 1);
    end
end

function testFractionalWeightsFinitePositiveNonIncreasing(testCase)
    w = caputo_l1_weights(0.7, 40);
    testCase.verifyTrue(all(isfinite(w)));
    testCase.verifyTrue(all(w > 0));
    testCase.verifyTrue(all(diff(w) <= 0 + 10 * eps));
end

function testStableWeightsNearAlphaOne(testCase)
    w = caputo_l1_weights(1 - 1e-12, 50);
    testCase.verifyTrue(all(isfinite(w)));
    testCase.verifyTrue(all(w > 0));
    testCase.verifyEqual(w(1), 1);
end

function testAlphaOneWeightsExact(testCase)
    w = caputo_l1_weights(1, 6);
    testCase.verifyEqual(w, [1; zeros(5, 1)]);
end

%% --- 7-14. Rejection / validation ---
function testRejectAlphaNonPositive(testCase)
    testCase.verifyError(@() caputo_l1_weights(0, 3), ...
        'caputo_l1_weights:AlphaOutOfRange');
    testCase.verifyError(@() caputo_l1_weights(-0.1, 3), ...
        'caputo_l1_weights:AlphaOutOfRange');
end

function testRejectAlphaGreaterThanOne(testCase)
    testCase.verifyError(@() caputo_l1_weights(1.01, 3), ...
        'caputo_l1_weights:AlphaOutOfRange');
end

function testRejectNonFiniteComplexAlpha(testCase)
    testCase.verifyError(@() caputo_l1_weights(NaN, 3), ...
        'caputo_l1_weights:InvalidAlpha');
    testCase.verifyError(@() caputo_l1_weights(Inf, 3), ...
        'caputo_l1_weights:InvalidAlpha');
    testCase.verifyError(@() caputo_l1_weights(0.5 + 1i, 3), ...
        'caputo_l1_weights:InvalidAlpha');
end

function testRejectInvalidNTerms(testCase)
    testCase.verifyError(@() caputo_l1_weights(0.5, -1), ...
        'caputo_l1_weights:InvalidNTerms');
    testCase.verifyError(@() caputo_l1_weights(0.5, 1.5), ...
        'caputo_l1_weights:InvalidNTerms');
    testCase.verifyError(@() caputo_l1_weights(0.5, NaN), ...
        'caputo_l1_weights:InvalidNTerms');
end

function testRejectInvalidDt(testCase)
    X = [0; 1];
    testCase.verifyError(@() caputo_l1_derivative(X, 0, 0.5), ...
        'caputo_l1_derivative:InvalidDt');
    testCase.verifyError(@() caputo_l1_derivative(X, -0.1, 0.5), ...
        'caputo_l1_derivative:InvalidDt');
    testCase.verifyError(@() caputo_l1_semiimplicit_step(X, 0, NaN, 0.5, 1), ...
        'caputo_l1_semiimplicit_step:InvalidDt');
end

function testRejectInvalidTauX(testCase)
    X = [1];
    testCase.verifyError(@() caputo_l1_semiimplicit_step(X, 0, 0.1, 0.5, 0), ...
        'caputo_l1_semiimplicit_step:InvalidTau');
    testCase.verifyError(@() caputo_l1_semiimplicit_step(X, 0, 0.1, 0.5, -1), ...
        'caputo_l1_semiimplicit_step:InvalidTau');
end

function testRejectNonFiniteComplexInputs(testCase)
    testCase.verifyError(@() caputo_l1_derivative([0; NaN], 0.1, 0.5), ...
        'caputo_l1_derivative:NonFiniteX');
    testCase.verifyError(@() caputo_l1_derivative([0; 1+1i], 0.1, 0.5), ...
        'caputo_l1_derivative:NonFiniteX');
    testCase.verifyError(@() caputo_l1_semiimplicit_step([1; Inf], 0, 0.1, 0.5, 1), ...
        'caputo_l1_semiimplicit_step:NonFiniteHistory');
    testCase.verifyError(@() caputo_l1_semiimplicit_step([1], NaN, 0.1, 0.5, 1), ...
        'caputo_l1_semiimplicit_step:InvalidDrive');
end

function testRejectStateDimensionMismatch(testCase)
    Xh = [1, 2; 3, 4];
    testCase.verifyError( ...
        @() caputo_l1_semiimplicit_step(Xh, [1, 2, 3], 0.1, 0.5, 1), ...
        'caputo_l1_semiimplicit_step:DriveDimensionMismatch');
    drive = ones(5, 2);
    testCase.verifyError( ...
        @() simulate_caputo_l1_reference(drive, [1, 2, 3], 0.1, 0.5, 1), ...
        'simulate_caputo_l1_reference:X0DimensionMismatch');
end

%% --- 15. Vector vs scalar ---
function testVectorStatesMatchIndependentScalars(testCase)
    dt = 0.05;
    alpha = 0.6;
    tau_x = 1.2;
    Xh = [0.1, -0.2, 0.3; 0.15, -0.1, 0.25; 0.2, 0.0, 0.2];
    drive = [0.5, -0.3, 0.1];
    [x_vec, ~] = caputo_l1_semiimplicit_step(Xh, drive, dt, alpha, tau_x);
    x_sc = zeros(1, 3);
    for j = 1:3
        [x_sc(j), ~] = caputo_l1_semiimplicit_step(Xh(:, j), drive(j), dt, alpha, tau_x);
    end
    testCase.verifyEqual(x_vec, x_sc, 'AbsTol', 0);
end

%% --- 16. First fractional step H_1 = 0 ---
function testFirstFractionalStepH1Zero(testCase)
    [x1, info] = caputo_l1_semiimplicit_step(1.0, 0.5, 0.1, 0.5, 1.0);
    testCase.verifyEqual(info.history_term, 0);
    kappa = info.kappa;
    x1_exact = (kappa * 1.0 + 0.5) / (kappa + 1);
    testCase.verifyEqual(x1, x1_exact, 'AbsTol', 0);
end

%% --- 17-18. Full history used; early increment matters for alpha < 1 ---
function testFractionalStepUsesAllHistory(testCase)
    Xh = (0:5).';
    [~, info] = caputo_l1_semiimplicit_step(Xh, 0, 0.1, 0.5, 1);
    testCase.verifyEqual(info.n_fractional_history_increments_used, 5);
    testCase.verifyTrue(info.full_history_used);
end

function testEarlyHistoryChangesFractionalNext(testCase)
    Xa = [0; 1; 2; 3];
    Xb = [0.5; 1; 2; 3];  % same latest state, different early increment
    [xa, ~] = caputo_l1_semiimplicit_step(Xa, 0, 0.1, 0.5, 1);
    [xb, ~] = caputo_l1_semiimplicit_step(Xb, 0, 0.1, 0.5, 1);
    testCase.verifyNotEqual(xa, xb);
end

%% --- 19. Alpha=1 ignores early history ---
function testAlphaOneIgnoresEarlyHistory(testCase)
    Xa = [0; 1; 2; 3];
    Xb = [9; 8; 7; 3];  % same x_{n-1}, different earlier rows
    [xa, info_a] = caputo_l1_semiimplicit_step(Xa, 0.2, 0.1, 1, 1);
    [xb, info_b] = caputo_l1_semiimplicit_step(Xb, 0.2, 0.1, 1, 1);
    testCase.verifyEqual(xa, xb, 'AbsTol', 0);
    testCase.verifyTrue(info_a.alpha_one_branch_used);
    testCase.verifyTrue(info_b.alpha_one_branch_used);
end

%% --- 20. Future drive cannot affect earlier outputs ---
function testFutureDriveDoesNotAffectEarlierOutputs(testCase)
    N = 20;
    drive_a = (0.1 * (1:N)).';
    drive_b = drive_a;
    drive_b(15:end) = drive_b(15:end) + 10;
    [Xa, ~] = simulate_caputo_l1_reference(drive_a, 1, 0.05, 0.5, 1);
    [Xb, ~] = simulate_caputo_l1_reference(drive_b, 1, 0.05, 0.5, 1);
    % Changing drive after index m=14 (0-based d_14..) must not affect X(1:15,:)
    % drive rows are d_0..d_{N-1}; changing from index 15 means d_14 onward (1-based 15)
    m = 14;  % 0-based last unchanged drive index
    testCase.verifyEqual(Xa(1:(m + 1), :), Xb(1:(m + 1), :), 'AbsTol', 0);
end

%% --- 21-22. Determinism / RNG ---
function testRepeatCallsBitwiseIdentical(testCase)
    drive = [0.1; -0.2; 0.3; 0.0; 0.5];
    [X1, info1] = simulate_caputo_l1_reference(drive, 0.25, 0.02, 0.75, 1.5);
    [X2, info2] = simulate_caputo_l1_reference(drive, 0.25, 0.02, 0.75, 1.5);
    testCase.verifyEqual(X1, X2, 'AbsTol', 0);
    testCase.verifyEqual(info1.core_version, info2.core_version);
end

function testCallerGlobalRngUnchanged(testCase)
    rng(12345, 'twister');
    s0 = rng;
    drive = (0.05 * (1:30)).';
    simulate_caputo_l1_reference(drive, 1, 0.01, 0.5, 1);
    caputo_l1_weights(0.5, 100);
    caputo_l1_derivative([(0:20).^2 / 400].', 0.05, 0.5);
    s1 = rng;
    testCase.verifyEqual(s0.Type, s1.Type);
    testCase.verifyEqual(s0.Seed, s1.Seed);
    testCase.verifyEqual(s0.State, s1.State);
end

%% --- 23-25. Simulator dimensions / truncation / finiteness ---
function testSimulatorOutputDimensions(testCase)
    drive = ones(12, 3);
    [X, info] = simulate_caputo_l1_reference(drive, [0, 0, 0], 0.1, 0.5, 1);
    testCase.verifyEqual(size(X), [13, 3]);
    testCase.verifyEqual(info.step_count, 12);
    testCase.verifyEqual(info.state_dimension, 3);
end

function testSimulatorReportsNoTruncation(testCase)
    [~, info] = simulate_caputo_l1_reference(zeros(8, 1), 1, 0.1, 0.5, 1);
    testCase.verifyTrue(info.full_history_used);
    testCase.verifyFalse(info.truncated);
    testCase.verifyTrue(info.deterministic);
end

function testNoNonfiniteOnModerateReferenceRun(testCase)
    N = 200;
    t = (0:N-1).' * 0.02;
    drive = sin(t);
    [X, ~] = simulate_caputo_l1_reference(drive, 0, 0.02, 0.8, 1);
    testCase.verifyTrue(all(isfinite(X(:))));
end
