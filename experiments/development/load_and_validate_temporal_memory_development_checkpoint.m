function checkpoint = load_and_validate_temporal_memory_development_checkpoint( ...
        run_dir, cfg, commit_sha)
%LOAD_AND_VALIDATE_TEMPORAL_MEMORY_DEVELOPMENT_CHECKPOINT  Resume-safe loader.
%
%   checkpoint = load_and_validate_temporal_memory_development_checkpoint( ...
%       run_dir, cfg, commit_sha)
%
% Rejects protocol/commit/input/order mismatches, unknown or duplicate keys,
% nonfinite required results, reserved seeds, publication authorization, and
% any semantic/binary hash mismatch. Never silently replaces a completed
% artifact whose stored hash fails.

    run_dir = char(run_dir);
    path = fullfile(run_dir, 'diagnostic_checkpoint.mat');
    if ~isfile(path)
        error('load_and_validate_temporal_memory_development_checkpoint:MissingCheckpoint', ...
            'Missing diagnostic_checkpoint.mat in %s', run_dir);
    end
    S = load(path, 'diagnostic_checkpoint');
    checkpoint = S.diagnostic_checkpoint;

    if ~strcmp(char(local_get(checkpoint, 'schema_version', '')), ...
            'temporal_memory_development_checkpoint_v1')
        error('load_and_validate_temporal_memory_development_checkpoint:SchemaMismatch', ...
            'Unexpected checkpoint schema.');
    end

    status = char(local_get(checkpoint, 'status', ''));
    if ~any(strcmp(status, {'running', 'complete'}))
        error('load_and_validate_temporal_memory_development_checkpoint:BadStatus', ...
            'Checkpoint status must be running or complete, got %s.', status);
    end

    if local_get(checkpoint, 'can_authorize_publication', false) || ...
            local_get(checkpoint, 'publication_ready', false) || ...
            local_get(checkpoint, 'publication_evidence', false)
        error('load_and_validate_temporal_memory_development_checkpoint:PublicationClaim', ...
            'Checkpoint can never authorize a publication claim.');
    end

    if ~strcmp(char(checkpoint.protocol_version), char(cfg.protocol_version))
        error('load_and_validate_temporal_memory_development_checkpoint:ProtocolMismatch', ...
            'Checkpoint protocol version mismatch.');
    end
    if ~strcmp(char(checkpoint.protocol_fingerprint), char(cfg.protocol_fingerprint))
        error('load_and_validate_temporal_memory_development_checkpoint:ProtocolMismatch', ...
            'Checkpoint protocol fingerprint mismatch.');
    end
    if ~strcmp(char(checkpoint.code_commit_sha), char(commit_sha))
        error('load_and_validate_temporal_memory_development_checkpoint:CommitMismatch', ...
            'Checkpoint commit SHA mismatch.');
    end

    expected_seeds = cfg.model_seeds(:);
    expected_cells = cfg.diagnostic_cell_names(:);
    expected_lags = cfg.lags(:);
    if ~isequal(checkpoint.ordered_model_seeds(:), expected_seeds)
        error('load_and_validate_temporal_memory_development_checkpoint:SeedOrderChanged', ...
            'Checkpoint model-seed order mismatch.');
    end
    if ~isequal(cellstr(string(checkpoint.ordered_cell_keys(:))), ...
            cellstr(string(expected_cells)))
        error('load_and_validate_temporal_memory_development_checkpoint:CellOrderChanged', ...
            'Checkpoint cell order mismatch.');
    end
    if ~isequal(checkpoint.lag_vector(:), expected_lags)
        error('load_and_validate_temporal_memory_development_checkpoint:LagsChanged', ...
            'Checkpoint lag vector mismatch.');
    end

    reserved = flatten_numeric(local_get(cfg, 'reserved_future_v2', struct()));
    if any(ismember(checkpoint.ordered_model_seeds(:), reserved(:)))
        error('load_and_validate_temporal_memory_development_checkpoint:ReservedSeed', ...
            'Checkpoint lists reserved future seeds.');
    end
    if any(checkpoint.ordered_model_seeds(:) == 9003)
        error('load_and_validate_temporal_memory_development_checkpoint:ReservedSeed', ...
            'Checkpoint lists forbidden seed 9003.');
    end

    verify_input_hashes(checkpoint, run_dir);

    keys = cellstr(string(local_get(checkpoint, 'completed_keys', {})));
    keys = keys(:);
    if numel(keys) ~= numel(unique(keys))
        error('load_and_validate_temporal_memory_development_checkpoint:DuplicateKey', ...
            'Duplicate completed keys in checkpoint.');
    end

    result_hashes = local_get(checkpoint, 'result_hashes', struct());
    file_hashes = local_get(checkpoint, 'file_hashes', struct());
    artifact_roles = local_get(checkpoint, 'artifact_roles', struct());

    for i = 1:numel(keys)
        key = keys{i};
        if ~is_known_checkpoint_key(key, expected_cells, expected_seeds)
            error('load_and_validate_temporal_memory_development_checkpoint:UnknownKey', ...
                'Unknown completed key %s.', key);
        end
        field = key_to_field(key);
        if ~isfield(result_hashes, field) || isempty(result_hashes.(field))
            error('load_and_validate_temporal_memory_development_checkpoint:MissingResultHash', ...
                'Missing result hash for key %s.', key);
        end
        expected_hash = char(result_hashes.(field));

        if contains(key, 'cell:')
            assert_cell_seed_artifact_finite(run_dir, key);
            assert_cell_result_hash(run_dir, key, expected_hash);
            assert_optional_file_hash(run_dir, key, file_hashes, field, ...
                cell_artifact_relpath(key));
        elseif startsWith(key, 'conventional|')
            assert_conventional_bundle_identity(run_dir, key, cfg);
            assert_conventional_result_hash(run_dir, key, expected_hash);
        elseif strcmp(key, 'shared_task_controls')
            assert_shared_task_hash(run_dir, expected_hash);
        elseif startsWith(key, 'no_recurrent|')
            assert_no_recurrent_hash(run_dir, key, expected_hash);
        elseif startsWith(key, 'shuffled_target|')
            assert_shuffled_hash(run_dir, key, expected_hash);
        end

        if isfield(artifact_roles, field) && isempty(artifact_roles.(field))
            error('load_and_validate_temporal_memory_development_checkpoint:MissingRole', ...
                'Missing artifact role for key %s.', key);
        end
    end

    if strcmp(status, 'complete')
        expected_keys = temporal_memory_expected_checkpoint_keys(cfg);
        if numel(keys) ~= numel(expected_keys) || ...
                ~isempty(setdiff(expected_keys, keys)) || ...
                ~isempty(setdiff(keys, expected_keys))
            error('load_and_validate_temporal_memory_development_checkpoint:IncompleteKeys', ...
                ['Complete checkpoint key set mismatch (expected %d unique keys).'], ...
                numel(expected_keys));
        end
        cell_keys = local_get(checkpoint, 'completed_cell_seed_keys', {});
        n_cells = numel(expected_cells);
        n_seeds = numel(expected_seeds);
        if numel(cell_keys) ~= n_cells * n_seeds
            error('load_and_validate_temporal_memory_development_checkpoint:IncompleteKeys', ...
                'Complete checkpoint expected %d cell-seed keys.', n_cells * n_seeds);
        end
    end

    verify_win_hashes_against_artifacts(checkpoint, run_dir, expected_cells, expected_seeds);

    hash_ok = strcmp(char(checkpoint.checkpoint_content_hash), ...
        canonical_sha256(checkpoint_for_hash(checkpoint)));
    if ~hash_ok
        error('load_and_validate_temporal_memory_development_checkpoint:CheckpointHashMismatch', ...
            'Checkpoint content hash is inconsistent.');
    end
