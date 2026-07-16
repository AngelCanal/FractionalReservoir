function diag = probe_operating_point_activity(esn, U, op)
%PROBE_OPERATING_POINT_ACTIVITY  Post-washout neuronal rate activity metrics.
%
%   diag = probe_operating_point_activity(esn, U, op)
%
% Uses authoritative neuronal count size(esn.W,1), not packed-state width.

    run_opts = struct( ...
        'reset_before', true, ...
        'update_internal_state', false, ...
        'ode_reltol', op.ode_reltol, ...
        'ode_abstol', op.ode_abstol, ...
        'dde_reltol', op.dde_reltol, ...
        'dde_abstol', op.dde_abstol);
    [~, S_hist] = esn.runReservoir(U, run_opts);
    eval_idx = (op.washout_steps + 1):op.total_steps;
    n_eval = numel(eval_idx);
    packed_state_dimension = size(S_hist, 2);
    n_neurons = size(esn.W, 1);
    assert(n_neurons == op.network_size, ...
        'probe_operating_point_activity:NeuronCount', ...
        'Expected n_neurons=%d, got %d.', op.network_size, n_neurons);
    assert(n_neurons == 40, ...
        'probe_operating_point_activity:PublicationNeuronCount', ...
        'Publication calibration requires n_neurons=40.');

    rates = zeros(n_neurons, n_eval);
    for k = 1:n_eval
        packed = S_hist(eval_idx(k), :)';
        r = esn.computeRates(packed);
        assert(numel(r) == n_neurons, ...
            'probe_operating_point_activity:RateDimension', ...
            'computeRates must return %d rates, got %d.', n_neurons, numel(r));
        rates(:, k) = r;
    end

    diag = struct();
    diag.mean_rate = mean(rates(:));
    diag.saturation_fraction = mean(rates(:) >= 0.99);
    diag.silent_fraction = mean(rates(:) <= 0.01);
    diag.n_eval_time_points = n_eval;
    diag.n_neurons = n_neurons;
    diag.n_rate_observations = numel(rates);
    diag.packed_state_dimension = packed_state_dimension;
end
