function tests = test_fair_sfa_profiles
% test_fair_sfa_profiles  Phase 3 adaptation profiles, features, and masks.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    testCase.TestData.repo_root = repo_root;
    testCase.TestData.c_total_E = 0.1 / 7;
    testCase.TestData.c_total_I = 0.1 / 4;
end

function testEveryProfileHasExpectedTauAndCoupling(testCase)
    cfg = mechanism_ablation_config('publication');
    expected = expected_profile_table(testCase);
    for i = 1:numel(cfg.adaptation_profiles)
        p = cfg.adaptation_profiles{i};
        testCase.verifyTrue(isfield(expected, p.label), p.label);
        e = expected.(p.label);
        testCase.verifyEqual(p.n_a_E, e.n_a_E, p.label);
        testCase.verifyEqual(p.n_a_I, e.n_a_I, p.label);
        testCase.verifyEqual(p.tau_a_E, e.tau_a_E, 'AbsTol', 0, p.label);
        testCase.verifyEqual(p.tau_a_I, e.tau_a_I, 'AbsTol', 0, p.label);
        testCase.verifyEqual(p.c_a_E, e.c_a_E, 'AbsTol', 0, p.label);
        testCase.verifyEqual(p.c_a_I, e.c_a_I, 'AbsTol', 0, p.label);
        testCase.verifyTrue(isfield(p, 'analysis_role'));
        testCase.verifyTrue(isfield(p, 'analysis_set'));
        testCase.verifyTrue(isfield(p, 'scientific_description'));
        testCase.verifyFalse(isempty(p.scientific_description), p.label);
    end
end

function testNonOffProfilesSumToTotalCoupling(testCase)
    cfg = mechanism_ablation_config('publication');
    for i = 1:numel(cfg.adaptation_profiles)
        p = cfg.adaptation_profiles{i};
        if strcmp(p.label, 'off')
            testCase.verifyEqual(sum(p.c_a_E), 0);
            testCase.verifyEqual(sum(p.c_a_I), 0);
            continue;
        end
        testCase.verifyEqual(sum(p.c_a_E), testCase.TestData.c_total_E, ...
            'AbsTol', 1e-15, p.label);
        testCase.verifyEqual(sum(p.c_a_I), testCase.TestData.c_total_I, ...
            'AbsTol', 1e-15, p.label);
    end
end

function testFrozenInhibitoryAdaptationAcrossNonOff(testCase)
    cfg = mechanism_ablation_config('publication');
    for i = 1:numel(cfg.adaptation_profiles)
        p = cfg.adaptation_profiles{i};
        if strcmp(p.label, 'off')
            continue;
        end
        testCase.verifyEqual(p.n_a_I, 1, p.label);
        testCase.verifyEqual(p.tau_a_I, 0.25, 'AbsTol', 0, p.label);
        testCase.verifyEqual(p.c_a_I, testCase.TestData.c_total_I, ...
            'AbsTol', 0, p.label);
    end
    testCase.verifyTrue(contains(string(cfg.manipulated_mechanism), ...
        "multi-timescale excitatory SFA"));
end

function testThreeTimescalesAndMomentMatchedEqualTotalCoupling(testCase)
    cfg = mechanism_ablation_config('publication');
    three = profile_by_label(cfg, 'three_timescales');
    single = profile_by_label(cfg, 'single_moment_matched');
    testCase.verifyEqual(sum(three.c_a_E), sum(single.c_a_E), 'AbsTol', 1e-15);
    testCase.verifyEqual(sum(three.c_a_I), sum(single.c_a_I), 'AbsTol', 1e-15);
end

function testMomentMatchedTauIs925(testCase)
    cfg = mechanism_ablation_config('publication');
    p = profile_by_label(cfg, 'single_moment_matched');
    tau_eff = (0.25 + 2.5 + 25) / 3;
    testCase.verifyEqual(tau_eff, 9.25, 'AbsTol', 0);
    testCase.verifyEqual(p.tau_a_E, 9.25, 'AbsTol', 0);
    testCase.verifyEqual(cfg.moment_matched_tau_E, 9.25, 'AbsTol', 0);
