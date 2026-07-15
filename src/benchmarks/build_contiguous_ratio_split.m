function split = build_contiguous_ratio_split(n_timesteps, train_ratio, val_ratio, washout_steps)
% BUILD_CONTIGUOUS_RATIO_SPLIT  Deterministic train/val/test index blocks.
%
%   split = build_contiguous_ratio_split(n_timesteps, train_ratio, val_ratio, washout_steps)
%
% Matches SRNN_ESN.trainReadout contiguous ratio splits. Model state must not
% affect this construction. Test targets are never consulted.

    if nargin < 4
        washout_steps = 0;
    end
    n_timesteps = double(n_timesteps);
    n_train = floor(n_timesteps * train_ratio);
    n_val = floor(n_timesteps * val_ratio);
    n_test = n_timesteps - n_train - n_val;
    if n_test < 1
        error('build_contiguous_ratio_split:EmptyTestBlock', ...
            'Test block must have at least one sample.');
    end
    if washout_steps >= n_train
        error('build_contiguous_ratio_split:InvalidWashout', ...
            'washout_steps (%d) must be less than n_train (%d).', ...
            washout_steps, n_train);
    end

    split = struct();
    split.train_idx = (1:n_train)';
    split.val_idx = ((n_train + 1):(n_train + n_val))';
    split.test_idx = ((n_train + n_val + 1):n_timesteps)';
    split.washout_steps = washout_steps;
    split.n_train_after_washout = n_train - washout_steps;
    split.n_val = n_val;
    split.n_test = n_test;
    split.train_ratio = train_ratio;
    split.val_ratio = val_ratio;
    split.split_hash = hash_split_indices(split);
end

function hex = hash_split_indices(split)
    payload = struct( ...
        'train_idx', split.train_idx(:), ...
        'val_idx', split.val_idx(:), ...
        'test_idx', split.test_idx(:), ...
        'washout_steps', split.washout_steps);
    hex = canonical_sha256(payload);
end
