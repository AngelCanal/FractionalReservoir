function J = compute_Jacobian_fast(S, params)
% COMPUTE_JACOBIAN_FAST  Vectorized ODE Jacobian matching compute_Jacobian.
%
%   J = compute_Jacobian_fast(S, params)
%
% Same mathematical blocks as the dense Jacobian, assembled with layout maps
% and sparse/vectorized assignments. Does not call compute_Jacobian.
% Delayed systems raise MESN:DelayedJacobianUnsupported.

    params = validate_MESN_params(params);
    if ~isempty(params.lags)
        error('MESN:DelayedJacobianUnsupported', ...
            'Finite-dimensional Jacobian is not defined for delayed MESN dynamics.');
    end

    if params.n_b_E > 1 || params.n_b_I > 1
        error('MESN:MultipleSTDUnsupported', ...
            'Fast Jacobian supports at most one STD resource per population.');
    end

    if ~isfield(params, 'activation_function_derivative') || ...
            ~isa(params.activation_function_derivative, 'function_handle')
        error('compute_Jacobian_fast:MissingActivationFunctionDerivative', ...
            'params.activation_function_derivative must be a function handle.');
    end
    if ~isfield(params, 'activation_function') || ...
            ~isa(params.activation_function, 'function_handle')
        error('compute_Jacobian_fast:MissingActivationFunction', ...
            'params.activation_function must be a function handle.');
    end

    layout = state_layout(params);
    state = unpack_state(S, params);

    n = params.n;
    E = params.E_indices(:);
    I = params.I_indices(:);
    W = sparse(params.W);
    tau_d = params.tau_d;

    q = compute_effective_q(state, params);
    r = params.activation_function(q);
    g = params.activation_function_derivative(q);

    b = ones(n, 1);
    if params.n_b_E > 0
        b(E) = state.b_E;
    end
    if params.n_b_I > 0
        b(I) = state.b_I;
    end

    J = sparse(layout.n_total, layout.n_total);

    % --- dx/dt blocks ---
    % J_xx = (-I + W*diag(b.*g)) / tau_d
    J(layout.idx_x, layout.idx_x) = spdiags(-ones(n, 1) / tau_d, 0, n, n) + ...
        (W * spdiags(b .* g, 0, n, n)) / tau_d;

    % d(dx)/d(a_pop(:,k)) via layout maps (column-major timescale blocks)
    J = assign_dx_da_blocks(J, layout, params, 'E', E, W, b, g, tau_d);
    J = assign_dx_da_blocks(J, layout, params, 'I', I, W, b, g, tau_d);

    if params.n_b_E > 0
        J(layout.idx_x, layout.idx_b_E) = (W(:, E) * spdiags(r(E), 0, params.n_E, params.n_E)) / tau_d;
    end
    if params.n_b_I > 0
        J(layout.idx_x, layout.idx_b_I) = (W(:, I) * spdiags(r(I), 0, params.n_I, params.n_I)) / tau_d;
    end

    % --- adaptation and resource blocks ---
    J = assign_adaptation_blocks(J, layout, params, 'E', E, g);
    J = assign_adaptation_blocks(J, layout, params, 'I', I, g);
    J = assign_resource_blocks(J, layout, params, 'E', E, b, r, g);
    J = assign_resource_blocks(J, layout, params, 'I', I, b, r, g);
end

function J = assign_dx_da_blocks(J, layout, params, pop, pop_indices, W, b, g, tau_d)
    n_a = params.(sprintf('n_a_%s', pop));
    if n_a == 0
        return;
    end

    n_pop = numel(pop_indices);
    map_a = layout.(sprintf('map_a_%s', pop));
    c_a = params.(sprintf('c_a_%s', pop));
    G = W(:, pop_indices) * spdiags(b(pop_indices) .* g(pop_indices), 0, n_pop, n_pop);

    % Column-major: contiguous timescale blocks map_a(:,k)
    % J(idx_x, map_a(:,k)) = G * (-c_a(k)/tau_d)
    scale = -c_a(:)' / tau_d;  % 1 x n_a
    J(layout.idx_x, map_a(:)) = kron(scale, G);
end

function J = assign_adaptation_blocks(J, layout, params, pop, pop_indices, g)
    n_a = params.(sprintf('n_a_%s', pop));
    if n_a == 0
        return;
    end

    n_pop = numel(pop_indices);
    map_a = layout.(sprintf('map_a_%s', pop));
    tau_a = params.(sprintf('tau_a_%s', pop));
    c_a = params.(sprintf('c_a_%s', pop));
    g_pop = g(pop_indices);
    Dg = spdiags(g_pop, 0, n_pop, n_pop);

    % Column-major packing: leak = kron(diag(-1./tau_a), I_n_pop)
    leak = kron(spdiags(-1 ./ tau_a(:), 0, n_a, n_a), speye(n_pop));

    % Coupling block (k,l) = (-c_a(l)/tau_a(k)) * diag(g)
    Alpha = (-1 ./ tau_a(:)) * c_a;  % n_a x n_a
    coupling = kron(sparse(Alpha), Dg);

    J(map_a(:), map_a(:)) = leak + coupling;

    % d(da_k)/dx on population columns: stacked diag(g)/tau_a(k)
    J(map_a(:), layout.idx_x(pop_indices)) = kron(1 ./ tau_a(:), Dg);
end

function J = assign_resource_blocks(J, layout, params, pop, pop_indices, b, r, g)
    n_b = params.(sprintf('n_b_%s', pop));
    if n_b == 0
        return;
    end

    n_pop = numel(pop_indices);
    rows = layout.(sprintf('idx_b_%s', pop));
    tau_rec = params.(sprintf('tau_b_%s_rec', pop));
    tau_rel = params.(sprintf('tau_b_%s_rel', pop));
    b_pop = b(pop_indices);
    r_pop = r(pop_indices);
    g_pop = g(pop_indices);

    J(rows, layout.idx_x(pop_indices)) = spdiags(-b_pop .* g_pop / tau_rel, 0, n_pop, n_pop);
    J(rows, rows) = spdiags(-1 / tau_rec - r_pop / tau_rel, 0, n_pop, n_pop);

    n_a = params.(sprintf('n_a_%s', pop));
    if n_a > 0
        map_a = layout.(sprintf('map_a_%s', pop));
        c_a = params.(sprintf('c_a_%s', pop));
        % J(rows, map_a(:,l)) = diag(b.*g*c_a(l)/tau_rel)
        scale = c_a(:)' / tau_rel;  % 1 x n_a
        base = spdiags(b_pop .* g_pop, 0, n_pop, n_pop);
        J(rows, map_a(:)) = kron(scale, base);
    end
end
