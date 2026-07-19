function registry = build_temporal_memory_artifact_registry(run_dir, cfg, checkpoint)
%BUILD_TEMPORAL_MEMORY_ARTIFACT_REGISTRY  Manifest artifact file registry.
%
%   registry = build_temporal_memory_artifact_registry(run_dir, cfg, checkpoint)
%
% Entries bind relative path, role, binary SHA-256, semantic content hash where
% applicable, schema version, and producing checkpoint key. Does not include
% the registry or manifest files themselves (avoids circular self-hashing).

    run_dir = char(run_dir);
    cells = cfg.diagnostic_cell_names(:);
    seeds = cfg.model_seeds(:);
    entries = {};

    entries{end+1} = make_entry(run_dir, 'diagnostic_config.mat', ...
        'diagnostic_config', 'temporal_memory_development_config_v1', '', ...
        @() config_semantic(run_dir)); %#ok<*AGROW>

    entries{end+1} = make_entry(run_dir, 'shared/splits.mat', ...
        'shared_splits', 'temporal_memory_splits_v1', '', []);

    entries{end+1} = make_entry(run_dir, 'shared/task_controls.mat', ...
        'shared_task_controls', 'temporal_memory_task_controls_v1', ...
        temporal_memory_checkpoint_key('shared_task_controls'), ...
        @() task_controls_semantic(run_dir));

    for is = 1:numel(seeds)
        seed = seeds(is);
        for ic = 1:numel(cells)
            cn = char(cells{ic});
            rel = sprintf('seed_cell_results/seed_%d__%s.mat', seed, cn);
            key = temporal_memory_checkpoint_key('cell', cn, seed);
            entries{end+1} = make_entry(run_dir, rel, 'seed_cell_result', ...
                'temporal_memory_seed_cell_result_v1', key, ...
                @() cell_semantic(run_dir, seed, cn));
        end
        rel = sprintf('shared/conventional/seed_%d_conventional.mat', seed);
        key = temporal_memory_checkpoint_key('conventional', seed);
        entries{end+1} = make_entry(run_dir, rel, 'conventional_bundle', ...
            'matched_conventional_memory_curve_v1', key, ...
            @() conventional_semantic(run_dir, seed));

        rel = sprintf('shared/reference_controls/seed_%d_no_recurrent.mat', seed);
        key = temporal_memory_checkpoint_key('no_recurrent', seed);
        entries{end+1} = make_entry(run_dir, rel, 'no_recurrent_control', ...
            'temporal_memory_control_v1', key, ...
            @() no_recurrent_semantic(run_dir, seed));

        rel = sprintf('shared/reference_controls/seed_%d_shuffled_target.mat', seed);
        key = temporal_memory_checkpoint_key('shuffled_target', seed);
        entries{end+1} = make_entry(run_dir, rel, 'shuffled_target_control', ...
            'temporal_memory_control_v1', key, ...
            @() shuffled_semantic(run_dir, seed));
    end

    table_bases = { ...
        'temporal_memory_long_table', 'long_table'; ...
        'temporal_memory_summary_table', 'summary_table'; ...
        'temporal_memory_contrast_table', 'contrast_table'; ...
        'temporal_memory_control_long_table', 'control_long_table'};
    for i = 1:size(table_bases, 1)
        base = table_bases{i, 1};
        role = table_bases{i, 2};
        mat_rel = [base, '.mat'];
        csv_rel = [base, '.csv'];
        entries{end+1} = make_entry(run_dir, mat_rel, [role '_mat'], ...
            'temporal_memory_table_v1', '', ...
            @() table_mat_semantic(run_dir, base));
        entries{end+1} = make_entry(run_dir, csv_rel, [role '_csv'], ...
            'temporal_memory_table_csv_v1', '', []);
    end

    entries{end+1} = make_entry(run_dir, 'control_summary.mat', ...
        'control_summary', 'temporal_memory_control_summary_v1', '', ...
        @() control_summary_semantic(run_dir));
    entries{end+1} = make_entry(run_dir, 'diagnostic_result.mat', ...
        'diagnostic_result', 'temporal_memory_development_result_v1', '', ...
        @() diagnostic_result_semantic(run_dir));

    registry = struct();
    registry.schema_version = 'temporal_memory_artifact_registry_v1';
    registry.entries = [entries{:}];
    registry.n_entries = numel(registry.entries);
    if nargin >= 3 && isstruct(checkpoint) && isfield(checkpoint, 'status')
        registry.checkpoint_status = char(checkpoint.status);
    else
        registry.checkpoint_status = '';
    end
    registry.registry_content_hash = canonical_sha256(registry_for_hash(registry));
end

