function tests = test_test_harness
tests = functiontests(localfunctions);
end

function testMakeTestParamsDeterministic(testCase)
    params = make_test_params();

    testCase.verifyEqual(params.n, 6);
    testCase.verifyEqual(params.n_E, 3);
    testCase.verifyEqual(params.n_I, 3);
    testCase.verifySize(params.W_in, [6, 1]);
    testCase.verifyTrue(all(isfinite(params.W_in(:))));
end

function testHarnessDiscoversTests(testCase)
    tests_dir = fileparts(fileparts(mfilename('fullpath')));
    testCase.verifyEqual(exist(fullfile(tests_dir, 'run_all_tests.m'), 'file'), 2);
    layout_results = runtests(fullfile(tests_dir, 'unit', 'test_state_layout.m'), ...
        'OutputDetail', matlab.unittest.Verbosity.None);
    testCase.verifyTrue(all([layout_results.Passed]));
end
