function J_eff = compute_J_eff(S, params)
% COMPUTE_J_EFF  Quasi-static fast-subsystem Jacobian (ODE x,x block).
%
%   J_eff = compute_J_eff(S, params)
%
% Returns the dx/dt-by-x block of the full non-delayed ODE Jacobian, with
% adaptation a and resource b treated as frozen at the current state:
%
%   J_eff = (-I + W * diag(b .* phi'(q))) / tau_d
%
% where q = compute_effective_q(state, params).
%
% This is a local, trajectory-dependent diagnostic for the non-delayed ODE.
% It is not a theorem for the full ODE, and it is not a DDE ESP proof.
% Nonempty lags raise MESN:DelayedJacobianUnsupported.
%
% See also: compute_Jacobian, J_eff_notes.md

    params = validate_MESN_params(params);
    if ~isempty(params.lags)
        error('MESN:DelayedJacobianUnsupported', ...
            ['Finite-dimensional effective Jacobian is not defined for ' ...
            'delayed MESN dynamics.']);
    end

    if ~isfield(params, 'activation_function_derivative') || ...
            ~isa(params.activation_function_derivative, 'function_handle')
        error('compute_J_eff:MissingActivationFunctionDerivative', ...
            'params.activation_function_derivative must be a function handle.');
    end

    layout = state_layout(params);
    state = unpack_state(S, params);

    n = params.n;
    E = params.E_indices(:);
    I = params.I_indices(:);
    W = params.W;
    tau_d = params.tau_d;

    q = compute_effective_q(state, params);
    g = params.activation_function_derivative(q);

    b = ones(n, 1);
    if params.n_b_E > 0
        b(E) = state.b_E;
    end
    if params.n_b_I > 0
        b(I) = state.b_I;
    end

    % Exactly the full-Jacobian x,x block (a,b frozen in the sense of this
    % partial derivative with respect to x only).
    J_eff = (-eye(n) + W * diag(b .* g)) / tau_d;
end
