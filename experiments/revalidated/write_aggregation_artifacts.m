function aggregate = write_aggregation_artifacts(run_dir, aggregate, tables, matrix)
%WRITE_AGGREGATION_ARTIFACTS  Persist Phase 5A aggregation tables and manifest.
%
%   aggregate = write_aggregation_artifacts(run_dir, aggregate, tables, matrix)
%
% Writes under run_dir/aggregation/:
%   aggregation_manifest.mat
%   raw_cell_table.mat/.csv
%   autonomous_fixed_horizon_table.mat/.csv
%   unique_seed_baseline_table.mat/.csv
%   seed_contrast_table.mat/.csv
%   benchmark_contrast_table.mat/.csv
%   dale_resolution_table.mat/.csv
%   aggregate_seed_contrasts.mat
%
% Also writes a schema-superseded stub aggregate_paired.mat at run_dir root
% pointing at aggregate_seed_contrasts.mat (no legacy global-control estimates).
%
% See also: aggregate_ablation_results

    if nargin < 4
        matrix = local_get(aggregate, 'matrix', struct());
    end
    if nargin < 3 || isempty(tables)
        tables = local_get(aggregate, 'tables', struct());
    end

    run_dir = char(run_dir);
    agg_dir = fullfile(run_dir, 'aggregation');
    if ~isfolder(agg_dir)
        mkdir(agg_dir);
    end

    commit_sha = try_git_head(run_dir);

    % Ensure required table fields exist
    tables = ensure_table(tables, 'raw_cell');
    tables = ensure_table(tables, 'autonomous_fixed_horizon');
    tables = ensure_table(tables, 'unique_seed_baseline');
    tables = ensure_table(tables, 'dale_resolution');
    tables = ensure_table(tables, 'seed_contrast');
    tables = ensure_table(tables, 'benchmark_contrast');

    hashes = struct();
    hashes.raw_cell_table = save_table_pair(agg_dir, 'raw_cell_table', ...
        tables.raw_cell);
    hashes.autonomous_fixed_horizon_table = save_table_pair(agg_dir, ...
        'autonomous_fixed_horizon_table', tables.autonomous_fixed_horizon);
    hashes.unique_seed_baseline_table = save_table_pair(agg_dir, ...
        'unique_seed_baseline_table', tables.unique_seed_baseline);
    hashes.seed_contrast_table = save_table_pair(agg_dir, ...
        'seed_contrast_table', tables.seed_contrast);
    hashes.benchmark_contrast_table = save_table_pair(agg_dir, ...
        'benchmark_contrast_table', tables.benchmark_contrast);
    hashes.dale_resolution_table = save_table_pair(agg_dir, ...
        'dale_resolution_table', tables.dale_resolution);

    %% aggregate_seed_contrasts.mat
    seed_payload = struct();
    seed_payload.aggregate = aggregate_for_save(aggregate);
    seed_payload.seed_contrast_table = tables.seed_contrast;
    seed_payload.benchmark_contrast_table = tables.benchmark_contrast;
    seed_payload.inference_status = 'deferred_to_phase_5b';
    seed_payload.schema_version = 'aggregate_seed_contrasts_v1';
    seed_payload.no_cliff_delta = true;
    seed_payload.no_p_values = true;
    seed_payload.no_bootstrap_ci = true;
    agg_contrasts_path = fullfile(agg_dir, 'aggregate_seed_contrasts.mat');
    force_atomic_save(agg_contrasts_path, seed_payload);
    hashes.aggregate_seed_contrasts = canonical_sha256(struct( ...
        'schema_version', seed_payload.schema_version, ...
        'inference_status', seed_payload.inference_status, ...
        'seed_contrast_hash', hashes.seed_contrast_table, ...
        'benchmark_contrast_hash', hashes.benchmark_contrast_table));

    %% aggregation_manifest
    manifest = struct();
    manifest.aggregation_protocol_version = char(local_get(aggregate, ...
        'protocol_version', 'matched_seed_contrasts_v1'));
    manifest.source_run_directory = run_dir;
    manifest.source_protocol_fingerprint = char(local_get(aggregate, ...
        'protocol_fingerprint', ''));
    manifest.active_analysis_set = char(local_get(aggregate, 'analysis_set', ''));
    manifest.expected_seeds = local_get(matrix, 'expected_seeds', ...
        local_get(aggregate, 'seeds', []));
    manifest.expected_cell_keys = local_get(matrix, 'expected_cell_keys', ...
        local_get(aggregate, 'cell_keys', {}));
    manifest.expected_pair_count = local_get(matrix, 'expected_pair_count', ...
        numel(local_get(matrix, 'expected_pairs', {})));
    manifest.observed_pair_count = local_get(matrix, 'observed_pair_count', ...
        numel(local_get(matrix, 'observed_pairs', {})));
    manifest.source_file_list = local_get(matrix, 'source_files', {});
    manifest.table_row_counts = struct( ...
        'raw_cell', height(tables.raw_cell), ...
        'autonomous_fixed_horizon', height(tables.autonomous_fixed_horizon), ...
        'unique_seed_baseline', height(tables.unique_seed_baseline), ...
        'seed_contrast', height(tables.seed_contrast), ...
        'benchmark_contrast', height(tables.benchmark_contrast), ...
        'dale_resolution', height(tables.dale_resolution));
    manifest.no_inference = true;
    manifest.inference_status = 'deferred_to_phase_5b';
    manifest.creation_code_commit_sha = commit_sha;
    manifest.structural_validation_status = char(local_get(aggregate, 'status', ''));
    manifest.failure_reasons = local_get(matrix, 'reasons', ...
        local_get(aggregate, 'failure_reasons', {}));
    manifest.table_content_hashes = hashes;
    manifest.matched_seed_contrast_structure_complete = logical(local_get( ...
        aggregate, 'matched_seed_contrast_structure_complete', false));
    manifest.aggregation_inference_complete = false;
    manifest.created_utc = char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));

    force_atomic_save(fullfile(agg_dir, 'aggregation_manifest.mat'), ...
        struct('aggregation_manifest', manifest));

    aggregate.aggregation_dir = agg_dir;
    aggregate.aggregation_manifest = manifest;
    aggregate.table_content_hashes = hashes;
    aggregate.commit_sha = commit_sha;

    %% Superseded stub for legacy aggregate_paired.mat callers
    stub = struct();
    stub.schema_superseded = true;
    stub.replacement = 'aggregation/aggregate_seed_contrasts.mat';
    stub.inference_status = 'deferred_to_phase_5b';
    stub.note = [ ...
        'Legacy global-control paired inference schema superseded by Phase 5A ', ...
        'matched seed-level contrasts. Old cliff_delta / bootstrap CI fields ', ...
        'are not produced.'];
    stub.aggregate = struct( ...
        'status', char(local_get(aggregate, 'status', '')), ...
        'inference_status', 'deferred_to_phase_5b', ...
        'schema_superseded', true, ...
        'replacement', stub.replacement, ...
        'run_dir', run_dir);
    force_atomic_save(fullfile(run_dir, 'aggregate_paired.mat'), stub);