end

function assert_cell_result_hash(run_dir, key, expected_hash)
    tok = regexp(key, '^cell:([^|]+)\|seed:(\d+)$', 'tokens', 'once');
    path = fullfile(run_dir, 'seed_cell_results', ...
        sprintf('seed_%s__%s.mat', tok{2}, tok{1}));
    S = load(path, 'seed_cell_result');
    got = temporal_memory_seed_result_content_hash(S.seed_cell_result);
    if ~strcmp(got, expected_hash)
        error('load_and_validate_temporal_memory_development_checkpoint:ResultHashMismatch', ...
            'Cell result content hash mismatch for %s.', key);
    end
end

function assert_conventional_result_hash(run_dir, key, expected_hash)
    seed = str2double(erase(key, 'conventional|seed:'));
    path = fullfile(run_dir, 'shared', 'conventional', ...
        sprintf('seed_%d_conventional.mat', seed));
    S = load(path, 'conventional_bundle');
    b = S.conventional_bundle;
    got = temporal_memory_conventional_bundle_content_hash(b);
    if isfield(b, 'bundle_content_hash') && ~isempty(b.bundle_content_hash) && ...
            ~strcmp(char(b.bundle_content_hash), got)
        error('load_and_validate_temporal_memory_development_checkpoint:ConventionalHashFail', ...
            ['Conventional stored bundle_content_hash disagrees with canonical ', ...
             'hash for seed %d; resume stops rather than replacing.'], seed);
    end
    if ~strcmp(got, expected_hash)
        error('load_and_validate_temporal_memory_development_checkpoint:ConventionalHashFail', ...
            ['Conventional result hash mismatch for seed %d; ', ...
             'resume stops rather than replacing.'], seed);
    end
