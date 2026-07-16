function report = validate_publication_run(run_dir, options)
% validate_publication_run  Strict publication gate over an immutable run dir.
%
%   report = validate_publication_run(run_dir)
%   report = validate_publication_run(run_dir, options)
%
% Verifies protocol tier/fingerprint, exact seeds/conditions, no missing or
% duplicate pairs, finite primary endpoints, cell status, Dale/QA bounds,
% unsupported-DDE hygiene, manifest/commit metadata, artifact hashes when
% present, and independently revalidates the persisted temporal learning gate.
% publication_ready is the logical AND of all publication requirements and never
% depends only on seed/cell counts.

    if nargin < 1 || isempty(run_dir)
        error('validate_publication_run:MissingRunDir', 'run_dir is required.');
    end
    if nargin < 2 || isempty(options)
        options = struct();
    end
    run_dir = char(run_dir);
    if ~isfolder(run_dir)
        error('validate_publication_run:MissingRunDir', ...
            'Run directory does not exist: %s', run_dir);
    end

    this_dir = fileparts(mfilename('fullpath'));
    addpath(this_dir);

    cfg = load_run_cfg(run_dir);
    if strcmp(char(cfg.protocol_tier), 'publication') && ...
            isfield(options, 'expected_cfg') && ~isempty(options.expected_cfg)
        error('validate_publication_run:ExpectedCfgOverrideForbidden', ...
            ['options.expected_cfg is forbidden for publication runs; ', ...
             'the protocol reference must be constructed internally.']);
    end
    cell_records = load_cell_records(run_dir);

    has_manifest = isfile(fullfile(run_dir, 'manifest.mat')) || ...
        isfile(fullfile(run_dir, 'manifest.json'));
    has_commit_sha = false;
    if has_manifest
        has_commit_sha = manifest_has_commit_sha(run_dir);
    end
    has_artifact_hashes = isfile(fullfile(run_dir, 'checksums.sha256')) || ...
        isfile(fullfile(run_dir, 'publication_readiness.json'));

    [gate_result, gate_load] = load_temporal_learning_gate_artifact(run_dir);

    eval_opts = struct( ...
        'cell_records', cell_records, ...
        'has_manifest', has_manifest, ...
        'has_commit_sha', has_commit_sha, ...
        'has_artifact_hashes', has_artifact_hashes, ...
        'run_dir', run_dir);
    if isfield(options, 'expected_cfg')
        eval_opts.expected_cfg = options.expected_cfg;
    end

    gate_validation_ok = false;
    gate_validation_detail = gate_load.detail;
    if gate_load.ok
        [gate_validation_ok, gate_val_report] = ...
            validate_temporal_learning_gate_result(gate_result, cfg);
        if gate_validation_ok
            eval_opts.temporal_learning_gate = gate_result;
            gate_validation_detail = 'temporal_learning_gate_independent_ok';
        else
            gate_validation_detail = strjoin(gate_val_report.reasons, ',');
            if isempty(gate_validation_detail)
                gate_validation_detail = 'temporal_learning_gate_independent_failed';
            end
        end
    end

    report = evaluate_publication_readiness(cfg, eval_opts);
    report.source = 'validate_publication_run';
    report.run_dir = run_dir;
    report.cfg = cfg;
    report.n_cell_files = numel(cell_records);
    report.temporal_learning_gate_load = gate_load;
    if gate_load.ok
        report.temporal_learning_gate = gate_result;
    end

    inf_val = struct('valid', false, 'detail', 'not_validated', ...
        'manifest_hash', '');
    try
        inf_report = validate_aggregation_inference_artifact(run_dir, cfg);
        inf_val.valid = inf_report.valid;
        inf_val.detail = strjoin(inf_report.reasons, ',');
        if isempty(inf_val.detail)
            inf_val.detail = 'valid';
        end
        inf_val.manifest_hash = inf_report.manifest_hash;
        inf_val.aggregation_inference_complete = inf_report.aggregation_inference_complete;
    catch ME
        inf_val.detail = ME.identifier;
    end
    report.inference_validation = inf_val;

    % Explicit path immutability reminder for callers.
    report.checks(end+1) = struct( ...
        'name', 'result_path_explicit', ...
        'pass', ~isempty(run_dir) && isfolder(run_dir), ...
        'detail', run_dir);

    report.checks(end+1) = struct( ...
        'name', 'temporal_learning_gate_artifact_present', ...
        'pass', gate_load.ok, ...
        'detail', gate_load.detail);

    report.checks(end+1) = struct( ...
        'name', 'temporal_learning_gate_independent_validation', ...
        'pass', gate_validation_ok, ...
        'detail', gate_validation_detail);

    report.checks(end+1) = struct( ...
        'name', 'aggregation_inference_independent_validation', ...
        'pass', inf_val.valid, ...
        'detail', inf_val.detail);

    % Recompute publication_ready with the appended checks (fail closed).
    names = {report.checks.name};
    pass = [report.checks.pass];
    artifact_ok = all(pass(strcmp(names, 'result_path_explicit'))) && ...
        all(pass(strcmp(names, 'temporal_learning_gate_artifact_present'))) && ...
        all(pass(strcmp(names, 'temporal_learning_gate_independent_validation'))) && ...
        all(pass(strcmp(names, 'aggregation_inference_independent_validation')));
    report.all_qa_checks_pass = report.all_qa_checks_pass && artifact_ok;
    if ~isfield(report, 'all_required_secondary_endpoints_complete')
        report.all_required_secondary_endpoints_complete = false;
    end
    if ~isfield(report, 'matched_seed_contrast_structure_complete')
        report.matched_seed_contrast_structure_complete = false;
    end
    if ~isfield(report, 'aggregation_inference_complete')
        report.aggregation_inference_complete = false;
    end
    report.publication_ready = report.publication_protocol_complete && ...
        report.structurally_complete && ...
        report.all_primary_endpoints_finite && ...
        report.all_qa_checks_pass && ...
        report.all_required_secondary_endpoints_complete && ...
        report.matched_seed_contrast_structure_complete && ...
        report.aggregation_inference_complete && ...
        report.artifact_package_complete;
