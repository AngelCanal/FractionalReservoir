function splits = build_temporal_memory_development_splits(cfg, options)
%BUILD_TEMPORAL_MEMORY_DEVELOPMENT_SPLITS  Independent train/val/test inputs.
%
%   splits = build_temporal_memory_development_splits(cfg)
%   splits = build_temporal_memory_development_splits(cfg, options)
%
% For every split:
%   length = washout + max_lag + requested_samples
%
% Uses local mt19937ar RandStream objects only. Does not mutate the global RNG.
% Scored indices leave sufficient history for every lag in cfg.lags (max 50).

    if nargin < 1 || ~isstruct(cfg)
        error('build_temporal_memory_development_splits:InvalidCfg', ...
            'cfg must be a struct.');
    end
    if nargin < 2 || isempty(options)
        options = struct();
    end

    wash = local_get(cfg.lengths, 'washout_steps', 200);
    max_lag = max(cfg.lags(:));
    n_train = local_get(cfg.lengths, 'train_samples', 4000);
    n_val = local_get(cfg.lengths, 'validation_samples', 1000);
    n_test = local_get(cfg.lengths, 'test_samples', 2000);

    if isfield(options, 'washout_steps'); wash = options.washout_steps; end
    if isfield(options, 'train_samples'); n_train = options.train_samples; end
    if isfield(options, 'validation_samples'); n_val = options.validation_samples; end
    if isfield(options, 'test_samples'); n_test = options.test_samples; end
    if isfield(options, 'max_lag'); max_lag = options.max_lag; end

    task = cfg.task_seeds;
    if isfield(options, 'task_seeds'); task = options.task_seeds; end

    assert_seed_roles_allowed(cfg, task);

    global_before = RandStream.getGlobalStream().State;

    splits = struct();
    splits.train = make_split(task.train, wash, max_lag, n_train, cfg);
    splits.validation = make_split(task.validation, wash, max_lag, n_val, cfg);
    splits.test = make_split(task.test, wash, max_lag, n_test, cfg);
    splits.max_lag = max_lag;
    splits.washout_steps = wash;
    splits.lags = cfg.lags(:)';

    seeds = [splits.train.seed, splits.validation.seed, splits.test.seed];
    if numel(unique(seeds)) ~= 3
        error('build_temporal_memory_development_splits:SeedCollision', ...
            'Train, validation, and test seeds must be distinct.');
    end
    if isequal(splits.train.U, splits.validation.U) || ...
            isequal(splits.train.U, splits.test.U) || ...
            isequal(splits.validation.U, splits.test.U)
        error('build_temporal_memory_development_splits:SequenceCollision', ...
            'Train, validation, and test sequences must be distinct.');
    end
    if splits.train.n_samples_used ~= n_train || ...
            splits.validation.n_samples_used ~= n_val || ...
            splits.test.n_samples_used ~= n_test
        error('build_temporal_memory_development_splits:SampleCount', ...
            'Exact requested sample counts were not obtained.');
    end

    global_after = RandStream.getGlobalStream().State;
    if ~isequal(global_before, global_after)
        error('build_temporal_memory_development_splits:GlobalRNGMutated', ...
            'Global RNG state must be unchanged.');
    end
    splits.global_rng_unchanged = true;
end

function split = make_split(seed, wash, max_lag, n_samples, cfg)
    L = wash + max_lag + n_samples;
    stream = RandStream('mt19937ar', 'Seed', seed);
    U = cfg.input_min + (cfg.input_max - cfg.input_min) * rand(stream, L, 1);
    if size(U, 2) ~= 1
        error('build_temporal_memory_development_splits:InputDim', ...
            'Input dimension must be one.');
    end
    if any(~isfinite(U))
        error('build_temporal_memory_development_splits:NonFinite', ...
            'Generated inputs contain nonfinite values.');
    end
    scored_idx = ((wash + max_lag + 1):L)';
    split = struct();
    split.seed = seed;
    split.U = U;
    split.scored_idx = scored_idx;
    split.U_scored = U(scored_idx);
    split.n_samples_used = numel(scored_idx);
    split.total_length = L;
    split.washout_steps = wash;
    split.max_lag = max_lag;
end

function assert_seed_roles_allowed(cfg, task)
    executed = [task.train, task.validation, task.test];
    if any(executed == 9003)
        error('build_temporal_memory_development_splits:ForbiddenSeed9003', ...
            'v1 test seed 9003 is forbidden in development splits.');
    end
    if isfield(cfg, 'forbidden_executed_seeds')
        bad = intersect(executed, cfg.forbidden_executed_seeds(:)');
        if ~isempty(bad)
            error('build_temporal_memory_development_splits:ForbiddenSeed', ...
                'Forbidden executed seed(s): %s', mat2str(bad));
        end
    end
    if isfield(cfg, 'reserved_future_v2')
        reserved = flatten_numeric(cfg.reserved_future_v2);
        bad = intersect(executed, reserved(:)');
        if ~isempty(bad)
            error('build_temporal_memory_development_splits:ReservedFutureSeed', ...
                'Reserved future-v2 seed(s) rejected: %s', mat2str(bad));
        end
    end
end

function vals = flatten_numeric(S)
    vals = [];
    if isnumeric(S)
        vals = S(:)';
        return;
    end
    if ~isstruct(S)
        return;
    end
    if numel(S) ~= 1
        for i = 1:numel(S)
            vals = [vals, flatten_numeric(S(i))]; %#ok<AGROW>
        end
        return;
    end
    fn = fieldnames(S);
    for i = 1:numel(fn)
        vals = [vals, flatten_numeric(S.(fn{i}))]; %#ok<AGROW>
    end
end

function v = local_get(S, name, default)
    if isstruct(S) && isfield(S, name) && ~isempty(S.(name))
        v = S.(name);
    else
        v = default;
    end
end
