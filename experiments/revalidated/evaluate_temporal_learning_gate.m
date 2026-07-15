function result = evaluate_temporal_learning_gate(cfg, options)
% EVALUATE_TEMPORAL_LEARNING_GATE  Reservoir-dependent delayed-input gate.
%
%   result = evaluate_temporal_learning_gate(cfg)
%   result = evaluate_temporal_learning_gate(cfg, options)
%
% Asks: can MESN reservoir features reconstruct y(t)=u(t-k) for i.i.d. u with
% k>0 when raw input is excluded from the readout?
%
% This is an implementation-validity gate, not a confirmatory paper endpoint.
% Phase 4A ridge fitting is mandatory. include_input must be false.

    if nargin < 1 || ~isstruct(cfg)
        error('evaluate_temporal_learning_gate:InvalidCfg', 'cfg must be a struct.');
    end
    if nargin < 2 || isempty(options)
        options = struct();
    end
    if ~isfield(cfg, 'temporal_learning_gate')
        error('evaluate_temporal_learning_gate:MissingConfig', ...
            'cfg.temporal_learning_gate is required.');
    end

    gate = cfg.temporal_learning_gate;
    if ~logical(gate.enabled)
        error('evaluate_temporal_learning_gate:Disabled', ...
            'temporal_learning_gate.enabled must be true to evaluate.');
    end
    if ~strcmp(char(gate.protocol_version), 'temporal_learning_gate_v1')
        error('evaluate_temporal_learning_gate:BadVersion', ...
            'Unsupported protocol_version: %s', char(gate.protocol_version));
    end
    if logical(gate.include_input)
        error('evaluate_temporal_learning_gate:IncludeInputForbidden', ...
            'MESN temporal learning gate requires include_input=false.');
    end
    if ~(isfinite(gate.target_lag_steps) && gate.target_lag_steps > 0 && ...
            gate.target_lag_steps == floor(gate.target_lag_steps))
        error('evaluate_temporal_learning_gate:InvalidLag', ...
            'target_lag_steps must be a positive integer.');
    end

    dt = cfg.base.dt;
    target_lag_time = gate.target_lag_steps * dt;
    if isfield(gate, 'target_lag_time') && isfinite(gate.target_lag_time)
        if abs(gate.target_lag_time - target_lag_time) > 1e-12
            error('evaluate_temporal_learning_gate:LagTimeMismatch', ...
                'target_lag_time must equal target_lag_steps * dt.');
        end
    end

    model_seeds = gate.model_seeds(:)';
    n_seeds = numel(model_seeds);
    lambda_grid = gate.lambda_grid(:);
    thresholds = gate.thresholds;
    cell_spec = gate.reference_cell;
    run_opts = struct( ...
        'reset_before', true, ...
        'update_internal_state', false, ...
        'ode_reltol', gate.ode_reltol, ...
        'ode_abstol', gate.ode_abstol, ...
        'dde_reltol', gate.dde_reltol, ...
        'dde_abstol', gate.dde_abstol);

    mutate_test_target = [];
    if isfield(options, 'mutate_test_target') && ~isempty(options.mutate_test_target)
        mutate_test_target = options.mutate_test_target;
    end

    seed_results = cell(n_seeds, 1);
    failure_reasons = {};
    all_finite = true;
    split_meta = struct();
    split_meta.recorded = false;

    for i = 1:n_seeds
        seed = model_seeds(i);
        try
            [seed_results{i}, split_info] = evaluate_one_seed(cfg, gate, cell_spec, seed, ...
                lambda_grid, run_opts, dt, target_lag_time, mutate_test_target);
            if ~split_meta.recorded
                split_meta = split_info;
                split_meta.recorded = true;
            end
            if ~seed_results{i}.all_finite
                all_finite = false;
                failure_reasons{end+1} = sprintf('seed_%g_nonfinite', seed); %#ok<AGROW>
            end
        catch ME
            all_finite = false;
            failed = empty_seed_result();
            failed.model_seed = seed;
            failed.status = 'failed';
            failed.error_id = ME.identifier;
            failed.error_message = ME.message;
            failed.all_finite = false;
            seed_results{i} = failed;
            failure_reasons{end+1} = sprintf('seed_%g_error:%s', seed, ME.identifier); %#ok<AGROW>
        end
    end
    seed_results = [seed_results{:}];
    seed_results = seed_results(:);

    if ~split_meta.recorded
        splits = generate_temporal_gate_splits(gate);
        split_meta = capture_split_metadata(gate, splits);
        split_meta.recorded = true;
    end

    aggregate = aggregate_seed_results(seed_results, thresholds, n_seeds);
    controls_ok = seed_controls_present(seed_results);
    diagnostics_ok = seed_diagnostics_present(seed_results);
    gate_conditions = evaluate_gate_conditions(aggregate, gate, thresholds, ...
        all_finite, n_seeds, target_lag_time, split_meta, controls_ok, diagnostics_ok);
    failed = {};
    names = fieldnames(gate_conditions);
    for i = 1:numel(names)
        if ~logical(gate_conditions.(names{i}))
            failed{end+1} = names{i}; %#ok<AGROW>
        end
    end
    failure_reasons = unique([failure_reasons(:); failed(:)], 'stable');
    passed = isempty(failed) && all_finite;

    result = struct();
    result.protocol_version = char(gate.protocol_version);
    result.protocol_tier = char(cfg.protocol_tier);
    result.protocol_fingerprint = '';
    if isfield(cfg, 'protocol_fingerprint')
        result.protocol_fingerprint = char(cfg.protocol_fingerprint);
    end
    result.status = ternary(all(strcmp({seed_results.status}, 'ok')), 'complete', 'incomplete');
    if passed
        result.status = 'complete';
    elseif strcmp(result.status, 'complete') && ~passed
        result.status = 'complete'; % completed evaluation, gate failed
    end
    result.passed = passed;
    result.failure_reasons = failure_reasons(:)';

    result.include_input = false;
    result.feature_mode = char(gate.feature_mode);
    result.feature_dimension = gate.feature_dimension;
    result.target_definition = 'y(t)=u(t-k)';
    result.target_lag_steps = gate.target_lag_steps;
    result.dt = dt;
    result.target_lag_time = target_lag_time;
    result.input_distribution = char(gate.input_distribution);
    result.input_range = [gate.input_min, gate.input_max];
    result.washout_steps = gate.washout_steps;
    result.train_samples_requested = gate.train_samples;
    result.validation_samples_requested = gate.validation_samples;
    result.test_samples_requested = gate.test_samples;
    if n_seeds > 0 && strcmp(seed_results(1).status, 'ok')
        result.train_samples_used = seed_results(1).train_samples_used;
        result.validation_samples_used = seed_results(1).validation_samples_used;
        result.test_samples_used = seed_results(1).test_samples_used;
    else
        result.train_samples_used = NaN;
        result.validation_samples_used = NaN;
        result.test_samples_used = NaN;
    end
    result.model_seeds = model_seeds;
    result.train_input_seed = gate.train_input_seed;
    result.validation_input_seed = gate.validation_input_seed;
    result.test_input_seed = gate.test_input_seed;
    result.shuffle_train_seed = gate.shuffle_train_seed;
    result.shuffle_validation_seed = gate.shuffle_validation_seed;
    result.shuffle_test_seed = gate.shuffle_test_seed;
    result.split_seeds = split_meta.split_seeds;
    result.split_independence = split_meta.split_independence;
    result.lambda_grid = lambda_grid;
    result.thresholds = thresholds;
    result.reference_cell_key = char(gate.reference_cell_key);
    result.controls = gate.controls;
    result.seed_results = seed_results;
    result.aggregate_results = aggregate;
    result.gate_conditions = gate_conditions;
