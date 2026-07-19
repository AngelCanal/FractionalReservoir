function validate_temporal_memory_conventional_artifact(run_dir, seed, cfg)
%VALIDATE_TEMPORAL_MEMORY_CONVENTIONAL_ARTIFACT  Fail-closed conventional check.
%
%   validate_temporal_memory_conventional_artifact(run_dir, seed, cfg)
%
% Used on resume so a completed conventional bundle is never silently replaced.

    path = fullfile(run_dir, 'shared', 'conventional', ...
        sprintf('seed_%d_conventional.mat', seed));
    if ~isfile(path)
        error('validate_temporal_memory_conventional_artifact:Missing', ...
            'Missing conventional bundle for seed %d.', seed);
    end
    S = load(path, 'conventional_bundle');
    b = S.conventional_bundle;
    cmb = cfg.conventional_memory_baseline;

    if local_get(b, 'n_candidates', NaN) ~= cmb.candidate_count
        error('validate_temporal_memory_conventional_artifact:Identity', ...
            'Conventional n_candidates mismatch for seed %d.', seed);
    end
    if ~isequal(b.selection_lags(:), cmb.selection_lags(:))
        error('validate_temporal_memory_conventional_artifact:Identity', ...
            'Conventional selection_lags mismatch for seed %d.', seed);
    end
    if ~isscalar(b.selected_candidate_index) || ~isfinite(b.selected_candidate_index)
        error('validate_temporal_memory_conventional_artifact:Identity', ...
            'Conventional selected_candidate_index must be one scalar.');
    end
    idx = [b.per_lag.selected_candidate_index];
    if ~all(idx == b.selected_candidate_index)
        error('validate_temporal_memory_conventional_artifact:Identity', ...
            'All lag rows must use the same selected candidate.');
    end
    if ~logical(b.same_reservoir_for_all_lags)
        error('validate_temporal_memory_conventional_artifact:Identity', ...
            'same_reservoir_for_all_lags must be true.');
    end
    if logical(b.test_targets_used_for_selection)
        error('validate_temporal_memory_conventional_artifact:Identity', ...
            'test_targets_used_for_selection must be false.');
    end
    if ~strcmp(char(local_get(b, 'provenance', '')), 'production') && ...
            ~logical(local_get(b, 'is_test_fixture', false))
        error('validate_temporal_memory_conventional_artifact:Identity', ...
            'Conventional provenance must be production (or explicit test fixture).');
    end

    recomputed = temporal_memory_conventional_bundle_content_hash(b);
    if isfield(b, 'bundle_content_hash') && ~isempty(b.bundle_content_hash)
        if ~strcmp(char(b.bundle_content_hash), recomputed)
            error('validate_temporal_memory_conventional_artifact:HashFail', ...
                ['Conventional bundle content hash failed for seed %d; ', ...
                 'resume stops rather than replacing.'], seed);
        end
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
