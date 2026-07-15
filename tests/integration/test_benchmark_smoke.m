function tests = test_benchmark_smoke
% test_benchmark_smoke  Reduced-length smoke tests for standardized benchmarks.
% Checks execution, return shape, and finite metrics — not scientific quality.
tests = functiontests(localfunctions);
end

function params = smoke_params()
    params = make_test_params(struct( ...
        'n', 8, ...
        'fraction_E', 0.5, ...
        'n_a_E', 1, ...
        'n_a_I', 0, ...
        'n_b_E', 0, ...
        'n_b_I', 0, ...
        'lags', [], ...
        'level_of_chaos', 0.9));
end

function opts = smoke_split_opts(extra)
    bb = build_matched_task_baselines_config(struct('base', struct('n', 8)));
    bb.conventional_leaky_esn.spectral_radius_candidates = 0.9;
    bb.conventional_leaky_esn.leak_rate_candidates = 1.0;
    bb.conventional_leaky_esn.input_scaling_candidates = 0.5;
    opts = struct( ...
        'train_ratio', 0.5, ...
        'val_ratio', 0.25, ...
        'washout_steps', 10, ...
        'seed', 1729, ...
        'base_seed', 1700, ...
        'lambda_grid', [0, 1e-4, 1e-2], ...
        'benchmark_baselines', bb);
    if nargin >= 1 && ~isempty(extra)
        f = fieldnames(extra);
        for i = 1:numel(f)
            opts.(f{i}) = extra.(f{i});
        end
    end
end

function assert_common_fields(testCase, bench)
    required = {'configuration', 'split', 'selected_lambda', 'metrics', ...
        'predictions', 'targets', 'baselines', 'seed', 'status', 'prediction_mode'};
    for i = 1:numel(required)
        testCase.verifyTrue(isfield(bench, required{i}), ...
            sprintf('missing field %s', required{i}));
    end
    testCase.verifyEqual(bench.status, 'ok');
    testCase.verifyEqual(bench.prediction_mode, 'reset_with_context');
    testCase.verifyTrue(isfinite(bench.selected_lambda) || bench.selected_lambda == 0);
    testCase.verifyGreaterThan(bench.split.n_train_after_washout, 0);
    testCase.verifyGreaterThan(bench.split.n_val, 0);
    testCase.verifyGreaterThan(bench.split.n_test, 0);
    testCase.verifyEqual(bench.split.n_train_after_washout, ...
        numel(bench.split.train_idx) - bench.split.washout_steps);
end

function testNarmaSmoke(testCase)
    esn = SRNN_ESN(smoke_params());
    bench = narma_benchmark(esn, smoke_split_opts(struct('order', 10, 'T', 120)));
    assert_common_fields(testCase, bench);
    testCase.verifyTrue(isfinite(bench.metrics_test.nrmse));
    testCase.verifyTrue(isfinite(bench.metrics_val.nrmse));
    testCase.verifyTrue(isfinite(bench.metrics_train.nrmse));
    testCase.verifyEqual(size(bench.predictions.test, 1), bench.split.n_test);
    testCase.verifyTrue(isfield(bench.baselines, 'target_mean'));
    testCase.verifyTrue(isfield(bench.baselines, 'linear_input_ar'));
    testCase.verifyTrue(isfield(bench.baselines, 'conventional_leaky_esn'));
    testCase.verifyTrue(isfield(bench.baselines, 'dale_mesn_control'));
    testCase.verifyTrue(isfinite(bench.baselines.target_mean.metrics_test.nrmse));
    testCase.verifyTrue(isfinite(bench.baselines.linear_input_ar.metrics_test.nrmse));
    testCase.verifyEqual(bench.baselines.conventional_leaky_esn.status, 'computed');
end