end

function [seed, split_meta] = evaluate_one_seed(cfg, gate, cell_spec, model_seed, lambda_grid, ...
        run_opts, dt, target_lag_time, mutate_test_target)
    k = gate.target_lag_steps;
    [params, ~] = build_ablation_params(cell_spec, model_seed, cfg);
    params.include_input = false;
    params.which_states = char(gate.feature_mode);

    esn = SRNN_ESN(params);
    if logical(esn.include_input)
        error('evaluate_temporal_learning_gate:IncludeInputAssert', ...
            'include_input must be false after construction.');
    end

    params_nr = params;
    params_nr.W = zeros(size(params.W));
    esn_nr = SRNN_ESN(params_nr);
    if any(esn_nr.W(:) ~= 0)
        error('evaluate_temporal_learning_gate:NonzeroRecurrence', ...
            'no_recurrent_coupling_control W must be identically zero.');
    end
    if ~isempty(esn_nr.W_components)
        for c = 1:numel(esn_nr.W_components)
            if any(esn_nr.W_components{c}(:) ~= 0)
                error('evaluate_temporal_learning_gate:NonzeroDelayedRecurrence', ...
                    'Delayed recurrent components must rebuild to zero.');
            end
        end
    end
    if ~isequal(esn_nr.W_in, esn.W_in)
        error('evaluate_temporal_learning_gate:WinMismatch', ...
            'no_recurrent_coupling_control must preserve W_in.');
    end

    splits = generate_temporal_gate_splits(gate);
    assert_split_independence(splits);
    split_meta = capture_split_metadata(gate, splits);

    [X_tr, Y_tr, n_tr] = run_split_features(esn, splits.train, k, run_opts, gate);
    [X_va, Y_va, n_va] = run_split_features(esn, splits.validation, k, run_opts, gate);
    [X_te, Y_te, n_te] = run_split_features(esn, splits.test, k, run_opts, gate);

    feature_dim = size(X_tr, 2);
    if feature_dim ~= gate.feature_dimension
        error('evaluate_temporal_learning_gate:FeatureDimMismatch', ...
            'Expected feature_dimension %d, got %d.', gate.feature_dimension, feature_dim);
    end
    if size(X_tr, 2) ~= params.n
        error('evaluate_temporal_learning_gate:UnexpectedInputColumn', ...
            'MESN design matrix must contain only reservoir features (n columns).');
    end

    % MESN fit (train/validation only; test target never enters selection)
    mesn_sel = select_ridge_lambda(X_tr, Y_tr, X_va, Y_va, lambda_grid);
    mesn_model = mesn_sel.selected_model;

    % Current-input-only control
    Xu_tr = splits.train.U_scored;
    Xu_va = splits.validation.U_scored;
    Xu_te = splits.test.U_scored;
    cur_sel = select_ridge_lambda(Xu_tr, Y_tr, Xu_va, Y_va, lambda_grid);
    if size(Xu_tr, 2) ~= 1
        error('evaluate_temporal_learning_gate:CurrentControlDim', ...
            'current_input_only_control must have exactly one feature column.');
    end

    % No-recurrent-coupling control
    [Xnr_tr, ~, ~] = run_split_features(esn_nr, splits.train, k, run_opts, gate);
    [Xnr_va, ~, ~] = run_split_features(esn_nr, splits.validation, k, run_opts, gate);
    [Xnr_te, ~, ~] = run_split_features(esn_nr, splits.test, k, run_opts, gate);
    nr_sel = select_ridge_lambda(Xnr_tr, Y_tr, Xnr_va, Y_va, lambda_grid);

    % Shuffled-target negative control (shuffle train/val before fit)
    Y_tr_s = permute_with_seed(Y_tr, gate.shuffle_train_seed);
    Y_va_s = permute_with_seed(Y_va, gate.shuffle_validation_seed);
    Y_te_s = permute_with_seed(Y_te, gate.shuffle_test_seed);
    sh_sel = select_ridge_lambda(X_tr, Y_tr_s, X_va, Y_va_s, lambda_grid);

    % Exact-lag history positive control
    [Xh_tr, Xh_va, Xh_te] = history_design_matrices(splits, k);
    if size(Xh_tr, 2) ~= k + 1
        error('evaluate_temporal_learning_gate:HistoryWidth', ...
            'Exact-lag history must have k+1 columns.');
    end
    % Column k+1 is u(t-k)
    if max(abs(Xh_tr(:, end) - Y_tr)) > 1e-14
        error('evaluate_temporal_learning_gate:HistoryLagColumn', ...
            'Last history column must equal u(t-k).');
    end
    hist_sel = select_ridge_lambda(Xh_tr, Y_tr, Xh_va, Y_va, lambda_grid);

    % Optional test-only mutation for isolation tests (after all fits).
    if ~isempty(mutate_test_target)
        Y_te = mutate_test_target(Y_te);
        Y_te_s = permute_with_seed(Y_te, gate.shuffle_test_seed);
    end

    mesn_pred = apply_ridge_readout(mesn_model, X_te);
    mesn_metrics = compute_gate_metrics(mesn_pred, Y_te);
    cur_pred = apply_ridge_readout(cur_sel.selected_model, Xu_te);
    cur_metrics = compute_gate_metrics(cur_pred, Y_te);
    nr_pred = apply_ridge_readout(nr_sel.selected_model, Xnr_te);
    nr_metrics = compute_gate_metrics(nr_pred, Y_te);
    sh_pred = apply_ridge_readout(sh_sel.selected_model, X_te);
    sh_metrics = compute_gate_metrics(sh_pred, Y_te_s);
    hist_pred = apply_ridge_readout(hist_sel.selected_model, Xh_te);
    hist_metrics = compute_gate_metrics(hist_pred, Y_te);

    seed = empty_seed_result();
    seed.model_seed = model_seed;
    seed.status = 'ok';
    seed.target_lag_steps = k;
    seed.target_lag_time = target_lag_time;
    seed.dt = dt;
    seed.include_input = false;
    seed.feature_mode = char(gate.feature_mode);
    seed.feature_dimension = feature_dim;
    seed.train_samples_used = n_tr;
    seed.validation_samples_used = n_va;
    seed.test_samples_used = n_te;
    seed.mesn = pack_fit(mesn_sel, mesn_metrics, mesn_pred, lambda_grid);
    seed.current_input_only_control = pack_fit(cur_sel, cur_metrics, cur_pred, lambda_grid);
    seed.no_recurrent_coupling_control = pack_fit(nr_sel, nr_metrics, nr_pred, lambda_grid);
    seed.shuffled_target_control = pack_fit(sh_sel, sh_metrics, sh_pred, lambda_grid);
    seed.exact_history_control = pack_fit(hist_sel, hist_metrics, hist_pred, lambda_grid);
    seed.delta_vs_current_nrmse = cur_metrics.nrmse - mesn_metrics.nrmse;
    seed.delta_vs_no_recurrence_nrmse = nr_metrics.nrmse - mesn_metrics.nrmse;
    seed.beats_current = seed.delta_vs_current_nrmse > 0;
    seed.beats_no_recurrence = seed.delta_vs_no_recurrence_nrmse > 0;
    seed.all_finite = all_metrics_finite(seed);
    seed.W_in_hash = local_hash(esn.W_in);
    seed.W_norm = norm(esn.W, 'fro');
    seed.W_nr_norm = norm(esn_nr.W, 'fro');
