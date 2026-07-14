function tests = test_empirical_esp_controls
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'tests', 'helpers')));
    testCase.TestData.repo_root = repo_root;
end

%% --- simulate_fn controls (physical-time slopes) ---

function testStableScalarODEContractsNearKnownRate(testCase)
    lambda = -0.4;
    dt = 0.05;
    T = 400;
    U = zeros(T, 1);
    sim = @(U_in, S0) scalar_ode_traj(U_in, S0, lambda, dt);
    esp = verify_echo_state_property([], U, struct( ...
        'simulate_fn', sim, ...
        'n_state', 1, ...
        'dt', dt, ...
        'n_ic', 6, ...
        'ic_scale', 1.0, ...
        'washout_steps', 20, ...
        'tail_window', [0.5, 1.0], ...
        'min_tail_points', 30, ...
        'verbose', false, ...
        'ic_seed', 7));
    testCase.verifyEqual(esp.classification, 'empirically_contracting_on_test_set');
    testCase.verifyEqual(esp.slope_per_time_units, 'per_second');
    testCase.verifyEqual(esp.median_pair_slope, lambda, 'AbsTol', 0.05 * abs(lambda) + 1e-3);
    testCase.verifyEqual(esp.mean_pair_slope, lambda, 'AbsTol', 0.05 * abs(lambda) + 1e-3);
end

function testUnstableScalarODENotContracting(testCase)
    lambda = 0.35;
    dt = 0.05;
    T = 300;
    U = zeros(T, 1);
    sim = @(U_in, S0) scalar_ode_traj(U_in, S0, lambda, dt);
    esp = verify_echo_state_property([], U, struct( ...
        'simulate_fn', sim, ...
        'n_state', 1, ...
        'dt', dt, ...
        'n_ic', 6, ...
        'ic_scale', 0.2, ...
        'washout_steps', 5, ...
        'tail_window', [0.4, 1.0], ...
        'min_tail_points', 20, ...
        'verbose', false, ...
        'ic_seed', 9));
    testCase.verifyEqual(esp.classification, 'not_contracting_on_test_set');
    testCase.verifyGreaterThan(esp.median_pair_slope, 0);
end

function testInsufficientDurationInconclusive(testCase)
    lambda = -0.5;
    dt = 0.1;
    T = 30;
    U = zeros(T, 1);
    sim = @(U_in, S0) scalar_ode_traj(U_in, S0, lambda, dt);
    esp = verify_echo_state_property([], U, struct( ...
        'simulate_fn', sim, ...
        'n_state', 1, ...
        'dt', dt, ...
        'n_ic', 4, ...
        'washout_steps', 20, ...
        'min_tail_points', 50, ...
        'verbose', false));
    testCase.verifyEqual(esp.classification, 'inconclusive');
end

function testNoEspProvenField(testCase)
    lambda = -1;
    dt = 0.1;
    T = 200;
    U = zeros(T, 1);
    sim = @(U_in, S0) scalar_ode_traj(U_in, S0, lambda, dt);
    esp = verify_echo_state_property([], U, struct( ...
        'simulate_fn', sim, 'n_state', 1, 'dt', dt, 'n_ic', 3, ...
        'washout_steps', 10, 'verbose', false));
    testCase.verifyFalse(isfield(esp, 'esp_holds'));
    testCase.verifyTrue(ismember(esp.classification, { ...
        'empirically_contracting_on_test_set', ...
        'not_contracting_on_test_set', ...
        'inconclusive'}));
    testCase.verifyTrue(isfield(esp, 'median_pair_slope'));
    testCase.verifyTrue(isfield(esp, 'mean_pair_slope'));
    testCase.verifyTrue(isfield(esp, 'pair_slopes'));
end

