function key = build_calibration_trial_key(candidate_index, cell_key, calibration_seed)
%BUILD_CALIBRATION_TRIAL_KEY  Unique trial identity for checkpoint/resume.
%
%   key = build_calibration_trial_key(candidate_index, cell_key, calibration_seed)

    key = sprintf('%d|%s|%d', candidate_index, char(cell_key), calibration_seed);
end
