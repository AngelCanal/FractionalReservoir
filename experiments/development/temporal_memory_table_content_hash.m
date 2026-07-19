function hex = temporal_memory_table_content_hash(T)
%TEMPORAL_MEMORY_TABLE_CONTENT_HASH  Canonical table semantic hash.
%
%   hex = temporal_memory_table_content_hash(T)

    if isempty(T) || height(T) == 0
        hex = canonical_sha256(struct( ...
            'empty', true, ...
            'varnames', {T.Properties.VariableNames}));
        return;
    end
    payload = struct();
    payload.varnames = T.Properties.VariableNames(:)';
    payload.nrows = height(T);
    cols = cell(1, width(T));
    for i = 1:width(T)
        col = T{:, i};
        name = T.Properties.VariableNames{i};
        entry = struct('name', name);
        if isnumeric(col) || islogical(col)
            entry.kind = 'numeric';
            entry.values = col;
            entry.missing = isnan(double(col));
        elseif isstring(col) || iscellstr(col) || ischar(col)
            entry.kind = 'string';
            entry.values = cellstr(string(col));
        elseif iscategorical(col)
            entry.kind = 'categorical';
            entry.values = cellstr(string(col));
        else
            entry.kind = 'other';
            entry.values = cellstr(string(col));
        end
        cols{i} = entry;
    end
    payload.columns = cols;
    hex = canonical_sha256(payload);
end
