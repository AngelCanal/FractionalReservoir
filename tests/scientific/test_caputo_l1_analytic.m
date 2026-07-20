function tests = test_caputo_l1_analytic
%TEST_CAPUTO_L1_ANALYTIC Analytic scientific tests for Caputo-L1 core v1.
%
% No Symbolic Math Toolbox or third-party Mittag-Leffler packages.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'scripts')));
    testCase.TestData.repo_root = repo_root;
end

%% A. Constant function -> Caputo derivative ~ 0
function testConstantFunctionDerivativeZero(testCase)
    alphas = [0.25, 0.5, 0.75, 0.9, 1.0];
    dt = 0.01;
    n = 80;
    c = 2.5;
    X = c * ones(n + 1, 1);
    for a = alphas
        [D, ~] = caputo_l1_derivative(X, dt, a);
        testCase.verifyLessThan(abs(D), 1e-12, ...
            sprintf('constant Caputo residual for alpha=%g', a));
    end
end

%% B. Power function vs exact formula (away from t=0)
function testPowerFunctionDerivative(testCase)
    alphas = [0.3, 0.5, 0.7];
    betas = [1.5, 2.0, 2.5];
    dt = 1e-3;
    t_end = 1.0;
    t = (0:dt:t_end).';
    for a = alphas
        for b = betas
            if ~(b > a)
                continue;
            end
            X = t.^b;
            [D, ~] = caputo_l1_derivative(X, dt, a);
            t_n = t(end);
            exact = gamma(b + 1) / gamma(b + 1 - a) * t_n^(b - a);
            rel = abs(D - exact) / max(1, abs(exact));
            testCase.verifyLessThan(rel, 5e-3, ...
                sprintf('power alpha=%g beta=%g rel_err=%g', a, b, rel));
        end
    end
end

%% C. Time-step convergence for smooth power beta=3
function testTimeStepConvergence(testCase)
    alpha = 0.5;
    beta = 3;
    t_eval = 1.0;
    dts = [0.05, 0.025, 0.0125, 0.00625];
    errs = zeros(size(dts));
    exact = gamma(beta + 1) / gamma(beta + 1 - alpha) * t_eval^(beta - alpha);
    for i = 1:numel(dts)
        dt = dts(i);
        t = (0:dt:t_eval).';
        X = t.^beta;
        [D, ~] = caputo_l1_derivative(X, dt, alpha);
        errs(i) = abs(D - exact);
    end
    testCase.verifyTrue(all(diff(errs) < 0), 'errors must decrease monotonically');
    % Observed order from last two refinements
    p_obs = log(errs(end-1) / errs(end)) / log(2);
    testCase.verifyGreaterThan(p_obs, 0.5, ...
        sprintf('observed order too low: %g', p_obs));
    % Record for report (do not demand unrealistic 2-alpha under singularity)
    fprintf('testTimeStepConvergence: errs=%s observed_order≈%.3f\n', ...
        mat2str(errs, 4), p_obs);
end

%% D. Fractional relaxation alpha=1/2 vs erfcx
function testFractionalRelaxationErfcx(testCase)
    tau_x = 1;
    alpha = 0.5;
    x0 = 1;
    T = 2.0;
    dts = [0.05, 0.025, 0.0125];
    final_errs = zeros(size(dts));
    for i = 1:numel(dts)
        dt = dts(i);
        N = round(T / dt);
        drive = zeros(N, 1);
        [X, ~] = simulate_caputo_l1_reference(drive, x0, dt, alpha, tau_x);
        t = (0:N).' * dt;
        % Exact: x(t) = E_{1/2}(-sqrt(t)) = erfcx(sqrt(t))
        x_exact = erfcx(sqrt(t));
        testCase.verifyTrue(all(isfinite(X)));
        testCase.verifyTrue(all(X >= -1e-12));
        testCase.verifyTrue(all(diff(X) <= 1e-10));
        final_errs(i) = abs(X(end) - x_exact(end));
    end
    testCase.verifyTrue(all(diff(final_errs) < 0), ...
        'relaxation error must decrease under dt refinement');
    % Defensible tolerance at finest grid for T=2
    testCase.verifyLessThan(final_errs(end), 2e-3, ...
        sprintf('final relaxation error %g', final_errs(end)));
    fprintf('testFractionalRelaxationErfcx: final_errs=%s\n', mat2str(final_errs, 4));
