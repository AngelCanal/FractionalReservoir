function authority_dir = copy_calibration_authority(calibration_run_dir, publication_run_dir)
%COPY_CALIBRATION_AUTHORITY  Self-contained calibration authority for a run.
%
%   authority_dir = copy_calibration_authority(calibration_run_dir, publication_run_dir)
%
% Validates source and destination artifacts; requires matching manifest hashes.

    calibration_run_dir = char(calibration_run_dir);
    publication_run_dir = char(publication_run_dir);

    source_report = validate_operating_point_calibration(calibration_run_dir);
    if ~source_report.valid
        error('copy_calibration_authority:InvalidSourceArtifact', ...
            'Source calibration artifact failed validation: %s', ...
            strjoin(source_report.reasons, ','));
    end
    if ~source_report.authorizes_publication_run
        error('copy_calibration_authority:SourceNotAuthorizing', ...
            'Source calibration artifact does not authorize publication runs.');
    end

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

    dest_report = validate_operating_point_calibration(authority_dir);
    if ~dest_report.valid
        error('copy_calibration_authority:InvalidCopiedArtifact', ...
            'Copied calibration authority failed validation: %s', ...
            strjoin(dest_report.reasons, ','));
    end
    if ~dest_report.authorizes_publication_run
        error('copy_calibration_authority:CopiedNotAuthorizing', ...
            'Copied calibration authority does not authorize publication runs.');
    end
    if ~strcmp(source_report.calibration_manifest_hash, dest_report.calibration_manifest_hash)
        error('copy_calibration_authority:ManifestHashMismatch', ...
            'Copied manifest hash differs from source.');
    end
end
