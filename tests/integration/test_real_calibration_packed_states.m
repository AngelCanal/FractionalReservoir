function tests = test_real_calibration_packed_states
%TEST_REAL_CALIBRATION_PACKED_STATES  Real SRNN packed-state integration checks.
%
% Synthetic/diagnostic short trajectories only. Does not create authorizing artifacts.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testAdaptOffStdOffOdePackedState(testCase)
    run_packed_state_case(testCase, ...
        'adapt-off__std-off__delay-ode_off__feat-x', false);
end

function testThreeTimescaleSfaStdOnOdePackedState(testCase)
    run_packed_state_case(testCase, ...
        'adapt-three_timescales__std-on__delay-ode_off__feat-x', true);
end

function testThreeTimescaleSfaStdOnDdePackedState(testCase)
    run_packed_state_case(testCase, ...
        'adapt-three_timescales__std-on__delay-dde_on__feat-x', true);
end

function testProbeUsesNeuronCountNotPackedWidth(testCase)
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    [probe_keys, probe_cells] = build_operating_point_calibration_probe_keys(cfg);
    cell_key = 'adapt-three_timescales__std-on__delay-ode_off__feat-x';
    idx = find(strcmp(probe_keys, cell_key), 1);
    cell_spec = probe_cells{idx};
    op = diagnostic_operating_point(cfg.operating_point);
    seed = op.calibration_seeds(1);
    ov = struct('input_scaling', op.candidate_order{1}.input_scaling, ...
        'level_of_chaos', op.candidate_order{1}.level_of_chaos);
    [params, ~] = build_ablation_params(cell_spec, seed, cfg, ov);
    esn = SRNN_ESN(params);
    U = diagnostic_calibration_input(cfg, op, seed);
    diag = probe_operating_point_activity(esn, U, op);
    testCase.verifyEqual(diag.n_neurons, 40);
    testCase.verifyEqual(diag.n_eval_time_points, op.evaluation_steps);
    testCase.verifyEqual(diag.n_rate_observations, diag.n_eval_time_points * diag.n_neurons);
    testCase.verifyGreaterThan(diag.packed_state_dimension, 40);
end
