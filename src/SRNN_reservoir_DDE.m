function dS_dt = SRNN_reservoir_DDE(t, S, Z, u_fun, params)
% SRNN_reservoir_DDE  DDE reservoir with one scalar inhibitory delay.
%
% Current b.*r drives SFA/STD; W_components{1} uses current b.*r,
% W_components{2} uses delayed b.*r.

    if size(Z, 2) ~= 1
        error('SRNN_reservoir_DDE:InvalidDelayHistory', ...
            'Exactly one scalar delay is supported (size(Z,2) must be 1).');
    end
    if numel(params.W_components) ~= 2
        error('SRNN_reservoir_DDE:InvalidConnectivity', ...
            'Scalar delay mode requires exactly two W_components.');
    end

    u = u_fun(t);
    if ~isequal(size(u), [params.n, 1])
        error('SRNN_reservoir_DDE:InvalidInputShape', ...
            'u_fun(t) must return an n x 1 column vector.');
    end

    state = unpack_state(S, params);
    [~, r_current, b_current] = mesn_q_r_b_from_state(state, params);

    state_delayed = unpack_state(Z(:, 1), params);
    [~, r_delayed, b_delayed] = mesn_q_r_b_from_state(state_delayed, params);

    W_inst = params.W_components{1};
    W_delayed = params.W_components{2};
    input_recurrent = W_inst * (b_current .* r_current) + ...
        W_delayed * (b_delayed .* r_delayed);

    tau_d = params.tau_d;
    dx_dt = (-state.x + input_recurrent + u) / tau_d;

    E_indices = params.E_indices;
    I_indices = params.I_indices;

    if params.n_a_E > 0
        da_E_dt = (r_current(E_indices) - state.a_E) ./ params.tau_a_E;
    else
        da_E_dt = zeros(params.n_E, 0);
    end

    if params.n_a_I > 0
        da_I_dt = (r_current(I_indices) - state.a_I) ./ params.tau_a_I;
    else
        da_I_dt = zeros(params.n_I, 0);
    end

    if params.n_b_E > 0
        db_E_dt = (1 - state.b_E) / params.tau_b_E_rec - ...
            (state.b_E .* r_current(E_indices)) / params.tau_b_E_rel;
    else
        db_E_dt = zeros(0, 1);
    end

    if params.n_b_I > 0
        db_I_dt = (1 - state.b_I) / params.tau_b_I_rec - ...
            (state.b_I .* r_current(I_indices)) / params.tau_b_I_rel;
    else
        db_I_dt = zeros(0, 1);
    end

    dstate = struct();
    dstate.a_E = da_E_dt;
    dstate.a_I = da_I_dt;
    dstate.b_E = db_E_dt;
    dstate.b_I = db_I_dt;
    dstate.x = dx_dt;

    dS_dt = pack_state(dstate, params);
end

function [q, r, b] = mesn_q_r_b_from_state(state, params)
    n = params.n;
    q = compute_effective_q(state, params);
    r = params.activation_function(q);

    b = ones(n, 1);
    if params.n_b_E > 0
        b(params.E_indices) = state.b_E;
    end
    if params.n_b_I > 0
        b(params.I_indices) = state.b_I;
    end
end
