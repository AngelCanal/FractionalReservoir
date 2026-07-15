function tests = test_autonomous_generation
tests = functiontests(localfunctions);
end

function testTwoStepMatchesManualReference(testCase)
    esn = make_linear_autonomous_esn();
    init_data = 0.15 * ones(8, 1);
    n_steps = 2;

    Y_gen = esn.generateAutonomous(init_data, n_steps, struct( ...
        'washout_steps', 8, 'ode_reltol', 1e-8, 'ode_abstol', 1e-10));
    Y_manual = manual_autonomous_reference(esn, init_data, n_steps);

    testCase.verifyEqual(Y_gen, Y_manual, 'RelTol', 1e-6, 'AbsTol', 1e-8);
    testCase.verifyGreaterThan(abs(Y_gen(2) - Y_gen(1)), 1e-6);
end

function testFirstStepEqualsOriginReadout(testCase)
    esn = make_linear_autonomous_esn();
    init_data = 0.15 * ones(8, 1);
    opts = struct('ode_reltol', 1e-8, 'ode_abstol', 1e-10);
    [~, S_hist] = esn.runReservoir(init_data, struct( ...
        'reset_before', true, 'update_internal_state', false, ...
        'ode_reltol', 1e-8, 'ode_abstol', 1e-10));
    X0 = esn.extractFeatures(S_hist(end, :), init_data(end, :));
    y0 = apply_ridge_readout(esn.readout_model, X0);
    Y_gen = esn.generateAutonomous(init_data, 3, opts);
    testCase.verifyEqual(Y_gen(1), y0, 'AbsTol', 1e-10);
end

function testChangingFirstPredictionChangesLaterOutput(testCase)
    esn = make_linear_autonomous_esn();
    init_data = 0.15 * ones(8, 1);
    opts = struct('washout_steps', 8, 'ode_reltol', 1e-8, 'ode_abstol', 1e-10);

    esn.readout_model.coefficients = 1.0;
    esn.W_out = 1.0;
    Y_a = esn.generateAutonomous(init_data, 2, opts);

    esn.readout_model.coefficients = 1.4;
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

function testContextTruncationRejected(testCase)
    esn = make_linear_autonomous_esn();
    init_data = 0.1 * ones(8, 1);
    testCase.verifyError(@() esn.generateAutonomous(init_data, 2, struct( ...
        'washout_steps', 4)), 'SRNN_ESN:AutonomousContextTruncationRejected');
end

function testObjectStateUnchanged(testCase)
    esn = make_linear_autonomous_esn();
    S_before = esn.S;
    init_data = 0.12 * ones(6, 1);
    esn.generateAutonomous(init_data, 4, struct('ode_reltol', 1e-8, 'ode_abstol', 1e-10));
    testCase.verifyEqual(esn.S, S_before, 'AbsTol', 0);
    [~, S_hist] = esn.runReservoir(init_data, struct( ...
        'reset_before', true, 'update_internal_state', false));
    esn.generateAutonomousFromState(S_hist(end, :).', init_data(end, :), 3, ...
        struct('ode_reltol', 1e-8, 'ode_abstol', 1e-10));
    testCase.verifyEqual(esn.S, S_before, 'AbsTol', 0);
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
    % Identity-scaled ridge model equivalent to Y = 2*X + 0
    model = struct();
    model.intercept = 0;
    model.coefficients = 2;
    model.mu = 0;
    model.sigma = 1;
    model.lambda = 0;
    model.n_features = 1;
    model.n_outputs = 1;
    model.constant_feature = false;
    esn.readout_model = model;
    esn.W_out = 2;
    esn.b_out = 0;
    esn.is_trained = true;
    esn.n_outputs = 1;
end

function Y = manual_autonomous_reference(esn, init_data, n_steps)
    % Corrected recurrence: step 1 from origin state; feedback from step 2.
    sim_opts = struct('reset_before', true, 'update_internal_state', false, ...
        'ode_reltol', 1e-8, 'ode_abstol', 1e-10);
    [~, S_hist] = esn.runReservoir(init_data, sim_opts);
    S = S_hist(end, :).';
    X0 = esn.extractFeatures(S.', init_data(end, :));
    Y = zeros(n_steps, esn.n_outputs);
    Y(1, :) = apply_ridge_readout(esn.readout_model, X0);
    step_opts = struct('reset_before', false, 'update_internal_state', false, ...
        'ode_reltol', 1e-8, 'ode_abstol', 1e-10);
    for t = 2:n_steps
        step_opts.initial_state = S;
        [X_t, S_hist_t] = esn.runReservoir(Y(t-1, :), step_opts);
        S = S_hist_t(end, :).';
        Y(t, :) = apply_ridge_readout(esn.readout_model, X_t);
    end
end
