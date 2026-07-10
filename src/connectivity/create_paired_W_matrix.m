function [W, M, G, Z, meta] = create_paired_W_matrix(params)
% CREATE_PAIRED_W_MATRIX Creates a connectivity matrix with paired E-I structure
%
% Presynaptic Dale signs are enforced on columns when params.dale is true
% (default). Row centering is disabled by default and is incompatible with
% Dale constraints.

    n_E = params.n_E;
    n_I = params.n_I;
    n = params.n;

    if n_E ~= n_I
        error('create_paired_W_matrix:UnequalPopulations', ...
              'Paired connectivity requires equal E and I populations (n_E=%d, n_I=%d)', n_E, n_I);
    end
    if n ~= (n_E + n_I)
        error('create_paired_W_matrix:SizeMismatch', ...
              'params.n (%d) must equal params.n_E + params.n_I (%d)', n, n_E + n_I);
    end

    dale = get_param(params, 'dale', true);
    row_center_W = get_param(params, 'row_center_W', false);
    if dale && row_center_W
        error('create_paired_W_matrix:DaleCenteringUnsupported', ...
            'Row centering is incompatible with Dale sign constraints.');
    end

    E_cols = 1:n_E;
    I_cols = (n_E + 1):n;

    W = zeros(n);

    p_connect = params.indegree / n_E;
    M_EE = params.mu_E * ones(n_E);
    G_EE = params.G_stdev * randn(n_E);
    W_EE = M_EE + G_EE;
    Z_EE = rand(n_E) > p_connect;
    W_EE(Z_EE) = 0;

    w_drive = 5.0;
    W_IE = eye(n_E) * w_drive;

    beta = 1.2;
    W_EI = -abs(W_EE) * beta;

    M_II = params.mu_I * ones(n_I);
    G_II = params.G_stdev * randn(n_I);
    W_II = M_II + G_II;
    Z_II = rand(n_I) > p_connect;
    W_II(Z_II) = 0;
    W_II = -abs(W_II);

    W(1:n_E, 1:n_E) = W_EE;
    W(1:n_E, (n_E+1):n) = W_EI;
    W((n_E+1):n, 1:n_E) = W_IE;
    W((n_E+1):n, (n_E+1):n) = W_II;

    Z = ones(n);
    Z(1:n_E, 1:n_E) = Z_EE;
    Z((n_E+1):n, 1:n_E) = ~eye(n_E);
    Z(1:n_E, (n_E+1):n) = Z_EE;
    Z((n_E+1):n, (n_E+1):n) = Z_II;

    if row_center_W
        nonzero_mask = W_EE ~= 0;
        row_means = sum(W_EE, 2) ./ max(1, sum(nonzero_mask, 2));
        W_EE = W_EE - bsxfun(@times, row_means, nonzero_mask);
        W(1:n_E, 1:n_E) = W_EE;

        nonzero_mask = W_II ~= 0;
        row_means = sum(W_II, 2) ./ max(1, sum(nonzero_mask, 2));
        W_II = W_II - bsxfun(@times, row_means, nonzero_mask);
        W((n_E+1):n, (n_E+1):n) = W_II;
    end

    if dale
        W(:, E_cols) = abs(W(:, E_cols));
        W(:, I_cols) = -abs(W(:, I_cols));
    end

    M = zeros(n);
    G = zeros(n);

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
