function path_out = atomic_save_results(path_out, variables)
% atomic_save_results  Save a struct of variables atomically; never overwrite.
%
%   path_out = atomic_save_results(path_out, variables)
%
% Writes to path_out.tmp then movefile on success. Errors if path_out exists.

    if exist(path_out, 'file')
        error('atomic_save_results:RefuseOverwrite', ...
            'Refusing to overwrite existing result file: %s', path_out);
    end

    parent = fileparts(path_out);
    if ~isempty(parent) && ~exist(parent, 'dir')
        mkdir(parent);
    end

    tmp = [path_out, '.tmp'];
    if exist(tmp, 'file')
        delete(tmp);
    end
    save(tmp, '-struct', 'variables');
    movefile(tmp, path_out);
end
