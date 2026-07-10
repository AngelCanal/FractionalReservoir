function S = pack_state(state, params)
% pack_state  Pack structured reservoir state into canonical vector S.

    layout = state_layout(params);
    validate_state_struct(state, params, layout);

    S = [state.a_E(:); state.a_I(:); state.b_E(:); state.b_I(:); state.x(:)];

    if numel(S) ~= layout.n_total
        error('MESN:InvalidStateLength', ...
            'Packed state length %d does not match expected %d.', numel(S), layout.n_total);
    end
end

function validate_state_struct(state, params, layout)
    required = {'a_E', 'a_I', 'b_E', 'b_I', 'x'};
    for i = 1:numel(required)
        if ~isfield(state, required{i})
            error('MESN:InvalidStateShape', 'State struct missing field %s.', required{i});
        end
    end

    expected = struct();
    expected.a_E = [params.n_E, params.n_a_E];
    expected.a_I = [params.n_I, params.n_a_I];
    expected.b_E = [params.n_E * params.n_b_E, 1];
    expected.b_I = [params.n_I * params.n_b_I, 1];
    expected.x = [params.n, 1];

    fields = fieldnames(expected);
    for i = 1:numel(fields)
        f = fields{i};
        value = state.(f);
        exp_size = expected.(f);
        if ~isequal(size(value), exp_size)
            error('MESN:InvalidStateShape', ...
                'Field %s has size [%s], expected [%s].', f, num2str(size(value)), num2str(exp_size));
        end
        if ~isempty(value) && ~all(isfinite(value(:)))
            error('MESN:InvalidStateShape', 'Field %s contains non-finite values.', f);
        end
    end
end
