function fingerprint = compute_calibration_protocol_fingerprint(cfg, probe_keys)
%COMPUTE_CALIBRATION_PROTOCOL_FINGERPRINT  Hash of frozen calibration plan.
%
%   fingerprint = compute_calibration_protocol_fingerprint(cfg)
%   fingerprint = compute_calibration_protocol_fingerprint(cfg, probe_keys)
%
% Excludes timestamps, paths, hostnames, and runtime execution metadata.

    if nargin < 2 || isempty(probe_keys)
        probe_keys = build_operating_point_calibration_probe_keys(cfg);
    end
    op = cfg.operating_point;

    payload = struct();
    payload.protocol_version = op.protocol_version;
    payload.network_size = op.network_size;
    payload.dt = op.dt;
    payload.calibration_seeds = op.calibration_seeds(:)';
    payload.publication_seeds_hash = canonical_sha256(cfg.publication_seeds(:)');
    payload.input_distribution = op.input_distribution;
    payload.input_min = op.input_min;
    payload.input_max = op.input_max;
    payload.input_seed_offset = op.input_seed_offset;
    payload.washout_steps = op.washout_steps;
    payload.evaluation_steps = op.evaluation_steps;
    payload.total_steps = op.total_steps;
    payload.ode_reltol = op.ode_reltol;
    payload.ode_abstol = op.ode_abstol;
    payload.dde_reltol = op.dde_reltol;
    payload.dde_abstol = op.dde_abstol;
    payload.bands = struct( ...
        'mean_rate_band', op.mean_rate_band, ...
        'saturation_fraction_max', op.saturation_fraction_max, ...
        'silent_fraction_max', op.silent_fraction_max, ...
        'dale_violations_max', 0);
    payload.candidate_order = op.candidate_order;
    payload.probe_cell_keys = probe_keys;
    payload.selection_rule = op.selection_rule;
    payload.base_publication_config_fingerprint = compute_protocol_fingerprint(cfg);

    fingerprint = canonical_sha256(payload);
end
