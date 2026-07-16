function written = write_inference_artifacts(run_dir, result, cfg, plan, agg_manifest)
%WRITE_INFERENCE_ARTIFACTS  Persist Phase 5B inference tables and manifest.
%
%   written = write_inference_artifacts(run_dir, result, cfg, plan, agg_manifest)
%
% Writes under run_dir/aggregation/inference/ atomically.

    run_dir = char(run_dir);
    inf_dir = fullfile(run_dir, 'aggregation', 'inference');
    if ~isfolder(inf_dir)
        mkdir(inf_dir);
    end

    commit_sha = try_git_head();

    hashes = struct();
    hashes.inference_summary_table = save_inference_table_pair(inf_dir, ...
        'inference_summary_table', result.inference_summary_table);
    hashes.multiplicity_table = save_inference_table_pair(inf_dir, ...
        'multiplicity_table', result.multiplicity_table);
    hashes.resampling_provenance_table = save_inference_table_pair(inf_dir, ...
        'resampling_provenance_table', result.resampling_provenance_table);
    hashes.dimension_control_diagnostic = save_inference_struct_pair(inf_dir, ...
        'dimension_control_diagnostic', result.dimension_control_diagnostic);

    agg_inf = result.aggregate_seed_inference;
    agg_inf.schema_version = 'aggregate_seed_inference_v1';
    force_inference_atomic_save(fullfile(inf_dir, 'aggregate_seed_inference.mat'), ...
        struct('aggregate_seed_inference', sanitize_for_hash(agg_inf)));
    hashes.aggregate_seed_inference = canonical_sha256(sanitize_for_hash(agg_inf));

    fam_observed = count_families(result.inference_summary_table, plan);
    fam_expected = struct();
    fn = fieldnames(plan.testing_families);
    for i = 1:numel(fn)
        fam = plan.testing_families.(fn{i});
        fam_expected.(fam.family_id) = fam.expected_count;
    end

    manifest = struct();
    manifest.schema_version = 'seed_level_inference_artifact_v1';
    manifest.inference_protocol_version = plan.protocol_version;
    manifest.phase5a_protocol_version = char(local_get(cfg.aggregation_plan, ...
        'protocol_version', 'matched_seed_contrasts_v1'));
    manifest.protocol_fingerprint = char(cfg.protocol_fingerprint);
    manifest.protocol_tier = char(local_get(cfg, 'protocol_tier', ''));
    manifest.analysis_set = char(result.analysis_set);
    manifest.expected_seeds = result.expected_seeds(:)';
    manifest.expected_seed_hash = result.expected_seed_hash;
    manifest.source_phase5a_table_hashes = result.source_table_hashes;
    manifest.inference_plan_hash = result.inference_plan_hash;
    manifest.output_table_hashes = hashes;
    manifest.family_expected_counts = fam_expected;
    manifest.family_observed_counts = fam_observed;
    manifest.resampling_settings = struct( ...
        'alpha', plan.alpha, ...
        'bootstrap_replicates', plan.bootstrap_replicates, ...
        'sign_flip_exact_max_n', plan.sign_flip_exact_max_n, ...
        'sign_flip_monte_carlo_replicates', plan.sign_flip_monte_carlo_replicates, ...
        'multiplicity_method', plan.multiplicity_method);
    manifest.rng_algorithm = plan.rng_algorithm;
    manifest.master_seed = plan.rng_master_seed;
    manifest.provenance_mode = 'executed_from_immutable_phase5a_tables';
    manifest.overrides_used = false;
    manifest.synthetic_fixture = false;
    manifest.global_rng_mutated = false;
    manifest.creation_code_commit_sha = commit_sha;
    manifest.inference_execution_status = result.inference_execution_status;
    manifest.publication_inference_complete = result.publication_inference_complete;
    manifest.created_utc = char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));

    manifest_hash = canonical_sha256(manifest_for_hash(manifest));
    manifest.manifest_hash = manifest_hash;

    force_inference_atomic_save(fullfile(inf_dir, 'inference_manifest.mat'), ...
        struct('inference_manifest', manifest));

    json_text = jsonencode(manifest);
    json_path = fullfile(inf_dir, 'inference_manifest.json');
    write_text_atomic(json_path, json_text);

    written = struct();
    written.inference_manifest = manifest;
    written.manifest_hash = manifest_hash;
    written.output_table_hashes = hashes;
    written.inference_dir = inf_dir;
end

