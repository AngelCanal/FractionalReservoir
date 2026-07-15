function task = build_narma_task_dataset(opts)
% BUILD_NARMA_TASK_DATASET  Deterministic NARMA inputs, targets, and splits.
%
%   task = build_narma_task_dataset(opts)
%
% Pure helper shared by matched baselines and narma_benchmark. No model state
% may affect construction. Test targets never enter fitting or selection.

    if nargin < 1 || isempty(opts)
        opts = struct();
    end
    order = local_get(opts, 'order', 10);
    T = local_get(opts, 'T', 6000);
    washout_steps = local_get(opts, 'washout_steps', 200);
    train_ratio = local_get(opts, 'train_ratio', 0.6);
    val_ratio = local_get(opts, 'val_ratio', 0.2);
    seed = local_get(opts, 'seed', 1);
    u_range = local_get(opts, 'u_range', [0, 0.5]);

    if ~(order == 10 || order == 20)
        error('build_narma_task_dataset:InvalidOrder', 'order must be 10 or 20');
    end

    rng(seed);
    U = u_range(1) + (u_range(2) - u_range(1)) * rand(T, 1);
    Y = generate_narma_series(U, order);
    split = build_contiguous_ratio_split(size(U, 1), train_ratio, val_ratio, washout_steps);

    task = struct();
    task.task = 'narma';
    task.U = U;
    task.Y = Y;
    task.split = split;
    task.order = order;
    task.T = T;
    task.seed = seed;
    task.u_range = u_range(:);
    task.train_ratio = train_ratio;
    task.val_ratio = val_ratio;
    task.washout_steps = washout_steps;
    task.task_data_hash = canonical_sha256(struct( ...
        'U_hash', hash_numeric_array(U), ...
        'Y_hash', hash_numeric_array(Y), ...
        'order', order, ...
        'seed', seed, ...
        'u_range', u_range(:)));
    task.split_hash = split.split_hash;
end

function y = generate_narma_series(u, order)
    T = numel(u);
    y = zeros(T, 1);
    y(1:order) = 0.1;
    for t = order:(T-1)
        y_sum = sum(y((t-order+1):t));
        y(t+1) = 0.3*y(t) + 0.05*y(t)*y_sum + 1.5*u(t-order+1)*u(t) + 0.1;
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
