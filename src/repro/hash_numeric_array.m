function hex = hash_numeric_array(A)
% HASH_NUMERIC_ARRAY  Deterministic SHA-256 identity for a numeric array.
%
%   hex = hash_numeric_array(A)
%
% Hashes IEEE-754 little-endian doubles plus size. Empty arrays are allowed.

    if ~(isnumeric(A) || islogical(A))
        error('hash_numeric_array:BadType', 'A must be numeric or logical.');
    end
    md = java.security.MessageDigest.getInstance('SHA-256');
    sz = int64(size(A));
    md.update(typecast(sz(:), 'uint8'));
    class_bytes = uint8(unicode2native(class(A), 'UTF-8'));
    md.update(class_bytes);
    if ~isempty(A)
        md.update(typecast(reshape(double(A), [], 1), 'uint8'));
    end
    digest = typecast(md.digest(), 'uint8');
    hex = lower(sprintf('%02x', digest));
end
