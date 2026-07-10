function paths = resolve_paper_result_paths(options)
% resolve_paper_result_paths  Load explicit paper-figure result paths.
%
% Accepts either:
%   options.result_paths  struct with fields esp_phase, parameter_grid,
%                         timescale_invariance, meanfield, benchmarks
%   options.manifest_path path to .mat containing result_paths (or paths)
%
% Rejects missing fields and does not search for "latest" files.

    if nargin < 1 || isempty(options)
        options = struct();
    end

    if isfield(options, 'manifest_path') && ~isempty(options.manifest_path)
        mp = options.manifest_path;
        if exist(mp, 'file') ~= 2
            error('resolve_paper_result_paths:MissingManifest', ...
                'manifest_path does not exist: %s', mp);
        end
        S = load(mp);
        if isfield(S, 'result_paths')
            paths = S.result_paths;
        elseif isfield(S, 'paths')
            paths = S.paths;
        elseif isfield(S, 'manifest') && isfield(S.manifest, 'result_paths')
            paths = S.manifest.result_paths;
        else
            error('resolve_paper_result_paths:AmbiguousManifest', ...
                ['Manifest must contain result_paths (or paths). ', ...
                 'Ambiguous or incomplete manifest: %s'], mp);
        end
    elseif isfield(options, 'result_paths') && ~isempty(options.result_paths)
        paths = options.result_paths;
    else
        error('resolve_paper_result_paths:MissingPaths', ...
            ['make_paper_figures requires options.result_paths or ', ...
             'options.manifest_path. Finding the latest result is disabled.']);
    end

    required = {'esp_phase', 'parameter_grid', 'timescale_invariance', ...
        'meanfield', 'benchmarks'};
    for i = 1:numel(required)
        f = required{i};
        if ~isfield(paths, f) || isempty(paths.(f))
            error('resolve_paper_result_paths:MissingField', ...
                'result_paths.%s is required and must be nonempty.', f);
        end
        paths.(f) = require_explicit_result_path(paths.(f), f);
    end
end