end

function testIdenticalDimensionControlMatchesThreeTimescaleStateDim(testCase)
    cfg = mechanism_ablation_config('publication');
    three = profile_by_label(cfg, 'three_timescales');
    identical = profile_by_label(cfg, 'three_identical_dimension_control');
    testCase.verifyEqual(identical.n_a_E, three.n_a_E);
    testCase.verifyEqual(identical.n_a_I, three.n_a_I);
    testCase.verifyEqual(sum(identical.c_a_E), sum(three.c_a_E), 'AbsTol', 1e-15);
end

function testIdenticalControlMatchedEffectiveAdaptationAtInit(testCase)
    cfg = mechanism_ablation_config('publication', 'sfa_sensitivity');
    seed = 1729;
    cell_single = find_cell(cfg, 'single_moment_matched', 'x');
    cell_ident = find_cell(cfg, 'three_identical_dimension_control', 'x');
    [p_single, ~] = build_ablation_params(cell_single, seed, cfg);
    [p_ident, ~] = build_ablation_params(cell_ident, seed, cfg);

    esn_s = SRNN_ESN(p_single);
    esn_i = SRNN_ESN(p_ident);
    st_s = unpack_state(esn_s.S0, p_single);
    st_i = unpack_state(esn_i.S0, p_ident);

    eff_s = st_s.a_E * p_single.c_a_E(:);
    eff_i = st_i.a_E * p_ident.c_a_E(:);
    testCase.verifyEqual(eff_s, eff_i, 'AbsTol', 1e-14);
    testCase.verifyEqual(st_i.a_E(:, 1), st_i.a_E(:, 2), 'AbsTol', 0);
    testCase.verifyEqual(st_i.a_E(:, 1), st_i.a_E(:, 3), 'AbsTol', 0);
end

