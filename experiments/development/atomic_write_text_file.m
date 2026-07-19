function atomic_write_text_file(path, text)
%ATOMIC_WRITE_TEXT_FILE  Write text via temp file then atomic replace.
%
%   atomic_write_text_file(path, text)
%
% On supported platforms, an interruption leaves either the previous complete
% file or no authoritative file — never a partial accepted artifact.

    path = char(path);
    parent = fileparts(path);
    if ~isempty(parent) && ~isfolder(parent)
        mkdir(parent);
    end
    tmp = [path, '.tmp'];
    if isfile(tmp)
        delete(tmp);
    end
    fid = fopen(tmp, 'w');
    if fid < 0
        error('atomic_write_text_file:OpenFailed', 'Could not open %s', tmp);
    end
    try
        fprintf(fid, '%s', text);
    catch ME
        fclose(fid);
        if isfile(tmp); delete(tmp); end
        rethrow(ME);
    end
    fclose(fid);
    if isfile(path)
        delete(path);
    end
    movefile(tmp, path);
end
