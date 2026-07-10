function state = unpack_state(S, params)
% unpack_state  Unpack canonical vector S into structured reservoir state.

    layout = state_layout(params);

    if numel(S) ~= layout.n_total
        error('MESN:InvalidStateLength', ...
            'State vector length %d does not match expected %d.', numel(S), layout.n_total);
    end
    if ~all(isfinite(S))
        error('MESN:InvalidStateShape', 'State vector contains non-finite values.');
    end

    state = struct();
    state.a_E = unpack_matrix(S, layout.map_a_E, params.n_E, params.n_a_E);
    state.a_I = unpack_matrix(S, layout.map_a_I, params.n_I, params.n_a_I);
    state.b_E = unpack_vector(S, layout.idx_b_E, params.n_E, params.n_b_E);
    state.b_I = unpack_vector(S, layout.idx_b_I, params.n_I, params.n_b_I);
    state.x = S(layout.idx_x);
    state.x = state.x(:);

    if numel(state.x) ~= params.n
        error('MESN:InvalidStateShape', 'Unpacked x must be n x 1.');
    end
end

function M = unpack_matrix(S, map, n_population, n_types)
    if n_types == 0
        M = zeros(n_population, 0);
    else
        M = reshape(S(map), n_population, n_types);
    end
end

function v = unpack_vector(S, idx, n_population, n_types)
    if n_types == 0
        v = zeros(0, 1);
    else
        v = S(idx);
        v = v(:);
        if numel(v) ~= n_population * n_types
            error('MESN:InvalidStateShape', 'Unexpected STD vector length.');
        end
    end
end
