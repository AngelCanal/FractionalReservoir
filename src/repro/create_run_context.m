function ctx = create_run_context(experiment_name, options)
% create_run_context  Create an immutable revalidated experiment directory.
%
% ctx = create_run_context('my_experiment')
% ctx = create_run_context('my_experiment', struct('run_id', 'fixed_id', 'master_seed', 1729))

    if nargin < 2
        options = struct();
    end

    if ~ischar(experiment_name) && ~(isstring(experiment_name) && isscalar(experiment_name))
        error('create_run_context:InvalidExperimentName', ...
            'experiment_name must be a character vector or string scalar.');
    end
    experiment_name = char(experiment_name);

    if isempty(regexp(experiment_name, '^[A-Za-z0-9_-]+$', 'once'))
        error('create_run_context:InvalidExperimentName', ...
            'experiment_name must match [A-Za-z0-9_-]+.');
    end

    repo_root = find_repo_root();
    if isfield(options, 'revalidated_root_override') && ~isempty(options.revalidated_root_override)
        revalidated_root = char(options.revalidated_root_override);
    else
        revalidated_root = fullfile(repo_root, 'results', 'revalidated');
    end

    if isfield(options, 'run_id') && ~isempty(options.run_id)
        run_id = char(options.run_id);
    else
        utc_now = datetime('now', 'TimeZone', 'UTC');
        ts = datestr(utc_now, 'yyyymmdd_HHMMSS');
        short_sha = git_short_sha(repo_root);
        run_id = sprintf('%s_%s_%s', ts, experiment_name, short_sha);
    end

    run_dir = fullfile(revalidated_root, run_id);

    if isfolder(run_dir)
        contents = dir(run_dir);
        contents = contents(~ismember({contents.name}, {'.', '..'}));
        if ~isempty(contents)
            error('create_run_context:RunDirectoryExists', ...
                'Refusing to reuse nonempty run directory: %s', run_dir);
        end
    end

    if ~isfolder(revalidated_root)
        mkdir(revalidated_root);
    end
    mkdir(run_dir);

    utc_iso = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
    [full_sha, dirty_flag] = git_status(repo_root);

    ctx = struct();
    ctx.run_dir = run_dir;
    ctx.run_id = run_id;
    ctx.utc_timestamp = utc_iso;
    ctx.git_sha_full = full_sha;
    ctx.git_sha_short = full_sha(1:min(7, numel(full_sha)));
    ctx.git_dirty = dirty_flag;
    ctx.matlab_version = version;
    ctx.operating_system = computer('arch');
    ctx.hostname = safe_hostname();
    ctx.experiment_name = experiment_name;

    if isfield(options, 'master_seed') && ~isempty(options.master_seed)
        ctx.master_seed = options.master_seed;
    else
        ctx.master_seed = 1729;
    end

    if isfield(options, 'solver_options')
        ctx.solver_options = options.solver_options;
    else
        ctx.solver_options = struct();
    end
end

function repo_root = find_repo_root()
    this_file = mfilename('fullpath');
    % create_run_context lives in src/repro/ — climb to repository root.
    cand = fileparts(fileparts(fileparts(this_file)));
    if isfolder(fullfile(cand, 'src')) && isfolder(fullfile(cand, 'results'))
        repo_root = cand;
        return;
    end
    % Fallback: walk upward looking for .git / results
    d = fileparts(this_file);
    for k = 1:6
        if isfolder(fullfile(d, '.git')) || ...
                (isfolder(fullfile(d, 'src')) && isfolder(fullfile(d, 'results')))
            repo_root = d;
            return;
        end
        parent = fileparts(d);
        if strcmp(parent, d); break; end
        d = parent;
    end
    error('create_run_context:RepoRootNotFound', ...
        'Could not locate repository root from %s', this_file);
end

function short_sha = git_short_sha(repo_root)
    [status, result] = system(sprintf('git -C "%s" rev-parse --short HEAD', repo_root));
    if status ~= 0
        short_sha = 'nogit';
        return;
    end
    short_sha = strtrim(result);
end

function [full_sha, dirty_flag] = git_status(repo_root)
    [status, result] = system(sprintf('git -C "%s" rev-parse HEAD', repo_root));
    if status ~= 0
        full_sha = 'unknown';
        dirty_flag = true;
        return;
    end
    full_sha = strtrim(result);

    [status2, result2] = system(sprintf('git -C "%s" status --porcelain', repo_root));
    dirty_flag = (status2 ~= 0) || ~isempty(strtrim(result2));
end

function name = safe_hostname()
    try
        name = char(java.net.InetAddress.getLocalHost.getHostName());
    catch
        name = 'unknown';
    end
end