end

function [X, Y, n_used] = run_split_features(esn, split, k, run_opts, gate)
    esn.resetState();
    [X_all, ~] = esn.runReservoir(split.U, run_opts);
    if logical(esn.include_input)
        error('evaluate_temporal_learning_gate:IncludeInputRuntime', ...
            'MESN include_input became true during feature extraction.');
    end
    idx = split.scored_idx;
    X = X_all(idx, :);
    Y = split.Y_scored;
    n_used = numel(idx);
    if n_used < 10
        error('evaluate_temporal_learning_gate:InsufficientSamples', ...
            'Usable sample count %d is insufficient.', n_used);
    end
    if size(X, 1) ~= size(Y, 1)
        error('evaluate_temporal_learning_gate:XYMismatch', 'Feature/target rows mismatch.');
    end
    if any(~isfinite(X(:))) || any(~isfinite(Y(:)))
        error('evaluate_temporal_learning_gate:NonFiniteFeatures', ...
            'Features or targets contain nonfinite values.');
    end
    % Constant-feature collapse check
    if all(std(X, 0, 1) < sqrt(eps))
        error('evaluate_temporal_learning_gate:ConstantFeatures', ...
            'Feature matrix is numerically constant.');
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
        error('evaluate_temporal_learning_gate:SeedCollision', ...
            'Train/validation/test input seeds must be distinct.');
    end
    if isequal(splits.train.U, splits.validation.U) || ...
            isequal(splits.train.U, splits.test.U) || ...
            isequal(splits.validation.U, splits.test.U)
        error('evaluate_temporal_learning_gate:SequenceCollision', ...
            'Train/validation/test sequences must be distinct realizations.');
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

