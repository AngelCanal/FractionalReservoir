function written = write_operating_point_calibration_artifacts(run_dir, payload)
%WRITE_OPERATING_POINT_CALIBRATION_ARTIFACTS  Persist immutable calibration bundle.
%
%   written = write_operating_point_calibration_artifacts(run_dir, payload)
%
% payload fields: cfg, plan, trial_table, candidate_table, result, manifest

    run_dir = char(run_dir);
    if ~isfolder(run_dir)
        mkdir(run_dir);
    end

    written = struct();
    written.calibration_config = atomic_save_results( ...
        fullfile(run_dir, 'calibration_config.mat'), ...
        struct('calibration_config', payload.cfg));
    written.calibration_trial_table = atomic_save_results( ...
        fullfile(run_dir, 'calibration_trial_table.mat'), ...
        struct('calibration_trial_table', payload.trial_table));
    writetable(payload.trial_table, fullfile(run_dir, 'calibration_trial_table.csv'));
    written.calibration_candidate_table = atomic_save_results( ...
        fullfile(run_dir, 'calibration_candidate_table.mat'), ...
        struct('calibration_candidate_table', payload.candidate_table));
    writetable(payload.candidate_table, fullfile(run_dir, 'calibration_candidate_table.csv'));
    written.calibration_result = atomic_save_results( ...
        fullfile(run_dir, 'calibration_result.mat'), ...
        struct('calibration_result', payload.result));
    written.calibration_manifest = atomic_save_results( ...
        fullfile(run_dir, 'calibration_manifest.mat'), ...
        struct('calibration_manifest', payload.manifest));

    json_text = jsonencode(payload.manifest);
    json_path = fullfile(run_dir, 'calibration_manifest.json');
    fid = fopen(json_path, 'w');
    if fid < 0
        error('write_operating_point_calibration_artifacts:JsonWriteFailed', ...
            'Could not write %s', json_path);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', json_text);
    written.calibration_manifest_json = json_path;
end
