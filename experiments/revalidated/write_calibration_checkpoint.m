function checkpoint = write_calibration_checkpoint(run_dir, checkpoint)
%WRITE_CALIBRATION_CHECKPOINT  Atomically persist resumable calibration state.
%
%   checkpoint = write_calibration_checkpoint(run_dir, checkpoint)

    run_dir = char(run_dir);
    checkpoint.schema_version = 'publication_operating_point_calibration_checkpoint_v1';
    checkpoint.updated_utc = char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
    payload = checkpoint_for_hash(checkpoint);
    checkpoint.checkpoint_content_hash = canonical_sha256(payload);

    path = fullfile(run_dir, 'calibration_checkpoint.mat');
    tmp = [path, '.tmp'];
    if isfile(tmp)
        delete(tmp);
    end
    calibration_checkpoint = checkpoint; %#ok<NASGU>
    save(tmp, 'calibration_checkpoint');
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
    if isfield(cp, 'completed_trial_rows') && istable(cp.completed_trial_rows)
        cp.completed_trial_rows = table2struct(cp.completed_trial_rows);
    end
end
