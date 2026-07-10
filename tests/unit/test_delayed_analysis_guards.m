function tests = test_delayed_analysis_guards
tests = functiontests(localfunctions);
end

function testJacobianGuards(testCase)
    params = make_test_params(struct('lags', 0.05));
    S = zeros(state_layout(params).n_total, 1);
    testCase.verifyError(@() compute_Jacobian(S, params), 'MESN:DelayedJacobianUnsupported');
    testCase.verifyError(@() compute_Jacobian_fast(S, params), 'MESN:DelayedJacobianUnsupported');
    testCase.verifyError(@() compute_J_eff(S, params), 'MESN:DelayedJacobianUnsupported');
    S_out = S.';
    testCase.verifyError(@() compute_Jacobian_at_indices(S_out, 1, params), ...
        'MESN:DelayedJacobianUnsupported');
end

function testLyapunovGuards(testCase)
    params = make_test_params(struct('lags', 0.05));
    S_out = zeros(10, state_layout(params).n_total);
    t_out = (0:9)' * params.dt;
    testCase.verifyError(@() compute_lyapunov_exponents('benettin', S_out, t_out, ...
        params.dt, 1/params.dt, [0, 1], params, odeset(), @ode45, ...
        @(t,S) S, t_out, zeros(params.n, 10)), ...
        'MESN:DelayedLyapunovUnsupported');
    testCase.verifyError(@() benettin_algorithm(S_out, t_out, params.dt, 1/params.dt, ...
        1e-8, [0, 1], params.dt, params, odeset(), @(t,S) S, t_out, zeros(params.n,10), @ode45), ...
        'MESN:DelayedLyapunovUnsupported');
    testCase.verifyError(@() lyapunov_spectrum_qr(S_out, t_out, params.dt, params, ...
        @ode45, odeset(), @(S) eye(size(S_out,2)), [0, 1], size(S_out,2), 1/params.dt), ...
        'MESN:DelayedLyapunovUnsupported');
end

function testFisherSensitivityGuard(testCase)
    params = make_test_params(struct('lags', 0.05));
    U = randn(100, 1);
    testCase.verifyError(@() compute_fisher_memory_curve(params, U, struct('K_max', 5)), ...
        'MESN:DelayedSensitivityUnsupported');
end

function testAutonomousDdeGuard(testCase)
    params = make_test_params(struct('lags', 0.05, 'n_inputs', 1));
    esn = SRNN_ESN(params);
    esn.is_trained = true;
    esn.n_outputs = 1;
    esn.W_out = zeros(1, params.n);
    esn.b_out = 0;
    testCase.verifyError(@() esn.generateAutonomous(zeros(5,1), 3), ...
        'SRNN_ESN:DDEAutonomousUnsupported');
end

function testGuardErrorsBeforePartialResultFiles(testCase)
    % Calling delayed Fisher must not create a results file.
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    out_dir = fullfile(repo_root, 'results', 'revalidated');
    before = {};
    if isfolder(out_dir)
        d = dir(fullfile(out_dir, '**', '*'));
        before = {d(~[d.isdir]).name};
    end

    params = make_test_params(struct('lags', 0.02));
    try
        compute_fisher_memory_curve(params, randn(50,1), struct());
        testCase.verifyFail('Expected DelayedSensitivityUnsupported');
    catch ME
        testCase.verifyEqual(ME.identifier, 'MESN:DelayedSensitivityUnsupported');
    end

    after = {};
    if isfolder(out_dir)
        d = dir(fullfile(out_dir, '**', '*'));
        after = {d(~[d.isdir]).name};
    end
    testCase.verifyEqual(numel(after), numel(before));
end