end

function [gate_result, info] = load_temporal_learning_gate_artifact(run_dir)
    info = struct('ok', false, 'detail', '', 'path', '');
    gate_result = [];

    val_dir = fullfile(run_dir, 'validation');
    if ~isfolder(val_dir)
        info.detail = 'temporal_learning_gate_validation_dir_missing';
        return;
    end

    matches = dir(fullfile(val_dir, 'temporal_learning_gate*.mat'));
    if isempty(matches)
        info.detail = 'temporal_learning_gate_artifact_missing';
        return;
    end
    if numel(matches) > 1
        info.detail = sprintf('temporal_learning_gate_artifact_duplicated_n=%d', numel(matches));
        return;
    end

    path = fullfile(val_dir, matches(1).name);
    info.path = path;
    if ~strcmp(matches(1).name, 'temporal_learning_gate.mat')
        info.detail = sprintf('temporal_learning_gate_unexpected_name=%s', matches(1).name);
        return;
    end

    try
        S = load(path);
    catch ME
        info.detail = sprintf('temporal_learning_gate_unreadable:%s', ME.identifier);
        return;
    end

    if isfield(S, 'temporal_learning_gate')
        gate_result = S.temporal_learning_gate;
    elseif isfield(S, 'gate_result')
        gate_result = S.gate_result;
    else
        info.detail = 'temporal_learning_gate_malformed_missing_variable';
        return;
    end

    if ~isstruct(gate_result) || numel(gate_result) ~= 1
        info.detail = 'temporal_learning_gate_malformed_not_scalar_struct';
        gate_result = [];
        return;
    end

    info.ok = true;
    info.detail = 'temporal_learning_gate_artifact_loaded';
end

function cfg = load_run_cfg(run_dir)
    cfg_path = fullfile(run_dir, 'preregistered_config.mat');
    if isfile(cfg_path)
        S = load(cfg_path);
        if isfield(S, 'cfg')
            cfg = S.cfg;
            return;
        end
        if isfield(S, 'params') && isstruct(S.params)
            cfg = S.params;
            return;
        end
    end

    man_mat = fullfile(run_dir, 'manifest.mat');
    if isfile(man_mat)
        S = load(man_mat);
        if isfield(S, 'manifest') && isfield(S.manifest, 'params')
            cfg = S.manifest.params;
            return;
        end
    end

    error('validate_publication_run:MissingConfig', ...
        'Could not load preregistered config from %s', run_dir);
end

function records = load_cell_records(run_dir)
    cells_dir = fullfile(run_dir, 'cells');
    if ~isfolder(cells_dir)
        records = struct([]);
        return;
    end
    files = dir(fullfile(cells_dir, '*.mat'));
    records = cell(numel(files), 1);
    for i = 1:numel(files)
        S = load(fullfile(cells_dir, files(i).name));
        if isfield(S, 'cell_result')
            records{i} = S.cell_result;
        elseif isfield(S, 'result')
            records{i} = S.result;
        else
            error('validate_publication_run:InvalidCellFile', ...
                'No cell_result in %s', files(i).name);
        end
    end
    if isempty(records)
        records = struct([]);
    else
        records = [records{:}];
    end
end

function tf = manifest_has_commit_sha(run_dir)
    tf = false;
    mat_path = fullfile(run_dir, 'manifest.mat');
    if isfile(mat_path)
        S = load(mat_path);
        if isfield(S, 'manifest') && isfield(S.manifest, 'context')
            ctx = S.manifest.context;
            if isfield(ctx, 'git_sha_full') && ~isempty(ctx.git_sha_full) && ...
                    ~strcmp(ctx.git_sha_full, 'unknown')
                tf = true;
                return;
            end
        end
    end
    json_path = fullfile(run_dir, 'manifest.json');
    if isfile(json_path)
        txt = fileread(json_path);
        parsed = jsondecode(txt);
        if isfield(parsed, 'context') && isfield(parsed.context, 'git_sha_full')
            sha = parsed.context.git_sha_full;
            tf = ~isempty(sha) && ~strcmp(sha, 'unknown');
        end
    end
end
