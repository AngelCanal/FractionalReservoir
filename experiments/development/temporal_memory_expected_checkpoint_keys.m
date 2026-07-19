function keys = temporal_memory_expected_checkpoint_keys(cfg)
%TEMPORAL_MEMORY_EXPECTED_CHECKPOINT_KEYS  Exact completed-key set for a config.
%
%   keys = temporal_memory_expected_checkpoint_keys(cfg)
%
% Production: 24 cell-seed + 1 shared-task + 3 conventional + 3 no-recurrent
% + 3 shuffled-target = 34 unique keys.

    cells = cfg.diagnostic_cell_names(:);
    seeds = cfg.model_seeds(:);
    keys = {};
    for is = 1:numel(seeds)
        seed = seeds(is);
        for ic = 1:numel(cells)
            keys{end+1} = temporal_memory_checkpoint_key('cell', cells{ic}, seed); %#ok<AGROW>
        end
        keys{end+1} = temporal_memory_checkpoint_key('conventional', seed);
        keys{end+1} = temporal_memory_checkpoint_key('no_recurrent', seed);
        keys{end+1} = temporal_memory_checkpoint_key('shuffled_target', seed);
    end
    keys{end+1} = temporal_memory_checkpoint_key('shared_task_controls');
    keys = keys(:);
end
