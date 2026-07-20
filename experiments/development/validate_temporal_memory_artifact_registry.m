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

    expected_n = expected_temporal_memory_registry_entry_count(cfg);
    if numel(entries) ~= expected_n
        error('validate_temporal_memory_artifact_registry:EntryCount', ...
            'Expected %d registry entries, got %d.', expected_n, numel(entries));
    end
    if local_get(registry, 'n_entries', NaN) ~= expected_n
        error('validate_temporal_memory_artifact_registry:EntryCount', ...
            'Registry n_entries (%d) does not match expected %d.', ...
            local_get(registry, 'n_entries', NaN), expected_n);
    end

    paths = cell(numel(entries), 1);
    path_roles = cell(numel(entries), 1);
    for i = 1:numel(entries)
        e = entries(i);
        rel = char(e.relative_path);
        paths{i} = rel;
        path_roles{i} = sprintf('%s|%s', rel, char(e.artifact_role));
        assert_safe_relpath(rel);
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
    if numel(path_roles) ~= numel(unique(path_roles))
        error('validate_temporal_memory_artifact_registry:DuplicatePathRole', ...
            'Duplicate path/role pairs in artifact registry.');
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

    got_hash = canonical_sha256(temporal_memory_registry_hash_payload(registry));
    if ~strcmp(char(registry.registry_content_hash), got_hash)
        error('validate_temporal_memory_artifact_registry:RegistryHashMismatch', ...
            'Stored registry_content_hash does not match canonical payload.');
    end

    fresh = build_temporal_memory_artifact_registry(run_dir, cfg);
    if ~registries_canonically_equal(registry, fresh)
        error('validate_temporal_memory_artifact_registry:RegistryMismatch', ...
            'Stored registry does not match independent rebuild.');
    end

    if nargin >= 4 && ~isempty(expected_keys)
        ck_keys = {};
        for i = 1:numel(entries)
            k = char(entries(i).producing_checkpoint_key);
            if ~isempty(k)
                ck_keys{end+1} = k; %#ok<AGROW>
            end
        end
        ck_keys = ck_keys(:);
        missing_keys = setdiff(expected_keys(:), ck_keys);
        extra_keys = setdiff(ck_keys, expected_keys(:));
        if ~isempty(missing_keys) || ~isempty(extra_keys)
            error('validate_temporal_memory_artifact_registry:CheckpointKeyCoverage', ...
                'Producing checkpoint key coverage mismatch.');
        end
    end
end

function tf = registries_canonically_equal(a, b)
    tf = false;
    if ~strcmp(char(a.schema_version), char(b.schema_version))
        return;
    end
    if a.n_entries ~= b.n_entries
        return;
    end
    if ~strcmp(char(a.registry_content_hash), char(b.registry_content_hash))
        return;
    end
    ea = a.entries;
    eb = b.entries;
    if numel(ea) ~= numel(eb)
        return;
    end
    fields = {'relative_path', 'artifact_role', 'binary_sha256', ...
        'semantic_content_hash', 'schema_version', 'producing_checkpoint_key'};
    for i = 1:numel(ea)
        for f = 1:numel(fields)
            fn = fields{f};
            if ~strcmp(char(ea(i).(fn)), char(eb(i).(fn)))
                return;
            end
        end
    end
    tf = true;
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

function assert_safe_relpath(rel)
    rel = strrep(char(rel), '\', '/');
    if isempty(rel) || startsWith(rel, '/') || startsWith(rel, '\') || ...
            ~isempty(regexp(rel, '^[A-Za-z]:', 'once'))
        error('validate_temporal_memory_artifact_registry:AbsolutePath', ...
            'Registry must not contain absolute paths: %s', rel);
    end
    if contains(rel, '..')
        error('validate_temporal_memory_artifact_registry:PathTraversal', ...
            'Registry path traversal forbidden: %s', rel);
    end
    parts = strsplit(rel, '/');
    for i = 1:numel(parts)
        if strcmp(parts{i}, '.') || strcmp(parts{i}, '..')
            error('validate_temporal_memory_artifact_registry:PathTraversal', ...
                'Registry path must not contain . or .. components: %s', rel);
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
