function tests = test_explicit_result_paths
% test_explicit_result_paths  Explicit immutable paths for experiment entry points.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'scripts')));
    testCase.TestData.repo_root = repo_root;
    testCase.TestData.root_override = fullfile(tempdir, ...
        ['reval_' char(java.util.UUID.randomUUID)]);
    mkdir(testCase.TestData.root_override);
end

function teardownOnce(testCase)
    if exist(testCase.TestData.root_override, 'dir')
        try
            rmdir(testCase.TestData.root_override, 's');
        catch
        end
    end
end

function testDryRunCreatesImmutableRunDir(testCase)
    root = testCase.TestData.root_override;
    opts = struct('dry_run', true, 'save_results', true, ...
        'revalidated_root_override', root, 'run_id', 'dry_bench_001', ...
        'make_figures', false);

    [result, run_dir] = run_benchmarks(opts);
    testCase.verifyEqual(result.status, 'dry_run');
    testCase.verifyEqual(run_dir, fullfile(root, 'dry_bench_001'));
    testCase.verifyTrue(exist(fullfile(run_dir, 'manifest.mat'), 'file') == 2);
    testCase.verifyEqual(result.run_dir, run_dir);
end

function testEntryPointsDefaultRunDependenciesFalse(testCase)
    root = testCase.TestData.root_override;
    [r, run_dir] = run_full_characterisation(struct( ...
        'dry_run', true, 'save_results', true, ...
        'revalidated_root_override', root, ...
        'run_id', 'char_dry_001', ...
        'flags', struct('parameter_sweep', true, 'meanfield_bifurcation', true, ...
            'benchmarks', true)));
    testCase.verifyEqual(r.status, 'dry_run');
    testCase.verifyTrue(exist(fullfile(run_dir, 'manifest.mat'), 'file') == 2);

    src = fileread(fullfile(testCase.TestData.repo_root, ...
        'scripts', 'run_full_characterisation.m'));
    testCase.verifyTrue(contains(src, 'run_dependencies'));
    testCase.verifyTrue(contains(src, "local_get(options, 'run_dependencies', false)"));
end

function testMakePaperFiguresRequiresExplicitPaths(testCase)
    testCase.verifyError(@() make_paper_figures(struct('dry_run', false, ...
        'save_results', false)), 'resolve_paper_result_paths:MissingPaths');
end

function testMakePaperFiguresRejectsMissingFile(testCase)
    paths = struct( ...
        'esp_phase', fullfile(tempdir, 'missing_esp.mat'), ...
        'parameter_grid', fullfile(tempdir, 'missing_grid.mat'), ...
        'timescale_invariance', fullfile(tempdir, 'missing_ts.mat'), ...
        'meanfield', fullfile(tempdir, 'missing_mf.mat'), ...
        'benchmarks', fullfile(tempdir, 'missing_bench.mat'));
    testCase.verifyError(@() make_paper_figures(struct( ...
        'result_paths', paths, 'save_results', false)), ...
        'require_explicit_result_path:MissingFile');
end

function testMakePaperFiguresAcceptsExplicitExistingPaths(testCase)
    root = testCase.TestData.root_override;
    paths = struct();
    fields = {'esp_phase', 'parameter_grid', 'timescale_invariance', ...
        'meanfield', 'benchmarks'};
    for i = 1:numel(fields)
        p = fullfile(root, [fields{i} '.mat']);
        % Minimal stubs with fields referenced by plotting (dry_run skips plot)
        S = struct('stub', true);
        save(p, '-struct', 'S');
        paths.(fields{i}) = p;
    end

    [result, run_dir] = make_paper_figures(struct( ...
        'result_paths', paths, 'dry_run', true, 'save_results', false));
    testCase.verifyEqual(result.status, 'dry_run');
    testCase.verifyEqual(run_dir, '');
    testCase.verifyEqual(result.result_paths.esp_phase, paths.esp_phase);
end

function testMakePaperFiguresRejectsAmbiguousManifest(testCase)
    root = testCase.TestData.root_override;
    mp = fullfile(root, 'ambiguous_manifest.mat');
    unrelated = 1; %#ok<NASGU>
    save(mp, 'unrelated');
    testCase.verifyError(@() make_paper_figures(struct( ...
        'manifest_path', mp, 'save_results', false)), ...
        'resolve_paper_result_paths:AmbiguousManifest');
end

function testAtomicSaveRefusesOverwrite(testCase)
    root = testCase.TestData.root_override;
    p = fullfile(root, 'once.mat');
    atomic_save_results(p, struct('a', 1));
    testCase.verifyError(@() atomic_save_results(p, struct('a', 2)), ...
        'atomic_save_results:RefuseOverwrite');
end

function testParameterGridDryRun(testCase)
    root = testCase.TestData.root_override;
    [result, run_dir] = run_parameter_grid(struct( ...
        'dry_run', true, 'save_results', true, ...
        'revalidated_root_override', root, 'run_id', 'grid_dry_001', ...
        'make_figures', false));
    testCase.verifyEqual(result.status, 'dry_run');
    testCase.verifyTrue(exist(fullfile(run_dir, 'manifest.mat'), 'file') == 2);
    testCase.verifyGreaterThan(result.n_cells, 0);
end