function m = compute_gate_metrics(y_hat, y)
    y_hat = y_hat(:);
    y = y(:);
    if any(~isfinite(y_hat)) || any(~isfinite(y))
        error('evaluate_temporal_learning_gate:NonFinitePrediction', ...
            'Predictions or targets are nonfinite.');
    end
    if std(y, 1) == 0
        error('evaluate_temporal_learning_gate:ZeroTargetVariance', ...
            'Target variance is zero.');
    end
    rmse = sqrt(mean((y_hat - y).^2));
    nrmse = rmse / std(y, 1);
    ss_res = sum((y_hat - y).^2);
    ss_tot = sum((y - mean(y)).^2);
    r2 = 1 - ss_res / ss_tot;
    if std(y_hat, 1) > 0 && std(y, 1) > 0
        C = corrcoef(y_hat, y);
        pearson = C(1, 2);
    else
        pearson = NaN;
    end
    if any(~isfinite([rmse, nrmse, r2]))
        error('evaluate_temporal_learning_gate:NonFiniteMetric', ...
            'Required metrics are nonfinite.');
    end
    m = struct('rmse', rmse, 'nrmse', nrmse, 'r2', r2, 'pearson', pearson);
end

function pack = pack_fit(selection, metrics, y_hat, lambda_grid)
    model = selection.selected_model;
    pack = struct();
    pack.metrics = metrics;
    pack.selected_lambda = selection.selected_lambda;
    pack.selected_val_score = selection.selected_val_score;
    pack.ridge = extract_ridge_diagnostics(model);
    pack.y_hat_finite = all(isfinite(y_hat(:)));
    pack.fit_status = 'ok';
    pack.lambda_selection_table = compact_lambda_selection_table(selection);
    grid = lambda_grid(:);
    if isempty(grid)
        grid = selection.lambda_grid(:);
    end
    pack.selected_at_grid_boundary = isfinite(selection.selected_lambda) && ...
        (selection.selected_lambda == min(grid) || selection.selected_lambda == max(grid));
