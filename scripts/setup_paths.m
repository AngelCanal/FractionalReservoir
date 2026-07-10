function setup_paths()
%SETUP_PATHS Add repository src and scripts directories to the MATLAB path.
%
% Idempotent: repeated calls do not duplicate path entries.

    persistent paths_configured
    if ~isempty(paths_configured) && paths_configured
        return;
    end

    scriptDir = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(scriptDir);
    srcPath = fullfile(projectRoot, 'src');

    if ~isfolder(srcPath)
        error('setup_paths:MissingSrc', ...
            'Could not find src directory at %s', srcPath);
    end

    addpath_once(scriptDir);
    addpath_once(srcPath);
    % Also add recursive contents via genpath, but avoid re-adding if present
    addpath_genpath_once(scriptDir);
    addpath_genpath_once(srcPath);

    paths_configured = true;
end

function addpath_once(p)
    pathCell = strsplit(path, pathsep);
    if ~any(strcmpi(pathCell, p))
        addpath(p);
    end
end

function addpath_genpath_once(rootDir)
    entries = strsplit(genpath(rootDir), pathsep);
    entries = entries(~cellfun(@isempty, entries));
    pathCell = strsplit(path, pathsep);
    to_add = entries(~ismember(lower(entries), lower(pathCell)));
    if ~isempty(to_add)
        addpath(strjoin(to_add, pathsep));
    end
end
