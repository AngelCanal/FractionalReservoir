function tests = test_constructor_invariants
tests = functiontests(localfunctions);
end

function testConstructorValidatesParams(testCase)
    params = make_test_params();
    esn = SRNN_ESN(params);
    testCase.verifyEqual(esn.n, params.n);
    testCase.verifyEqual(esn.params.n, params.n);
end

function testInvalidParamsRejectedAtConstruction(testCase)
    params = make_test_params();
    params.n_I = params.n_I + 1;
    testCase.verifyError(@() SRNN_ESN(params), 'MESN:InvalidPopulationSize');
end

function testDdeWComponentsPartitionRecurrentMatrix(testCase)
    params = make_test_params(struct('lags', 0.04));
    esn = SRNN_ESN(params);
    testCase.verifyEqual(numel(esn.W_components), 2);
    W_sum = esn.W_components{1} + esn.W_components{2};
    testCase.verifyEqual(W_sum, esn.W);
    testCase.verifyEqual(esn.W_components{1}(:, esn.I_indices), zeros(esn.n, esn.n_I));
    testCase.verifyEqual(esn.W_components{2}(:, esn.E_indices), zeros(esn.n, esn.n_E));
end

function testOdeModeHasEmptyWComponents(testCase)
    params = make_test_params(struct('lags', []));
    esn = SRNN_ESN(params);
    testCase.verifyEmpty(esn.W_components);
    testCase.verifyEmpty(esn.lags);
end

function testExportParamsReturnsValidatedStruct(testCase)
    params = make_test_params();
    esn = SRNN_ESN(params);
    exported = esn.exportParams();
    testCase.verifyEqual(exported.n, params.n);
    testCase.verifyEqual(exported.W, params.W);
    validated = validate_MESN_params(exported);
    testCase.verifyEqual(validated.n, params.n);
end

function testVectorDelayRejectedAtConstruction(testCase)
    params = make_test_params();
    params.lags = [0.1, 0.2];
    testCase.verifyError(@() SRNN_ESN(params), 'MESN:VectorDelayUnsupported');
end

function testMultipleStdRejectedAtConstruction(testCase)
    params = make_test_params();
    params.n_b_E = 2;
    testCase.verifyError(@() SRNN_ESN(params), 'MESN:MultipleSTDUnsupported');
end
