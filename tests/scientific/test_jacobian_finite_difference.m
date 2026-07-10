function tests = test_jacobian_finite_difference
tests = functiontests(localfunctions);
end

function testGateG3AllMechanismConfigsPass(testCase)
    result = verifyJacobianConsistency(struct( ...
        'seed', 1729, ...
        'n_states', 3, ...
        'save_results', false));

    testCase.verifyEqual(result.n_cases, 15);
    testCase.verifyTrue(result.all_pass, ...
        sprintf(['Gate G3 failed: max rel Frobenius dense-FD=%.3e, ' ...
        'max abs dense-FD=%.3e, max rel Frobenius fast-FD=%.3e, ' ...
        'max abs fast-FD=%.3e'], ...
        result.max_rel_fro_dense_fd, result.max_abs_dense_fd, ...
        result.max_rel_fro_fast_fd, result.max_abs_fast_fd));

    for i = 1:numel(result.cases)
        c = result.cases(i);
        testCase.verifyLessThan(c.rel_fro_dense_fd, 1e-5, ...
            sprintf('%s state %d dense-FD rel Frobenius', c.label, c.state_index));
        testCase.verifyLessThan(c.max_abs_dense_fd, 1e-4, ...
            sprintf('%s state %d dense-FD max abs', c.label, c.state_index));
        testCase.verifyLessThan(c.rel_fro_fast_fd, 1e-5, ...
            sprintf('%s state %d fast-FD rel Frobenius', c.label, c.state_index));
        testCase.verifyLessThan(c.max_abs_fast_fd, 1e-4, ...
            sprintf('%s state %d fast-FD max abs', c.label, c.state_index));
    end
end

function testFiniteDifferenceHelperRespectsStepOverride(testCase)
    % Scalar linear system: dx/dt = A*x with known Jacobian A.
    A = [ -1.0, 0.2; 0.3, -0.5 ];
    rhs = @(S) A * S(:);
    S = [0.4; -0.2];
    J_fd = finite_difference_jacobian(rhs, S, struct('h', 1e-6));
    testCase.verifyEqual(J_fd, A, 'AbsTol', 1e-8, 'RelTol', 1e-8);
end

function testVerifyScriptHasNoClearOrClc(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    src = fileread(fullfile(repo_root, 'scripts', 'verifyJacobianConsistency.m'));
    testCase.verifyFalse(contains(src, 'clear;') || contains(src, 'clear ') || ...
        contains(src, 'clc;') || contains(src, 'clc '), ...
        'verifyJacobianConsistency must not call clear or clc');
end