end

% =============================================================================
function tables = ensure_table(tables, name)
    if ~isfield(tables, name) || isempty(tables.(name))
        tables.(name) = table();
    end
end

function hex = save_table_pair(agg_dir, base_name, T)
    mat_path = fullfile(agg_dir, [base_name, '.mat']);
    csv_path = fullfile(agg_dir, [base_name, '.csv']);
    payload = struct();
    payload.(base_name) = T;
    force_atomic_save(mat_path, payload);

    Tcsv = flatten_table_for_csv(T);
    if isfile(csv_path)
        delete(csv_path);
    end
    if height(Tcsv) == 0 && width(Tcsv) == 0
        % writetable rejects completely empty tables; write headerless empty file
        fid = fopen(csv_path, 'w');
        if fid < 0
            error('write_aggregation_artifacts:CsvWriteFailed', ...
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
        if iscell(col)
            for r = 1:numel(col)
                if isstruct(col{r})
                    col{r} = '<struct>';
                elseif isnumeric(col{r}) || islogical(col{r})
                    col{r} = mat2str(col{r});
                else
                    col{r} = char(string(col{r}));
                end
            end
            T.(T.Properties.VariableNames{i}) = col;
        elseif isstring(col)
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
    % Exclude timestamp-like columns if present
    drop = {};
    vn = T.Properties.VariableNames;
    for i = 1:numel(vn)
        if contains(lower(vn{i}), 'timestamp') || contains(lower(vn{i}), 'created_utc')
            drop{end+1} = vn{i}; %#ok<AGROW>
        end
    end
    if ~isempty(drop)
        T = removevars(T, drop);
    end
    try
        S = table2struct(T);
    catch
        S = struct('nrows', height(T), 'varnames', {T.Properties.VariableNames});
    end
    hex = canonical_sha256(S);
end

function force_atomic_save(path_out, variables)
% Aggregation artifacts may be rewritten; remove prior file then atomic save.
    if isfile(path_out)
        delete(path_out);
    end
    atomic_save_results(path_out, variables);
end

function out = aggregate_for_save(aggregate)
% Drop bulky nested matrix.cells payloads from the summary mat if present.
    out = aggregate;
    if isfield(out, 'matrix') && isstruct(out.matrix) && isfield(out.matrix, 'cells')
        out.matrix = rmfield(out.matrix, 'cells');
    end
    if isfield(out, 'tables')
        out = rmfield(out, 'tables');
    end
end

function sha = try_git_head(~)
    sha = '';
    try
        root = run_dir;
        % Prefer repo root via git from run_dir
        [status, out] = system('git rev-parse HEAD');
        if status == 0
            sha = strtrim(out);
        end
    catch
        sha = '';
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
