function layout = state_layout(params)
% state_layout  Canonical packed-state descriptor for MESN dynamics.
%
% State order: S = [a_E(:); a_I(:); b_E(:); b_I(:); x(:)]
% Column-major: neuron i, timescale k -> index i + (k-1)*n_population.

    n = params.n;
    n_E = params.n_E;
    n_I = params.n_I;
    n_a_E = params.n_a_E;
    n_a_I = params.n_a_I;
    n_b_E = params.n_b_E;
    n_b_I = params.n_b_I;

    len_a_E = n_E * n_a_E;
    len_a_I = n_I * n_a_I;
    len_b_E = n_E * n_b_E;
    len_b_I = n_I * n_b_I;
    len_x = n;

    start_a_E = 1;
    start_a_I = start_a_E + len_a_E;
    start_b_E = start_a_I + len_a_I;
    start_b_I = start_b_E + len_b_E;
    start_x = start_b_I + len_b_I;

    n_total = len_a_E + len_a_I + len_b_E + len_b_I + len_x;

    layout = struct();
    layout.len_a_E = len_a_E;
    layout.len_a_I = len_a_I;
    layout.len_b_E = len_b_E;
    layout.len_b_I = len_b_I;
    layout.len_x = len_x;
    layout.n_total = n_total;

    layout.idx_a_E = index_slice(start_a_E, len_a_E);
    layout.idx_a_I = index_slice(start_a_I, len_a_I);
    layout.idx_b_E = index_slice(start_b_E, len_b_E);
    layout.idx_b_I = index_slice(start_b_I, len_b_I);
    layout.idx_x = index_slice(start_x, len_x);

    layout.map_a_E = reshape_index_map(layout.idx_a_E, n_E, n_a_E);
    layout.map_a_I = reshape_index_map(layout.idx_a_I, n_I, n_a_I);
    layout.map_b_E = reshape_index_map(layout.idx_b_E, n_E, n_b_E);
    layout.map_b_I = reshape_index_map(layout.idx_b_I, n_I, n_b_I);

    layout.n = n;
    layout.n_E = n_E;
    layout.n_I = n_I;
    layout.E_indices = params.E_indices;
    layout.I_indices = params.I_indices;

    all_idx = [layout.idx_a_E(:); layout.idx_a_I(:); layout.idx_b_E(:); layout.idx_b_I(:); layout.idx_x(:)];
    if n_total == 0
        if ~isempty(all_idx)
            error('state_layout:InvalidLayout', 'Unexpected indices for empty state.');
        end
        return;
    end
    if numel(unique(all_idx)) ~= n_total || ~isequal(sort(all_idx), (1:n_total)')
        error('state_layout:InvalidLayout', 'State indices are not a permutation of 1:n_total.');
    end
end

function idx = index_slice(start_idx, len)
    if len == 0
        idx = zeros(1, 0);
    else
        idx = start_idx:(start_idx + len - 1);
    end
end

function map = reshape_index_map(idx, n_population, n_types)
    if n_types == 0
        map = zeros(n_population, 0);
    else
        map = reshape(idx, n_population, n_types);
    end
end
