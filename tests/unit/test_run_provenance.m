function tests = test_run_provenance
tests = functiontests(localfunctions);
end

function testCreateAndSaveManifest(testCase)
    tmp_root = tempname;
    mkdir(tmp_root);
    cleaner = onCleanup(@() rmdir(tmp_root, 's'));

    run_id = 'test_provenance_fixed_id';
    run_dir = fullfile(tmp_root, run_id);
    mkdir(run_dir);

    ctx = struct();
    ctx.run_dir = run_dir;
    ctx.run_id = run_id;
    ctx.utc_timestamp = '2026-07-10T17:00:00Z';
    ctx.git_sha_full = 'abc123def456';
    ctx.git_sha_short = 'abc123d';
    ctx.git_dirty = false;
    ctx.matlab_version = version;
    ctx.operating_system = computer('arch');
    ctx.hostname = 'testhost';
    ctx.experiment_name = 'unit_test';
    ctx.master_seed = 1729;
    ctx.solver_options = struct('ode_reltol', 1e-6);

    params = make_test_params();
    params.activation_function = @(x) piecewiseSigmoid(x, 0.85, 0.4);

    manifest_path = save_run_manifest(ctx, params, struct('note', 'provenance test'));
    testCase.verifyTrue(isfile(manifest_path));

    json_path = fullfile(run_dir, 'manifest.json');
    testCase.verifyTrue(isfile(json_path));

    json_text = fileread(json_path);
    parsed = jsondecode(json_text);
    testCase.verifyEqual(parsed.context.experiment_name, 'unit_test');
    testCase.verifyEqual(parsed.extra.note, 'provenance test');
    testCase.verifyTrue(ischar(parsed.params.activation_function));

    fid = fopen(fullfile(run_dir, 'sentinel.txt'), 'w');
    fclose(fid);
    testCase.verifyError(@() create_run_context('unit_test', struct( ...
        'run_id', run_id, ...
        'revalidated_root_override', tmp_root)), ...
        'create_run_context:RunDirectoryExists');
end

function testInvalidExperimentName(testCase)
    testCase.verifyError(@() create_run_context('bad name!'), ...
        'create_run_context:InvalidExperimentName');
end
