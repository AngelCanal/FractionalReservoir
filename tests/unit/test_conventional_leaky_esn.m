function tests = test_conventional_leaky_esn
% Phase 4C-A conventional leaky tanh ESN (not Dale MESN).
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
    testCase.TestData.repo_root = repo_root;
end

%% A. Equations
function testExactOneStepUpdate(testCase)
    n = 3;
    Wres = [0.1, 0, 0; 0, 0.2, 0; 0, 0, 0.3];
    Win = [1; 0; -1];
    U = [0.5; -0.25];
    alpha = 0.4;
    [H, info] = run_conventional_leaky_esn(U, Wres, Win, alpha);
    h = zeros(n, 1);
    pre1 = Wres * h + Win * U(1);
    h1 = (1 - alpha) * h + alpha * tanh(pre1);
    pre2 = Wres * h1 + Win * U(2);
    h2 = (1 - alpha) * h1 + alpha * tanh(pre2);
    testCase.verifyEqual(H(1, :)', h1, 'AbsTol', 1e-14);
    testCase.verifyEqual(H(2, :)', h2, 'AbsTol', 1e-14);
    testCase.verifyEqual(info.feature_dimension, n);
    testCase.verifyFalse(info.include_input);
end

function testAlphaOneIsNonLeaky(testCase)
    Wres = 0.5 * eye(2);
    Win = [1; -1];
    U = [0.3; 0.7];
    [H, ~] = run_conventional_leaky_esn(U, Wres, Win, 1.0);
    h = zeros(2, 1);
    h = tanh(Wres * h + Win * U(1));
    testCase.verifyEqual(H(1, :)', h, 'AbsTol', 1e-14);
    h = tanh(Wres * h + Win * U(2));
    testCase.verifyEqual(H(2, :)', h, 'AbsTol', 1e-14);
end

function testZeroInitialStateAndNoRawInput(testCase)
    n = 4;
    [Wres, ~] = build_conventional_leaky_esn_Wres(n, 0.9, 11);
    Win = zeros(n, 1); Win(1) = 0.5; Win(3) = -0.5;
    [H, info] = run_conventional_leaky_esn(randn(20, 1), Wres, Win, 0.3);
    testCase.verifyEqual(size(H, 2), n);
    testCase.verifyEqual(info.feature_dimension, n);
    testCase.verifyFalse(info.include_input);
end

%% B. Recurrent matrix
function testDenseUnconstrainedSpectralRadius(testCase)
    n = 12;
    rho = 0.9;
    [W1, info1] = build_conventional_leaky_esn_Wres(n, rho, 101);
    [W2, ~] = build_conventional_leaky_esn_Wres(n, rho, 101);
    [W3, ~] = build_conventional_leaky_esn_Wres(n, rho, 102);
    testCase.verifyEqual(W1, W2);
    testCase.verifyFalse(isequal(W1, W3));
    testCase.verifyEqual(info1.achieved_spectral_radius, rho, 'AbsTol', 1e-10);
    testCase.verifyFalse(info1.recurrent_dale_constrained);
    % Unconstrained: both signs present with high probability
    testCase.verifyTrue(any(W1(:) > 0) && any(W1(:) < 0));
end

%% C. Input matching
function testInputMatchingFromMesnTemplate(testCase)
    mesn_Win = zeros(8, 1);
    mesn_Win([2, 5, 7]) = [0.4; -0.8; 0.2];
    [Win, info] = build_conventional_leaky_esn_Win(mesn_Win, 0.5);
    testCase.verifyEqual(find(Win ~= 0), find(mesn_Win ~= 0));
    testCase.verifyEqual(info.input_nonzero_count, 3);
    testCase.verifyEqual(nnz(Win([1, 3, 4, 6, 8])), 0);
    testCase.verifyEqual(sign(Win(find(Win))), sign(mesn_Win(find(mesn_Win)))); %#ok<FNDSB>
    scale = mean(abs(mesn_Win(mesn_Win ~= 0)));
    testCase.verifyEqual(Win(2), (mesn_Win(2) / scale) * 0.5, 'AbsTol', 1e-14);
end

%% D/F. Selection isolation + determinism
function testSelectionIgnoresTestTargets(testCase)
    n = 6;
    T = 160;
    stream = RandStream('mt19937ar', 'Seed', 3);
    U = 2 * rand(stream, T, 1) - 1;
    Y = filter(ones(4, 1)/4, 1, U);
    wash = 10;
    split = struct( ...
        'train_idx', (1:80)', ...
        'val_idx', (81:110)', ...
        'test_idx', (111:T)', ...
        'washout_steps', wash);
    Win0 = zeros(n, 1); Win0(1:2) = [1; -1];
    ce = build_matched_task_baselines_config(struct('base', struct('n', n)));
    opts = struct( ...
        'conventional_config', ce.conventional_leaky_esn, ...
        'lambda_grid', [1e-4, 1e-2, 1], ...
        'base_seed', 50);
    r1 = select_conventional_leaky_esn(U, Y, split, wash, Win0, opts);
    Y2 = Y;
    Y2(split.test_idx) = Y2(split.test_idx) + 5;
    r2 = select_conventional_leaky_esn(U, Y2, split, wash, Win0, opts);
    testCase.verifyEqual(r1.selected_lambda, r2.selected_lambda);
    testCase.verifyEqual(r1.selected_candidate_index, r2.selected_candidate_index);
    testCase.verifyEqual(r1.hyperparameters.spectral_radius, r2.hyperparameters.spectral_radius);
    testCase.verifyEqual(r1.ridge_diagnostics.coefficients, r2.ridge_diagnostics.coefficients);
    testCase.verifyEqual(r1.ridge_diagnostics.feature_mean, r2.ridge_diagnostics.feature_mean);
    testCase.verifyTrue(isequaln(r1.candidate_selection_table, r2.candidate_selection_table));
    testCase.verifyNotEqual(r1.metrics_test.nrmse, r2.metrics_test.nrmse);
    testCase.verifyEqual(r1.status, 'computed');
    testCase.verifyFalse(r1.recurrent_dale_constrained);
    testCase.verifyFalse(r1.has_sfa);
end

%% G. Comparison convention
function testBaselineComparisonSign(testCase)
    cmp = baseline_model_comparison(0.5, 0.8);
    testCase.verifyEqual(cmp.improvement_nrmse, 0.3, 'AbsTol', 1e-14);
    testCase.verifyEqual(cmp.ratio_nrmse, 0.5 / 0.8, 'AbsTol', 1e-14);
end

function testDaleReferenceKeys(testCase)
    testCase.verifyEqual(dale_mesn_control_reference_key('x'), ...
        'adapt-off__std-off__delay-ode_off__feat-x');
    testCase.verifyEqual(dale_mesn_control_reference_key('r'), ...
        'adapt-off__std-off__delay-ode_off__feat-r');
end
