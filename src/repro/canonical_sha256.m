function hex = canonical_sha256(value)
% CANONICAL_SHA256  SHA-256 of a canonically serialized MATLAB value.
%
%   hex = canonical_sha256(value)
%
% Same convention as compute_protocol_fingerprint: function handles via
% func2str, struct fields sorted alphabetically, JSON via jsonencode, then
% SHA-256 hex (lowercase). Do not invent a second hashing convention.

    canon = canonicalize_for_hash(value);
    text = jsonencode(to_json_safe_sorted(canon));
    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(uint8(unicode2native(text, 'UTF-8')));
    digest = typecast(md.digest(), 'uint8');
    hex = lower(sprintf('%02x', digest));
end

function out = canonicalize_for_hash(value)
    if isa(value, 'function_handle')
        out = func2str(value);
        return;
    end
    if ischar(value) || (isstring(value) && isscalar(value))
        out = char(value);
        return;
    end
    if isstring(value)
        out = cellstr(value);
        return;
    end
    if islogical(value) || isnumeric(value)
        out = value;
        return;
    end
    if iscell(value)
        out = cell(size(value));
        for i = 1:numel(value)
            out{i} = canonicalize_for_hash(value{i});
        end
        return;
    end
    if isstruct(value)
        if numel(value) ~= 1
            out = cell(size(value));
            for i = 1:numel(value)
                out{i} = canonicalize_for_hash(value(i));
            end
            return;
        end
        f = sort(fieldnames(value));
        out = struct();
        for i = 1:numel(f)
            out.(f{i}) = canonicalize_for_hash(value.(f{i}));
        end
        return;
    end
    out = char(string(value));
end

function out = to_json_safe_sorted(value)
    if isa(value, 'function_handle')
        out = func2str(value);
        return;
    end
    if isstruct(value)
        if numel(value) ~= 1
            out = cell(size(value));
            for i = 1:numel(value)
                out{i} = to_json_safe_sorted(value(i));
            end
            return;
        end
        f = sort(fieldnames(value));
        out = struct();
        for i = 1:numel(f)
            out.(f{i}) = to_json_safe_sorted(value.(f{i}));
        end
        return;
    end
    if iscell(value)
        out = cell(size(value));
        for i = 1:numel(value)
            out{i} = to_json_safe_sorted(value{i});
        end
        return;
    end
    if isstring(value)
        if isscalar(value)
            out = char(value);
        else
            out = cellstr(value);
        end
        return;
    end
    out = value;
end
