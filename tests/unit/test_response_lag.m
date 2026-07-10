function tests = test_response_lag
tests = functiontests(localfunctions);
end

function testDelayedCopyPeaksAtNegativeLag(testCase)
    T = 500;
    delay = 7;
    u = randn(T, 1);
    X = [zeros(delay, 1); u(1:end-delay)];
    rl = compute_response_lag(X, u, struct('max_lag', 20, 'max_neurons', 1, 'seed', 1));
    testCase.verifyEqual(rl.peak_lag_samples, -delay);
    testCase.verifyEqual(rl.peak_lag_time, -delay); % dt default 1
end

function testLeadingCopyPeaksAtPositiveLag(testCase)
    T = 500;
    lead = 5;
    u = randn(T, 1);
    X = [u((lead+1):end); zeros(lead, 1)];
    rl = compute_response_lag(X, u, struct('max_lag', 20, 'max_neurons', 1, 'seed', 1));
    testCase.verifyEqual(rl.peak_lag_samples, lead);
end

function testZeroLagCopyPeaksAtZero(testCase)
    T = 400;
    u = randn(T, 1);
    X = u;
    rl = compute_response_lag(X, u, struct('max_lag', 15, 'max_neurons', 1, 'seed', 1, 'dt', 0.1));
    testCase.verifyEqual(rl.peak_lag_samples, 0);
    testCase.verifyEqual(rl.peak_lag_time, 0);
end

function testWrapperMatchesResponseLagAndWarns(testCase)
    T = 300;
    u = randn(T, 1);
    X = [zeros(3, 1); u(1:end-3)];
    opts = struct('max_lag', 12, 'max_neurons', 1, 'seed', 2, 'dt', 0.25);

    rl = compute_response_lag(X, u, opts);
    testCase.verifyWarning(@() compute_phase_advance(X, u, opts), ...
        'MESN:DeprecatedPhaseAdvance');
    % Re-call with warning off to compare values
    warn_state = warning('off', 'MESN:DeprecatedPhaseAdvance');
    cleanup = onCleanup(@() warning(warn_state));
    pa = compute_phase_advance(X, u, opts);

    testCase.verifyEqual(pa.lags, rl.lags);
    testCase.verifyEqual(pa.peak_lag_samples, rl.peak_lag_samples);
    testCase.verifyEqual(pa.peak_lag_time, rl.peak_lag_time);
    testCase.verifyEqual(pa.correlation_by_lag, rl.correlation_by_lag);
    testCase.verifyEqual(pa.peak_lag_per_unit, rl.peak_lag_samples);
    testCase.verifyEqual(pa.mean_peak_lag, rl.mean_peak_lag_samples);
end
