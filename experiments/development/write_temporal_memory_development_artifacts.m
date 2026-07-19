function written = write_temporal_memory_development_artifacts(run_dir, payload)
%WRITE_TEMPORAL_MEMORY_DEVELOPMENT_ARTIFACTS  Persist diagnostic tables/manifest.
%
%   written = write_temporal_memory_development_artifacts(run_dir, payload)
%
% payload fields:
%   cfg, tables, control_summary, result, commit_sha, is_test_fixture (optional)

    run_dir = char(run_dir);
    if ~isfolder(run_dir)
        mkdir(run_dir);
    end

    tables = payload.tables;
    cfg = payload.cfg;
    commit_sha = char(local_get(payload, 'commit_sha', ''));
    is_fixture = logical(local_get(payload, 'is_test_fixture', false));

    hashes = struct();
    hashes.long_table = save_table_pair(run_dir, 'temporal_memory_long_table', ...
        tables.long_table);
    hashes.summary_table = save_table_pair(run_dir, 'temporal_memory_summary_table', ...
        tables.summary_table);
    hashes.contrast_table = save_table_pair(run_dir, 'temporal_memory_contrast_table', ...
        tables.contrast_table);
    hashes.control_long_table = save_table_pair(run_dir, ...
        'temporal_memory_control_long_table', tables.control_long_table);

    control_summary = local_get(payload, 'control_summary', tables.control_summary);
    hashes.control_summary = canonical_sha256(sanitize_for_hash(control_summary));
    atomic_save_results(fullfile(run_dir, 'control_summary.mat'), ...
        struct('control_summary', control_summary));

    result = payload.result;
    result.publication_evidence = false;
    result.publication_ready = false;
    result.can_authorize_publication = false;
    hashes.diagnostic_result = canonical_sha256(sanitize_for_hash(result));
    atomic_save_results(fullfile(run_dir, 'diagnostic_result.mat'), ...
        struct('diagnostic_result', result));

    alloc = local_get(control_summary, 'allocation', struct());
    manifest = struct();
    manifest.schema_version = 'temporal_memory_development_artifact_v1';
    manifest.protocol_version = char(cfg.protocol_version);
    manifest.protocol_fingerprint = char(cfg.protocol_fingerprint);
    manifest.protocol_role = char(cfg.protocol_role);
    manifest.protocol_tier = char(cfg.protocol_tier);
    manifest.code_commit_sha = commit_sha;
    manifest.model_seeds = cfg.model_seeds(:)';
    manifest.diagnostic_cell_names = cfg.diagnostic_cell_names(:)';
    manifest.lags = cfg.lags(:)';
    manifest.row_counts = struct( ...
        'long_table', height(tables.long_table), ...
        'summary_table', height(tables.summary_table), ...
        'contrast_table', height(tables.contrast_table), ...
        'control_long_table', height(tables.control_long_table), ...
        'expected_long_rows', local_get(tables, 'expected_long_rows', NaN), ...
        'expected_summary_rows', local_get(tables, 'expected_summary_rows', NaN), ...
        'expected_control_lag_rows', local_get(tables, 'expected_control_lag_rows', NaN));
    manifest.table_content_hashes = hashes;
    manifest.control_allocation = alloc;
    manifest.publication_evidence = false;
    manifest.publication_ready = false;
    manifest.can_authorize_publication = false;
    manifest.can_satisfy_publication_readiness = false;
    manifest.is_test_fixture = is_fixture;
    manifest.synthetic_provenance = is_fixture;
    manifest.created_utc = char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
    manifest.manifest_content_hash = canonical_sha256(manifest_for_hash(manifest));

    atomic_save_results(fullfile(run_dir, 'diagnostic_manifest.mat'), ...
        struct('diagnostic_manifest', manifest));

    json_path = fullfile(run_dir, 'diagnostic_manifest.json');
    fid = fopen(json_path, 'w');
    if fid < 0
        error('write_temporal_memory_development_artifacts:JsonWriteFailed', ...
            'Could not write %s', json_path);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', jsonencode(manifest));

    written = struct();
    written.manifest = manifest;
    written.table_content_hashes = hashes;
    written.diagnostic_manifest_json = json_path;
end

function hex = save_table_pair(run_dir, base_name, T)
    mat_path = fullfile(run_dir, [base_name, '.mat']);
    csv_path = fullfile(run_dir, [base_name, '.csv']);
    payload = struct();
    payload.(base_name) = T;
    atomic_save_results(mat_path, payload);

    Tcsv = flatten_table_for_csv(T);
    if isfile(csv_path)
        delete(csv_path);
    end
    if height(Tcsv) == 0 && width(Tcsv) == 0
        fid = fopen(csv_path, 'w');
        if fid < 0
            error('write_temporal_memory_development_artifacts:CsvWriteFailed', ...
                'Could not write %s', csv_path);
        end
        fclose(fid);
    else
        writetable(Tcsv, csv_path);
    end
    hex = hash_table_content(T);
end

function T = flatten_table_for_csv(T)
    if isempty(T) || width(T) == 0
        return;
    end
    for i = 1:width(T)
        col = T{:, i};
        if isstring(col)
            T.(T.Properties.VariableNames{i}) = cellstr(col);
        end
    end
end

function hex = hash_table_content(T)
    if isempty(T) || height(T) == 0
        hex = canonical_sha256(struct( ...
            'empty', true, ...
            'varnames', {T.Properties.VariableNames}));
        return;
    end
    try
        S = table2struct(T);
    catch
        S = struct('nrows', height(T), 'varnames', {T.Properties.VariableNames});
    end
    hex = canonical_sha256(S);
end

function m = manifest_for_hash(manifest)
    m = manifest;
    if isfield(m, 'created_utc')
        m = rmfield(m, 'created_utc');
    end
    if isfield(m, 'manifest_content_hash')
        m = rmfield(m, 'manifest_content_hash');
    end
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

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
