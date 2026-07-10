function tests = test_meanfield_parameter_sweep
% test_meanfield_parameter_sweep  Per-cell parameter closure for mean-field sweeps.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'scripts')));
    testCase.TestData.repo_root = repo_root;
end

function testRhsDiffersForSeparatedIextE(testCase)
    % IextE appears in the E drive; RHS at fixed state must change with IextE.
    mf = meanfield_EI_STD_DDE(struct('tau_delay', 0.05));
    idx = find(strcmp(mf.par_names, 'IextE'));
    y = [0.1; 0.1; 0.0; 1.0];
    xx = [y, y];

    par_lo = mf.par(:).'; par_lo(idx) = 0.0;
    par_hi = mf.par(:).'; par_hi(idx) = 2.0;
    dy_lo = meanfield_EI_STD_DDE_rhs(xx, par_lo);
    dy_hi = meanfield_EI_STD_DDE_rhs(xx, par_hi);

    testCase.verifyGreaterThan(norm(dy_lo - dy_hi), 1e-8);
end

function testRhsDiffersForSeparatedAdaptation(testCase)
    mf = meanfield_EI_STD_DDE(struct('c_a', 0.0, 'tau_delay', 0.05));
    idx = find(strcmp(mf.par_names, 'c_a'));
    y = [0.1; 0.1; 0.5; 1.0]; % nonzero adaptation state
    xx = [y, y];

    par_lo = mf.par(:).'; par_lo(idx) = 0.0;
    par_hi = mf.par(:).'; par_hi(idx) = 3.0;
    dy_lo = meanfield_EI_STD_DDE_rhs(xx, par_lo);
    dy_hi = meanfield_EI_STD_DDE_rhs(xx, par_hi);

    testCase.verifyGreaterThan(norm(dy_lo - dy_hi), 1e-8);
end

function testIextSweepClosesOverPerCellParameters(testCase)
    out_dir = fullfile(tempdir, ['mf_iext_' char(java.util.UUID.randomUUID)]);
    cleaner = onCleanup(@() cleanup_dir(out_dir)); %#ok<NASGU>

    result = run_bifurcation_meanfield(struct( ...
        'Iext_vals', [0.0, 2.0], ...
        'tspan', [0, 40], ...
        'save_results', true, ...
        'out_dir', out_dir, ...
        'make_figures', false, ...
        'trajectory_idx', [1, 2]));

    testCase.verifyTrue(result.rhs_differs_across_sweep);
    testCase.verifyEqual(result.analysis_type, 'dynamical_regime_sweep');
    testCase.verifyFalse(result.is_bifurcation_diagram);
    testCase.verifyEqual(numel(result.diagnostics), 2);
    testCase.verifyEqual(result.diagnostics(1).IextE, 0.0);
    testCase.verifyEqual(result.diagnostics(2).IextE, 2.0);
    testCase.verifyGreaterThanOrEqual(numel(result.trajectories), 1);
    testCase.verifyTrue(isfield(result.trajectories(1), 'y'));
    testCase.verifyTrue(exist(result.save_path, 'file') == 2);

    testCase.verifyTrue(isfinite(result.diagnostics(1).varE));
    testCase.verifyTrue(isfinite(result.diagnostics(2).varE));
end

function testAdaptationSweepClosesOverPerCellParameters(testCase)
    out_dir = fullfile(tempdir, ['mf_ca_' char(java.util.UUID.randomUUID)]);
    cleaner = onCleanup(@() cleanup_dir(out_dir)); %#ok<NASGU>

    result = run_meanfield_adaptation_bifurcation(struct( ...
        'ca_vals', [0.0, 3.0], ...
        'ca_grid', [0.0, 3.0], ...
        'delay_grid', [0.05], ...
        'tspan', [0, 40], ...
        'save_results', true, ...
        'out_dir', out_dir, ...
        'make_figures', false, ...
        'trajectory_cells', [1, 1; 2, 1]));

    testCase.verifyTrue(result.rhs_differs_across_sweep);
    testCase.verifyEqual(result.analysis_type, 'dynamical_regime_sweep');
    testCase.verifyFalse(result.is_bifurcation_diagram);
    testCase.verifyEqual(numel(result.Evar), 2);
    testCase.verifyTrue(all(isfinite(result.Evar)));
    testCase.verifyEqual(size(result.VAR), [2, 1]);
    testCase.verifyGreaterThanOrEqual(numel(result.trajectories), 1);
    testCase.verifyTrue(exist(result.save_path, 'file') == 2);

    if result.null_sweep
        testCase.verifyEqual(result.analysis_label, 'null_regime_sweep');
        testCase.verifyTrue(contains(result.note, 'Null sweep'));
    else
        testCase.verifyEqual(result.analysis_label, 'dynamical_regime_sweep');
    end
end

function testDryRunReportsRhsSensitivityWithoutIntegration(testCase)
    r1 = run_bifurcation_meanfield(struct( ...
        'Iext_vals', [0.2, 1.8], 'dry_run', true, ...
        'save_results', false, 'make_figures', false));
    r2 = run_meanfield_adaptation_bifurcation(struct( ...
        'ca_vals', [0.1, 2.5], 'dry_run', true, ...
        'save_results', false, 'make_figures', false));

    testCase.verifyEqual(r1.mode, 'dry_run');
    testCase.verifyEqual(r2.mode, 'dry_run');
    testCase.verifyTrue(r1.rhs_differs_across_sweep);
    testCase.verifyTrue(r2.rhs_differs_across_sweep);
end

function cleanup_dir(p)
    if exist(p, 'dir')
        try
            rmdir(p, 's');
        catch
        end
    end
end
