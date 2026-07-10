function results = run_all_tests
% run_all_tests  Discover and run all MESN validation tests.
%
% Callable from the repository root:
%   addpath(genpath(pwd));
%   results = run_all_tests;
%   assertSuccess(results);

    this_file = mfilename('fullpath');
    tests_dir = fileparts(this_file);
    repo_root = fileparts(tests_dir);

    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'scripts')));
    addpath(genpath(tests_dir));

    suite_dirs = { ...
        fullfile(tests_dir, 'unit'), ...
        fullfile(tests_dir, 'integration'), ...
        fullfile(tests_dir, 'scientific') ...
    };

    results = matlab.unittest.TestResult.empty(0, 1);
    for i = 1:numel(suite_dirs)
        if isfolder(suite_dirs{i})
            folder_results = runtests(suite_dirs{i}, 'IncludeSubfolders', false, ...
                'OutputDetail', matlab.unittest.Verbosity.Concise);
            if isempty(folder_results)
                continue;
            end
            folder_results = folder_results(:);
            if isempty(results)
                results = folder_results;
            else
                results = [results; folder_results]; %#ok<AGROW>
            end
        end
    end

    if isempty(results)
        error('run_all_tests:NoTestsFound', ...
            'No tests discovered under tests/unit, tests/integration, or tests/scientific.');
    end

    results = results(:);
end
