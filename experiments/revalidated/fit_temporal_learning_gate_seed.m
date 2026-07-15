function bundle = fit_temporal_learning_gate_seed(cfg, model_seed)
% FIT_TEMPORAL_LEARNING_GATE_SEED  Train/validation fits only (no test scoring).
%
%   bundle = fit_temporal_learning_gate_seed(cfg, model_seed)
%
% Separates fingerprinted train/validation fitting from test-target scoring so
% isolation tests can score frozen readouts against alternate test vectors.

    if nargin < 2 || ~isfinite(model_seed)
        error('fit_temporal_learning_gate_seed:InvalidSeed', 'model_seed is required.');
    end
    if ~isstruct(cfg) || ~isfield(cfg, 'temporal_learning_gate')
        error('fit_temporal_learning_gate_seed:InvalidCfg', ...
            'cfg.temporal_learning_gate is required.');
    end

    gate = cfg.temporal_learning_gate;
    k = gate.target_lag_steps;
    cell_spec = gate.reference_cell;
    lambda_grid = gate.lambda_grid(:);
    run_opts = struct( ...
        'reset_before', true, ...
        'update_internal_state', false, ...
        'ode_reltol', gate.ode_reltol, ...
        'ode_abstol', gate.ode_abstol, ...
        'dde_reltol', gate.dde_reltol, ...
        'dde_abstol', gate.dde_abstol);

    [params, ~] = build_ablation_params(cell_spec, model_seed, cfg);
    params.include_input = false;
    params.which_states = char(gate.feature_mode);

    esn = SRNN_ESN(params);
    params_nr = params;
    params_nr.W = zeros(size(params.W));
    esn_nr = SRNN_ESN(params_nr);

    splits = generate_temporal_gate_splits(gate);
    assert_split_independence(splits);

    [X_tr, Y_tr, n_tr] = run_split_features(esn, splits.train, k, run_opts, gate);
    [X_va, Y_va, n_va] = run_split_features(esn, splits.validation, k, run_opts, gate);
    [X_te, Y_te, n_te] = run_split_features(esn, splits.test, k, run_opts, gate);

    feature_dim = size(X_tr, 2);
    if feature_dim ~= gate.feature_dimension
        error('fit_temporal_learning_gate_seed:FeatureDimMismatch', ...
            'Expected feature_dimension %d, got %d.', gate.feature_dimension, feature_dim);
    end

    mesn_sel = select_ridge_lambda(X_tr, Y_tr, X_va, Y_va, lambda_grid);

    Xu_tr = splits.train.U_scored;
    Xu_va = splits.validation.U_scored;
    Xu_te = splits.test.U_scored;
    cur_sel = select_ridge_lambda(Xu_tr, Y_tr, Xu_va, Y_va, lambda_grid);

    [Xnr_tr, ~, ~] = run_split_features(esn_nr, splits.train, k, run_opts, gate);
    [Xnr_va, ~, ~] = run_split_features(esn_nr, splits.validation, k, run_opts, gate);
    [Xnr_te, ~, ~] = run_split_features(esn_nr, splits.test, k, run_opts, gate);
    nr_sel = select_ridge_lambda(Xnr_tr, Y_tr, Xnr_va, Y_va, lambda_grid);

    Y_tr_s = permute_with_seed(Y_tr, gate.shuffle_train_seed);
    Y_va_s = permute_with_seed(Y_va, gate.shuffle_validation_seed);
    sh_sel = select_ridge_lambda(X_tr, Y_tr_s, X_va, Y_va_s, lambda_grid);

    [Xh_tr, Xh_va, Xh_te] = history_design_matrices(splits, k);
    hist_sel = select_ridge_lambda(Xh_tr, Y_tr, Xh_va, Y_va, lambda_grid);

    bundle = struct();
    bundle.model_seed = model_seed;
    bundle.target_lag_steps = k;
    bundle.feature_mode = char(gate.feature_mode);
    bundle.feature_dimension = feature_dim;
    bundle.train_samples_used = n_tr;
    bundle.validation_samples_used = n_va;
    bundle.test_samples_used = n_te;
    bundle.lambda_grid = lambda_grid;
    bundle.mesn_sel = mesn_sel;
    bundle.cur_sel = cur_sel;
    bundle.nr_sel = nr_sel;
    bundle.sh_sel = sh_sel;
    bundle.hist_sel = hist_sel;
    bundle.X_te = X_te;
    bundle.Y_te_protocol = Y_te;
    bundle.Y_te_shuffled_protocol = permute_with_seed(Y_te, gate.shuffle_test_seed);
    bundle.Xu_te = Xu_te;
    bundle.Xnr_te = Xnr_te;
    bundle.Xh_te = Xh_te;
    bundle.W_in_hash = local_hash(esn.W_in);
    bundle.W_norm = norm(esn.W, 'fro');
    bundle.W_nr_norm = norm(esn_nr.W, 'fro');
    bundle.split_meta = capture_split_metadata(gate, splits);
