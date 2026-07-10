function tests = test_ridge_selection
tests = functiontests(localfunctions);
end

function testPositiveLambdaBeatsZeroOnOverfit(testCase)
    rng(1729);
    % Few train samples, many features -> lambda=0 overfits; positive lambda better on val
    n_train = 30;
    n_val = 200;
    n_feat = 40;
    X_train = randn(n_train, n_feat);
    true_w = [ones(5, 1); zeros(n_feat - 5, 1)];
    Y_train = X_train * true_w + 0.05 * randn(n_train, 1);
    X_val = randn(n_val, n_feat);
    Y_val = X_val * true_w + 0.05 * randn(n_val, 1);

    sel = select_ridge_lambda(X_train, Y_train, X_val, Y_val, [0, 1e-2, 1, 10]);
    score0 = sel.table(1).val_score;
    score_sel = sel.selected_val_score;
    testCase.verifyGreaterThan(sel.selected_lambda, 0);
    testCase.verifyLessThanOrEqual(score_sel, score0);
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