function testFloorSaturatedSamplesExcludedFromFit(testCase)
    % Distances collapse below floor early; usable fit interval must exclude them.
    lambda = -5;
    dt = 0.05;
    T = 200;
    U = zeros(T, 1);
    sim = @(U_in, S0) scalar_ode_traj(U_in, S0, lambda, dt);
    esp = verify_echo_state_property([], U, struct( ...
        'simulate_fn', sim, 'n_state', 1, 'dt', dt, 'n_ic', 4, ...
        'ic_scale', 1.0, 'washout_steps', 5, 'tail_window', [0.05, 1.0], ...
        'distance_floor', 1e-6, 'min_tail_points', 10, 'verbose', false, ...
        'ic_seed', 3));
    testCase.verifyGreaterThan(esp.fraction_at_floor, 0);
    if ~isempty(esp.pair_meta)
        for i = 1:numel(esp.pair_meta)
            testCase.verifyLessThanOrEqual( ...
                esp.pair_meta(i).n_usable_tail_points, numel(esp.t_idx));
        end
    end
end

%% --- actual-class SRNN_ESN regression ---

function testDistinctExplicitInitialStatesProduceDistinctTrajectories(testCase)
    % Regression: old reset_before=true path discarded distinct ICs.
    params = make_linear_activation_params(struct( ...
        'n', 2, 'n_a_E', 0, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0, 'lags', []));
    params.W = zeros(2);
    params = validate_MESN_params(params);
    esn = SRNN_ESN(params);
    esn.ode_solver = @ode45;
    layout = state_layout(params);
    S1 = zeros(layout.n_total, 1);
    S2 = zeros(layout.n_total, 1);
    S1(layout.idx_x) = [0.4; -0.2];
    S2(layout.idx_x) = [-0.3; 0.5];
    U = zeros(40, 1);
    opts = struct('reset_before', false, 'update_internal_state', false, ...
        'ode_reltol', 1e-8, 'ode_abstol', 1e-10);
    [~, S_hist1, info1] = esn.runReservoir(U, setfield(opts, 'initial_state', S1)); %#ok<SFLD>
    [~, S_hist2, info2] = esn.runReservoir(U, setfield(opts, 'initial_state', S2)); %#ok<SFLD>
    testCase.verifyGreaterThan(norm(info1.S_start - info2.S_start), 1e-12);
    testCase.verifyGreaterThan(norm(S_hist1(1, :) - S_hist2(1, :)), 1e-12);
    testCase.verifyGreaterThan(max(abs(S_hist1 - S_hist2), [], 'all'), 1e-8);
end

function testInitialStateDoesNotMutateObjectUnlessRequested(testCase)
    params = make_linear_activation_params(struct('lags', []));
    params.W = zeros(params.n);
    params = validate_MESN_params(params);
    esn = SRNN_ESN(params);
    S_before = esn.S;
    layout = state_layout(params);
    S_ic = S_before;
    S_ic(layout.idx_x) = S_ic(layout.idx_x) + 0.2;
    U = zeros(20, 1);
    esn.runReservoir(U, struct( ...
        'reset_before', false, 'update_internal_state', false, ...
        'initial_state', S_ic));
    testCase.verifyEqual(esn.S, S_before, 'AbsTol', 0);
end

function testConflictingInitialStateAndResetRejected(testCase)
    params = make_linear_activation_params(struct('lags', []));
    esn = SRNN_ESN(params);
    S = esn.S;
    testCase.verifyError(@() esn.runReservoir(zeros(5, 1), struct( ...
        'reset_before', true, 'initial_state', S)), ...
        'SRNN_ESN:ConflictingInitialState');
end

function testInvalidInitialStateLengthRejected(testCase)
    params = make_linear_activation_params(struct('lags', []));
    esn = SRNN_ESN(params);
    testCase.verifyError(@() esn.runReservoir(zeros(5, 1), struct( ...
        'reset_before', false, 'initial_state', zeros(3, 1))), ...
        'MESN:InvalidStateLength');
end

function testResourceOutsideUnitIntervalRejected(testCase)
    params = make_test_params(struct( ...
        'n_a_E', 0, 'n_a_I', 0, 'n_b_E', 1, 'n_b_I', 1, 'lags', []));
    esn = SRNN_ESN(params);
    layout = state_layout(params);
    S = esn.S0;
    S(layout.idx_b_E(1)) = 1.5;
    testCase.verifyError(@() esn.runReservoir(zeros(5, 1), struct( ...
        'reset_before', false, 'initial_state', S)), ...
        'MESN:InvalidResourceState');
end

