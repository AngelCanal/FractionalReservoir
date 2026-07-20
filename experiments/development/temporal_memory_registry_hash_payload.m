function payload = temporal_memory_registry_hash_payload(registry)
%TEMPORAL_MEMORY_REGISTRY_HASH_PAYLOAD  Canonical artifact-registry identity.
%
%   payload = temporal_memory_registry_hash_payload(registry)
%
% Single source of truth for registry_content_hash. Contains only immutable
% artifact identity: schema, entry count, and ordered entry fields.

    if nargin < 1 || ~isstruct(registry)
        error('temporal_memory_registry_hash_payload:Invalid', ...
            'registry must be a struct.');
    end
    entries = local_get(registry, 'entries', []);
    n = numel(entries);
    ordered = repmat(empty_entry(), max(n, 1), 1);
    if n == 0
        ordered = ordered([]);
    else
        for i = 1:n
            e = entries(i);
            ordered(i).relative_path = char(e.relative_path);
            ordered(i).artifact_role = char(e.artifact_role);
            ordered(i).binary_sha256 = char(e.binary_sha256);
            ordered(i).semantic_content_hash = char(e.semantic_content_hash);
            ordered(i).schema_version = char(e.schema_version);
            ordered(i).producing_checkpoint_key = char(e.producing_checkpoint_key);
        end
    end
    payload = struct();
    payload.schema_version = char(local_get(registry, 'schema_version', ''));
    payload.n_entries = n;
    payload.entries = ordered;
end

function row = empty_entry()
    row = struct( ...
        'relative_path', '', ...
        'artifact_role', '', ...
        'binary_sha256', '', ...
        'semantic_content_hash', '', ...
        'schema_version', '', ...
        'producing_checkpoint_key', '');
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
