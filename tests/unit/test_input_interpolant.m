function tests = test_input_interpolant
tests = functiontests(localfunctions);
end

function testEndpointAndMidpoint(testCase)
    t_grid = [0; 1; 2];
    drive = [1 0 1; 0 1 0];
    u_fun = make_input_interpolant(t_grid, drive);

    testCase.verifyEqual(u_fun(0), [1; 0], 'AbsTol', 0);
    testCase.verifyEqual(u_fun(2), [1; 0], 'AbsTol', 0);
    testCase.verifyEqual(u_fun(1), [0; 1], 'AbsTol', 1e-12);
end

function testTwoDimensions(testCase)
    t_grid = (0:4)';
    drive = rand(3, numel(t_grid));
    u_fun = make_input_interpolant(t_grid, drive);
    testCase.verifyEqual(u_fun(2.5), drive(:, 3) * 0.5 + drive(:, 4) * 0.5, 'RelTol', 1e-12);
end

function testMismatchErrors(testCase)
    testCase.verifyError(@() make_input_interpolant([0 1], rand(2, 3)), ...
        'MESN:InvalidInputGrid');
end

function testOutOfRangeError(testCase)
    u_fun = make_input_interpolant([0 1], [0 0]);
    testCase.verifyError(@() u_fun(2), 'MESN:InputTimeOutOfRange');
end

function testDistinctFactories(testCase)
    t = [0; 1];
    f1 = make_input_interpolant(t, [1 1]);
    f2 = make_input_interpolant(t, [2 2]);
    testCase.verifyEqual(f1(0.5), 1, 'AbsTol', 0);
    testCase.verifyEqual(f2(0.5), 2, 'AbsTol', 0);
end