function testStableClassContracting(testCase)
    params = make_linear_activation_params(struct( ...
        'n', 2, 'n_a_E', 0, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0, 'lags', []));
    params.W = zeros(2);
    params.W_in = zeros(2, 1);
    params.tau_d = 1.0;
    params = validate_MESN_params(params);
    esn = SRNN_ESN(params);
    esn.ode_solver = @ode45;
    U = zeros(120, 1);
    esp = verify_echo_state_property(esn, U, struct( ...
        'n_ic', 4, 'ic_scale', 1.0, 'washout_steps', 5, ...
        'tail_window', [0.1, 0.7], 'min_tail_points', 20, ...
        'distance_floor', 1e-14, ...
        'verbose', false, 'ic_seed', 11));
    testCase.verifyEqual(esp.classification, 'empirically_contracting_on_test_set');
    testCase.verifyLessThan(esp.median_pair_slope, -0.1);
    testCase.verifyEqual(esp.median_pair_slope, -1.0, 'AbsTol', 0.25);
    testCase.verifyFalse(isfield(esp, 'esp_holds'));
end

function testUnstableClassNotContracting(testCase)
    params = make_linear_activation_params(struct( ...
        'n', 2, 'n_a_E', 0, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0, 'lags', []));
    % Amplifying linear map: dx/dt = (-x + W x)/tau with W = 3 I => growth.
    params.W = 3 * eye(2);
    params.W_in = zeros(2, 1);
    params.tau_d = 1.0;
    params = validate_MESN_params(params);
    esn = SRNN_ESN(params);
    esn.ode_solver = @ode45;
    U = zeros(120, 1);
    esp = verify_echo_state_property(esn, U, struct( ...
        'n_ic', 4, 'ic_scale', 0.05, 'washout_steps', 5, ...
        'tail_window', [0.2, 0.8], 'min_tail_points', 20, ...
        'verbose', false, 'ic_seed', 13, ...
        'slope_expanding_min', 1e-3));
    testCase.verifyEqual(esp.classification, 'not_contracting_on_test_set');
    testCase.verifyGreaterThan(esp.median_pair_slope, 0);
end

function testStdResourcesPerturbedNotResetToOne(testCase)
    params = make_test_params(struct( ...
        'n_a_E', 0, 'n_a_I', 0, 'n_b_E', 1, 'n_b_I', 1, 'lags', []));
    esn = SRNN_ESN(params);
    U = zeros(80, 1);
    esp = verify_echo_state_property(esn, U, struct( ...
        'n_ic', 4, 'ic_scale', 0.2, 'washout_steps', 10, ...
        'min_tail_points', 15, 'verbose', false, 'ic_seed', 21));
    layout = state_layout(params);
    % Reconstruct from summaries distance: all-ones resources would give
    % identical resource blocks across ICs only if reset-to-one. Digests differ.
    digests = {esp.initial_state_summaries.hash};
    testCase.verifyGreaterThan(numel(unique(digests)), 1);
    testCase.verifyTrue(isfield(esp, 'median_pair_slope'));
end

function testDdeConstantHistoriesEmpiricalOnly(testCase)
    params = make_linear_activation_params(struct( ...
        'n', 2, 'lags', 0.05, 'n_a_E', 0, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0));
    params.W = 0.2 * eye(2);
    params = validate_MESN_params(params);
    esn = SRNN_ESN(params);
    U = zeros(100, 1);
    esp = verify_echo_state_property(esn, U, struct( ...
        'n_ic', 3, 'ic_scale', 0.2, 'washout_steps', 15, ...
        'min_tail_points', 20, 'verbose', false, 'ic_seed', 5, ...
        'dde_history_mode', 'constant'));
    testCase.verifyTrue(esp.dde_empirical_only);
    testCase.verifyTrue(esp.history_space_sampled);
    testCase.verifyFalse(isfield(esp, 'esp_holds'));
    testCase.verifyTrue(ismember(esp.classification, { ...
        'empirically_contracting_on_test_set', ...
        'not_contracting_on_test_set', ...
        'inconclusive'}));
end

