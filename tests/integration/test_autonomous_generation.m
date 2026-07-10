function tests = test_autonomous_generation
tests = functiontests(localfunctions);
end

function testTwoStepMatchesManualReference(testCase)
    esn = make_linear_autonomous_esn();
    init_data = 0.15 * ones(8, 1);
    n_steps = 2;

    Y_gen = esn.generateAutonomous(init_data, n_steps, struct( ...
        'washout_steps', 8, 'ode_reltol', 1e-8, 'ode_abstol', 1e-10));
    Y_manual = manual_autonomous_reference(esn, init_data, n_steps, 8);

    testCase.verifyEqual(Y_gen, Y_manual, 'RelTol', 1e-6, 'AbsTol', 1e-8);
    testCase.verifyGreaterThan(abs(Y_gen(2) - Y_gen(1)), 1e-6);
end

function testChangingFirstPredictionChangesLaterOutput(testCase)
    esn = make_linear_autonomous_esn();
    init_data = 0.15 * ones(8, 1);
    opts = struct('washout_steps', 8, 'ode_reltol', 1e-8, 'ode_abstol', 1e-10);

    esn.W_out = 1.0;
    Y_a = esn.generateAutonomous(init_data, 2, opts);

    esn.W_out = 1.4;
    Y_b = esn.generateAutonomous(init_data, 2, opts);

    testCase.verifyGreaterThan(abs(Y_a(1) - Y_b(1)), 1e-6);
    testCase.verifyGreaterThan(abs(Y_a(2) - Y_b(2)), 1e-6);
end

function testDdeAutonomousRejectedBeforeStateMutation(testCase)
    params = make_test_params(struct('lags', 0.05));
    esn = SRNN_ESN(params);
    esn.W_out = ones(esn.n, 1);
    esn.b_out = 0;
    esn.is_trained = true;
    esn.n_outputs = 1;

    S_before = esn.S;
    testCase.verifyError(@() esn.generateAutonomous(randn(10, 1), 3), ...
        'SRNN_ESN:DDEAutonomousUnsupported');
    testCase.verifyEqual(esn.S, S_before, 'AbsTol', 0);
end

function testUnsupportedHorizonRejected(testCase)
    esn = make_linear_autonomous_esn();
    init_data = 0.1 * ones(5, 1);
    testCase.verifyError(@() esn.generateAutonomous(init_data, 2, struct('horizon', 2)), ...
        'SRNN_ESN:UnsupportedAutonomousHorizon');
end

function testDimensionMismatchRejected(testCase)
    params = make_test_params(struct('n_inputs', 1));
    esn = SRNN_ESN(params);
    esn.W_out = ones(esn.n, 2);
    esn.b_out = [0; 0];
    esn.is_trained = true;
    esn.n_outputs = 2;

    testCase.verifyError(@() esn.generateAutonomous(randn(10, 1), 2), ...
        'SRNN_ESN:AutonomousDimensionMismatch');
end

function esn = make_linear_autonomous_esn()
    overrides = struct( ...
        'n', 1, ...
        'fraction_E', 1, ...
        'n_a_E', 0, ...
        'n_a_I', 0, ...
        'n_b_E', 0, ...
        'n_b_I', 0, ...
        'n_inputs', 1, ...
        'lags', [], ...
        'W', 0, ...
        'W_in', 1, ...
        'tau_d', 1, ...
        'dt', 0.5, ...
        'activation_function', @(x) x, ...
        'activation_function_derivative', @(x) ones(size(x)), ...
        'which_states', 'x', ...
        'state_rng_seed', 1729, ...
        'weight_rng_seed', 1729, ...
        'input_rng_seed', 1730);
    params = default_MESN_config(overrides);
    esn = SRNN_ESN(params);
    esn.W_out = 2;
    esn.b_out = 0;
    esn.is_trained = true;
    esn.n_outputs = 1;
end

function Y = manual_autonomous_reference(esn, init_data, n_steps, washout_steps)
    sim_opts = struct('reset_before', true, 'update_internal_state', true, ...
        'ode_reltol', 1e-8, 'ode_abstol', 1e-10);
    step_opts = struct('reset_before', false, 'update_internal_state', true, ...
        'ode_reltol', 1e-8, 'ode_abstol', 1e-10);

    U_washout = init_data(1:washout_steps, :);
    [X_washout, ~] = esn.runReservoir(U_washout, sim_opts);
    feedback = X_washout(end, :) * esn.W_out + esn.b_out';

    Y = zeros(n_steps, esn.n_outputs);
    for t = 1:n_steps
        [X_t, ~] = esn.runReservoir(feedback, step_opts);
        Y(t, :) = X_t * esn.W_out + esn.b_out';
        feedback = Y(t, :);
    end
end
