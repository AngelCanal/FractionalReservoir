function q = compute_effective_q(state, params)
% compute_effective_q  Effective membrane input q before activation.
%
%   q(E) = x(E) - a_E * c_a_E(:)
%   q(I) = x(I) - a_I * c_a_I(:)

    q = state.x;
    if params.n_a_E > 0
        q(params.E_indices) = q(params.E_indices) - state.a_E * params.c_a_E(:);
    end
    if params.n_a_I > 0
        q(params.I_indices) = q(params.I_indices) - state.a_I * params.c_a_I(:);
    end
end