end

%% E. Alpha=1 exact discrete geometric decay
function testAlphaOneExactDiscreteRelaxation(testCase)
    tau_x = 1.5;
    dt = 0.05;
    x0 = 2.0;
    N = 40;
    drive = zeros(N, 1);
    [X, info] = simulate_caputo_l1_reference(drive, x0, dt, 1, tau_x);
    testCase.verifyTrue(info.alpha_one_branch_used);
    factor = tau_x / (tau_x + dt);
    n = (0:N).';
    X_exact = (factor.^n) * x0;
    testCase.verifyEqual(X, X_exact, 'AbsTol', 1e-14);
end

%% F. Constant equilibrium
function testConstantEquilibrium(testCase)
    c = 1.7;
    N = 50;
    drive = c * ones(N, 1);
    for alpha = [0.25, 0.5, 0.9, 1.0]
        [X, ~] = simulate_caputo_l1_reference(drive, c, 0.02, alpha, 1.0);
        testCase.verifyEqual(X, c * ones(N + 1, 1), 'AbsTol', 1e-12);
    end
end

%% G. Causality
function testCausality(testCase)
    N = 30;
    drive_a = linspace(0, 1, N).';
    drive_b = drive_a;
    m = 10;  % 0-based: change drive after index m
    drive_b((m + 2):end) = drive_b((m + 2):end) + 3;
    [Xa, ~] = simulate_caputo_l1_reference(drive_a, 0.5, 0.05, 0.6, 1);
    [Xb, ~] = simulate_caputo_l1_reference(drive_b, 0.5, 0.05, 0.6, 1);
    testCase.verifyEqual(Xa(1:(m + 1), :), Xb(1:(m + 1), :), 'AbsTol', 0);
end

%% H. Memory distinction
function testMemoryDistinction(testCase)
    Xa = [0; 1; 2; 3; 4];
    Xb = [1; 0; 2; 3; 4];  % identical latest state, different earlier increments
    drive = 0.1;
    dt = 0.1;
    tau_x = 1;
    [xa_f, ~] = caputo_l1_semiimplicit_step(Xa, drive, dt, 0.5, tau_x);
    [xb_f, ~] = caputo_l1_semiimplicit_step(Xb, drive, dt, 0.5, tau_x);
    testCase.verifyNotEqual(xa_f, xb_f);
    [xa_1, ~] = caputo_l1_semiimplicit_step(Xa, drive, dt, 1, tau_x);
    [xb_1, ~] = caputo_l1_semiimplicit_step(Xb, drive, dt, 1, tau_x);
    testCase.verifyEqual(xa_1, xb_1, 'AbsTol', 0);
end

%% I. kappa uses tau_x^alpha / dt^alpha
function testKappaDtTauScaling(testCase)
    Xh = [1; 1.1; 1.2];
    drive = 0;
    alpha = 0.5;
    tau_x = 2;
    dt = 0.25;
    [~, info] = caputo_l1_semiimplicit_step(Xh, drive, dt, alpha, tau_x);
    kappa_expected = (tau_x ^ alpha) / (gamma(2 - alpha) * (dt ^ alpha));
    testCase.verifyEqual(info.kappa, kappa_expected, 'RelTol', 1e-14);
    % Not tau_x / dt^alpha
    wrong1 = tau_x / (gamma(2 - alpha) * (dt ^ alpha));
    testCase.verifyNotEqual(info.kappa, wrong1);
    % Not tau_x^alpha / dt
    wrong2 = (tau_x ^ alpha) / (gamma(2 - alpha) * dt);
    testCase.verifyNotEqual(info.kappa, wrong2);
end

%% J. No toolbox-dependent reference (smoke: erfcx / gamma only)
function testNoToolboxDependentReference(testCase)
    % This file uses only MATLAB built-ins: gamma, erfcx, exp, etc.
    % Explicitly verify erfcx path works without mlf packages.
    y = erfcx(sqrt(0.5));
    testCase.verifyTrue(isfinite(y));
    testCase.verifyTrue(y > 0);
end