end

function rows = compact_lambda_selection_table(selection)
    src = selection.table;
    n = numel(src);
    rows = repmat(struct( ...
        'candidate_lambda', NaN, ...
        'validation_nrmse', NaN, ...
        'status', 'rejected', ...
        'numerical_rank', NaN, ...
        'coefficient_norm', NaN, ...
        'selected_candidate', false), n, 1);
    for i = 1:n
        rows(i).candidate_lambda = src(i).lambda;
        if isfinite(src(i).val_score)
            rows(i).validation_nrmse = src(i).val_score;
        elseif ~isempty(src(i).val_nrmse)
            rows(i).validation_nrmse = mean(src(i).val_nrmse);
        else
            rows(i).validation_nrmse = NaN;
        end
        if logical(src(i).accepted)
            rows(i).status = 'accepted';
        else
            rows(i).status = 'rejected';
        end
        rows(i).numerical_rank = src(i).numerical_rank;
        rows(i).coefficient_norm = src(i).coefficient_norm;
        rows(i).selected_candidate = logical(src(i).accepted) && ...
            isfinite(src(i).lambda) && isfinite(selection.selected_lambda) && ...
            src(i).lambda == selection.selected_lambda;
    end
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

function tf = seed_controls_present(seed_results)
    required = {'current_input_only_control', 'no_recurrent_coupling_control', ...
        'shuffled_target_control', 'exact_history_control'};
    tf = ~isempty(seed_results);
    for i = 1:numel(seed_results)
        if ~strcmp(seed_results(i).status, 'ok')
            tf = false;
            return;
        end
        for c = 1:numel(required)
            name = required{c};
            if ~isfield(seed_results(i), name)
                tf = false;
                return;
            end
            fit = seed_results(i).(name);
            if ~isstruct(fit) || ~isfield(fit, 'fit_status') || ...
                    ~strcmp(char(fit.fit_status), 'ok') || ...
                    ~isfield(fit, 'metrics')
                tf = false;
                return;
            end
        end
        if ~isfield(seed_results(i), 'mesn') || ...
                ~strcmp(char(seed_results(i).mesn.fit_status), 'ok')
            tf = false;
            return;
        end
    end
