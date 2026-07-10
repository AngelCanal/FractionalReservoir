function tests = test_composable_experiments
tests = functiontests(localfunctions);
end

function testTwoSequentialJacobianChecksUnaffected(testCase)
    % Smoke: two small experiment functions in one MATLAB process.
    r1 = verifyJacobianConsistency(struct('seed', 1729, 'n_states', 1, ...
        'save_results', false));
    r2 = verifyJacobianConsistency(struct('seed', 2718, 'n_states', 1, ...
        'save_results', false));

    testCase.verifyTrue(r1.all_pass);
    testCase.verifyTrue(r2.all_pass);
    testCase.verifyNotEqual(r1.seed, r2.seed);
    % Second run must still produce a complete case table
    testCase.verifyEqual(r2.n_cases, 5);
end

function testSetupPathsIdempotent(testCase)
    setup_paths();
    p1 = path;
    setup_paths();
    p2 = path;
    testCase.verifyEqual(p1, p2);
end

function testScriptsHaveNoClearClc(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    scripts_dir = fullfile(repo_root, 'scripts');
    files = dir(fullfile(scripts_dir, '*.m'));
    offenders = {};
    for i = 1:numel(files)
        src = fileread(fullfile(scripts_dir, files(i).name));
        % Match standalone clear/clc statements, not comments about them
        if ~isempty(regexp(src, '(?m)^[ \t]*clear(\s|;|$)', 'once')) || ...
                ~isempty(regexp(src, '(?m)^[ \t]*clc(\s|;|$)', 'once'))
            offenders{end+1} = files(i).name; %#ok<AGROW>
        end
    end
    testCase.verifyEmpty(offenders, sprintf('clear/clc found in: %s', strjoin(offenders, ', ')));
end
