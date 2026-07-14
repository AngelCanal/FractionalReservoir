function tests = test_ridge_selection
tests = functiontests(localfunctions);
end

function testPositiveLambdaBeatsZeroOnOverfit(testCase)
    rng(1729);
    % Few noisy train samples, many features: unregularized min-norm overfits;
    % stronger ridge should win on a nearly clean validation draw.
    n_train = 20;
    n_val = 400;
    n_feat = 60;
    X_train = randn(n_train, n_feat);
    true_w = [ones(4, 1); zeros(n_feat - 4, 1)];
    Y_train = X_train * true_w + 1.25 * randn(n_train, 1);
    X_val = randn(n_val, n_feat);
    Y_val = X_val * true_w + 0.01 * randn(n_val, 1);

    sel = select_ridge_lambda(X_train, Y_train, X_val, Y_val, [0, 1e-2, 1, 10, 100]);
    score0 = sel.table(1).val_score;
    score_sel = sel.selected_val_score;
    testCase.verifyGreaterThan(sel.selected_lambda, 0);
    testCase.verifyLessThanOrEqual(score_sel, score0 + sel.tie_tolerance);
end

function testTieBreaksToLargerLambda(testCase)
    % Identical constant targets -> all lambdas give same score; pick largest
    X_train = randn(20, 2);
    Y_train = ones(20, 1);
    X_val = randn(20, 2);
    Y_val = ones(20, 1);
    grid = [0, 1e-3, 1];
    sel = select_ridge_lambda(X_train, Y_train, X_val, Y_val, grid);
    testCase.verifyEqual(sel.selected_lambda, max(grid));
    testCase.verifyEqual(sel.tie_tolerance, 1e-12);
    testCase.verifyEqual(sort(sel.tied_candidate_lambdas), sort(grid(:)));
end

function testHeldOutArrayCannotAffectSelection(testCase)
    rng(5);
    X_train = randn(40, 3);
    Y_train = X_train * [1; -1; 0.5] + 0.1 * randn(40, 1);
    X_val = randn(40, 3);
    Y_val = X_val * [1; -1; 0.5] + 0.1 * randn(40, 1);
    Y_held = randn(40, 1); %#ok<NASGU>

    sel1 = select_ridge_lambda(X_train, Y_train, X_val, Y_val, [0, 1e-4, 1e-2]);
    % Mutate a variable never passed to the API
    Y_held = Y_held + 100; %#ok<NASGU>
    sel2 = select_ridge_lambda(X_train, Y_train, X_val, Y_val, [0, 1e-4, 1e-2]);
    testCase.verifyEqual(sel1.selected_lambda, sel2.selected_lambda);
    testCase.verifyEqual(sel1.selected_val_score, sel2.selected_val_score, ...
        'AbsTol', 0, 'RelTol', 0);
end

function testCandidateTableRecordsDiagnostics(testCase)
    rng(6);
    X_train = randn(40, 5);
    Y_train = X_train(:, 1:2) * [1; -1];
    X_val = randn(40, 5);
    Y_val = X_val(:, 1:2) * [1; -1];
    sel = select_ridge_lambda(X_train, Y_train, X_val, Y_val, [0, 1e-2, 1]);
    for i = 1:numel(sel.table)
        row = sel.table(i);
        testCase.verifyTrue(isfield(row, 'lambda'));
        testCase.verifyTrue(isfield(row, 'val_score'));
        testCase.verifyTrue(isfield(row, 'fit_status'));
        testCase.verifyTrue(isfield(row, 'numerical_rank'));
        testCase.verifyTrue(isfield(row, 'conditioning_status'));
        testCase.verifyTrue(isfield(row, 'coefficient_norm'));
        testCase.verifyTrue(isfield(row, 'finite_predictions'));
        testCase.verifyTrue(isfield(row, 'accepted'));
        testCase.verifyEqual(row.fit_status, 'ok');
        testCase.verifyTrue(row.accepted);
    end
end

function testSelectsBestFiniteValidationCandidate(testCase)
    rng(7);
    n_train = 25;
    n_val = 200;
    p = 30;
    X_train = randn(n_train, p);
    w = [ones(3, 1); zeros(p - 3, 1)];
    Y_train = X_train * w + 0.02 * randn(n_train, 1);
    X_val = randn(n_val, p);
    Y_val = X_val * w + 0.02 * randn(n_val, 1);
    grid = [0, 1e-4, 1e-1, 10];
    sel = select_ridge_lambda(X_train, Y_train, X_val, Y_val, grid);
    scores = arrayfun(@(r) r.val_score, sel.table);
    testCase.verifyEqual(sel.selected_val_score, min(scores), 'AbsTol', 1e-12);
    % Among numerical ties, larger lambda wins
    tied = abs(scores - sel.selected_val_score) <= sel.tie_tolerance;
    testCase.verifyEqual(sel.selected_lambda, max(grid(tied)));
end

function testRejectsNonfiniteCandidateExplicitly(testCase)
    % Inject a candidate that cannot be scored by corrupting validation targets
    % after a wrapper-less direct check: empty accepted set via invalid lambda
    % is not available (fit rejects negative). Instead verify NaN features fail.
    X_train = randn(20, 2);
    Y_train = randn(20, 1);
    X_val = randn(20, 2);
    Y_val = randn(20, 1);
    X_val(1) = Inf;
    testCase.verifyError( ...
        @() select_ridge_lambda(X_train, Y_train, X_val, Y_val, [1e-2]), ...
        'select_ridge_lambda:NoValidCandidate');
end

function testChangingValTargetsDoesNotChangeFittedModelFields(testCase)
    rng(8);
    X_train = randn(50, 3);
    Y_train = X_train * [1; 0; -1] + 0.05 * randn(50, 1);
    X_val = randn(50, 3);
    Y_val = X_val * [1; 0; -1] + 0.05 * randn(50, 1);
    sel1 = select_ridge_lambda(X_train, Y_train, X_val, Y_val, [1e-3, 1e-1]);
    model1 = sel1.selected_model;

    Y_val2 = Y_val + 10;
    sel2 = select_ridge_lambda(X_train, Y_train, X_val, Y_val2, [1e-3, 1e-1]);
    % Train fit at a fixed lambda must be independent of validation targets
    m_a = fit_ridge_readout(X_train, Y_train, 1e-1);
    m_b = fit_ridge_readout(X_train, Y_train, 1e-1);
    testCase.verifyEqual(m_a.feature_mean, m_b.feature_mean);
    testCase.verifyEqual(m_a.coefficients, m_b.coefficients);
    testCase.verifyEqual(m_a.intercept, m_b.intercept);
    testCase.verifyEqual(model1.feature_mean, m_a.feature_mean);
    % Selection may change with different val targets, but training transforms
    % for a given selected lambda remain training-only.
    m_sel = fit_ridge_readout(X_train, Y_train, sel2.selected_lambda);
    testCase.verifyEqual(sel2.selected_model.feature_mean, m_sel.feature_mean);
    testCase.verifyEqual(sel2.selected_model.coefficients, m_sel.coefficients);
end
