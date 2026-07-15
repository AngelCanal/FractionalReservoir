function tests = test_factorial_contrast_estimands
% test_factorial_contrast_estimands  Exact synthetic matched-seed contrasts.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
    testCase.TestData.repo_root = repo_root;
end

function testKnownSyntheticExactSfaStdDelayCombinedDid(testCase)
    run_dir = make_synthetic_aggregation_run(struct('absurd_marker', 7777));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    T = agg.tables.seed_contrast;

    for s = agg.seeds(:)'
        % SFA timescale distribution: three vs single → delta_raw = 1
        verify_seed_contrast(testCase, T, s, 'sfa_timescale_distribution', ...
            'mc_total', 1, +1);
        % STD main effect → 1
        verify_seed_contrast(testCase, T, s, 'std_main_effect', 'mc_total', 1, +1);
        % Delay main effect → 4
        verify_seed_contrast(testCase, T, s, 'delay_main_effect', 'mc_total', 4, +1);
        % Combined architecture → 3+1+4 = 8
        verify_seed_contrast(testCase, T, s, 'combined_architecture_system_contrast', ...
            'mc_total', 8, +1);
        % DiD A×S additive → 0
        verify_seed_contrast(testCase, T, s, 'sfa_distribution_x_std', ...
            'mc_total', 0, +1);
        verify_seed_contrast(testCase, T, s, 'sfa_distribution_x_delay', ...
            'mc_total', 0, +1);
        verify_seed_contrast(testCase, T, s, 'std_x_delay', 'mc_total', 0, +1);
    end
end