function testMackeyGlassSmoke(testCase)
    esn = SRNN_ESN(smoke_params());
    bench = mackey_glass_benchmark(esn, smoke_split_opts(struct( ...
        'T', 150, 'discard', 50, 'do_rollout', true, 'rollout_steps', 20)));
    assert_common_fields(testCase, bench);
    testCase.verifyTrue(isfinite(bench.metrics_test.nrmse));
    testCase.verifyTrue(isfield(bench.baselines, 'persistence'));
    testCase.verifyTrue(isfield(bench.baselines, 'linear_ar'));
    testCase.verifyTrue(isfield(bench.baselines, 'conventional_leaky_esn'));
    testCase.verifyTrue(isfinite(bench.baselines.persistence.metrics_test.nrmse));
    testCase.verifyEqual(bench.baselines.conventional_leaky_esn.status, 'computed');
    testCase.verifyTrue(isfield(bench, 'rollout'));
    testCase.verifyTrue(ismember(bench.rollout.status, {'computed', 'skipped'}));
    testCase.verifyEqual(bench.rollout.prediction_mode, 'ode_autonomous');
    if strcmp(bench.rollout.status, 'computed')
        testCase.verifyTrue(isfinite(bench.rollout.metrics.nrmse));
    end
end

function testLorenzSmoke(testCase)
    esn = SRNN_ESN(smoke_params());
    bench = lorenz_benchmark(esn, smoke_split_opts(struct( ...
        'T', 200, 'discard', 50, 'do_rollout', false)));
    assert_common_fields(testCase, bench);
    testCase.verifyTrue(isfinite(bench.metrics_test.nrmse));
    testCase.verifyTrue(isfield(bench.baselines, 'persistence'));
    testCase.verifyTrue(isfield(bench.baselines, 'linear_ar'));
    testCase.verifyTrue(isfinite(bench.baselines.linear_ar.metrics_test.nrmse));
end

function testFrequencyDiscriminationSmoke(testCase)
    esn = SRNN_ESN(smoke_params());
    bench = frequency_discrimination_benchmark(esn, smoke_split_opts(struct( ...
        'T', 240, 'min_seg', 20, 'max_seg', 40, ...
        'freq_set', [0.05 0.2], 'summary_window', 10)));
    assert_common_fields(testCase, bench);
    testCase.verifyTrue(isfinite(bench.metrics_test.accuracy));
    testCase.verifyGreaterThanOrEqual(bench.metrics_test.accuracy, 0);
    testCase.verifyLessThanOrEqual(bench.metrics_test.accuracy, 1);
    testCase.verifyTrue(isfield(bench.baselines, 'majority_class'));
    testCase.verifyTrue(isfield(bench.baselines, 'linear_classifier'));
    testCase.verifyTrue(isfinite(bench.baselines.majority_class.metrics_test.accuracy));
    testCase.verifyTrue(isfinite(bench.baselines.linear_classifier.metrics_test.accuracy));
    testCase.verifyEqual(numel(bench.predictions.test), bench.split.n_test);
end

function testStimulusCountingSmoke(testCase)
    esn = SRNN_ESN(smoke_params());
    bench = stimulus_counting_benchmark(esn, smoke_split_opts(struct( ...
        'T', 200, 'min_isi', 8, 'max_isi', 20, 'pulse_width', 2, ...
        'summary_window', 10)));
    assert_common_fields(testCase, bench);
    testCase.verifyTrue(isfinite(bench.metrics_test.accuracy));
    testCase.verifyGreaterThanOrEqual(bench.metrics_test.accuracy, 0);
    testCase.verifyLessThanOrEqual(bench.metrics_test.accuracy, 1);
    testCase.verifyTrue(isfield(bench.baselines, 'majority_class'));
    testCase.verifyTrue(isfield(bench.baselines, 'linear_classifier'));
    testCase.verifyTrue(isfinite(bench.baselines.linear_classifier.metrics_test.accuracy));
    testCase.verifyEqual(numel(bench.targets.test), bench.split.n_test);
end
