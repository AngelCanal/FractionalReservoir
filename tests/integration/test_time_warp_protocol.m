function tests = test_time_warp_protocol
tests = functiontests(localfunctions);
end

function testChangingTestTargetDoesNotAlterModel(testCase)
    params = make_test_params(struct( ...
        'n', 8, 'n_a_E', 1, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0, ...
        'lags', [], 'level_of_chaos', 0.8, 'dt', 0.1));
    opts = base_opts();
    opts.test_warps = [1.0, 1.5];
    esn = SRNN_ESN(params);
    warp = evaluate_time_warp_generalization(esn, opts);
    W1 = warp.readout_snapshot.W_out;
    b1 = warp.readout_snapshot.b_out;

    % Re-run with different test seed (different test target/input)
    opts.seed_test = opts.seed_test + 17;
    esn2 = SRNN_ESN(params);
    warp2 = evaluate_time_warp_generalization(esn2, opts);
    % Same train seed => identical trained model
    testCase.verifyEqual(warp2.readout_snapshot.W_out, W1, 'AbsTol', 1e-12);
    testCase.verifyEqual(warp2.readout_snapshot.b_out, b1, 'AbsTol', 1e-12);
end

function testTrainTestInputsDisjoint(testCase)
    params = make_test_params(struct( ...
        'n', 6, 'n_a_E', 0, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0, ...
        'lags', [], 'dt', 0.1));
    opts = base_opts();
    opts.test_warps = 1.0;
    warp = evaluate_time_warp_generalization(params, opts);
    testCase.verifyNotEqual(warp.protocol.u_train_hash, warp.protocol.u_test_hash);
    testCase.verifyNotEqual(warp.protocol.seed_train, warp.protocol.seed_test);
end

function testWarpLabelsMatchTimeAxes(testCase)
    params = make_test_params(struct( ...
        'n', 6, 'n_a_E', 0, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0, ...
        'lags', [], 'dt', 0.1));
    opts = base_opts();
    opts.T_base = 200;
    opts.test_warps = [0.5, 1.0, 2.0];
    opts.washout_steps = 20;
    opts.context_len = 10;
    warp = evaluate_time_warp_generalization(params, opts);
    for i = 1:numel(warp.results)
        w = warp.results(i).warp;
        t_axis = warp.results(i).time_axis;
        expected_len = numel(1:(1/w):opts.T_base);
        testCase.verifyEqual(numel(t_axis), expected_len);
        testCase.verifyEqual(t_axis(1), 1, 'AbsTol', 1e-12);
        if numel(t_axis) > 1
            testCase.verifyEqual(t_axis(2) - t_axis(1), 1/w, 'AbsTol', 1e-12);
        end
    end
    testCase.verifyEqual(warp.protocol.warp_definition, 'resample_fixed_waveform');
end

function testLeakedProtocolCaught(testCase)
    params = make_test_params(struct( ...
        'n', 4, 'n_a_E', 0, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0, 'lags', []));
    opts = base_opts();
    opts.force_same_sequence_fit_and_score = true;
    testCase.verifyError(@() evaluate_time_warp_generalization(params, opts), ...
        'evaluate_time_warp_generalization:LeakedProtocol');
end

function testSeedCollisionCaught(testCase)
    params = make_test_params(struct( ...
        'n', 4, 'n_a_E', 0, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0, 'lags', []));
    opts = base_opts();
    opts.seed_test = opts.seed_train;
    testCase.verifyError(@() evaluate_time_warp_generalization(params, opts), ...
        'evaluate_time_warp_generalization:SeedCollision');
end

function testTimeWarpNoSingularMatrixWarnings(testCase)
    % Phase 4A regression: promote singular-matrix warnings to errors.
    warn_near = warning('error', 'MATLAB:nearlySingularMatrix');
    warn_sing = warning('error', 'MATLAB:singularMatrix');
    cleanup = onCleanup(@() restore_warn_states(warn_near, warn_sing)); %#ok<NASGU>

    params = make_test_params(struct( ...
        'n', 8, 'n_a_E', 1, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0, ...
        'lags', [], 'level_of_chaos', 0.8, 'dt', 0.1));
    opts = base_opts();
    opts.test_warps = [1.0, 1.5];
    esn = SRNN_ESN(params);
    warp = evaluate_time_warp_generalization(esn, opts);
    testCase.verifyTrue(isstruct(warp.readout_snapshot));
    testCase.verifyTrue(isfinite(esn.readout_model.coefficient_norm));
end

function restore_warn_states(warn_near, warn_sing)
    warning(warn_near);
    warning(warn_sing);
end

function opts = base_opts()
    opts = struct( ...
        'T_base', 400, ...
        'seed_train', 11, ...
        'seed_val', 22, ...
        'seed_test', 33, ...
        'train_warps', 1.0, ...
        'val_warps', 1.0, ...
        'test_warps', [0.75, 1.0, 1.25], ...
        'washout_steps', 40, ...
        'context_len', 20, ...
        'train_ratio', 0.6, ...
        'val_ratio', 0.2, ...
        'include_esn_baseline', true);
end
