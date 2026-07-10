function tests = test_no_duplicate_state_indexing
% test_no_duplicate_state_indexing  Guard against manual packed-state arithmetic.
tests = functiontests(localfunctions);
end

function testNoDuplicatedPackedStateArithmetic(testCase)
    repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));

    canonical_files = {
        fullfile(repo_root, 'src', 'state', 'state_layout.m')
        fullfile(repo_root, 'src', 'state', 'pack_state.m')
        fullfile(repo_root, 'src', 'state', 'unpack_state.m')
        };

    % Jacobian helpers are rewritten in T40; this test enforces the rule elsewhere.
    exclude_prefixes = {
        fullfile(repo_root, 'src', 'algorithms', 'Jacobian')
        fullfile(repo_root, 'tests', 'unit', 'test_no_duplicate_state_indexing.m')
        };

    prohibited_patterns = {
        'len_a_E\s*=\s*params\.n_E\s*\*\s*params\.n_a_E'
        'len_a_E\s*=\s*n_E\s*\*\s*n_a_E'
        'len_a_E\s*=\s*esn\.n_E\s*\*\s*esn\.n_a_E'
        'current_idx\s*='
        'x_start_idx\s*='
        'x_start\s*=\s*len_a_E\s*\+\s*len_a_I'
        'idx_x\s*=\s*\(len_a_E'
        'idx_b_E\s*=\s*\(len_a_E'
        };

    matlab_files = collect_matlab_files(repo_root);
    violations = {};

    for i = 1:numel(matlab_files)
        filepath = matlab_files{i};
        if is_excluded(filepath, canonical_files, exclude_prefixes)
            continue;
        end

        text = fileread(filepath);
        for p = 1:numel(prohibited_patterns)
            if ~isempty(regexp(text, prohibited_patterns{p}, 'once'))
                violations{end + 1} = sprintf('%s matches %s', filepath, prohibited_patterns{p}); %#ok<AGROW>
            end
        end
    end

    if ~isempty(violations)
        testCase.assertFail(sprintf('Duplicated packed-state indexing found:\n%s', ...
            strjoin(violations, newline)));
    end
end

function files = collect_matlab_files(root_dir)
    files = {};
    scan_dirs = {fullfile(root_dir, 'src'), fullfile(root_dir, 'scripts'), root_dir};
    for d = 1:numel(scan_dirs)
        if ~isfolder(scan_dirs{d})
            continue;
        end
        listing = dir(fullfile(scan_dirs{d}, '**', '*.m'));
        for k = 1:numel(listing)
            files{end + 1} = fullfile(listing(k).folder, listing(k).name); %#ok<AGROW>
        end
    end
    files = unique(files);
end

function tf = is_excluded(filepath, canonical_files, exclude_prefixes)
    tf = any(strcmp(filepath, canonical_files));
    if tf
        return;
    end
    for i = 1:numel(exclude_prefixes)
        prefix = exclude_prefixes{i};
        if startsWith(filepath, prefix)
            tf = true;
            return;
        end
    end
end
