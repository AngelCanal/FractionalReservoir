function tests = test_validate_params
tests = functiontests(localfunctions);
end

function testValidParamsPass(testCase)
    params = valid_params();
    validated = validate_MESN_params(params);
    testCase.verifyEqual(validated.n, params.n);
end

function testInvalidN(testCase)
    params = valid_params();
    params.n = 0;
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:InvalidN');
end

function testInvalidPopulationSum(testCase)
    params = valid_params();
    params.n_I = params.n_I + 1;
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:InvalidPopulationSize');
end

function testInvalidEIndices(testCase)
    params = valid_params();
    params.E_indices = [2, 3, 4];
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:InvalidIndices');
end

function testInvalidWShape(testCase)
    params = valid_params();
    params.W = params.W(1:end-1, :);
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:InvalidMatrix');
end

function testInvalidWInRows(testCase)
    params = valid_params();
    params.W_in = params.W_in(1:end-1, :);
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:InvalidMatrix');
end

function testInvalidTauD(testCase)
    params = valid_params();
    params.tau_d = -1;
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:InvalidScalar');
end

function testInvalidTauAE(testCase)
    params = valid_params();
    params.tau_a_E = [1, -2];
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:InvalidTauA');
end

function testInvalidCouplingCE(testCase)
    params = valid_params();
    params.c_a_E(1) = -0.1;
    params.c_total_E = sum(params.c_a_E);
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:InvalidCoupling');
end

function testMultipleStdUnsupported(testCase)
    params = valid_params();
    params.n_b_E = 2;
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:MultipleSTDUnsupported');
end

function testInvalidStdRecovery(testCase)
    params = valid_params();
    params.tau_b_E_rec = 0;
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:InvalidScalar');
end

function testVectorDelayUnsupported(testCase)
    params = valid_params();
    params.lags = [0.1, 0.2];
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:VectorDelayUnsupported');
end

function testInvalidScalarLag(testCase)
    params = valid_params();
    params.lags = -0.5;
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:InvalidLags');
end

function testScalarLagSupported(testCase)
    params = valid_params();
    params.lags = 0.05;
    validated = validate_MESN_params(params);
    testCase.verifyEqual(validated.lags, 0.05);
end

function testInvalidActivationHandle(testCase)
    params = valid_params();
    params.activation_function = 1;
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:InvalidActivation');
end

function testInvalidDt(testCase)
    params = valid_params();
    params.dt = 0;
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:InvalidScalar');
end

function testInvalidWhichStates(testCase)
    params = valid_params();
    params.which_states = 'q';
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:InvalidWhichStates');
end

function testInvalidLambda(testCase)
    params = valid_params();
    params.lambda = -1;
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:InvalidLambda');
end

function testZeroAdaptationRequiresEmptyTau(testCase)
    params = valid_params();
    params.n_a_E = 0;
    params.tau_a_E = [1];
    testCase.verifyError(@() validate_MESN_params(params), 'MESN:InvalidTauA');
end

function params = valid_params()
    params = make_test_params();
end
