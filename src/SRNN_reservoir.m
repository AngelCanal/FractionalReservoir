function [dS_dt] = SRNN_reservoir(t, S, u_fun, params)
% SRNN_reservoir  ODE reservoir dynamics with SFA and STD.
%
% State order: S = [a_E(:); a_I(:); b_E(:); b_I(:); x(:)]
%
%   q(E) = x(E) - a_E*c_a_E(:);  q(I) analogous
%   r    = activation_function(q)
%   dx   = (-x + W*(b.*r) + u) / tau_d
%   da   = (r - a) ./ tau_a
%   db   = (1-b)/tau_rec - (b.*r)/tau_rel

    u = u_fun(t);
    if ~isequal(size(u), [params.n, 1])
        error('SRNN_reservoir:InvalidInputShape', ...
            'u_fun(t) must return an n x 1 column vector.');
    end

    state = unpack_state(S, params);
    q = compute_effective_q(state, params);
    r = params.activation_function(q);

    n = params.n;
    b = ones(n, 1);
    if params.n_b_E > 0
        b(params.E_indices) = state.b_E;
    end
    if params.n_b_I > 0
        b(params.I_indices) = state.b_I;
    end

    n_E = params.n_E;
    n_I = params.n_I;
    E_indices = params.E_indices;
    I_indices = params.I_indices;

    W = params.W;
    tau_d = params.tau_d;
    tau_a_E = params.tau_a_E;
    tau_a_I = params.tau_a_I;
    tau_b_E_rec = params.tau_b_E_rec;
    tau_b_E_rel = params.tau_b_E_rel;
    tau_b_I_rec = params.tau_b_I_rec;
    tau_b_I_rel = params.tau_b_I_rel;

    dx_dt = (-state.x + W * (b .* r) + u) / tau_d;

    if params.n_a_E > 0
        da_E_dt = (r(E_indices) - state.a_E) ./ tau_a_E;
    else
        da_E_dt = zeros(params.n_E, 0);
    end

    if params.n_a_I > 0
        da_I_dt = (r(I_indices) - state.a_I) ./ tau_a_I;
    else
        da_I_dt = zeros(params.n_I, 0);
    end

    if params.n_b_E > 0
        db_E_dt = (1 - state.b_E) / tau_b_E_rec - (state.b_E .* r(E_indices)) / tau_b_E_rel;
    else
        db_E_dt = zeros(0, 1);
    end

    if params.n_b_I > 0
        db_I_dt = (1 - state.b_I) / tau_b_I_rec - (state.b_I .* r(I_indices)) / tau_b_I_rel;
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