end

function tf = seed_diagnostics_present(seed_results)
    fit_names = {'mesn', 'current_input_only_control', 'no_recurrent_coupling_control', ...
        'shuffled_target_control', 'exact_history_control'};
    required_finite = {'numerical_rank', 'coefficient_norm', 'lambda', 'intercept'};
    tf = ~isempty(seed_results);
    for i = 1:numel(seed_results)
        if ~strcmp(seed_results(i).status, 'ok')
            tf = false;
            return;
        end
        for f = 1:numel(fit_names)
            fit = seed_results(i).(fit_names{f});
            if ~isfield(fit, 'ridge') || ~isstruct(fit.ridge) || ...
                    ~isfield(fit, 'lambda_selection_table') || ...
                    isempty(fit.lambda_selection_table) || ...
                    ~isfield(fit, 'selected_at_grid_boundary')
                tf = false;
                return;
            end
            d = fit.ridge;
            if ~isfield(d, 'solver_method') || isempty(char(string(d.solver_method)))
                tf = false;
                return;
            end
            for r = 1:numel(required_finite)
                name = required_finite{r};
                if ~isfield(d, name) || any(~isfinite(d.(name)(:)))
                    tf = false;
                    return;
                end
            end
            if ~isfield(d, 'feature_mean') || ~isfield(d, 'feature_scale') || ...
                    any(~isfinite(d.feature_mean(:))) || any(~isfinite(d.feature_scale(:)))
                tf = false;
                return;
            end
        end
    end
end

function d = extract_ridge_diagnostics(model)
    d = struct();
    d.solver_method = local_field(model, 'solver_method', '');
    d.lambda = model.lambda;
    d.n_samples = local_field(model, 'n_samples', NaN);
    d.n_features = model.n_features;
    d.numerical_rank = local_field(model, 'numerical_rank', NaN);
    d.rank_tolerance = local_field(model, 'rank_tolerance', NaN);
    d.singular_values = local_field(model, 'singular_values', []);
    d.largest_singular_value = local_field(model, 'largest_singular_value', NaN);
    d.smallest_retained_singular_value = ...
        local_field(model, 'smallest_retained_singular_value', NaN);
    d.raw_condition_estimate = local_field(model, 'raw_condition_estimate', NaN);
    d.regularized_condition_estimate = ...
        local_field(model, 'regularized_condition_estimate', NaN);
    d.conditioning_status = local_field(model, 'conditioning_status', '');
    d.coefficient_norm = local_field(model, 'coefficient_norm', NaN);
    d.zero_variance_mask = local_field(model, 'zero_variance_mask', ...
        local_field(model, 'constant_feature', false(1, model.n_features)));
    d.n_zero_variance_features = local_field(model, 'n_zero_variance_features', ...
        nnz(d.zero_variance_mask));
    d.feature_mean = local_field(model, 'feature_mean', model.mu);
    d.feature_scale = local_field(model, 'feature_scale', model.sigma);
    d.target_mean = local_field(model, 'target_mean', model.intercept);
    d.intercept = model.intercept;
    d.coefficients = model.coefficients;
end

