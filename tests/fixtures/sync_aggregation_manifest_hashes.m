function sync_aggregation_manifest_hashes(run_dir)
%SYNC_AGGREGATION_MANIFEST_HASHES  Recompute Phase 5A table hashes after test edits.
    agg_dir = fullfile(run_dir, 'aggregation');
    Sa = load(fullfile(agg_dir, 'aggregation_manifest.mat'), 'aggregation_manifest');
    manifest = Sa.aggregation_manifest;
    names = {'seed_contrast_table', 'benchmark_contrast_table'};
    for i = 1:numel(names)
        nm = names{i};
        path = fullfile(agg_dir, [nm, '.mat']);
        if isfile(path)
            S = load(path);
            T = S.(nm);
            manifest.table_content_hashes.(nm) = hash_table(T);
        end
    end
    aggregation_manifest = manifest; %#ok<NASGU>
    save(fullfile(agg_dir, 'aggregation_manifest.mat'), 'aggregation_manifest');
end

function hex = hash_table(T)
    if isempty(T) || height(T) == 0
        hex = canonical_sha256(struct('empty', true, 'varnames', {T.Properties.VariableNames}));
        return;
    end
    hex = canonical_sha256(table2struct(T));
end
