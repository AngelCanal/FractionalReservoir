function selection = select_ridge_lambda(X_train, Y_train, X_val, Y_val, lambda_grid)
% SELECT_RIDGE_LAMBDA  Choose ridge strength on a later validation block.
%
%   selection = select_ridge_lambda(X_train,Y_train,X_val,Y_val)
%   selection = select_ridge_lambda(X_train,Y_train,X_val,Y_val,lambda_grid)
%
% Never accepts test arrays. On exact score ties, chooses the larger lambda.

    if nargin < 5 || isempty(lambda_grid)
        lambda_grid = [0, logspace(-12, 2, 15)];
    end
    lambda_grid = lambda_grid(:)';

    if size(X_train, 1) ~= size(Y_train, 1) || size(X_val, 1) ~= size(Y_val, 1)
        error('select_ridge_lambda:RowMismatch', 'Feature/target rows must match.');
    end
    if size(X_train, 2) ~= size(X_val, 2) || size(Y_train, 2) ~= size(Y_val, 2)
        error('select_ridge_lambda:DimMismatch', 'Train/val dimensions must match.');
    end

    n_lambda = numel(lambda_grid);
    n_out = size(Y_train, 2);
    table_rows = struct('lambda', {}, 'train_nrmse', {}, 'val_nrmse', {}, ...
        'val_score', {}, 'fallback_used', {});

    best_score = inf;
    best_lambda = lambda_grid(1);
    best_model = [];

    for i = 1:n_lambda
        lam = lambda_grid(i);
        model = fit_ridge_readout(X_train, Y_train, lam);
        Ytr = apply_ridge_readout(model, X_train);
        Yva = apply_ridge_readout(model, X_val);

        [train_nrmse, ~] = per_output_nrmse(Ytr, Y_train);
        [val_nrmse, fallback_used] = per_output_nrmse(Yva, Y_val);
        score = mean(val_nrmse);

        table_rows(i).lambda = lam;
        table_rows(i).train_nrmse = train_nrmse;
        table_rows(i).val_nrmse = val_nrmse;
        table_rows(i).val_score = score;
        table_rows(i).fallback_used = fallback_used;

        if score < best_score - 0 || (abs(score - best_score) < eps && lam > best_lambda)
            best_score = score;
            best_lambda = lam;
            best_model = model;
        end
    end

    selection = struct();
    selection.lambda_grid = lambda_grid;
    selection.table = table_rows;
    selection.selected_lambda = best_lambda;
    selection.selected_model = best_model;
    selection.selected_val_score = best_score;
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