% =============================================================================
function hex = save_inference_table_pair(inf_dir, base_name, T)
    if ~istable(T)
        if isempty(T)
            T = table();
        else
            T = struct2table(T);
        end
    end
    mat_path = fullfile(inf_dir, [base_name, '.mat']);
    payload = struct();
    payload.(base_name) = T;
    force_inference_atomic_save(mat_path, payload);

    csv_path = fullfile(inf_dir, [base_name, '.csv']);
    Tcsv = flatten_table_for_csv(T);
    if isfile(csv_path)
        delete(csv_path);
    end
    if height(Tcsv) == 0 && width(Tcsv) == 0
        fid = fopen(csv_path, 'w');
        if fid >= 0; fclose(fid); end
    else
        writetable(Tcsv, csv_path);
    end
    hex = hash_inference_table(T);
end

function hex = save_inference_struct_pair(inf_dir, base_name, S)
    mat_path = fullfile(inf_dir, [base_name, '.mat']);
    payload = struct();
    payload.(base_name) = S;
    force_inference_atomic_save(mat_path, payload);

    csv_path = fullfile(inf_dir, [base_name, '.csv']);
    T = struct_to_flat_table(S);
    if isfile(csv_path)
        delete(csv_path);
    end
    if isempty(T) || (height(T) == 0 && width(T) == 0)
        fid = fopen(csv_path, 'w');
        if fid >= 0; fclose(fid); end
    else
        writetable(T, csv_path);
    end
    hex = canonical_sha256(sanitize_for_hash(S));
end

function force_inference_atomic_save(path_out, variables)
    if isfile(path_out)
        delete(path_out);
    end
    atomic_save_results(path_out, variables);
end

function write_text_atomic(path_out, text)
    tmp = [path_out, '.tmp'];
    fid = fopen(tmp, 'w');
    if fid < 0
        error('write_inference_artifacts:WriteFailed', 'Could not write %s', tmp);
    end
    fwrite(fid, text, 'char');
    fclose(fid);
    if isfile(path_out)
        delete(path_out);
    end
    movefile(tmp, path_out);
end

function hex = hash_inference_table(T)
    if isempty(T) || height(T) == 0
        hex = canonical_sha256(struct( ...
            'empty', true, ...
            'varnames', {T.Properties.VariableNames}));
        return;
    end
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
    S = table2struct(T);
    hex = canonical_sha256(S);
end

function T = flatten_table_for_csv(T)
    if isempty(T) || width(T) == 0
        return;
    end
    for i = 1:width(T)
        col = T{:, i};
        if iscell(col)
            for r = 1:numel(col)
                if isnumeric(col{r}) || islogical(col{r})
                    col{r} = mat2str(col{r});
                elseif isstruct(col{r})
                    col{r} = '<struct>';
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

function T = struct_to_flat_table(S)
    if isempty(S) || ~isstruct(S)
        T = table();
        return;
    end
    if isfield(S, 'endpoint_results') && ~isempty(S.endpoint_results)
        rows = {};
        for i = 1:numel(S.endpoint_results)
            r = S.endpoint_results(i);
            rows{end+1} = struct( ...
                'endpoint_id', r.endpoint_id, ...
                'gated', r.gated, ...
                'pass', r.pass, ...
                'n_seeds_exceeding_tolerance', r.n_seeds_exceeding_tolerance, ...
                'max_absolute_discrepancy', r.max_absolute_discrepancy); %#ok<AGROW>
        end
        T = struct2table([rows{:}]');
        return;
    end
    T = struct2table(S, 'AsArray', true);
end

function counts = count_families(summary_T, plan)
    counts = struct();
    fn = fieldnames(plan.testing_families);
    for i = 1:numel(fn)
        fam_id = plan.testing_families.(fn{i}).family_id;
        counts.(fam_id) = 0;
    end
    if ~istable(summary_T) || height(summary_T) == 0
        return;
    end
    for r = 1:height(summary_T)
        row = summary_T(r, :);
        if strcmp(char(row.executed_action), 'test_and_holm') && ...
                isfield(counts, char(row.multiplicity_family))
            counts.(char(row.multiplicity_family)) = ...
                counts.(char(row.multiplicity_family)) + 1;
        end
    end
end

function m = manifest_for_hash(manifest)
    m = manifest;
    drop = {'created_utc', 'manifest_hash', 'creation_code_commit_sha'};
    for i = 1:numel(drop)
        if isfield(m, drop{i})
            m = rmfield(m, drop{i});
        end
    end
end

function s = sanitize_for_hash(s)
    if isstruct(s)
        fn = fieldnames(s);
        for i = 1:numel(fn)
            v = s.(fn{i});
            if isa(v, 'RandStream')
                s = rmfield(s, fn{i});
            elseif isstruct(v)
                s.(fn{i}) = sanitize_for_hash(v);
            end
        end
    end
end

function sha = try_git_head()
    sha = '';
    try
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