function testIdenticalControlDynamicsAgreeWithMomentMatched(testCase)
    % Documented tolerance for ODE integration of dynamically equivalent
    % single_moment_matched vs three_identical_dimension_control under
    % paired_weighted_match initialization and identical input.
    tol_rate = 1e-6;
    tol_eff = 1e-6;
    cfg = mechanism_ablation_config('smoke', 'sfa_sensitivity');
    seed = 31415;
    cell_single = find_cell(cfg, 'single_moment_matched', 'x');
    cell_ident = find_cell(cfg, 'three_identical_dimension_control', 'x');
    [p_single, ~] = build_ablation_params(cell_single, seed, cfg);
    [p_ident, ~] = build_ablation_params(cell_ident, seed, cfg);
    testCase.verifyEqual(p_single.W, p_ident.W);
    testCase.verifyEqual(p_single.W_in, p_ident.W_in);

    esn_s = SRNN_ESN(p_single);
    esn_i = SRNN_ESN(p_ident);
    esn_s.ode_solver = @ode45;
    esn_i.ode_solver = @ode45;

    rng(seed + 99);
    U = 2 * rand(40, size(p_single.W_in, 2)) - 1;
    opts = struct('reset_before', true, 'update_internal_state', false, ...
        'ode_reltol', 1e-8, 'ode_abstol', 1e-10);
    [~, S_s] = esn_s.runReservoir(U, opts);
    [~, S_i] = esn_i.runReservoir(U, opts);

    max_rate_err = 0;
    max_eff_err = 0;
    for t = 1:size(S_s, 1)
        st_s = unpack_state(S_s(t, :)', p_single);
        st_i = unpack_state(S_i(t, :)', p_ident);
        [r_s, ~] = esn_s.computeRates(S_s(t, :)');
        [r_i, ~] = esn_i.computeRates(S_i(t, :)');
        max_rate_err = max(max_rate_err, max(abs(r_s - r_i)));
        eff_s = st_s.a_E * p_single.c_a_E(:);
        eff_i = st_i.a_E * p_ident.c_a_E(:);
        max_eff_err = max(max_eff_err, max(abs(eff_s - eff_i)));
        testCase.verifyEqual(st_s.x, st_i.x, 'AbsTol', tol_rate);
    end
    testCase.verifyLessThanOrEqual(max_rate_err, tol_rate);
    testCase.verifyLessThanOrEqual(max_eff_err, tol_eff);
end

function testExplicitTauSurvivesBuildAblationParams(testCase)
    labels = {'single_fast', 'single_middle', 'single_slow', ...
        'single_moment_matched', 'three_timescales', ...
        'three_identical_dimension_control'};
    cfg_all = mechanism_ablation_config('publication');
    cfg_sens = mechanism_ablation_config('publication', 'sfa_sensitivity');
    for i = 1:numel(labels)
        c = find_cell(cfg_sens, labels{i}, 'x');
        testCase.verifyFalse(isempty(fieldnames(c)), labels{i});
        [params, ~] = build_ablation_params(c, 1729, cfg_sens);
        prof = profile_by_label(cfg_all, labels{i});
        testCase.verifyEqual(params.tau_a_E, prof.tau_a_E, 'AbsTol', 0, labels{i});
        testCase.verifyEqual(params.tau_a_I, prof.tau_a_I, 'AbsTol', 0, labels{i});
        if strcmp(labels{i}, 'single_moment_matched')
            legacy = logspace(log10(0.25), log10(25), 1);
            testCase.verifyNotEqual(params.tau_a_E, legacy);
        end
        if strcmp(labels{i}, 'three_timescales')
            testCase.verifyEqual(params.tau_a_E, [0.25, 2.5, 25], 'AbsTol', 1e-12);
        end
        if strcmp(labels{i}, 'three_identical_dimension_control')
            legacy3 = logspace(log10(0.25), log10(25), 3);
            testCase.verifyNotEqual(params.tau_a_E, legacy3);
        end
    end
end

function testConfirmatoryCellCountIs24(testCase)
    cfg = mechanism_ablation_config('publication');
    testCase.verifyEqual(cfg.active_analysis_set, 'confirmatory');
    testCase.verifyEqual(numel(cfg.cells), 24);
    testCase.verifyEqual(cfg.n_confirmatory_cells_per_seed, 24);
    testCase.verifyEqual(numel(cfg.cells_by_analysis_set.confirmatory), 24);
end

function testSensitivityCellCountIs12(testCase)
    cfg = mechanism_ablation_config('publication', 'sfa_sensitivity');
    testCase.verifyEqual(cfg.active_analysis_set, 'sfa_sensitivity');
    testCase.verifyEqual(numel(cfg.cells), 12);
    testCase.verifyEqual(cfg.n_sfa_sensitivity_cells_per_seed, 12);
end

function testNoAllFeatureCellIsConfirmatory(testCase)
    cfg_c = mechanism_ablation_config('publication', 'confirmatory');
    for i = 1:numel(cfg_c.cells)
        testCase.verifyNotEqual(cfg_c.cells{i}.which_states, 'all');
        testCase.verifyEqual(cfg_c.cells{i}.feature_analysis_role, 'confirmatory');
    end
    cfg_e = mechanism_ablation_config('publication', 'feature_exploratory');
    for i = 1:numel(cfg_e.cells)
        testCase.verifyEqual(cfg_e.cells{i}.which_states, 'all');
        testCase.verifyEqual(cfg_e.cells{i}.feature_analysis_role, 'exploratory');
        testCase.verifyEqual(cfg_e.cells{i}.analysis_set, 'feature_exploratory');
        testCase.verifyFalse(cfg_e.cells{i}.dimension_matched);
    end
end

function testXRFeatureDimensionsEqualNAcrossMechanisms(testCase)
    for aset = {'confirmatory', 'sfa_sensitivity'}
        cfg = mechanism_ablation_config('publication', aset{1});
        n = cfg.base.n;
        for i = 1:numel(cfg.cells)
            c = cfg.cells{i};
            if any(strcmp(c.which_states, {'x', 'r'}))
                testCase.verifyEqual(c.raw_feature_dimension, n, c.cell_key);
                testCase.verifyEqual(c.projected_feature_dimension, n, c.cell_key);
                testCase.verifyTrue(c.dimension_matched, c.cell_key);
                [params, ~] = build_ablation_params(c, 1729, cfg);
                esn = SRNN_ESN(params);
                U = zeros(5, size(params.W_in, 2));
                X = esn.runReservoir(U, struct('reset_before', true, ...
                    'update_internal_state', false));
                testCase.verifyEqual(size(X, 2), n, c.cell_key);
            end
        end
    end
end

function testPairedMechanismsShareWAndWin(testCase)
    cfg = mechanism_ablation_config('publication');
    seed = 10007;
    cells = cfg.cells;
    [p0, ~] = build_ablation_params(cells{1}, seed, cfg);
    for i = 2:numel(cells)
        [p, ~] = build_ablation_params(cells{i}, seed, cfg);
        testCase.verifyEqual(p.W, p0.W, cells{i}.cell_key);
        testCase.verifyEqual(p.W_in, p0.W_in, cells{i}.cell_key);
    end
end

function testFixedCountInputHasExactKNonzeros(testCase)
    n = 40;
    sparsity = 0.8;
    k = max(1, round((1 - sparsity) * n));
    [params, meta] = default_MESN_config(struct( ...
        'n', n, ...
        'n_inputs', 3, ...
        'input_sparsity', sparsity, ...
        'input_mask_mode', 'fixed_count', ...
        'input_rng_seed', 123));
    testCase.verifyEqual(params.input_mask_mode, 'fixed_count');
    for j = 1:size(params.W_in, 2)
        testCase.verifyEqual(nnz(params.W_in(:, j)), k);
        testCase.verifyEqual(params.input_nnz_per_channel(j), k);
        testCase.verifyEqual(numel(params.input_driven_indices{j}), k);
        testCase.verifyEqual(meta.input_nnz_per_channel(j), k);
    end
end

function testFixedCountInputIsDeterministic(testCase)
    ov = struct('n', 24, 'n_inputs', 2, 'input_sparsity', 0.75, ...
        'input_mask_mode', 'fixed_count', 'input_rng_seed', 777);
    p1 = default_MESN_config(ov);
    p2 = default_MESN_config(ov);
    testCase.verifyEqual(p1.W_in, p2.W_in);
    testCase.verifyEqual(p1.input_driven_indices, p2.input_driven_indices);
end

function testPublicationWinCannotBeCompletelyZero(testCase)
    cfg = mechanism_ablation_config('publication');
    testCase.verifyEqual(cfg.base.input_mask_mode, 'fixed_count');
    for i = 1:numel(cfg.cells)
        [params, ~] = build_ablation_params(cfg.cells{i}, cfg.seeds(1), cfg);
        testCase.verifyGreaterThan(nnz(params.W_in), 0, cfg.cells{i}.cell_key);
        testCase.verifyTrue(all(params.input_nnz_per_channel >= 1));
    end
end

function testLegacyBernoulliModeRemainsAvailable(testCase)
    [params, meta] = default_MESN_config(struct( ...
        'n', 30, ...
        'input_sparsity', 0.8, ...
        'input_mask_mode', 'bernoulli', ...
        'input_rng_seed', 9));
    testCase.verifyEqual(params.input_mask_mode, 'bernoulli');
    testCase.verifyEqual(meta.input_mask_mode, 'bernoulli');
    % Bernoulli may theoretically be all-zero; mode must still be selectable.
    testCase.verifyTrue(isfield(params, 'input_driven_indices'));
end

function testProtocolFingerprintChangesWithScientificPolicy(testCase)
    cfg = mechanism_ablation_config('publication');
    fp0 = cfg.protocol_fingerprint;

    cfg_a = cfg;
    cfg_a.adaptation_profiles{2}.tau_a_E = 0.26;
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg_a));

    cfg_b = cfg;
    cfg_b.feature_policy.x.feature_analysis_role = 'exploratory';
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg_b));

    cfg_c = cfg;
    cfg_c.base.input_mask_mode = 'bernoulli';
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg_c));

    cfg_d = cfg;
    cfg_d.base.adaptation_initialization_mode = 'legacy_independent';
    testCase.verifyNotEqual(fp0, compute_protocol_fingerprint(cfg_d));

    cfg_sens = mechanism_ablation_config('publication', 'sfa_sensitivity');
    testCase.verifyNotEqual(fp0, cfg_sens.protocol_fingerprint);
