function validate_temporal_memory_artifact_registry(registry, run_dir, cfg, expected_keys)
%VALIDATE_TEMPORAL_MEMORY_ARTIFACT_REGISTRY  Fail-closed registry checks.
%
%   validate_temporal_memory_artifact_registry(registry, run_dir, cfg, expected_keys)

    if ~isstruct(registry) || ~strcmp(char(local_get(registry, 'schema_version', '')), ...
            'temporal_memory_artifact_registry_v1')
        error('validate_temporal_memory_artifact_registry:Schema', ...
            'Unexpected artifact registry schema.');
    end
    entries = local_get(registry, 'entries', []);
    if isempty(entries)
        error('validate_temporal_memory_artifact_registry:Empty', ...
            'Artifact registry has no entries.');
    end

    paths = cell(numel(entries), 1);
    for i = 1:numel(entries)
        e = entries(i);
        rel = char(e.relative_path);
        paths{i} = rel;
        if isempty(rel) || startsWith(rel, '/') || startsWith(rel, '\') || ...
                ~isempty(regexp(rel, '^[A-Za-z]:', 'once'))
            error('validate_temporal_memory_artifact_registry:AbsolutePath', ...
                'Registry must not contain absolute paths: %s', rel);
        end
        if contains(rel, '..')
            error('validate_temporal_memory_artifact_registry:PathTraversal', ...
                'Registry path traversal forbidden: %s', rel);
        end
        abs_path = fullfile(run_dir, strrep(rel, '/', filesep));
        if ~isfile(abs_path)
            error('validate_temporal_memory_artifact_registry:MissingFile', ...
                'Registered artifact missing on disk: %s', rel);
        end
        got_bin = temporal_memory_file_sha256(abs_path);
        if ~strcmp(got_bin, char(e.binary_sha256))
            error('validate_temporal_memory_artifact_registry:BinaryHashMismatch', ...
                'Binary file hash changed for %s.', rel);
        end
    end

    if numel(paths) ~= numel(unique(paths))
        error('validate_temporal_memory_artifact_registry:DuplicatePath', ...
            'Duplicate relative paths in artifact registry.');
    end

    expected = expected_registry_paths(cfg);
    missing = setdiff(expected, paths);
    unknown = setdiff(paths, expected);
    if ~isempty(missing)
        error('validate_temporal_memory_artifact_registry:MissingEntry', ...
            'Missing registry entries: %s', strjoin(missing, ', '));
    end
    if ~isempty(unknown)
        error('validate_temporal_memory_artifact_registry:UnknownEntry', ...
            'Unknown registry entries: %s', strjoin(unknown, ', '));
    end

    fresh = build_temporal_memory_artifact_registry(run_dir, cfg, struct());
    if ~strcmp(char(registry.registry_content_hash), char(fresh.registry_content_hash))
        % Compare semantic hashes entry-wise for clearer failures
        for i = 1:numel(entries)
            e = entries(i);
            fe = fresh.entries(strcmp({fresh.entries.relative_path}, e.relative_path));
            if isempty(fe)
                continue;
            end
            if ~strcmp(char(e.semantic_content_hash), char(fe.semantic_content_hash))
                error('validate_temporal_memory_artifact_registry:SemanticHashMismatch', ...
                    'Semantic content hash mismatch for %s.', e.relative_path);
            end
            if ~strcmp(char(e.binary_sha256), char(fe.binary_sha256))
                error('validate_temporal_memory_artifact_registry:BinaryHashMismatch', ...
                    'Binary file hash mismatch for %s.', e.relative_path);
            end
        end
        error('validate_temporal_memory_artifact_registry:RegistryHashMismatch', ...
            'Artifact registry content hash mismatch.');
    end

    if nargin >= 4 && ~isempty(expected_keys)
        % Every completed checkpoint key with an artifact role must appear
        ck_keys = {};
        for i = 1:numel(entries)
            k = char(entries(i).producing_checkpoint_key);
            if ~isempty(k)
                ck_keys{end+1} = k; %#ok<AGROW>
            end
        end
        missing_keys = setdiff(expected_keys(:), ck_keys(:));
        if ~isempty(missing_keys)
            error('validate_temporal_memory_artifact_registry:MissingCheckpointKey', ...
                'Registry missing producing keys: %s', strjoin(missing_keys, ', '));
        end
    end
end

function paths = expected_registry_paths(cfg)
    cells = cfg.diagnostic_cell_names(:);
    seeds = cfg.model_seeds(:);
    paths = { ...
        'diagnostic_config.mat'; ...
        'shared/splits.mat'; ...
        'shared/task_controls.mat'};
    for is = 1:numel(seeds)
        seed = seeds(is);
        for ic = 1:numel(cells)
            paths{end+1} = sprintf('seed_cell_results/seed_%d__%s.mat', ...
                seed, cells{ic}); %#ok<AGROW>
        end
        paths{end+1} = sprintf('shared/conventional/seed_%d_conventional.mat', seed);
        paths{end+1} = sprintf( ...
            'shared/reference_controls/seed_%d_no_recurrent.mat', seed);
        paths{end+1} = sprintf( ...
            'shared/reference_controls/seed_%d_shuffled_target.mat', seed);
    end
    bases = {'temporal_memory_long_table', 'temporal_memory_summary_table', ...
        'temporal_memory_contrast_table', 'temporal_memory_control_long_table'};
    for i = 1:numel(bases)
        paths{end+1} = [bases{i}, '.mat'];
        paths{end+1} = [bases{i}, '.csv'];
    end
    paths{end+1} = 'control_summary.mat';
    paths{end+1} = 'diagnostic_result.mat';
    paths = paths(:);
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