function testDdeSmoothNonconstantHistories(testCase)
    params = make_linear_activation_params(struct( ...
        'n', 2, 'lags', 0.05, 'n_a_E', 0, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0));
    params.W = 0.2 * eye(2);
    params = validate_MESN_params(params);
    esn = SRNN_ESN(params);
    U = zeros(100, 1);
    esp = verify_echo_state_property(esn, U, struct( ...
        'n_ic', 3, 'ic_scale', 0.2, 'washout_steps', 15, ...
        'min_tail_points', 20, 'verbose', false, 'ic_seed', 8, ...
        'dde_history_mode', 'smooth'));
    testCase.verifyTrue(esp.dde_empirical_only);
    testCase.verifyTrue(esp.history_space_sampled);
    testCase.verifyEqual(esp.dde_history_mode, 'smooth');
    testCase.verifyFalse(isfield(esp, 'esp_holds'));
end

function testExplicitDdeHistoryFnStartsDistinctTrials(testCase)
    params = make_linear_activation_params(struct('n', 2, 'lags', 0.04));
    params.W = zeros(2);
    params = validate_MESN_params(params);
    esn = SRNN_ESN(params);
    layout = state_layout(params);
    S1 = zeros(layout.n_total, 1); S1(layout.idx_x) = [0.5; -0.1];
    S2 = zeros(layout.n_total, 1); S2(layout.idx_x) = [-0.4; 0.3];
    U = zeros(30, 1);
    [~, H1] = esn.runReservoir(U, struct( ...
        'reset_before', false, 'update_internal_state', false, ...
        'history_fn', @(t) S1));
    [~, H2] = esn.runReservoir(U, struct( ...
        'reset_before', false, 'update_internal_state', false, ...
        'history_fn', @(t) S2));
    testCase.verifyGreaterThan(norm(H1(1, :) - H2(1, :)), 1e-12);
end

function testCompactEspCanonicalFieldsAndCellFailure(testCase)
    addpath(genpath(fullfile(testCase.TestData.repo_root, 'experiments', 'revalidated')));
    esp = struct( ...
        'classification', 'empirically_contracting_on_test_set', ...
        'classification_reason', 'median_pair_slope_below_contracting_threshold', ...
        'pair_slopes', [-0.2; -0.25], ...
        'median_pair_slope', -0.225, ...
        'mean_pair_slope', -0.225, ...
        'slope_per_time_units', 'per_second', ...
        'pair_slopes_per_sample_compat', [-0.02; -0.025], ...
        'final_max_spread', 1e-3, ...
        'final_median_spread', 8e-4, ...
        'convergence_ratio', 0.1, ...
        'n_usable_tail_points', 40, ...
        'fraction_at_floor', 0, ...
        'fit_interval_seconds', [1, 5], ...
        'fit_quality_r2', 0.99, ...
        'dde_empirical_only', false, ...
        'history_space_sampled', false, ...
        'dde_constant_history_limitation', false);
    s = compact_empirical_convergence(esp);
    [ok, reason] = validate_empirical_convergence_endpoint(s);
    testCase.verifyTrue(ok, reason);
    testCase.verifyFalse(isfield(s, 'median_slope'));
    testCase.verifyFalse(isfield(s, 'mean_slope'));
    testCase.verifyFalse(isfield(s, 'slope_mean'));
    testCase.verifyFalse(isfield(s, 'esp_holds'));

    bad = s;
    bad.median_pair_slope = NaN;
    [ok_bad, reason_bad] = validate_empirical_convergence_endpoint(bad);
    testCase.verifyFalse(ok_bad);
    testCase.verifyEqual(reason_bad, 'nonfinite_required_pair_slope');

    legacy = rmfield(s, {'median_pair_slope', 'mean_pair_slope'});
    legacy.median_slope = -0.2;
    legacy.mean_slope = -0.2;
    [ok_legacy, reason_legacy] = validate_empirical_convergence_endpoint(legacy);
    testCase.verifyFalse(ok_legacy);
    testCase.verifyEqual(reason_legacy, 'legacy_slope_field_without_canonical_pair_slopes');
end

function X = scalar_ode_traj(U, S0, lambda, dt)
    T = size(U, 1);
    t = (0:T-1)' * dt;
    x0 = S0(1);
    X = x0 * exp(lambda * t);
end