end

function testProtocolFingerprintStableAcrossTimestamps(testCase)
    cfg_a = mechanism_ablation_config('publication');
    cfg_b = mechanism_ablation_config('publication');
    cfg_b.created_utc = '2099-12-31T23:59:59Z';
    testCase.verifyEqual(cfg_a.protocol_fingerprint, ...
        compute_protocol_fingerprint(cfg_b));
end

%% --- helpers ---

function expected = expected_profile_table(testCase)
    cE = testCase.TestData.c_total_E;
    cI = testCase.TestData.c_total_I;
    expected = struct();
    expected.off = struct('n_a_E', 0, 'n_a_I', 0, ...
        'tau_a_E', zeros(1, 0), 'tau_a_I', zeros(1, 0), ...
        'c_a_E', zeros(1, 0), 'c_a_I', zeros(1, 0));
    expected.single_fast = struct('n_a_E', 1, 'n_a_I', 1, ...
        'tau_a_E', 0.25, 'tau_a_I', 0.25, 'c_a_E', cE, 'c_a_I', cI);
    expected.single_middle = struct('n_a_E', 1, 'n_a_I', 1, ...
        'tau_a_E', 2.5, 'tau_a_I', 0.25, 'c_a_E', cE, 'c_a_I', cI);
    expected.single_slow = struct('n_a_E', 1, 'n_a_I', 1, ...
        'tau_a_E', 25, 'tau_a_I', 0.25, 'c_a_E', cE, 'c_a_I', cI);
    expected.single_moment_matched = struct('n_a_E', 1, 'n_a_I', 1, ...
        'tau_a_E', 9.25, 'tau_a_I', 0.25, 'c_a_E', cE, 'c_a_I', cI);
    expected.three_timescales = struct('n_a_E', 3, 'n_a_I', 1, ...
        'tau_a_E', [0.25, 2.5, 25], 'tau_a_I', 0.25, ...
        'c_a_E', ones(1, 3) * (cE / 3), 'c_a_I', cI);
    expected.three_identical_dimension_control = struct('n_a_E', 3, 'n_a_I', 1, ...
        'tau_a_E', [9.25, 9.25, 9.25], 'tau_a_I', 0.25, ...
        'c_a_E', ones(1, 3) * (cE / 3), 'c_a_I', cI);
end

function p = profile_by_label(cfg, label)
    p = [];
    for i = 1:numel(cfg.adaptation_profiles)
        if strcmp(cfg.adaptation_profiles{i}.label, label)
            p = cfg.adaptation_profiles{i};
            return;
        end
    end
    error('profile_by_label:Missing', 'Profile %s not found.', label);
end

function c = find_cell(cfg, adapt_label, feat_label)
    c = struct();
    for i = 1:numel(cfg.cells)
        if strcmp(cfg.cells{i}.adaptation, adapt_label) && ...
                strcmp(cfg.cells{i}.readout_features, feat_label)
            c = cfg.cells{i};
            return;
        end
    end
end
