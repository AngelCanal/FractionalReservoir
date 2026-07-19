function [features, info] = extract_temporal_memory_features(esn, split, cfg, options)
%EXTRACT_TEMPORAL_MEMORY_FEATURES  One reservoir simulation per split.
%
%   [features, info] = extract_temporal_memory_features(esn, split, cfg)
%   [features, info] = extract_temporal_memory_features(esn, split, cfg, options)
%
% Forces include_input=false semantics for scored features (caller must configure
% the ESN accordingly). Requires feature dimension 40. Resets before the run,
% uses update_internal_state=false, and restores the ESN object state afterward
% so the call leaves the object unchanged.
%
% Activity summaries are computed from neuronal rates (n=40), never from the
% packed SFA/STD state width.

    if nargin < 4 || isempty(options)
        options = struct();
    end
    if logical(esn.include_input)
        error('extract_temporal_memory_features:IncludeInputForbidden', ...
            'Temporal-memory features require include_input=false.');
    end
    mode = char(esn.which_states);
    if ~(strcmp(mode, 'x') || strcmp(mode, 'r'))
        error('extract_temporal_memory_features:FeatureMode', ...
            'Feature mode must be ''x'' or ''r'', got ''%s''.', mode);
    end

    lengths = cfg.lengths;
    run_opts = struct( ...
        'reset_before', true, ...
        'update_internal_state', false, ...
        'ode_reltol', local_get(lengths, 'ode_reltol', 1e-6), ...
        'ode_abstol', local_get(lengths, 'ode_abstol', 1e-8), ...
        'dde_reltol', local_get(lengths, 'dde_reltol', 1e-6), ...
        'dde_abstol', local_get(lengths, 'dde_abstol', 1e-8));
    if isfield(options, 'run_opts')
        fn = fieldnames(options.run_opts);
        for i = 1:numel(fn)
            run_opts.(fn{i}) = options.run_opts.(fn{i});
        end
    end
    run_opts.reset_before = true;
    run_opts.update_internal_state = false;

    state_before = esn.getState();

    [X_all, S_hist, run_info] = esn.runReservoir(split.U, run_opts);
    info = struct();
    info.n_reservoir_simulations = 1;
    info.run_info = run_info;

    idx = split.scored_idx(:);
    X = X_all(idx, :);
    feature_dim = size(X, 2);
    expected_dim = local_get(cfg.base, 'n', 40);
    if feature_dim ~= expected_dim
        error('extract_temporal_memory_features:FeatureDim', ...
            'Expected feature dimension %d, got %d.', expected_dim, feature_dim);
    end
    if any(~isfinite(X(:)))
        error('extract_temporal_memory_features:NonFiniteFeatures', ...
            'Feature matrix contains nonfinite values.');
    end

    n_neurons = size(esn.W, 1);
    packed_state_dimension = size(S_hist, 2);
    wash = split.washout_steps;
    eval_idx = (wash + 1):size(S_hist, 1);
    rates = zeros(n_neurons, numel(eval_idx));
    for k = 1:numel(eval_idx)
        r = esn.computeRates(S_hist(eval_idx(k), :)');
        if numel(r) ~= n_neurons
            error('extract_temporal_memory_features:RateDimension', ...
                'computeRates must return %d rates, got %d.', n_neurons, numel(r));
        end
        rates(:, k) = r(:);
    end

    activity = struct();
    activity.mean_rate = mean(rates(:));
    activity.saturation_fraction = mean(rates(:) >= 0.99);
    activity.silence_fraction = mean(rates(:) <= 0.01);
    activity.silent_fraction = activity.silence_fraction;
    activity.n_neurons = n_neurons;
    activity.packed_state_dimension = packed_state_dimension;
    activity.n_eval_time_points = numel(eval_idx);
    activity.n_rate_observations = numel(rates);
    activity.rates_are_neuronal = true;
    activity.packed_states_counted_as_neurons = false;

    features = struct();
    features.X = X;
    features.X_all = X_all;
    features.U_scored = split.U_scored;
    features.scored_idx = idx;
    features.feature_dimension = feature_dim;
    features.feature_mode = mode;
    features.include_input = false;
    features.activity = activity;
    features.mean_rate_trajectory = mean(rates, 1)';

    esn.setState(state_before);
    state_after = esn.getState();
    if ~isequal(state_before, state_after)
        error('extract_temporal_memory_features:StateMutated', ...
            'ESN object state must be unchanged after extraction.');
    end
    info.state_unchanged = true;
    info.activity = activity;
end

function v = local_get(S, name, default)
    if isstruct(S) && isfield(S, name) && ~isempty(S.(name))
        v = S.(name);
    else
        v = default;
    end
end