end

function assert_shared_task_hash(run_dir, expected_hash)
    path = fullfile(run_dir, 'shared', 'task_controls.mat');
    if ~isfile(path)
        error('load_and_validate_temporal_memory_development_checkpoint:MissingTaskControls', ...
            'Missing shared/task_controls.mat.');
    end
    S = load(path, 'task_controls');
    t = S.task_controls;
    got = canonical_sha256(struct( ...
        'current', temporal_memory_control_content_hash(t.current_input_only, ...
            struct('control_name', 'current_input_only', ...
            'execution_scope', 'shared_task', 'shared_task_identity', 'task')), ...
        'exact', temporal_memory_control_content_hash(t.exact_history, ...
            struct('control_name', 'exact_history', ...
            'execution_scope', 'shared_task', 'shared_task_identity', 'task'))));
    if ~strcmp(got, expected_hash)
        error('load_and_validate_temporal_memory_development_checkpoint:ControlHashMismatch', ...
            'Shared task-control content hash mismatch.');
    end
end

function assert_no_recurrent_hash(run_dir, key, expected_hash)
    seed = str2double(erase(key, 'no_recurrent|seed:'));
    path = fullfile(run_dir, 'shared', 'reference_controls', ...
        sprintf('seed_%d_no_recurrent.mat', seed));
    if ~isfile(path)
        error('load_and_validate_temporal_memory_development_checkpoint:MissingNoRecurrent', ...
            'Missing no-recurrent control for seed %d.', seed);
    end
    S = load(path, 'no_recurrent_control');
    got = temporal_memory_control_content_hash(S.no_recurrent_control, ...
        struct('control_name', 'no_recurrent_coupling', ...
        'execution_scope', 'reference_cell_per_model_seed', 'model_seed', seed));
    if ~strcmp(got, expected_hash)
        error('load_and_validate_temporal_memory_development_checkpoint:ControlHashMismatch', ...
            'No-recurrent control hash mismatch for seed %d.', seed);
    end
end

function assert_shuffled_hash(run_dir, key, expected_hash)
    seed = str2double(erase(key, 'shuffled_target|seed:'));
    path = fullfile(run_dir, 'shared', 'reference_controls', ...
        sprintf('seed_%d_shuffled_target.mat', seed));
    if ~isfile(path)
        error('load_and_validate_temporal_memory_development_checkpoint:MissingShuffled', ...
            'Missing shuffled-target control for seed %d.', seed);
    end
    S = load(path, 'shuffled_target_control');
    got = temporal_memory_control_content_hash(S.shuffled_target_control, ...
        struct('control_name', 'shuffled_target', ...
        'execution_scope', 'reference_cell_per_model_seed', 'model_seed', seed));
    if ~strcmp(got, expected_hash)
        error('load_and_validate_temporal_memory_development_checkpoint:ControlHashMismatch', ...
            'Shuffled-target control hash mismatch for seed %d.', seed);
    end
