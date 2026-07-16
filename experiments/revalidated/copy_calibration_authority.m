function authority_dir = copy_calibration_authority(calibration_run_dir, publication_run_dir)
%COPY_CALIBRATION_AUTHORITY  Self-contained calibration authority for a run.
%
%   authority_dir = copy_calibration_authority(calibration_run_dir, publication_run_dir)
%
% Copies enough artifact material for independent revalidation without the
% original external calibration path.

    calibration_run_dir = char(calibration_run_dir);
    publication_run_dir = char(publication_run_dir);
    authority_dir = fullfile(publication_run_dir, 'calibration_authority');
    if ~isfolder(authority_dir)
        mkdir(authority_dir);
    end

    files = { ...
        'calibration_config.mat', ...
        'calibration_trial_table.mat', ...
        'calibration_trial_table.csv', ...
        'calibration_candidate_table.mat', ...
        'calibration_candidate_table.csv', ...
        'calibration_result.mat', ...
        'calibration_manifest.mat', ...
        'calibration_manifest.json' ...
        };

    for i = 1:numel(files)
        src = fullfile(calibration_run_dir, files{i});
        dst = fullfile(authority_dir, files{i});
        if ~isfile(src)
            error('copy_calibration_authority:MissingArtifact', ...
                'Missing calibration artifact %s', src);
        end
        if isfile(dst)
            delete(dst);
        end
        copyfile(src, dst);
    end
end
