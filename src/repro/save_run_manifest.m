function manifest_path = save_run_manifest(ctx, params, extra)
% save_run_manifest  Save manifest.mat and manifest.json for a run context.
%
% manifest_path = save_run_manifest(ctx, params)
% manifest_path = save_run_manifest(ctx, params, extra_struct)

    if nargin < 3
        extra = struct();
    end

    if ~isstruct(ctx) || ~isfield(ctx, 'run_dir')
        error('save_run_manifest:InvalidContext', 'ctx must contain run_dir.');
    end

    manifest = struct();
    manifest.context = ctx;
    manifest.params = params;
    manifest.extra = extra;
    manifest.saved_at_utc = char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));

    mat_path = fullfile(ctx.run_dir, 'manifest.mat');
    json_path = fullfile(ctx.run_dir, 'manifest.json');

    save(mat_path, 'manifest');

    json_safe = to_json_safe(manifest);
    json_text = jsonencode(json_safe);
    fid = fopen(json_path, 'w');
    if fid < 0
        error('save_run_manifest:WriteFailed', 'Could not write %s', json_path);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', json_text);

    manifest_path = mat_path;
end

function out = to_json_safe(value)
    if isa(value, 'function_handle')
        out = func2str(value);
        return;
    end

    if isstruct(value)
        out = struct();
        f = fieldnames(value);
        for i = 1:numel(f)
            out.(f{i}) = to_json_safe(value.(f{i}));
        end
        return;
    end

    if iscell(value)
        out = cell(size(value));
        for i = 1:numel(value)
            out{i} = to_json_safe(value{i});
        end
        return;
    end

    out = value;
end
