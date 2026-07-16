function checkpoint = load_and_validate_calibration_checkpoint(run_dir, plan, commit_sha)
%LOAD_AND_VALIDATE_CALIBRATION_CHECKPOINT  Resume-safe checkpoint loader.
%
%   checkpoint = load_and_validate_calibration_checkpoint(run_dir, plan, commit_sha)
%
% Validates checkpoint identity against the current frozen calibration plan.
% Checkpoints never authorize publication.

    run_dir = char(run_dir);
    path = fullfile(run_dir, 'calibration_checkpoint.mat');
    if ~isfile(path)
        error('load_and_validate_calibration_checkpoint:MissingCheckpoint', ...
            'Missing calibration_checkpoint.mat in %s', run_dir);
    end
    S = load(path, 'calibration_checkpoint');
    checkpoint = S.calibration_checkpoint;

    if ~strcmp(char(local_get(checkpoint, 'schema_version', '')), ...
            'publication_operating_point_calibration_checkpoint_v1')
        error('load_and_validate_calibration_checkpoint:SchemaMismatch', ...
            'Unexpected checkpoint schema.');
    end

    status = char(local_get(checkpoint, 'status', ''));
    if ~any(strcmp(status, {'in_progress', 'complete'}))
        error('load_and_validate_calibration_checkpoint:BadStatus', ...
            'Checkpoint status must be in_progress or complete, got %s.', status);
    end

    if ~strcmp(char(checkpoint.calibration_protocol_version), plan.protocol_version)
        error('load_and_validate_calibration_checkpoint:ProtocolVersionMismatch', ...
            'Checkpoint protocol version mismatch.');
    end
    if ~strcmp(char(checkpoint.calibration_protocol_fingerprint), ...
            char(plan.calibration_protocol_fingerprint))
        error('load_and_validate_calibration_checkpoint:ProtocolFingerprintMismatch', ...
            'Checkpoint calibration protocol fingerprint mismatch.');
    end
    if ~strcmp(char(checkpoint.base_publication_config_fingerprint), ...
            char(plan.base_publication_config_fingerprint))
        error('load_and_validate_calibration_checkpoint:BaseFingerprintMismatch', ...
            'Checkpoint base publication fingerprint mismatch.');
    end
    if ~strcmp(char(checkpoint.creation_code_commit_sha), char(commit_sha))
        error('load_and_validate_calibration_checkpoint:CommitMismatch', ...
            'Checkpoint commit SHA mismatch.');
    end

    input_ok = verify_input_hashes_match(checkpoint.input_hashes_by_seed, plan, run_dir);
    if ~input_ok
        error('load_and_validate_calibration_checkpoint:InputHashMismatch', ...
            'Regenerated input hashes do not match checkpoint.');
    end

    if checkpoint.expected_row_count ~= 512
        error('load_and_validate_calibration_checkpoint:ExpectedRowCount', ...
            'Checkpoint expected_row_count must be 512.');
    end

    hash_ok = strcmp(char(checkpoint.checkpoint_content_hash), ...
        canonical_sha256(checkpoint_for_hash(checkpoint)));
    if ~hash_ok
        error('load_and_validate_calibration_checkpoint:CheckpointHashMismatch', ...
            'Checkpoint content hash is inconsistent.');
    end

    keys = checkpoint.completed_trial_keys(:)';
    if numel(keys) ~= numel(unique(keys))
        error('load_and_validate_calibration_checkpoint:DuplicateTrialKey', ...
            'Duplicate completed trial keys in checkpoint.');
    end

    if istable(checkpoint.completed_trial_rows)
        rows = checkpoint.completed_trial_rows;
        for i = 1:height(rows)
            expected_key = build_calibration_trial_key( ...
                rows.candidate_index(i), rows.cell_key{i}, rows.calibration_seed(i));
            if ~any(strcmp(keys, expected_key))
                error('load_and_validate_calibration_checkpoint:UnknownTrialRow', ...
                    'Completed row key missing from completed_trial_keys.');
            end
        end
        for i = 1:numel(keys)
            parts = strsplit(keys{i}, '|');
            cand = str2double(parts{1});
            seed = str2double(parts{3});
            cell_key = parts{2};
            mask = rows.candidate_index == cand & ...
                strcmp(rows.cell_key, cell_key) & rows.calibration_seed == seed;
            if ~any(mask)
                error('load_and_validate_calibration_checkpoint:UnknownTrialKey', ...
                    'Unknown completed trial key %s.', keys{i});
            end
        end
    end

    if checkpoint.completed_row_count ~= numel(keys)
        error('load_and_validate_calibration_checkpoint:RowCountMismatch', ...
            'completed_row_count must equal numel(completed_trial_keys).');
    end
end

function ok = verify_input_hashes_match(stored_hashes, plan, run_dir)
    ok = true;
    seeds = plan.calibration_seeds(:)';
    for i = 1:numel(seeds)
        seed = seeds(i);
        input_seed = seed + plan.input_seed_offset;
        stream = RandStream('mt19937ar', 'Seed', input_seed);
        n_inputs = local_get(plan, 'n_inputs', 1);
        U = plan.input_min + (plan.input_max - plan.input_min) * ...
            rand(stream, plan.total_steps, n_inputs);
        got = canonical_sha256(U);
        field = sprintf('seed_%d', seed);
        if ~isfield(stored_hashes, field)
            ok = false;
            return;
        end
        if ~strcmp(char(stored_hashes.(field)), got)
            ok = false;
            return;
        end
    end
    %#ok<NASGU> run_dir reserved for future audit hooks
end

function cp = checkpoint_for_hash(checkpoint)
    cp = checkpoint;
    drop = {'created_utc', 'updated_utc', 'checkpoint_content_hash'};
    for i = 1:numel(drop)
        if isfield(cp, drop{i})
            cp = rmfield(cp, drop{i});
        end
    end
    if isfield(cp, 'completed_trial_rows') && istable(cp.completed_trial_rows)
        cp.completed_trial_rows = table2struct(cp.completed_trial_rows);
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
