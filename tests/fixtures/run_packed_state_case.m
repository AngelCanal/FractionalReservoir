function run_packed_state_case(testCase, cell_key, expect_packed_gt_40)
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    [probe_keys, probe_cells] = build_operating_point_calibration_probe_keys(cfg);
    idx = find(strcmp(probe_keys, cell_key), 1);
    testCase.verifyNotEmpty(idx, sprintf('Missing probe key %s', cell_key));
    cell_spec = probe_cells{idx};
    op = diagnostic_operating_point(cfg.operating_point);
    seed = op.calibration_seeds(1);
    ov = struct('input_scaling', op.candidate_order{1}.input_scaling, ...
        'level_of_chaos', op.candidate_order{1}.level_of_chaos);
    [params, ~] = build_ablation_params(cell_spec, seed, cfg, ov);
    esn = SRNN_ESN(params);
    U = diagnostic_calibration_input(cfg, op, seed);

    run_opts = struct( ...
        'reset_before', true, ...
        'update_internal_state', false, ...
        'ode_reltol', op.ode_reltol, ...
        'ode_abstol', op.ode_abstol, ...
        'dde_reltol', op.dde_reltol, ...
        'dde_abstol', op.dde_abstol);
    [~, S_hist] = esn.runReservoir(U, run_opts);

    packed_dim = size(S_hist, 2);
    n_neurons = size(esn.W, 1);
    testCase.verifyEqual(n_neurons, op.network_size);
    testCase.verifyEqual(n_neurons, 40);

    eval_idx = (op.washout_steps + 1):op.total_steps;
    n_eval = numel(eval_idx);
    rates_correct = zeros(n_neurons, n_eval);
    for k = 1:n_eval
        r = esn.computeRates(S_hist(eval_idx(k), :)');
        testCase.verifyEqual(numel(r), 40);
        rates_correct(:, k) = r;
    end

    if expect_packed_gt_40
        testCase.verifyGreaterThan(packed_dim, 40);
        wrong_n = packed_dim;
        testCase.verifyNotEqual(wrong_n, n_neurons);
        rates_wrong = zeros(wrong_n, n_eval);
        testCase.verifySize(rates_wrong, [wrong_n, n_eval]);
    else
        testCase.verifyEqual(packed_dim, 40);
    end
    testCase.verifySize(rates_correct, [n_neurons, n_eval]);
    testCase.verifyEqual(numel(rates_correct), n_neurons * n_eval);
end
