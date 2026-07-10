function tests = test_memory_capacity_alignment
tests = functiontests(localfunctions);
end

function testDelayLinePeaksAtExactLag(testCase)
    % Synthetic delay-line: feature column k holds u(t-k) exactly.
    rng(1729);
    T = 800;
    K = 5;
    washout = 0;
    lags = (1:K)';

    [inject, opts] = make_delay_line_inject(T, K, lags, washout);
    mc = compute_memory_capacity(inject, opts);

    % Exact delay-line columns: capacity near one at every represented lag
    testCase.verifyGreaterThan(min(mc.MC_spectrum), 0.9);
    testCase.verifyGreaterThan(mc.MC_spectrum(mc.lags == 3), 0.95);
end

function testOffByOneWouldFailExactDelay(testCase)
    % Single exact delay of 3 samples: capacity peaks only at lag 3.
    % An off-by-one aligner (u(t-(k+/-1))) would miss this peak.
    rng(1729);
    T = 800;
    lags = (1:5)';
    inject = struct();
    seeds = [21, 22, 23];
    splits = {'train', 'val', 'test'};
    for si = 1:3
        rng(seeds(si));
        u = 2 * rand(T, 1) - 1;
        X = randn(T, 1) * 0.01; % distractor noise feature
        X((3+1):end, 1) = u(1:(end-3));
        inject.(['u_' splits{si}]) = u;
        inject.(['X_' splits{si}]) = X;
    end
    opts = struct( ...
        'lags', lags, ...
        'washout', 0, ...
        'minimum_scored_rows', 40, ...
        'T_train', T, 'T_val', T, 'T_test', T, ...
        'lambda_grid', [0, 1e-6]);
    mc = compute_memory_capacity(inject, opts);
    testCase.verifyGreaterThan(mc.MC_spectrum(lags == 3), 0.9);
    testCase.verifyLessThan(max(mc.MC_spectrum(lags ~= 3)), 0.25);
end

function testUnrelatedFeaturesCorrectedNearZero(testCase)
    rng(99);
    T = 600;
    lags = (1:8)';
    n_feat = 6;
    inject = struct();
    for split = {'train', 'val', 'test'}
        u = 2 * rand(T, 1) - 1;
        X = randn(T, n_feat);
        inject.(['u_' split{1}]) = u;
        inject.(['X_' split{1}]) = X;
    end
    opts = struct( ...
        'lags', lags, ...
        'washout', 0, ...
        'minimum_scored_rows', 40, ...
        'T_train', T, 'T_val', T, 'T_test', T, ...
        'lambda_grid', [0, 1e-4, 1e-2]);
    mc = compute_memory_capacity(inject, opts);
    testCase.verifyLessThan(mc.MC_total, 0.5);
end

function testRequiresPositiveIntegerLags(testCase)
    inject = struct('X_train', randn(100, 2), 'u_train', randn(100, 1), ...
        'X_val', randn(100, 2), 'u_val', randn(100, 1), ...
        'X_test', randn(100, 2), 'u_test', randn(100, 1));
    testCase.verifyError(@() compute_memory_capacity(inject, struct( ...
        'lags', [0 1], 'washout', 0, 'minimum_scored_rows', 10, ...
        'T_train', 100, 'T_val', 100, 'T_test', 100)), ...
        'compute_memory_capacity:InvalidLags');
end

function [inject, opts] = make_delay_line_inject(T, K, lags, washout)
    % Build u and X where column j is exactly u delayed by j samples.
    inject = struct();
    seeds = [11, 12, 13];
    splits = {'train', 'val', 'test'};
    for si = 1:3
        rng(seeds(si));
        u = 2 * rand(T, 1) - 1;
        X = zeros(T, K);
        for k = 1:K
            X((k+1):end, k) = u(1:(end-k));
        end
        inject.(['u_' splits{si}]) = u;
        inject.(['X_' splits{si}]) = X;
    end
    opts = struct( ...
        'lags', lags, ...
        'washout', washout, ...
        'minimum_scored_rows', 40, ...
        'T_train', T, 'T_val', T, 'T_test', T, ...
        'lambda_grid', [0, 1e-6, 1e-3]);
end