function testEqualStratumWeighting(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    T = agg.tables.seed_contrast;
    mask = strcmp(cellstr(string(T.contrast_id)), 'sfa_timescale_distribution') & ...
        strcmp(cellstr(string(T.endpoint_id)), 'mc_total') & ...
        strcmp(cellstr(string(T.status)), 'ok');
    sub = T(mask, :);
    testCase.verifyGreaterThan(height(sub), 0);
    % Equal weights ⇒ n_strata_observed matches expected and delta is mean
    for i = 1:height(sub)
        testCase.verifyEqual(sub.n_strata_observed(i), sub.n_strata_expected(i));
        testCase.verifyEqual(sub.delta_raw(i), 1, 'AbsTol', 1e-12);
    end
end

function testXAndRNotIndependentSeeds(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    T = agg.tables.seed_contrast;
    mask = strcmp(cellstr(string(T.contrast_id)), 'sfa_timescale_distribution') & ...
        strcmp(cellstr(string(T.endpoint_id)), 'mc_total');
    sub = T(mask, :);
    % One row per seed (x and r marginalized equally inside that seed)
    testCase.verifyEqual(height(sub), numel(agg.seeds));
    testCase.verifyEqual(numel(unique(sub.seed)), numel(agg.seeds));
end

function testRawDeltaIsTreatmentMinusControl(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    T = agg.tables.seed_contrast;
    mask = strcmp(cellstr(string(T.status)), 'ok') & ...
        strcmp(cellstr(string(T.contrast_id)), 'std_main_effect') & ...
        strcmp(cellstr(string(T.endpoint_id)), 'mc_total');
    sub = T(mask, :);
    for i = 1:height(sub)
        testCase.verifyEqual(sub.delta_raw(i), ...
            sub.treatment_mean_within_seed(i) - sub.control_mean_within_seed(i), ...
            'AbsTol', 1e-12);
    end
end

function testOrientationMcPositiveWhenTreatmentHigher(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    T = agg.tables.seed_contrast;
    mask = strcmp(cellstr(string(T.contrast_id)), 'sfa_timescale_distribution') & ...
        strcmp(cellstr(string(T.endpoint_id)), 'mc_total');
    sub = T(mask, :);
    testCase.verifyTrue(all(sub.delta_raw > 0));
    testCase.verifyTrue(all(sub.orientation_multiplier == +1));
    testCase.verifyEqual(sub.effect_oriented, sub.delta_raw, 'AbsTol', 1e-12);
end

function testOrientationNrmsePositiveWhenTreatmentLower(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    T = agg.tables.seed_contrast;
    mask = strcmp(cellstr(string(T.contrast_id)), 'sfa_timescale_distribution') & ...
        strcmp(cellstr(string(T.endpoint_id)), 'narma_test_nrmse');
    sub = T(mask, :);
    testCase.verifyTrue(all(sub.orientation_multiplier == -1));
    % Oriented effect = control - treatment for NRMSE (positive when treatment lower)
    testCase.verifyEqual(sub.effect_oriented, ...
        sub.control_mean_within_seed - sub.treatment_mean_within_seed, ...
        'AbsTol', 1e-12);
    % Hand-check: if treatment were lower by 0.25, oriented effect would be +0.25
    testCase.verifyEqual((-1) * (-0.25), 0.25, 'AbsTol', 0);
end

function testFavorableConvergenceAndWallTimeOrientations(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    T = agg.tables.seed_contrast;
    plan = agg.aggregation_plan;

    mask_w = strcmp(cellstr(string(T.contrast_id)), 'std_main_effect') & ...
        strcmp(cellstr(string(T.endpoint_id)), 'wall_time_seconds');
    sub_w = T(mask_w, :);
    testCase.verifyTrue(all(sub_w.orientation_multiplier == -1));
    testCase.verifyEqual( ...
        plan.endpoints.wall_time_seconds.favorable_direction, 'lower');

    mask_c = strcmp(cellstr(string(T.contrast_id)), 'std_main_effect') & ...
        strcmp(cellstr(string(T.endpoint_id)), 'empirical_convergence_slope_per_time');
    sub_c = T(mask_c, :);
    testCase.verifyTrue(all(sub_c.orientation_multiplier == -1));
    testCase.verifyEqual( ...
        plan.endpoints.empirical_convergence_slope_per_time.favorable_direction, ...
        'more_negative');
    % STD on makes convergence more negative → delta_raw < 0; oriented > 0
    testCase.verifyTrue(all(sub_c.delta_raw < 0));
    testCase.verifyTrue(all(sub_c.effect_oriented > 0));
end

function testEverySeedOneValuePerEstimand(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    T = agg.tables.seed_contrast;
    estimands = { ...
        'sfa_timescale_distribution', 'mc_total'; ...
        'std_main_effect', 'mc_total'; ...
        'delay_main_effect', 'mc_total'; ...
        'combined_architecture_system_contrast', 'mc_total'; ...
        'sfa_distribution_x_std', 'mc_total'};
    for i = 1:size(estimands, 1)
        mask = strcmp(cellstr(string(T.contrast_id)), estimands{i, 1}) & ...
            strcmp(cellstr(string(T.endpoint_id)), estimands{i, 2}) & ...
            strcmp(cellstr(string(T.status)), 'ok');
        sub = T(mask, :);
        testCase.verifyEqual(height(sub), numel(agg.seeds), estimands{i, 1});
        testCase.verifyEqual(numel(unique(sub.seed)), numel(agg.seeds));
    end
end

%% helpers
function verify_seed_contrast(testCase, T, seed, contrast_id, endpoint_id, ...
        expect_delta, expect_orient)
    mask = T.seed == seed & ...
        strcmp(cellstr(string(T.contrast_id)), contrast_id) & ...
        strcmp(cellstr(string(T.endpoint_id)), endpoint_id) & ...
        strcmp(cellstr(string(T.status)), 'ok');
    sub = T(mask, :);
    testCase.verifyEqual(height(sub), 1, sprintf('%s/%s seed %g', ...
        contrast_id, endpoint_id, seed));
    testCase.verifyEqual(sub.delta_raw(1), expect_delta, 'AbsTol', 1e-10);
    testCase.verifyEqual(sub.orientation_multiplier(1), expect_orient);
    testCase.verifyEqual(sub.effect_oriented(1), expect_orient * expect_delta, ...
        'AbsTol', 1e-10);
end