function tf = all_metrics_finite(seed)
    names = {'mesn', 'current_input_only_control', 'no_recurrent_coupling_control', ...
        'shuffled_target_control', 'exact_history_control'};
    tf = true;
    for i = 1:numel(names)
        m = seed.(names{i}).metrics;
        if ~all(isfinite([m.rmse, m.nrmse, m.r2])) || ...
                ~isfinite(seed.(names{i}).selected_lambda) || ...
                ~seed.(names{i}).y_hat_finite
            tf = false;
            return;
        end
    end
    tf = tf && isfinite(seed.delta_vs_current_nrmse) && ...
        isfinite(seed.delta_vs_no_recurrence_nrmse);
end

function agg = aggregate_seed_results(seed_results, thresholds, n_requested)
    ok = strcmp({seed_results.status}, 'ok');
    n_ok = nnz(ok);
    agg = struct();
    agg.n_seeds_requested = n_requested;
    agg.n_seeds_completed = n_ok;

    metric_names = {'mesn', 'current_input_only_control', ...
        'no_recurrent_coupling_control', 'shuffled_target_control', ...
        'exact_history_control'};
    fields = {'nrmse', 'r2', 'rmse'};
    for mi = 1:numel(metric_names)
        for fi = 1:numel(fields)
            vals = nan(n_requested, 1);
            for i = 1:n_requested
                if ok(i)
                    vals(i) = seed_results(i).(metric_names{mi}).metrics.(fields{fi});
                end
            end
            agg.([metric_names{mi} '_' fields{fi}]) = summarize_vec(vals);
        end
        lams = nan(n_requested, 1);
        for i = 1:n_requested
            if ok(i)
                lams(i) = seed_results(i).(metric_names{mi}).selected_lambda;
            end
        end
        agg.([metric_names{mi} '_selected_lambda']) = summarize_vec(lams);
    end

    d_cur = nan(n_requested, 1);
    d_nr = nan(n_requested, 1);
    beat_cur = false(n_requested, 1);
    beat_nr = false(n_requested, 1);
    for i = 1:n_requested
        if ok(i)
            d_cur(i) = seed_results(i).delta_vs_current_nrmse;
            d_nr(i) = seed_results(i).delta_vs_no_recurrence_nrmse;
            beat_cur(i) = seed_results(i).beats_current;
            beat_nr(i) = seed_results(i).beats_no_recurrence;
        end
    end
    agg.delta_vs_current_nrmse = summarize_vec(d_cur);
    agg.delta_vs_no_recurrence_nrmse = summarize_vec(d_nr);
    agg.fraction_beating_current = mean(beat_cur(ok));
    agg.fraction_beating_no_recurrence = mean(beat_nr(ok));
    agg.n_beating_current = nnz(beat_cur & ok(:));
    agg.n_beating_no_recurrence = nnz(beat_nr & ok(:));
    agg.thresholds = thresholds;
end

function s = summarize_vec(vals)
    v = vals(isfinite(vals));
    s = struct();
    if isempty(v)
        s.median = NaN;
        s.iqr = NaN;
        s.mean = NaN;
        s.values = vals(:)';
        return;
    end
    s.median = median(v);
    s.iqr = local_iqr(v);
    s.mean = mean(v);
    s.values = vals(:)';
end

function q = local_iqr(v)
    v = sort(v(:));
    n = numel(v);
    if n == 0
        q = NaN;
        return;
    end
    q1 = v(max(1, ceil(0.25 * n)));
    q3 = v(max(1, ceil(0.75 * n)));
    q = q3 - q1;
end

