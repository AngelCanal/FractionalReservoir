function n = expected_temporal_memory_registry_entry_count(cfg)
%EXPECTED_TEMPORAL_MEMORY_REGISTRY_ENTRY_COUNT  Frozen registry geometry.
%
%   n = expected_temporal_memory_registry_entry_count(cfg)
%
% 3 shared artifacts + n_cells*n_seeds cell results + 3*n_seeds shared
% controls + 8 table artifacts + control_summary + diagnostic_result.

    n_cells = numel(cfg.diagnostic_cell_names(:));
    n_seeds = numel(cfg.model_seeds(:));
    n = 13 + n_seeds * (n_cells + 3);
end
