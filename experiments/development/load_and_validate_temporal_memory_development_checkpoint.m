function checkpoint = load_and_validate_temporal_memory_development_checkpoint( ...
        run_dir, cfg, commit_sha)
%LOAD_AND_VALIDATE_TEMPORAL_MEMORY_DEVELOPMENT_CHECKPOINT  Resume-safe loader.
%
%   checkpoint = load_and_validate_temporal_memory_development_checkpoint( ...
%       run_dir, cfg, commit_sha)
%
% Rejects protocol/commit/input/order mismatches, unknown or duplicate keys,
% nonfinite required results, reserved seeds, and any publication authorization.

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
            local_get(checkpoint, 'publication_ready', false)
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
        if contains(key, 'cell:')
            assert_cell_seed_artifact_finite(run_dir, key);
            assert_cell_result_hash(run_dir, key, char(result_hashes.(field)));
        elseif startsWith(key, 'conventional|')
            assert_conventional_bundle_identity(run_dir, key, cfg);
            assert_stored_result_hash_matches_conventional(run_dir, key, ...
                char(result_hashes.(field)));
        end
    end

    if strcmp(status, 'complete')
        n_cells = numel(expected_cells);
        n_seeds = numel(expected_seeds);
        expected_n = n_cells * n_seeds + 1 + 3 * n_seeds;
        % 24 cell-seed + 1 shared task + 3 conventional + 3 no-recurrent + 3 shuffled
        % when n_cells=8 and n_seeds=3 => 34
        if numel(keys) ~= expected_n
            error('load_and_validate_temporal_memory_development_checkpoint:IncompleteKeys', ...
                'Complete checkpoint expected %d keys, found %d.', expected_n, numel(keys));
        end
        cell_keys = local_get(checkpoint, 'completed_cell_seed_keys', {});
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
    got = canonical_sha256(seed_result_hash_payload_local(S.seed_cell_result));
    if ~strcmp(got, expected_hash)
        error('load_and_validate_temporal_memory_development_checkpoint:ResultHashMismatch', ...
            'Cell result content hash mismatch for %s.', key);
    end
end

function assert_stored_result_hash_matches_conventional(run_dir, key, expected_hash)
    seed = str2double(erase(key, 'conventional|seed:'));
    path = fullfile(run_dir, 'shared', 'conventional', ...
        sprintf('seed_%d_conventional.mat', seed));
    S = load(path, 'conventional_bundle');
    b = S.conventional_bundle;
    if isfield(b, 'bundle_content_hash')
        got = char(b.bundle_content_hash);
    else
        got = conventional_bundle_content_hash(b);
    end
    if ~strcmp(got, expected_hash)
        error('load_and_validate_temporal_memory_development_checkpoint:ConventionalHashFail', ...
            ['Conventional result hash mismatch for seed %d; ', ...
             'resume stops rather than replacing.'], seed);
    end
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

function payload = seed_result_hash_payload_local(scored)
    % Must match run_temporal_memory_development_diagnostics/seed_result_hash_payload.
    payload = struct();
    payload.cell_name = scored.cell_name;
    payload.model_seed = scored.model_seed;
    payload.lags = scored.lags(:);
    n = numel(scored.per_lag);
    payload.nrmse = zeros(n, 1);
    payload.mc = zeros(n, 1);
    for i = 1:n
        payload.nrmse(i) = scored.per_lag(i).metrics.nrmse;
        payload.mc(i) = scored.per_lag(i).metrics.memory_coefficient;
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
    path = fullfile(run_dir, 'shared', 'conventional', ...
        sprintf('seed_%d_conventional.mat', seed));
    if ~isfile(path)
        error('load_and_validate_temporal_memory_development_checkpoint:MissingConventional', ...
            'Missing conventional bundle for %s.', key);
    end
    S = load(path, 'conventional_bundle');
    b = S.conventional_bundle;
    cmb = cfg.conventional_memory_baseline;
    if local_get(b, 'n_candidates', NaN) ~= cmb.candidate_count
        error('load_and_validate_temporal_memory_development_checkpoint:ConventionalIdentity', ...
            'Conventional n_candidates mismatch for seed %d.', seed);
    end
    if ~isequal(b.selection_lags(:), cmb.selection_lags(:))
        error('load_and_validate_temporal_memory_development_checkpoint:ConventionalIdentity', ...
            'Conventional selection_lags mismatch for seed %d.', seed);
    end
    if ~isscalar(b.selected_candidate_index) || ~isfinite(b.selected_candidate_index)
        error('load_and_validate_temporal_memory_development_checkpoint:ConventionalIdentity', ...
            'Conventional selected_candidate_index must be one scalar.');
    end
    idx = [b.per_lag.selected_candidate_index];
    if ~all(idx == b.selected_candidate_index)
        error('load_and_validate_temporal_memory_development_checkpoint:ConventionalIdentity', ...
            'All lag rows must use the same selected candidate.');
    end
    if ~logical(b.same_reservoir_for_all_lags)
        error('load_and_validate_temporal_memory_development_checkpoint:ConventionalIdentity', ...
            'same_reservoir_for_all_lags must be true.');
    end
    if logical(b.test_targets_used_for_selection)
        error('load_and_validate_temporal_memory_development_checkpoint:ConventionalIdentity', ...
            'test_targets_used_for_selection must be false.');
    end
    if ~strcmp(char(local_get(b, 'provenance', '')), 'production') && ...
            ~logical(local_get(b, 'is_test_fixture', false))
        error('load_and_validate_temporal_memory_development_checkpoint:ConventionalIdentity', ...
            'Conventional provenance must be production (or explicit test fixture).');
    end
    stored_hash = '';
    if isfield(b, 'bundle_content_hash')
        stored_hash = char(b.bundle_content_hash);
    end
    recomputed = conventional_bundle_content_hash(b);
    if ~isempty(stored_hash) && ~strcmp(stored_hash, recomputed)
        error('load_and_validate_temporal_memory_development_checkpoint:ConventionalHashFail', ...
            ['Conventional bundle content hash failed for seed %d; ', ...
             'resume stops rather than replacing.'], seed);
    end
end

function hex = conventional_bundle_content_hash(b)
    payload = struct();
    payload.model_seed = b.model_seed;
    payload.selected_candidate_index = b.selected_candidate_index;
    payload.selected_candidate_content_hash = b.selected_candidate_content_hash;
    payload.n_candidates = b.n_candidates;
    payload.selection_lags = b.selection_lags(:)';
    payload.same_reservoir_for_all_lags = b.same_reservoir_for_all_lags;
    hex = canonical_sha256(payload);
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
