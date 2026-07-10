function J = compute_Jacobian(S, params)
% COMPUTE_JACOBIAN  Dense ODE Jacobian of the MESN reservoir.
%
%   J = compute_Jacobian(S, params)
%
% State order: S = [a_E(:); a_I(:); b_E(:); b_I(:); x(:)] (column-major).
% Delayed systems are unsupported: nonempty lags raise
% MESN:DelayedJacobianUnsupported.
%
% Block derivatives use per-timescale coupling c_a_E / c_a_I.

    params = validate_MESN_params(params);
    if ~isempty(params.lags)
        error('MESN:DelayedJacobianUnsupported', ...
            'Finite-dimensional Jacobian is not defined for delayed MESN dynamics.');
    end

    if ~isfield(params, 'activation_function_derivative') || ...
            ~isa(params.activation_function_derivative, 'function_handle')
        error('compute_Jacobian:MissingActivationFunctionDerivative', ...
            'params.activation_function_derivative must be a function handle.');
    end
    if ~isfield(params, 'activation_function') || ...
            ~isa(params.activation_function, 'function_handle')
        error('compute_Jacobian:MissingActivationFunction', ...
            'params.activation_function must be a function handle.');
    end

    layout = state_layout(params);
    state = unpack_state(S, params);

    n = params.n;
    E = params.E_indices(:);
    I = params.I_indices(:);
    W = params.W;
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

    J = zeros(layout.n_total, layout.n_total);

    % Embedding maps: population vectors -> full n-vector
    D_E = population_embed(n, E);
    D_I = population_embed(n, I);

    % --- dx/dt blocks (n x *) ---
    % J_xx = (-I + W*diag(b.*g)) / tau_d
    J(layout.idx_x, layout.idx_x) = (-eye(n) + W * diag(b .* g)) / tau_d;

    % d(dx)/d(a_E(:,k)) = W*diag(b.*g)*D_E*(-c_a_E(k)) / tau_d
    for k = 1:params.n_a_E
        cols = layout.map_a_E(:, k);
        J(layout.idx_x, cols) = (W * diag(b .* g) * D_E) * (-params.c_a_E(k) / tau_d);
    end

    % d(dx)/d(a_I(:,k)) analogous
    for k = 1:params.n_a_I
        cols = layout.map_a_I(:, k);
        J(layout.idx_x, cols) = (W * diag(b .* g) * D_I) * (-params.c_a_I(k) / tau_d);
    end

    % d(dx)/db_E = W(:,E)*diag(r(E)) / tau_d
    if params.n_b_E > 0
        J(layout.idx_x, layout.idx_b_E) = (W(:, E) * diag(r(E))) / tau_d;
    end
    if params.n_b_I > 0
        J(layout.idx_x, layout.idx_b_I) = (W(:, I) * diag(r(I))) / tau_d;
    end

    % --- da_E/dt and da_I/dt blocks ---
    J = fill_adaptation_blocks(J, layout, params, 'E', E, g);
    J = fill_adaptation_blocks(J, layout, params, 'I', I, g);

    % --- db_E/dt and db_I/dt blocks ---
    J = fill_resource_blocks(J, layout, params, 'E', E, b, r, g);
    J = fill_resource_blocks(J, layout, params, 'I', I, b, r, g);
end

function D = population_embed(n, pop_indices)
    D = zeros(n, numel(pop_indices));
    for i = 1:numel(pop_indices)
        D(pop_indices(i), i) = 1;
    end
end

function J = fill_adaptation_blocks(J, layout, params, pop, pop_indices, g)
    n_a = params.(sprintf('n_a_%s', pop));
    if n_a == 0
        return;
    end

    map_a = layout.(sprintf('map_a_%s', pop));
    tau_a = params.(sprintf('tau_a_%s', pop));
    c_a = params.(sprintf('c_a_%s', pop));
    g_pop = g(pop_indices);

    for k = 1:n_a
        rows = map_a(:, k);
        % d(da_k)/dx = diag(g(pop)) / tau_a(k) on population x columns
        J(rows, layout.idx_x(pop_indices)) = diag(g_pop) / tau_a(k);

        for l = 1:n_a
            cols = map_a(:, l);
            % self leak on matching timescale plus rate-through-adaptation
            block = diag(g_pop) * (-c_a(l) / tau_a(k));
            if k == l
                block = block - eye(numel(pop_indices)) / tau_a(k);
            end
            J(rows, cols) = block;
        end
    end
end

function J = fill_resource_blocks(J, layout, params, pop, pop_indices, b, r, g)
    n_b = params.(sprintf('n_b_%s', pop));
    if n_b == 0
        return;
    end

    rows = layout.(sprintf('idx_b_%s', pop));
    tau_rec = params.(sprintf('tau_b_%s_rec', pop));
    tau_rel = params.(sprintf('tau_b_%s_rel', pop));
    b_pop = b(pop_indices);
    r_pop = r(pop_indices);
    g_pop = g(pop_indices);

    % d(db)/dx = -diag(b.*g) / tau_rel on population x columns
    J(rows, layout.idx_x(pop_indices)) = -diag(b_pop .* g_pop) / tau_rel;

    % resource self: -1/tau_rec - r/tau_rel
    J(rows, rows) = diag(-1 / tau_rec - r_pop / tau_rel);

    % rate-through-adaptation: (+b.*g*c_a(l)) / tau_rel
    n_a = params.(sprintf('n_a_%s', pop));
    if n_a > 0
        map_a = layout.(sprintf('map_a_%s', pop));
        c_a = params.(sprintf('c_a_%s', pop));
        for l = 1:n_a
            cols = map_a(:, l);
            J(rows, cols) = diag(b_pop .* g_pop * c_a(l) / tau_rel);
        end
    end
end