end

function [X, Y, n_used] = run_split_features(esn, split, k, run_opts, gate)
    esn.resetState();
    [X_all, ~] = esn.runReservoir(split.U, run_opts);
    idx = split.scored_idx;
    X = X_all(idx, :);
    Y = split.Y_scored;
    n_used = numel(idx);
    if n_used < 10
        error('fit_temporal_learning_gate_seed:InsufficientSamples', ...
            'Usable sample count %d is insufficient.', n_used);
    end
    if any(~isfinite(X(:))) || any(~isfinite(Y(:)))
        error('fit_temporal_learning_gate_seed:NonFiniteFeatures', ...
            'Features or targets contain nonfinite values.');
    end
    %#ok<INUSD>
end

function splits = generate_temporal_gate_splits(gate)
    splits = struct();
    splits.train = make_one_split(gate, gate.train_input_seed, gate.train_samples);
    splits.validation = make_one_split(gate, gate.validation_input_seed, gate.validation_samples);
    splits.test = make_one_split(gate, gate.test_input_seed, gate.test_samples);
end

function split = make_one_split(gate, seed, n_samples)
    k = gate.target_lag_steps;
    wash = gate.washout_steps;
    L = wash + k + n_samples;
    stream = RandStream('mt19937ar', 'Seed', seed);
    U = gate.input_min + (gate.input_max - gate.input_min) * rand(stream, L, 1);
    [Y, scored_idx, U_scored] = construct_delayed_input_target(U, k, wash, n_samples);
    split = struct();
    split.seed = seed;
    split.U = U;
    split.scored_idx = scored_idx;
    split.Y_scored = Y;
    split.U_scored = U_scored;
    split.n_samples_used = numel(scored_idx);
    split.total_length = L;
end

function assert_split_independence(splits)
    seeds = [splits.train.seed, splits.validation.seed, splits.test.seed];
    if numel(unique(seeds)) ~= 3
        error('fit_temporal_learning_gate_seed:SeedCollision', ...
            'Train/validation/test input seeds must be distinct.');
    end
end

function [Xh_tr, Xh_va, Xh_te] = history_design_matrices(splits, k)
    Xh_tr = history_matrix(splits.train.U, splits.train.scored_idx, k);
    Xh_va = history_matrix(splits.validation.U, splits.validation.scored_idx, k);
    Xh_te = history_matrix(splits.test.U, splits.test.scored_idx, k);
end

function Xh = history_matrix(U, scored_idx, k)
    n = numel(scored_idx);
    Xh = zeros(n, k + 1);
    for j = 0:k
        Xh(:, j + 1) = U(scored_idx - j);
    end
end

function y = permute_with_seed(y_in, seed)
    stream = RandStream('mt19937ar', 'Seed', seed);
    y = y_in(randperm(stream, numel(y_in)));
    y = y(:);
end

function meta = capture_split_metadata(gate, splits)
    meta = struct();
    meta.split_seeds = struct( ...
        'train_input_seed', gate.train_input_seed, ...
        'validation_input_seed', gate.validation_input_seed, ...
        'test_input_seed', gate.test_input_seed, ...
        'shuffle_train_seed', gate.shuffle_train_seed, ...
        'shuffle_validation_seed', gate.shuffle_validation_seed, ...
        'shuffle_test_seed', gate.shuffle_test_seed);
    task_seeds = [gate.train_input_seed, gate.validation_input_seed, gate.test_input_seed];
    shuffle_seeds = [gate.shuffle_train_seed, gate.shuffle_validation_seed, ...
        gate.shuffle_test_seed];
    model_seeds = gate.model_seeds(:)';
    sequences_distinct = ~(isequal(splits.train.U, splits.validation.U) || ...
        isequal(splits.train.U, splits.test.U) || ...
        isequal(splits.validation.U, splits.test.U));
    meta.split_independence = struct( ...
        'task_seeds_distinct', numel(unique(task_seeds)) == 3, ...
        'shuffle_seeds_distinct', numel(unique(shuffle_seeds)) == 3, ...
        'model_seeds_disjoint_from_task_seeds', ...
            isempty(intersect(model_seeds, task_seeds)), ...
        'model_seeds_disjoint_from_shuffle_seeds', ...
            isempty(intersect(model_seeds, shuffle_seeds)), ...
        'sequences_distinct', sequences_distinct, ...
        'verified', true);
end

function h = local_hash(x)
    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(typecast(x(:), 'uint8'));
    digest = typecast(md.digest(), 'uint8');
    h = lower(sprintf('%02x', digest));
end