end

function assert_optional_file_hash(run_dir, key, file_hashes, field, rel)
    if ~isstruct(file_hashes) || ~isfield(file_hashes, field) || ...
            isempty(file_hashes.(field))
        return;
    end
    abs_path = fullfile(run_dir, strrep(rel, '/', filesep));
    got = temporal_memory_file_sha256(abs_path);
    if ~strcmp(got, char(file_hashes.(field)))
        error('load_and_validate_temporal_memory_development_checkpoint:FileHashMismatch', ...
            'Binary file hash mismatch for %s.', key);
    end
end

function rel = cell_artifact_relpath(key)
    tok = regexp(key, '^cell:([^|]+)\|seed:(\d+)$', 'tokens', 'once');
    rel = sprintf('seed_cell_results/seed_%s__%s.mat', tok{2}, tok{1});
end

function verify_win_hashes_against_artifacts(checkpoint, run_dir, cells, seeds)
    wh = local_get(checkpoint, 'Win_hashes_by_seed', struct());
    if isempty(fieldnames(wh))
        return;
    end
    for is = 1:numel(seeds)
        sf = sprintf('seed_%d', seeds(is));
        if ~isfield(wh, sf)
            continue;
        end
        hashes = wh.(sf);
        vals = {};
        for ic = 1:numel(cells)
            cn = char(cells{ic});
            if ~isfield(hashes, cn)
                continue;
            end
            vals{end+1} = char(hashes.(cn)); %#ok<AGROW>
            art = fullfile(run_dir, 'seed_cell_results', ...
                sprintf('seed_%d__%s.mat', seeds(is), cn));
            if ~isfile(art)
                continue;
            end
            S = load(art, 'seed_cell_result');
            r = S.seed_cell_result;
            if isfield(r, 'W_in_hash') && ~isempty(r.W_in_hash)
                got = char(r.W_in_hash);
            elseif isfield(r, 'W_in')
                got = canonical_sha256(r.W_in);
            else
                continue;
            end
            if isfield(r, 'W_in') && ~isempty(r.W_in)
                computed = canonical_sha256(r.W_in);
                if ~strcmp(got, computed)
                    error('load_and_validate_temporal_memory_development_checkpoint:WinHashMismatch', ...
                        'W_in_hash does not match W_in for cell %s seed %d.', cn, seeds(is));
                end
            end
            if isfield(r, 'W_hash') && ~isempty(r.W_hash) && isfield(r, 'W') && ~isempty(r.W)
                if ~strcmp(char(r.W_hash), canonical_sha256(r.W))
                    error('load_and_validate_temporal_memory_development_checkpoint:WHashMismatch', ...
                        'W_hash does not match W for cell %s seed %d.', cn, seeds(is));
                end
            end
            if ~strcmp(got, char(hashes.(cn)))
                error('load_and_validate_temporal_memory_development_checkpoint:WinHashMismatch', ...
                    'W_in hash mismatch for cell %s seed %d.', cn, seeds(is));
            end
        end
        if numel(vals) > 1 && numel(unique(vals)) ~= 1
            error('load_and_validate_temporal_memory_development_checkpoint:WinHashMismatch', ...
                'W_in hashes differ across cells for seed %d.', seeds(is));
        end
    end
end

