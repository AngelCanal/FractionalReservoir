function [probe_keys, probe_cells] = build_operating_point_calibration_probe_keys(cfg)
%BUILD_OPERATING_POINT_CALIBRATION_PROBE_KEYS  Dynamic probe list for calibration.
%
%   [probe_keys, probe_cells] = build_operating_point_calibration_probe_keys(cfg)
%
% Builds 16 unique dynamic conditions from confirmatory and SFA-sensitivity
% analysis sets (feature x only). Validates against the frozen expected list.

    expected = expected_operating_point_calibration_probe_keys();
    if ~isstruct(cfg) || ~isfield(cfg, 'cells_by_analysis_set')
        error('build_operating_point_calibration_probe_keys:InvalidCfg', ...
            'cfg must contain cells_by_analysis_set.');
    end

    confirmatory = cfg.cells_by_analysis_set.confirmatory;
    sensitivity = cfg.cells_by_analysis_set.sfa_sensitivity;

    keys = {};
    cells = {};
    seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');

    for i = 1:numel(confirmatory)
        cell_spec = confirmatory{i};
        if ~strcmp(cell_spec.readout_features, 'x')
            continue;
        end
        key = dynamic_probe_key(cell_spec);
        if ~seen.isKey(key)
            seen(key) = true;
            keys{end+1} = key; %#ok<AGROW>
            cells{end+1} = cell_spec; %#ok<AGROW>
        end
    end

    for i = 1:numel(sensitivity)
        cell_spec = sensitivity{i};
        if ~strcmp(cell_spec.readout_features, 'x')
            continue;
        end
        key = dynamic_probe_key(cell_spec);
        if ~seen.isKey(key)
            seen(key) = true;
            keys{end+1} = key; %#ok<AGROW>
            cells{end+1} = cell_spec; %#ok<AGROW>
        end
    end

    if numel(keys) ~= 16
        error('build_operating_point_calibration_probe_keys:ProbeCount', ...
            'Expected 16 unique dynamic probe keys, got %d.', numel(keys));
    end

    ordered_keys = {};
    ordered_cells = {};
    for i = 1:numel(expected)
        idx = find(strcmp(keys, expected{i}), 1);
        if isempty(idx)
            error('build_operating_point_calibration_probe_keys:MissingCondition', ...
                'Missing expected dynamic condition %s.', expected{i});
        end
        ordered_keys{end+1} = expected{i}; %#ok<AGROW>
        ordered_cells{end+1} = cells{idx}; %#ok<AGROW>
    end

    if numel(unique(ordered_keys)) ~= 16
        error('build_operating_point_calibration_probe_keys:DuplicateCondition', ...
            'Duplicate dynamic probe keys detected.');
    end

    probe_keys = ordered_keys;
    probe_cells = ordered_cells;
end

function key = dynamic_probe_key(cell_spec)
    if ~strcmp(cell_spec.readout_features, 'x')
        error('build_operating_point_calibration_probe_keys:FeatureForbidden', ...
            'Calibration probes must use feature x, got %s.', cell_spec.readout_features);
    end
    key = sprintf('adapt-%s__std-%s__delay-%s__feat-x', ...
        cell_spec.adaptation, cell_spec.std, cell_spec.delay);
end
