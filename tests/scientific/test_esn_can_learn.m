function tests = test_esn_can_learn
tests = functiontests(localfunctions);
end

function testSyntheticLearningGateG5(testCase)
    % Gate G5: real-target test NRMSE < 0.5 and at least 0.4 lower than shuffled.
    seeds = [1729, 2718, 31415];
    for s = 1:numel(seeds)
        [nrmse_real, nrmse_shuf] = run_one_seed(seeds(s));
        fprintf('seed %d: real=%.4f shuf=%.4f gap=%.4f\n', ...
            seeds(s), nrmse_real, nrmse_shuf, nrmse_shuf - nrmse_real);
        testCase.verifyLessThan(nrmse_real, 0.5, ...
            sprintf('seed %d real NRMSE=%.3f', seeds(s), nrmse_real));
        testCase.verifyGreaterThanOrEqual(nrmse_shuf - nrmse_real, 0.4, ...
            sprintf('seed %d gap=%.3f (real=%.3f shuf=%.3f)', ...
            seeds(s), nrmse_shuf - nrmse_real, nrmse_real, nrmse_shuf));
    end
end

function [nrmse_real, nrmse_shuf] = run_one_seed(seed)
    rng(seed);
    params = make_linear_activation_params(struct( ...
        'n', 8, ...
        'fraction_E', 0.5, ...
        'n_a_E', 0, ...
        'n_a_I', 0, ...
        'n_b_E', 0, ...
        'n_b_I', 0, ...
        'lags', [], ...
        'dale', false, ...
        'weight_rng_seed', seed, ...
        'input_rng_seed', seed + 1, ...
        'level_of_chaos', 0.5));
    params = validate_MESN_params(params);

    esn = SRNN_ESN(params);
    esn.which_states = 'x';
    esn.include_input = true;  % exposes lag-0 input in the feature horizon

    T = 400;
    U = randn(T, 1);
    % Linear mix of recent lags within demonstrated horizon (lag 0 via include_input,
    % plus a small lag-1 component carried by leaky reservoir state).
    Y = 0.85 * U + 0.15 * [0; U(1:end-1)];

    opts = struct('train_ratio', 0.5, 'val_ratio', 0.25, 'washout_steps', 20, ...
        'lambda_grid', [0, 1e-6, 1e-4, 1e-2], ...
        'ode_reltol', 1e-4, 'ode_abstol', 1e-6);
    metrics = esn.trainReadout(U, Y, opts);

    test_idx = metrics.test_idx;
    context_len = min(40, test_idx(1) - 1);
    context_U = U(test_idx(1)-context_len:test_idx(1)-1, :);
    U_test = U(test_idx, :);
    Y_test = Y(test_idx, :);
    Y_pred = esn.predict(U_test, struct('context_U', context_U, ...
        'reset_before', true, 'ode_reltol', 1e-4, 'ode_abstol', 1e-6));
    nrmse_real = sqrt(mean((Y_pred - Y_test).^2)) / max(std(Y_test), eps);

    rng(seed + 99);
    Y_shuf = Y(randperm(T));
    esn2 = SRNN_ESN(params);
    esn2.which_states = 'x';
    esn2.include_input = true;
    esn2.trainReadout(U, Y_shuf, opts);
    Y_test_shuf = Y_shuf(test_idx);
    Y_pred_shuf = esn2.predict(U_test, struct('context_U', context_U, ...
        'reset_before', true, 'ode_reltol', 1e-4, 'ode_abstol', 1e-6));
    nrmse_shuf = sqrt(mean((Y_pred_shuf - Y_test_shuf).^2)) / max(std(Y_test_shuf), eps);
end
