function path = require_explicit_result_path(path, label)
% require_explicit_result_path  Validate a single explicit result file path.

    if nargin < 2
        label = 'result';
    end
    if isempty(path)
        error('require_explicit_result_path:MissingPath', ...
            'Explicit path required for %s (find-latest is disabled).', label);
    end
    if isstring(path)
        path = char(path);
    end
    if ~ischar(path)
        error('require_explicit_result_path:InvalidPath', ...
            'Path for %s must be a character vector or string.', label);
    end
    if exist(path, 'file') ~= 2
        error('require_explicit_result_path:MissingFile', ...
            'Required %s file does not exist: %s', label, path);
    end
end
