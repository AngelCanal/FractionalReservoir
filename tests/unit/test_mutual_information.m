function tests = test_mutual_information
tests = functiontests(localfunctions);
end

function testIndependentVariablesNearZero(testCase)
    rng(1);
    n = 4000;
    x = randn(n, 1);
    y = randn(n, 1);
    mi = mutual_info_SISO(x, y, struct( ...
        'n_bins_in', 8, 'n_bins_out', 8, 'n_null', 30, 'seed', 11, ...
        'min_expected_occupancy', 1));
    testCase.verifyEqual(mi.status, 'ok');
    testCase.verifyLessThan(mi.corrected, 0.05);
    testCase.verifyGreaterThanOrEqual(mi.corrected, 0);
end

function testIdenticalVariablesHighMI(testCase)
    rng(2);
    n = 4000;
    x = randn(n, 1);
    mi = mutual_info_SISO(x, x, struct( ...
        'n_bins_in', 8, 'n_bins_out', 8, 'n_null', 20, 'seed', 22, ...
        'min_expected_occupancy', 1));
    testCase.verifyEqual(mi.status, 'ok');
    testCase.verifyGreaterThan(mi.raw, 1.5);
    testCase.verifyGreaterThan(mi.corrected, 1.0);
    testCase.verifyGreaterThan(mi.corrected, mi.null_mean);
end

function testMonotonicNoisyRelationshipPositive(testCase)
    rng(3);
    n = 5000;
    x = randn(n, 1);
    y = 0.9 * x + 0.1 * randn(n, 1);
    mi = mutual_info_SISO(x, y, struct( ...
        'n_bins_in', 10, 'n_bins_out', 10, 'n_null', 25, 'seed', 33, ...
        'min_expected_occupancy', 1));
    testCase.verifyEqual(mi.status, 'ok');
    testCase.verifyGreaterThan(mi.corrected, 0.2);
    testCase.verifyGreaterThan(mi.raw, mi.null_mean);
end

function testLagAlignmentPeaksAtTrueDelay(testCase)
    rng(4);
    T = 3000;
    delay = 5;
    u = randn(T, 1);
    x = [zeros(delay, 1); u(1:end-delay)] + 0.05 * randn(T, 1);
    mi = compute_MI_lag_curve(x, u, struct( ...
        'K_max', 15, 'washout', 50, 'n_bins_u', 8, 'n_bins_x', 8, ...
        'max_neurons', 1, 'seed', 44, 'n_null', 15, 'min_expected_occupancy', 1));
    [~, k_peak] = max(mi.MI_corrected_mean);
    testCase.verifyEqual(mi.lags(k_peak), delay);
    testCase.verifyGreaterThan(mi.MI_corrected_mean(delay), ...
        mean(mi.MI_corrected_mean([1:delay-1, delay+1:end])));
end

function testTrainEdgesReusedOnEval(testCase)
    rng(5);
    n = 2000;
    x = randn(n, 1);
    y = x + 0.2 * randn(n, 1);
    n_train = 1000;
    opts = struct( ...
        'n_bins_in', 8, 'n_bins_out', 8, 'n_null', 10, 'seed', 55, ...
        'x_train', x(1:n_train), 'y_train', y(1:n_train), ...
        'min_expected_occupancy', 1);
    mi = mutual_info_SISO(x(n_train+1:end), y(n_train+1:end), opts);
    testCase.verifyEqual(numel(mi.edges_in), 9);
    testCase.verifyEqual(mi.n_train, n_train);
    testCase.verifyEqual(mi.n_eval, n - n_train);
    % Edges must come from training range, not eval-only extremes
    testCase.verifyEqual(mi.edges_in(1), min(x(1:n_train)), 'AbsTol', 1e-12);
    testCase.verifyEqual(mi.edges_in(end), max(x(1:n_train)), 'AbsTol', 1e-12);
end

function testOccupancyFieldsPresent(testCase)
    rng(6);
    x = randn(800, 1);
    y = randn(800, 1);
    mi = mutual_info_SISO(x, y, struct( ...
        'n_bins_in', 20, 'n_bins_out', 20, 'n_null', 5, 'seed', 66, ...
        'min_expected_occupancy', 50));
    testCase.verifyTrue(isfield(mi, 'occupied_bins_in'));
    testCase.verifyTrue(isfield(mi, 'occupied_joint'));
    testCase.verifyTrue(mi.low_occupancy_warning);
    testCase.verifyEqual(mi.bin_rule, 'equal_width_linspace_train_edges');
    testCase.verifyEqual(mi.estimator, 'histogram_plugin');
end
