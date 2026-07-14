function selection = select_ridge_lambda(X_train, Y_train, X_val, Y_val, lambda_grid)
% SELECT_RIDGE_LAMBDA  Choose ridge strength on a later validation block.
%
%   selection = select_ridge_lambda(X_train,Y_train,X_val,Y_val)
%   selection = select_ridge_lambda(X_train,Y_train,X_val,Y_val,lambda_grid)
%
% Never accepts test arrays. Rank-deficient designs that the SVD / minimum-
% norm solver handles safely remain eligible; selection is by validation
% score only among finite successful candidates.
%
% Deterministic tie-break (independent of publication results):
%   1. Minimize finite validation score.
%   2. Among scores within tie_tolerance (1e-12 absolute), choose larger lambda.
% Lambda is the absolute ridge strength used by fit_ridge_readout (not /n).

    if nargin < 5 || isempty(lambda_grid)
        lambda_grid = [0, logspace(-12, 2, 15)];
    end
    lambda_grid = lambda_grid(:);
    tie_tolerance = 1e-12;

    if size(X_train, 1) ~= size(Y_train, 1) || size(X_val, 1) ~= size(Y_val, 1)
        error('select_ridge_lambda:RowMismatch', 'Feature/target rows must match.');
    end
    if size(X_train, 2) ~= size(X_val, 2) || size(Y_train, 2) ~= size(Y_val, 2)
        error('select_ridge_lambda:DimMismatch', 'Train/val dimensions must match.');
    end

    n_lambda = numel(lambda_grid);
    n_out = size(Y_train, 2);
    table_rows = repmat(struct( ...
        'lambda', NaN, ...
        'train_nrmse', [], ...
        'val_nrmse', [], ...
        'val_score', NaN, ...
        'fallback_used', [], ...
        'fit_status', 'rejected', ...
        'numerical_rank', NaN, ...
        'conditioning_status', 'failed_nonfinite', ...
        'coefficient_norm', NaN, ...
        'finite_predictions', false, ...
        'accepted', false), n_lambda, 1);
    candidate_models = cell(n_lambda, 1);

    for i = 1:n_lambda
        lam = lambda_grid(i);
        row = table_rows(i);
        row.lambda = lam;
        try
            model = fit_ridge_readout(X_train, Y_train, lam);
            Ytr = apply_ridge_readout(model, X_train);
            Yva = apply_ridge_readout(model, X_val);

            finite_pred = all(isfinite(Ytr(:))) && all(isfinite(Yva(:)));
            [train_nrmse, ~] = per_output_nrmse(Ytr, Y_train);
            [val_nrmse, fallback_used] = per_output_nrmse(Yva, Y_val);
            score = mean(val_nrmse);

            row.train_nrmse = train_nrmse;
            row.val_nrmse = val_nrmse;
            row.val_score = score;
            row.fallback_used = fallback_used;
            row.fit_status = 'ok';
            row.numerical_rank = model.numerical_rank;
            row.conditioning_status = char(string(model.conditioning_status));
            row.coefficient_norm = model.coefficient_norm;
            row.finite_predictions = finite_pred;
            row.accepted = finite_pred && all(isfinite(model.coefficients(:))) && ...
                all(isfinite(model.intercept(:))) && isfinite(score);
            table_rows(i) = row;
            candidate_models{i} = model;
        catch ME
            id = ME.identifier;
            if isempty(id)
                id = 'fit_failed';
            end
            row.fit_status = id;
            row.conditioning_status = 'failed_nonfinite';
            row.finite_predictions = false;
            row.accepted = false;
            table_rows(i) = row;
        end
    end

    accepted = [table_rows.accepted];
    if ~any(accepted)
        error('select_ridge_lambda:NoValidCandidate', ...
            'No lambda candidate produced a finite valid fit and validation score.');
    end

    scores = nan(n_lambda, 1);
    for i = 1:n_lambda
        if table_rows(i).accepted
            scores(i) = table_rows(i).val_score;
        end
    end
    best_score = min(scores);
    tied = accepted(:) & isfinite(scores) & (abs(scores - best_score) <= tie_tolerance);
    tied_lambdas = lambda_grid(tied);
    selected_lambda = max(tied_lambdas);
    selected_idx = find(tied & (lambda_grid == selected_lambda), 1, 'last');
    best_model = candidate_models{selected_idx};

    selection = struct();
    selection.lambda_grid = lambda_grid;
    selection.table = table_rows;
    selection.selected_lambda = selected_lambda;
    selection.selected_model = best_model;
    selection.selected_val_score = best_score;
    selection.tie_tolerance = tie_tolerance;
    selection.tied_candidate_lambdas = tied_lambdas(:);
    selection.n_outputs = n_out;
end

function [nrmse, fallback_used] = per_output_nrmse(Y_hat, Y)
    n_out = size(Y, 2);
    nrmse = zeros(1, n_out);
    fallback_used = false(1, n_out);
    for j = 1:n_out
        err = Y_hat(:, j) - Y(:, j);
        rmse = sqrt(mean(err.^2));
        s = std(Y(:, j), 0, 1);
        if s < sqrt(eps)
            denom = max(abs(mean(Y(:, j))), 1);
            nrmse(j) = rmse / denom;
            fallback_used(j) = true;
        else
            nrmse(j) = rmse / s;
        end
    end
end