function verify_input_hashes(checkpoint, run_dir)
    split_path = fullfile(run_dir, 'shared', 'splits.mat');
    if ~isfile(split_path)
        error('load_and_validate_temporal_memory_development_checkpoint:MissingSplits', ...
            'Missing shared/splits.mat required for input-hash verification.');
    end
    S = load(split_path, 'splits', 'input_hashes');
    stored = checkpoint.input_hashes;
    fields = fieldnames(stored);
    for i = 1:numel(fields)
        f = fields{i};
        if ~isfield(S.input_hashes, f) || ~strcmp(char(S.input_hashes.(f)), char(stored.(f)))
            error('load_and_validate_temporal_memory_development_checkpoint:InputHashMismatch', ...
                'Input hash mismatch for %s.', f);
        end
        if isfield(S, 'splits')
            split_name = erase(f, 'split_');
            if isfield(S.splits, split_name) && isfield(S.splits.(split_name), 'U')
                got = canonical_sha256(S.splits.(split_name).U);
                if ~strcmp(got, char(stored.(f)))
                    error('load_and_validate_temporal_memory_development_checkpoint:InputHashMismatch', ...
                        'Regenerated input hash mismatch for %s.', f);
                end
            end
        end
    end
end

function ok = is_known_checkpoint_key(key, cells, seeds)
    ok = false;
    if strcmp(key, 'shared_task_controls')
        ok = true;
        return;
    end
    if startsWith(key, 'conventional|seed:')
        seed = str2double(erase(key, 'conventional|seed:'));
        ok = ismember(seed, seeds(:)');
        return;
    end
    if startsWith(key, 'no_recurrent|seed:')
        seed = str2double(erase(key, 'no_recurrent|seed:'));
        ok = ismember(seed, seeds(:)');
        return;
    end
    if startsWith(key, 'shuffled_target|seed:')
        seed = str2double(erase(key, 'shuffled_target|seed:'));
        ok = ismember(seed, seeds(:)');
        return;
    end
    tok = regexp(key, '^cell:([^|]+)\|seed:(\d+)$', 'tokens', 'once');
    if isempty(tok)
        return;
    end
    cell_name = tok{1};
    seed = str2double(tok{2});
    ok = any(strcmp(cell_name, cells)) && ismember(seed, seeds(:)');
end

function assert_cell_seed_artifact_finite(run_dir, key)
    tok = regexp(key, '^cell:([^|]+)\|seed:(\d+)$', 'tokens', 'once');
    if isempty(tok)
        return;
    end
    path = fullfile(run_dir, 'seed_cell_results', ...
        sprintf('seed_%s__%s.mat', tok{2}, tok{1}));
    if ~isfile(path)
        error('load_and_validate_temporal_memory_development_checkpoint:MissingCellArtifact', ...
            'Missing cell artifact for %s.', key);
    end
    S = load(path, 'seed_cell_result');
    r = S.seed_cell_result;
    if ~isfield(r, 'per_lag') || isempty(r.per_lag)
        error('load_and_validate_temporal_memory_development_checkpoint:NonfiniteResult', ...
            'Cell result missing per_lag for %s.', key);
    end
    for i = 1:numel(r.per_lag)
        m = r.per_lag(i).metrics;
        vals = [m.nrmse, m.r2, m.pearson, m.memory_coefficient, m.rmse];
        if any(~isfinite(vals))
            error('load_and_validate_temporal_memory_development_checkpoint:NonfiniteResult', ...
                'Nonfinite required metrics for %s.', key);
        end
    end
end

function assert_conventional_bundle_identity(run_dir, key, cfg)
    seed = str2double(erase(key, 'conventional|seed:'));
    validate_temporal_memory_conventional_artifact(run_dir, seed, cfg);
end

function cp = checkpoint_for_hash(checkpoint)
    cp = checkpoint;
    drop = {'created_utc', 'updated_utc', 'checkpoint_content_hash'};
    for i = 1:numel(drop)
        if isfield(cp, drop{i})
            cp = rmfield(cp, drop{i});
        end
    end
end

function field = key_to_field(key)
    field = regexprep(key, '[^A-Za-z0-9]', '_');
    if ~isempty(field) && field(1) >= '0' && field(1) <= '9'
        field = ['k_', field];
    end
end

function vals = flatten_numeric(S)
    vals = [];
    if isnumeric(S)
        vals = S(:);
        return;
    end
    if ~isstruct(S) || numel(S) ~= 1
        return;
    end
    fn = fieldnames(S);
    for i = 1:numel(fn)
        vals = [vals; flatten_numeric(S.(fn{i}))]; %#ok<AGROW>
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
