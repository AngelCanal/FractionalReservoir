function hex = temporal_memory_file_sha256(path)
%TEMPORAL_MEMORY_FILE_SHA256  Binary SHA-256 of a file on disk.
%
%   hex = temporal_memory_file_sha256(path)

    path = char(path);
    if ~isfile(path)
        error('temporal_memory_file_sha256:Missing', 'File not found: %s', path);
    end
    fid = fopen(path, 'r');
    if fid < 0
        error('temporal_memory_file_sha256:OpenFailed', 'Could not open %s', path);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes = fread(fid, Inf, '*uint8');
    md = java.security.MessageDigest.getInstance('SHA-256');
    if ~isempty(bytes)
        md.update(bytes);
    end
    digest = typecast(md.digest(), 'uint8');
    hex = lower(sprintf('%02x', digest));
end