function entry = make_entry(run_dir, rel, role, schema, ck_key, sem_fn)
    rel = strrep(char(rel), '\', '/');
    assert_safe_relpath(rel);
    abs_path = fullfile(run_dir, strrep(rel, '/', filesep));
    if ~isfile(abs_path)
        error('build_temporal_memory_artifact_registry:MissingArtifact', ...
            'Missing artifact for registry: %s', rel);
    end
    entry = struct();
    entry.relative_path = rel;
    entry.artifact_role = char(role);
    entry.binary_sha256 = temporal_memory_file_sha256(abs_path);
    entry.schema_version = char(schema);
    entry.producing_checkpoint_key = char(ck_key);
    if isempty(sem_fn)
        entry.semantic_content_hash = '';
    else
        entry.semantic_content_hash = char(sem_fn());
    end
end

function assert_safe_relpath(rel)
    if isempty(rel) || startsWith(rel, '/') || startsWith(rel, '\') || ...
            ~isempty(regexp(rel, '^[A-Za-z]:', 'once')) || ...
            contains(rel, '..')
        error('build_temporal_memory_artifact_registry:UnsafePath', ...
            'Registry path must be relative without traversal: %s', rel);
    end
end

function r = registry_for_hash(registry)
    r = registry;
    if isfield(r, 'registry_content_hash')
        r = rmfield(r, 'registry_content_hash');
    end
end

function hex = config_semantic(run_dir)
    S = load(fullfile(run_dir, 'diagnostic_config.mat'), 'diagnostic_config');
    hex = temporal_memory_development_config_content_hash(S.diagnostic_config);
end

function hex = task_controls_semantic(run_dir)
    S = load(fullfile(run_dir, 'shared', 'task_controls.mat'), 'task_controls');
    t = S.task_controls;
    hex = canonical_sha256(struct( ...
        'current', temporal_memory_control_content_hash(t.current_input_only, ...
            struct('control_name', 'current_input_only', ...
            'execution_scope', 'shared_task', 'shared_task_identity', 'task')), ...
        'exact', temporal_memory_control_content_hash(t.exact_history, ...
            struct('control_name', 'exact_history', ...
            'execution_scope', 'shared_task', 'shared_task_identity', 'task'))));
end

function hex = cell_semantic(run_dir, seed, cell_name)
    S = load(fullfile(run_dir, 'seed_cell_results', ...
        sprintf('seed_%d__%s.mat', seed, cell_name)), 'seed_cell_result');
    hex = temporal_memory_seed_result_content_hash(S.seed_cell_result);
end

function hex = conventional_semantic(run_dir, seed)
    S = load(fullfile(run_dir, 'shared', 'conventional', ...
        sprintf('seed_%d_conventional.mat', seed)), 'conventional_bundle');
    hex = temporal_memory_conventional_bundle_content_hash(S.conventional_bundle);
end

function hex = no_recurrent_semantic(run_dir, seed)
    S = load(fullfile(run_dir, 'shared', 'reference_controls', ...
        sprintf('seed_%d_no_recurrent.mat', seed)), 'no_recurrent_control');
    hex = temporal_memory_control_content_hash(S.no_recurrent_control, ...
        struct('control_name', 'no_recurrent_coupling', ...
        'execution_scope', 'reference_cell_per_model_seed', 'model_seed', seed));
end

function hex = shuffled_semantic(run_dir, seed)
    S = load(fullfile(run_dir, 'shared', 'reference_controls', ...
        sprintf('seed_%d_shuffled_target.mat', seed)), 'shuffled_target_control');
    hex = temporal_memory_control_content_hash(S.shuffled_target_control, ...
        struct('control_name', 'shuffled_target', ...
        'execution_scope', 'reference_cell_per_model_seed', 'model_seed', seed));
end

function hex = table_mat_semantic(run_dir, base)
    S = load(fullfile(run_dir, [base, '.mat']), base);
    hex = temporal_memory_table_content_hash(S.(base));
end

function hex = control_summary_semantic(run_dir)
    S = load(fullfile(run_dir, 'control_summary.mat'), 'control_summary');
    hex = canonical_sha256(sanitize_for_hash(S.control_summary));
end

function hex = diagnostic_result_semantic(run_dir)
    S = load(fullfile(run_dir, 'diagnostic_result.mat'), 'diagnostic_result');
    hex = canonical_sha256(sanitize_for_hash(S.diagnostic_result));
end

function out = sanitize_for_hash(value)
    out = value;
    if isstruct(value)
        drop = {'created_utc', 'updated_utc', 'hostname', 'matlab_version'};
        for i = 1:numel(drop)
            if isfield(out, drop{i})
                out = rmfield(out, drop{i});
            end
        end
    end
end
