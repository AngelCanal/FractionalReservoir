function bundle = fit_temporal_memory_seed(cfg, cell_spec, model_seed, options)
%FIT_TEMPORAL_MEMORY_SEED  Train/validation fits for one cell and model seed.
%
%   bundle = fit_temporal_memory_seed(cfg, cell_spec, model_seed)
%   bundle = fit_temporal_memory_seed(cfg, cell_spec, model_seed, options)
%
% Constructs one paired MESN, generates independent splits, simulates the
% reservoir exactly once per split, reuses feature matrices for all lags, and
% never uses test targets in fitting. Separated from scoring for isolation tests.

    if nargin < 4 || isempty(options)
        options = struct();
    end
    if ~isfinite(model_seed)
        error('fit_temporal_memory_seed:InvalidSeed', 'model_seed is required.');
    end
    assert_model_seed_allowed(cfg, model_seed);

    global_before = RandStream.getGlobalStream().State;

    lags = cfg.lags(:)';
    if isfield(options, 'lags'); lags = options.lags(:); end
    lambda_grid = cfg.lambda_grid(:);
    if isfield(options, 'lambda_grid'); lambda_grid = options.lambda_grid(:); end

    split_opts = struct();
    for f = {'washout_steps', 'train_samples', 'validation_samples', ...
            'test_samples', 'max_lag', 'task_seeds'}
        if isfield(options, f{1})
            split_opts.(f{1}) = options.(f{1});
        end
    end
    if isfield(options, 'max_lag')
        % keep
    elseif ~isempty(lags)
        split_opts.max_lag = max(lags);
    end
    splits = build_temporal_memory_development_splits(cfg, split_opts);

    [params, ~] = build_ablation_params(cell_spec, model_seed, cfg);
    params.include_input = false;
    if isfield(cell_spec, 'which_states')
        params.which_states = char(cell_spec.which_states);
    end
    esn = SRNN_ESN(params);
    if logical(esn.include_input)
        error('fit_temporal_memory_seed:IncludeInput', ...
            'include_input must be false.');
    end

    feat = struct();
    n_sims = 0;
    for name = {'train', 'validation', 'test'}
        nm = name{1};
        [feat.(nm), einfo] = extract_temporal_memory_features( ...
            esn, splits.(nm), cfg, options);
        n_sims = n_sims + einfo.n_reservoir_simulations;
    end
    if n_sims ~= 3
        error('fit_temporal_memory_seed:SimulationCount', ...
            'Expected exactly 3 reservoir simulations (one per split), got %d.', ...
            n_sims);
    end

    [Y_train, ~] = build_temporal_memory_targets(splits.train, lags);
    [Y_val, ~] = build_temporal_memory_targets(splits.validation, lags);
    [Y_test_protocol, ~] = build_temporal_memory_targets(splits.test, lags);

    fit_opts = struct( ...
        'X_test', feat.test.X, ...
        'n_reservoir_simulations', n_sims, ...
        'meta', struct('model_seed', model_seed));
    curve_bundle = fit_temporal_memory_curve( ...
        feat.train.X, feat.validation.X, Y_train, Y_val, lags, lambda_grid, fit_opts);

    feature_diag = compute_temporal_feature_diagnostics( ...
        feat.train.X, feat.train.activity);

    bundle = struct();
    bundle.model_seed = model_seed;
    bundle.cell_key = char(cell_spec.cell_key);
    if isfield(cell_spec, 'diagnostic_name')
        bundle.cell_name = char(cell_spec.diagnostic_name);
    else
        bundle.cell_name = '';
    end
    bundle.lags = lags;
    bundle.lambda_grid = lambda_grid;
    bundle.curve = curve_bundle;
    bundle.X_test = feat.test.X;
    bundle.Y_test_protocol = Y_test_protocol;
    bundle.Y_train = Y_train;
    bundle.Y_val = Y_val;
    bundle.splits = splits;
    bundle.mesn_features = feat;
    bundle.feature_diagnostics = feature_diag;
    bundle.feature_dimension = feat.train.feature_dimension;
    bundle.feature_mode = feat.train.feature_mode;
    bundle.include_input = false;
    bundle.n_reservoir_simulations = n_sims;
    bundle.simulations_per_split = 1;
    bundle.W = esn.W;
    bundle.W_in = esn.W_in;
    bundle.esn = esn;
    bundle.fit_uses_test_targets = false;

    global_after = RandStream.getGlobalStream().State;
    bundle.global_rng_unchanged = isequal(global_before, global_after);
    if ~bundle.global_rng_unchanged
        error('fit_temporal_memory_seed:GlobalRNGMutated', ...
            'Caller global RNG must be unchanged.');
    end
end

function assert_model_seed_allowed(cfg, model_seed)
    if model_seed == 9003
        error('fit_temporal_memory_seed:ForbiddenSeed9003', ...
            'v1 test seed 9003 is forbidden.');
    end
    if isfield(cfg, 'forbidden_executed_seeds') && ...
            any(cfg.forbidden_executed_seeds(:) == model_seed)
        % Development model seeds are removed from forbidden list; still guard.
        if isfield(cfg, 'model_seeds') && any(cfg.model_seeds(:) == model_seed)
            return;
        end
        error('fit_temporal_memory_seed:ForbiddenSeed', ...
            'Model seed %g is forbidden for execution.', model_seed);
    end
    if isfield(cfg, 'reserved_future_v2')
        reserved = flatten_numeric(cfg.reserved_future_v2);
        if any(reserved(:) == model_seed)
            error('fit_temporal_memory_seed:ReservedFutureSeed', ...
                'Reserved future-v2 model seed %g rejected.', model_seed);
        end
    end
end

function vals = flatten_numeric(S)
    vals = [];
    if isnumeric(S)
        vals = S(:)';
        return;
    end
    if ~isstruct(S) || numel(S) ~= 1
        return;
    end
    fn = fieldnames(S);
    for i = 1:numel(fn)
        vals = [vals, flatten_numeric(S.(fn{i}))]; %#ok<AGROW>
    end
end
