function cfg = calibration_config_for_hash(cfg)
%CALIBRATION_CONFIG_FOR_HASH  Canonical config payload for content hashing.

    if isfield(cfg, 'created_utc')
        cfg = rmfield(cfg, 'created_utc');
    end
end
