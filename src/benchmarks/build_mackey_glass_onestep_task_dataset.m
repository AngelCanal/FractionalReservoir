function task = build_mackey_glass_onestep_task_dataset(opts)
% BUILD_MACKEY_GLASS_ONESTEP_TASK_DATASET  Deterministic MG one-step task/split.
%
%   task = build_mackey_glass_onestep_task_dataset(opts)
%
% Pure helper shared by matched baselines and mackey_glass_benchmark. No model
% state may affect construction. Test targets never enter fitting or selection.

    if nargin < 1 || isempty(opts)
        opts = struct();
    end
    tau = local_get(opts, 'tau', 17);
    dt_mg = local_get(opts, 'dt_mg', 1.0);
    T = local_get(opts, 'T', 6000);
    discard = local_get(opts, 'discard', 1000);
    washout_steps = local_get(opts, 'washout_steps', 200);
    train_ratio = local_get(opts, 'train_ratio', 0.6);
    val_ratio = local_get(opts, 'val_ratio', 0.2);
    seed = local_get(opts, 'seed', 1);

    rng(seed);
    [t, x] = generate_mackey_glass('tau', tau, 'dt', dt_mg, ...
        'n_samples', T, 'discard', discard);
    U = x(1:end-1);
    Y = x(2:end);
    U = U(:);
    Y = Y(:);
    split = build_contiguous_ratio_split(size(U, 1), train_ratio, val_ratio, washout_steps);

    task = struct();
    task.task = 'mackey_glass_onestep';
    task.U = U;
    task.Y = Y;
    task.split = split;
    task.t = t;
    task.x = x;
    task.tau = tau;
    task.dt_mg = dt_mg;
    task.T = T;
    task.discard = discard;
    task.seed = seed;
    task.train_ratio = train_ratio;
    task.val_ratio = val_ratio;
    task.washout_steps = washout_steps;
    task.task_data_hash = canonical_sha256(struct( ...
        'U_hash', hash_numeric_array(U), ...
        'Y_hash', hash_numeric_array(Y), ...
        'x_hash', hash_numeric_array(x), ...
        'tau', tau, ...
        'dt_mg', dt_mg, ...
        'T', T, ...
        'discard', discard, ...
        'seed', seed));
    task.split_hash = split.split_hash;
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
