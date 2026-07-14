function report = validate_publication_run(run_dir, options)
% validate_publication_run  Strict publication gate over an immutable run dir.
%
%   report = validate_publication_run(run_dir)
%   report = validate_publication_run(run_dir, options)
%
% Verifies protocol tier/fingerprint, exact seeds/conditions, no missing or
% duplicate pairs, finite primary endpoints, cell status, Dale/QA bounds,
% unsupported-DDE hygiene, manifest/commit metadata, and artifact hashes when
% present. publication_ready is the logical AND of all publication requirements
% and never depends only on seed/cell counts.

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
    cell_records = load_cell_records(run_dir);

    has_manifest = isfile(fullfile(run_dir, 'manifest.mat')) || ...
        isfile(fullfile(run_dir, 'manifest.json'));
    has_commit_sha = false;
    if has_manifest
        has_commit_sha = manifest_has_commit_sha(run_dir);
    end
    has_artifact_hashes = isfile(fullfile(run_dir, 'checksums.sha256')) || ...
        isfile(fullfile(run_dir, 'publication_readiness.json'));

    eval_opts = struct( ...
        'cell_records', cell_records, ...
        'has_manifest', has_manifest, ...
        'has_commit_sha', has_commit_sha, ...
        'has_artifact_hashes', has_artifact_hashes, ...
        'run_dir', run_dir);
    if isfield(options, 'expected_cfg')
        eval_opts.expected_cfg = options.expected_cfg;
    end

    report = evaluate_publication_readiness(cfg, eval_opts);
    report.source = 'validate_publication_run';
    report.run_dir = run_dir;
    report.cfg = cfg;
    report.n_cell_files = numel(cell_records);

    % Explicit path immutability reminder for callers.
    report.checks(end+1) = struct( ...
        'name', 'result_path_explicit', ...
        'pass', ~isempty(run_dir) && isfolder(run_dir), ...
        'detail', run_dir);

    % Recompute publication_ready with the appended check.
    names = {report.checks.name};
    pass = [report.checks.pass];
    report.publication_ready = report.publication_protocol_complete && ...
        report.structurally_complete && ...
        report.all_primary_endpoints_finite && ...
        report.all_qa_checks_pass && ...
        report.artifact_package_complete && ...
        all(pass(strcmp(names, 'result_path_explicit')));
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