function gc = evaluate_gate_conditions(agg, gate, thr, all_finite, n_seeds, target_lag_time, ...
        split_meta, controls_ok, diagnostics_ok)
    gc = struct();
    gc.all_fits_and_metrics_finite = all_finite && ...
        isfinite(agg.mesn_nrmse.median) && isfinite(agg.mesn_r2.median);
    gc.include_input_false = ~logical(gate.include_input);
    gc.target_lag_positive = gate.target_lag_steps > 0;
    gc.target_lag_time_consistent = abs(target_lag_time - gate.target_lag_steps * gate.dt) <= 1e-12;
    if nargin >= 7 && isstruct(split_meta) && isfield(split_meta, 'split_independence')
        si = split_meta.split_independence;
        gc.splits_independent = logical(si.task_seeds_distinct) && ...
            logical(si.sequences_distinct) && logical(si.verified);
    else
        gc.splits_independent = false;
    end
    gc.mesn_median_nrmse_ok = isfinite(agg.mesn_nrmse.median) && ...
        agg.mesn_nrmse.median <= thr.mesn_median_nrmse_max;
    gc.mesn_median_r2_ok = isfinite(agg.mesn_r2.median) && ...
        agg.mesn_r2.median >= thr.mesn_median_r2_min;
    gc.median_delta_vs_current_ok = isfinite(agg.delta_vs_current_nrmse.median) && ...
        agg.delta_vs_current_nrmse.median >= thr.median_delta_vs_current_min;
    gc.fraction_beating_current_ok = isfinite(agg.fraction_beating_current) && ...
        agg.fraction_beating_current >= thr.fraction_beating_current_min;
    gc.median_delta_vs_no_recurrence_ok = isfinite(agg.delta_vs_no_recurrence_nrmse.median) && ...
        agg.delta_vs_no_recurrence_nrmse.median >= thr.median_delta_vs_no_recurrence_min;
    gc.fraction_beating_no_recurrence_ok = isfinite(agg.fraction_beating_no_recurrence) && ...
        agg.fraction_beating_no_recurrence >= thr.fraction_beating_no_recurrence_min;
    gc.shuffled_median_nrmse_ok = isfinite(agg.shuffled_target_control_nrmse.median) && ...
        agg.shuffled_target_control_nrmse.median >= thr.shuffled_median_nrmse_min;
    gc.exact_history_median_nrmse_ok = isfinite(agg.exact_history_control_nrmse.median) && ...
        agg.exact_history_control_nrmse.median <= thr.exact_history_median_nrmse_max;
    gc.seed_rows_complete = agg.n_seeds_completed == n_seeds;
    if nargin >= 8
        gc.controls_present = logical(controls_ok);
    else
        gc.controls_present = false;
    end
    if nargin >= 9
        gc.diagnostics_present = logical(diagnostics_ok);
    else
        gc.diagnostics_present = false;
    end
end

function s = empty_seed_result()
    blank_fit = struct( ...
        'metrics', struct('rmse', NaN, 'nrmse', NaN, 'r2', NaN, 'pearson', NaN), ...
        'selected_lambda', NaN, ...
        'selected_val_score', NaN, ...
        'ridge', struct(), ...
        'y_hat_finite', false, ...
        'fit_status', 'missing');
    s = struct();
    s.model_seed = NaN;
    s.status = 'missing';
    s.error_id = '';
    s.error_message = '';
    s.all_finite = false;
    s.target_lag_steps = NaN;
    s.target_lag_time = NaN;
    s.dt = NaN;
    s.include_input = false;
    s.feature_mode = '';
    s.feature_dimension = NaN;
    s.train_samples_used = NaN;
    s.validation_samples_used = NaN;
    s.test_samples_used = NaN;
    s.mesn = blank_fit;
    s.current_input_only_control = blank_fit;
    s.no_recurrent_coupling_control = blank_fit;
    s.shuffled_target_control = blank_fit;
    s.exact_history_control = blank_fit;
    s.delta_vs_current_nrmse = NaN;
    s.delta_vs_no_recurrence_nrmse = NaN;
    s.beats_current = false;
    s.beats_no_recurrence = false;
    s.W_in_hash = '';
    s.W_norm = NaN;
    s.W_nr_norm = NaN;
end

function v = local_field(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end

function out = ternary(cond, a, b)
    if cond
        out = a;
    else
        out = b;
    end
end

function h = local_hash(x)
    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(typecast(x(:), 'uint8'));
    digest = typecast(md.digest(), 'uint8');
    h = lower(sprintf('%02x', digest));
end
