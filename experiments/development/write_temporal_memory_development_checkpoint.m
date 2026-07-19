function checkpoint = write_temporal_memory_development_checkpoint(run_dir, checkpoint)
%WRITE_TEMPORAL_MEMORY_DEVELOPMENT_CHECKPOINT  Atomic resumable diagnostic state.
%
%   checkpoint = write_temporal_memory_development_checkpoint(run_dir, checkpoint)
%
% Schema: temporal_memory_development_checkpoint_v1
% A checkpoint can never authorize a publication claim.

    run_dir = char(run_dir);
    checkpoint.schema_version = 'temporal_memory_development_checkpoint_v1';
    checkpoint.updated_utc = char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
    checkpoint.can_authorize_publication = false;
    checkpoint.publication_ready = false;
    checkpoint.publication_evidence = false;

    payload = checkpoint_for_hash(checkpoint);
    checkpoint.checkpoint_content_hash = canonical_sha256(payload);

    path = fullfile(run_dir, 'diagnostic_checkpoint.mat');
    tmp = [path, '.tmp'];
    if isfile(tmp)
        delete(tmp);
    end
    diagnostic_checkpoint = checkpoint; %#ok<NASGU>
    save(tmp, 'diagnostic_checkpoint');
    if isfile(path)
        delete(path);
    end
    movefile(tmp, path);
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
