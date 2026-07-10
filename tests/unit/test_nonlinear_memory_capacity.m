function tests = test_nonlinear_memory_capacity
tests = functiontests(localfunctions);
end

function testUnequalLagCrossTermAlignment(testCase)
    % Cross term P1(u(t-2))*P1(u(t-7)) with exact synthetic feature.
    rng(1729);
    T = 700;
    k1 = 2;
    k2 = 7;
    inject = struct();
    seeds = [1, 2, 3];
    splits = {'train', 'val', 'test'};
    for si = 1:3
        rng(seeds(si));
        u = 2 * rand(T, 1) - 1;
        X = zeros(T, 1);
        kmax = max(k1, k2);
        t = (kmax+1):T;
        X(t, 1) = u(t - k1) .* u(t - k2);
        inject.(['u_' splits{si}]) = u;
        inject.(['X_' splits{si}]) = X;
    end
    opts = struct( ...
        'lags', [k1, k2], ...
        'degrees', 1, ... % also score single terms
        'include_cross_terms', true, ...
        'cross_degrees', [1 1], ...
        'cross_max_pairs', 10, ...
        'washout', 0, ...
        'minimum_scored_rows', 40, ...
        'T_train', T, 'T_val', T, 'T_test', T, ...
        'lambda_grid', 0);
    nmc = compute_nonlinear_memory_capacity(inject, opts);

    cross_labels = {nmc.cross_tasks.label};
    testCase.verifyTrue(any(strcmp(cross_labels, 'P_1(u(t-2))*P_1(u(t-7))')));
    idx = find(strcmp({nmc.tasks.label}, 'P_1(u(t-2))*P_1(u(t-7))'), 1);
    testCase.verifyGreaterThan(nmc.capacity(idx), 0.9);
end

function testEqualLagPairAndDegrees(testCase)
    rng(5);
    T = 600;
    k = 4;
    inject = struct();
    for si = 1:3
        rng(10 + si);
        u = 2 * rand(T, 1) - 1;
        X = zeros(T, 3);
        t = (k+1):T;
        X(t, 1) = u(t - k);
        X(t, 2) = 0.5 * (3*u(t - k).^2 - 1);
        X(t, 3) = 0.5 * (5*u(t - k).^3 - 3*u(t - k));
        splits = {'train', 'val', 'test'};
        inject.(['u_' splits{si}]) = u;
        inject.(['X_' splits{si}]) = X;
    end
    opts = struct( ...
        'lags', k, ...
        'degrees', [1 2 3], ...
        'include_cross_terms', false, ...
        'washout', 0, ...
        'minimum_scored_rows', 40, ...
        'T_train', T, 'T_val', T, 'T_test', T, ...
        'lambda_grid', 0);
    nmc = compute_nonlinear_memory_capacity(inject, opts);
    testCase.verifyEqual(numel(nmc.tasks), 3);
    testCase.verifyGreaterThan(min(nmc.capacity), 0.9);
end

function testDimensionMismatchErrors(testCase)
    T = 200;
    u = randn(T, 1);
    X = randn(T - 5, 2); % wrong length
    inject = struct( ...
        'u_train', u, 'X_train', X, ...
        'u_val', u, 'X_val', X, ...
        'u_test', u, 'X_test', X);
    opts = struct( ...
        'lags', 2, ...
        'degrees', 1, ...
        'washout', 0, ...
        'minimum_scored_rows', 10, ...
        'T_train', T, 'T_val', T, 'T_test', T, ...
        'lambda_grid', 0);
    testCase.verifyError(@() compute_nonlinear_memory_capacity(inject, opts), ...
        'compute_nonlinear_memory_capacity:SizeMismatch');
end

function testTaskLabelsRetainUnequalLags(testCase)
    rng(7);
    T = 400;
    inject = struct();
    for si = 1:3
        rng(30 + si);
        u = 2 * rand(T, 1) - 1;
        X = randn(T, 2);
        splits = {'train', 'val', 'test'};
        inject.(['u_' splits{si}]) = u;
        inject.(['X_' splits{si}]) = X;
    end
    opts = struct( ...
        'lags', [2 7], ...
        'degrees', 1, ...
        'include_cross_terms', true, ...
        'cross_degrees', [1 1], ...
        'washout', 0, ...
        'minimum_scored_rows', 30, ...
        'T_train', T, 'T_val', T, 'T_test', T, ...
        'lambda_grid', [0 1e-3]);
    nmc = compute_nonlinear_memory_capacity(inject, opts);
    labels = {nmc.tasks.label};
    testCase.verifyTrue(any(contains(labels, 't-2') & contains(labels, 't-7')));
    % Never collapse to a single ambiguous max-lag label only
    testCase.verifyTrue(any(strcmp(labels, 'P_1(u(t-2))*P_1(u(t-7))')));
end
