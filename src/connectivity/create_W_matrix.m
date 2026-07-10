function [W, M, G, Z, meta] = create_W_matrix(params)
% create_W_matrix - Generate connectivity matrix for SRNN
%
% Syntax:
%   [W, M, G, Z, meta] = create_W_matrix(params)
%
% Presynaptic Dale signs are enforced on columns when params.dale is true
% (default). Row centering is disabled by default and is incompatible with
% Dale constraints.

    dale = get_param(params, 'dale', true);
    row_center_W = get_param(params, 'row_center_W', false);
    if dale && row_center_W
        error('create_W_matrix:DaleCenteringUnsupported', ...
            'Row centering is incompatible with Dale sign constraints.');
    end

    E_cols = 1:params.n_E;
    I_cols = (params.n_E + 1):params.n;

    M = [params.mu_E .* ones(params.n, params.n_E), ...
         params.mu_I .* ones(params.n, params.n_I)];

    G = params.G_stdev * randn(params.n, params.n);
    W = M + G;

    d = params.indegree / params.n;
    Z = rand(params.n, params.n) > d;
    W(Z) = 0;

    if dale
        W(:, E_cols) = abs(W(:, E_cols));
        W(:, I_cols) = -abs(W(:, I_cols));
    end

    if row_center_W
        nonzero_mask = ~Z;
        row_counts = sum(nonzero_mask, 2);
        row_sums = sum(W, 2);
        row_means = zeros(size(row_sums));
        valid_rows = row_counts > 0;
        row_means(valid_rows) = row_sums(valid_rows) ./ row_counts(valid_rows);
        W = W - bsxfun(@times, row_means, nonzero_mask);
    end

    meta = struct();
    meta.sign_violations_E = sum(W(:, E_cols) < 0, 'all');
    meta.sign_violations_I = sum(W(:, I_cols) > 0, 'all');
end

function value = get_param(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end
