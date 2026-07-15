function tests = test_temporal_learning_gate_integration
% Real SRNN_ESN integration for the temporal learning gate (reduced smoke lengths).
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testRealSRNNTemporalGateSmokeSchema(testCase)
    cfg = mechanism_ablation_config('smoke');
    % Keep suite small: one model seed override on a copied gate config, then
    % restore multi-seed for schema checks via full smoke evaluation below.
    cfg.temporal_learning_gate.model_seeds = [1729, 2718, 31415];
    cfg.temporal_learning_gate.washout_steps = 30;
    cfg.temporal_learning_gate.train_samples = 160;
    cfg.temporal_learning_gate.validation_samples = 60;
    cfg.temporal_learning_gate.test_samples = 80;
    % Fingerprint uses gate fields; suite uses this reduced smoke-like cfg locally.
    cfg.protocol_fingerprint = compute_protocol_fingerprint(cfg);

    warn_near = warning('error', 'MATLAB:nearlySingularMatrix');
    warn_sing = warning('error', 'MATLAB:singularMatrix');
    cleanup = onCleanup(@() restore_warn(warn_near, warn_sing)); %#ok<NASGU>

    result = evaluate_temporal_learning_gate(cfg);

    testCase.verifyEqual(result.protocol_version, 'temporal_learning_gate_v1');
    testCase.verifyFalse(result.include_input);
    testCase.verifyEqual(result.feature_mode, 'r');
    testCase.verifyEqual(result.target_lag_steps, 10);
    testCase.verifyEqual(result.target_lag_time, 10 * cfg.base.dt, 'AbsTol', 0);
    testCase.verifyEqual(numel(result.seed_results), 3);
    testCase.verifyTrue(isfield(result, 'aggregate_results'));
    testCase.verifyTrue(isfield(result, 'gate_conditions'));
    testCase.verifyTrue(isfield(result, 'thresholds'));

    for i = 1:numel(result.seed_results)
        sr = result.seed_results(i);
        testCase.verifyEqual(sr.status, 'ok');
        testCase.verifyEqual(sr.include_input, false);
        testCase.verifyEqual(sr.feature_dimension, cfg.base.n);
        testCase.verifyTrue(isfield(sr.mesn, 'ridge'));
        testCase.verifyTrue(isfield(sr.mesn.ridge, 'solver_method'));
        testCase.verifyTrue(isfinite(sr.mesn.selected_lambda));
        testCase.verifyTrue(isfinite(sr.mesn.metrics.nrmse));
        testCase.verifyTrue(isfinite(sr.current_input_only_control.metrics.nrmse));
        testCase.verifyTrue(isfinite(sr.no_recurrent_coupling_control.metrics.nrmse));
        testCase.verifyTrue(isfinite(sr.shuffled_target_control.metrics.nrmse));
        testCase.verifyTrue(isfinite(sr.exact_history_control.metrics.nrmse));
        testCase.verifyLessThan(sr.exact_history_control.metrics.nrmse, 1e-6);
        testCase.verifyTrue(isfield(sr.mesn, 'lambda_selection_table'));
        testCase.verifyTrue(isfield(sr.mesn, 'selected_at_grid_boundary'));
        % Negative controls should not crush NRMSE like exact history
        testCase.verifyGreaterThan(sr.current_input_only_control.metrics.nrmse, 0.5);
        testCase.verifyGreaterThan(sr.shuffled_target_control.metrics.nrmse, 0.5);
        testCase.verifyEqual(sr.W_nr_norm, 0, 'AbsTol', 0);
    end

    % Determinism: identical cfg yields identical lambdas/metrics
    result2 = evaluate_temporal_learning_gate(cfg);
    for i = 1:numel(result.seed_results)
        testCase.verifyEqual(result.seed_results(i).mesn.selected_lambda, ...
            result2.seed_results(i).mesn.selected_lambda);
        testCase.verifyEqual(result.seed_results(i).mesn.metrics.nrmse, ...
            result2.seed_results(i).mesn.metrics.nrmse, 'AbsTol', 0, 'RelTol', 0);
    end

    fprintf(['temporal_gate smoke-like: passed=%d mesn_med_nrmse=%.4f ', ...
        'current_med=%.4f nr_med=%.4f shuf_med=%.4f hist_med=%.3e\n'], ...
        result.passed, ...
        result.aggregate_results.mesn_nrmse.median, ...
        result.aggregate_results.current_input_only_control_nrmse.median, ...
        result.aggregate_results.no_recurrent_coupling_control_nrmse.median, ...
        result.aggregate_results.shuffled_target_control_nrmse.median, ...
        result.aggregate_results.exact_history_control_nrmse.median);
end

function testNoRecurrenceRebuildsDelayedComponents(testCase)
    cfg = mechanism_ablation_config('smoke');
    cell_spec = cfg.temporal_learning_gate.reference_cell;
    [params, ~] = build_ablation_params(cell_spec, 1729, cfg);
    params.include_input = false;
    params_nr = params;
    params_nr.W = zeros(size(params.W));
    esn = SRNN_ESN(params);
    esn_nr = SRNN_ESN(params_nr);
    testCase.verifyEqual(norm(esn_nr.W, 'fro'), 0, 'AbsTol', 0);
    testCase.verifyEqual(esn_nr.W_in, esn.W_in);
    if ~isempty(esn_nr.W_components)
        for c = 1:numel(esn_nr.W_components)
            testCase.verifyEqual(norm(esn_nr.W_components{c}, 'fro'), 0, 'AbsTol', 0);
        end
    end
    testCase.verifyFalse(isempty(esn.lags));  % delay-on reference cell
end

function restore_warn(a, b)
    warning(a);
    warning(b);
end
