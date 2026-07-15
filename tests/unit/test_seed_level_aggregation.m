function tests = test_seed_level_aggregation
% test_seed_level_aggregation  Phase 5A matrix validation + seed tables.
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

function testExactMatrixPasses(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    report = validate_aggregation_run_matrix(run_dir, cfg);
    testCase.verifyTrue(report.ok, strjoin(report.reasons, '; '));
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    testCase.verifyEqual(agg.status, 'ok');
    testCase.verifyTrue(agg.matched_seed_contrast_structure_complete);
end

function testMissingCellFails(testCase)
    cfg0 = mechanism_ablation_config('smoke', 'confirmatory');
    key = cfg0.cells{1}.cell_key;
    seed = cfg0.seeds(1);
    run_dir = make_synthetic_aggregation_run(struct( ...
        'omit_pair', struct('seed', seed, 'cell_key', key)));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    report = validate_aggregation_run_matrix(run_dir, cfg);
    testCase.verifyFalse(report.ok);
    testCase.verifyTrue(any(startsWith(report.reasons, 'missing_pair:')));
    testCase.verifyError(@() aggregate_ablation_results(run_dir, struct('save', false)), ...
        'aggregate_ablation_results:MissingCells');
end

function testMissingSeedFails(testCase)
    cfg0 = mechanism_ablation_config('smoke', 'confirmatory');
    run_dir = make_synthetic_aggregation_run(struct('omit_seed', cfg0.seeds(1)));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    report = validate_aggregation_run_matrix(run_dir, cfg);
    testCase.verifyFalse(report.ok);
    testCase.verifyTrue(any(startsWith(report.reasons, 'missing_pair:')));
end

function testMissingConditionFails(testCase)
    cfg0 = mechanism_ablation_config('smoke', 'confirmatory');
    run_dir = make_synthetic_aggregation_run(struct( ...
        'omit_condition', cfg0.cells{1}.cell_key));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    report = validate_aggregation_run_matrix(run_dir, cfg);
    testCase.verifyFalse(report.ok);
    testCase.verifyTrue(any(startsWith(report.reasons, 'missing_pair:')));
end

function testDuplicateFails(testCase)
    cfg0 = mechanism_ablation_config('smoke', 'confirmatory');
    pair = struct('seed', cfg0.seeds(1), 'cell_key', cfg0.cells{1}.cell_key);
    run_dir = make_synthetic_aggregation_run(struct('duplicate_pair', pair));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    report = validate_aggregation_run_matrix(run_dir, cfg);
    testCase.verifyFalse(report.ok);
    testCase.verifyTrue(any(startsWith(report.reasons, 'duplicate_seed_cell_pair:')));
end

function testExtraSeedFails(testCase)
    run_dir = make_synthetic_aggregation_run(struct('extra_seed', 99901));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    report = validate_aggregation_run_matrix(run_dir, cfg);
    testCase.verifyFalse(report.ok);
    testCase.verifyTrue(any(startsWith(report.reasons, 'extra_seed:')));
end

function testExtraConditionFails(testCase)
    run_dir = make_synthetic_aggregation_run(struct( ...
        'extra_cell_key', 'adapt-extra__std-off__delay-ode_off__feat-x'));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    report = validate_aggregation_run_matrix(run_dir, cfg);
    testCase.verifyFalse(report.ok);
    testCase.verifyTrue(any(startsWith(report.reasons, 'extra_cell_key:')));
end

function testFailedCellFails(testCase)
    cfg0 = mechanism_ablation_config('smoke', 'confirmatory');
    pair = struct('seed', cfg0.seeds(1), 'cell_key', cfg0.cells{1}.cell_key);
    run_dir = make_synthetic_aggregation_run(struct('failed_cell', pair));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    report = validate_aggregation_run_matrix(run_dir, cfg);
    testCase.verifyFalse(report.ok);
    testCase.verifyTrue(any(startsWith(report.reasons, 'failed_cell:')));
end

function testWrongFingerprintFails(testCase)
    cfg0 = mechanism_ablation_config('smoke', 'confirmatory');
    pair = struct('seed', cfg0.seeds(1), 'cell_key', cfg0.cells{1}.cell_key);
    run_dir = make_synthetic_aggregation_run(struct( ...
        'wrong_fingerprint_pair', pair));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    report = validate_aggregation_run_matrix(run_dir, cfg);
    testCase.verifyFalse(report.ok);
    testCase.verifyTrue(any(startsWith(report.reasons, 'cell_fingerprint_mismatch:')));
end

function testWrongAnalysisSetFails(testCase)
    cfg0 = mechanism_ablation_config('smoke', 'confirmatory');
    pair = struct('seed', cfg0.seeds(1), 'cell_key', cfg0.cells{1}.cell_key);
    run_dir = make_synthetic_aggregation_run(struct( ...
        'wrong_analysis_set_pair', pair));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    report = validate_aggregation_run_matrix(run_dir, cfg);
    testCase.verifyFalse(report.ok);
    testCase.verifyTrue(any(startsWith(report.reasons, 'analysis_set_mismatch:')));
end

function testPartialPublicationNotInferenceReady(testCase)
    cfg0 = mechanism_ablation_config('smoke', 'confirmatory');
    run_dir = make_synthetic_aggregation_run(struct( ...
        'omit_seed', cfg0.seeds(1)));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct( ...
        'save', false, 'allow_incomplete_diagnostic', true));
    testCase.verifyEqual(agg.status, 'diagnostic_incomplete_not_for_inference');
    testCase.verifyFalse(agg.matched_seed_contrast_structure_complete);
    testCase.verifyFalse(agg.aggregation_inference_complete);
    testCase.verifyEqual(agg.inference_status, 'deferred_to_phase_5b');
end

function testOneUniqueBaselineRowPerSeed(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    T = agg.tables.unique_seed_baseline;
    testCase.verifyEqual(height(T), numel(agg.seeds));
    testCase.verifyEqual(numel(unique(T.seed)), height(T));
end

function testIdenticalCompactBaselinesDoNotDuplicateObservations(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    % Unique baseline table has one row/seed even though many ODE cells share
    % identical compact autonomous control hashes.
    testCase.verifyEqual(height(agg.tables.unique_seed_baseline), numel(agg.seeds));
    raw = agg.tables.raw_cell;
    for s = agg.seeds(:)'
        mask = raw.seed == s;
        hashes = unique(raw.autonomous_control_content_hash(mask));
        hashes = hashes(~cellfun(@isempty, cellstr(string(hashes))));
        testCase.verifyLessThanOrEqual(numel(hashes), 1);
    end
end

function testDifferentBaselineHashWithinSeedFails(testCase)
    run_dir = make_synthetic_aggregation_run(struct( ...
        'hash_mismatch_seed', mechanism_ablation_config('smoke').seeds(1)));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    report = validate_aggregation_run_matrix(run_dir, cfg);
    testCase.verifyFalse(report.ok);
    testCase.verifyTrue(any(startsWith(report.reasons, ...
        'autonomous_content_hash_mismatch:')));
end

function testDaleFeatXAndFeatRResolve(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    D = agg.tables.dale_resolution;
    testCase.verifyGreaterThan(height(D), 0);
    mask_x = strcmp(cellstr(string(D.feature_mode)), 'x');
    mask_r = strcmp(cellstr(string(D.feature_mode)), 'r');
    testCase.verifyTrue(any(mask_x));
    testCase.verifyTrue(any(mask_r));
    ref_x = unique(cellstr(string(D.reference_cell_key(mask_x))));
    ref_r = unique(cellstr(string(D.reference_cell_key(mask_r))));
    testCase.verifyEqual(ref_x, {'adapt-off__std-off__delay-ode_off__feat-x'});
    testCase.verifyEqual(ref_r, {'adapt-off__std-off__delay-ode_off__feat-r'});
end

function testCrossSeedDaleFails(testCase)
    % Omit Dale reference cells for one seed only → resolution must fail.
    run_dir = make_synthetic_aggregation_run(struct( ...
        'omit_dale_ref_for_seed', mechanism_ablation_config('smoke').seeds(1)));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    testCase.verifyError(@() aggregate_ablation_results(run_dir, struct('save', false)), ...
        'aggregate_ablation_results:MissingCells');
end

function testMissingDaleRefFails(testCase)
    run_dir = make_synthetic_aggregation_run(struct('missing_dale_ref_key', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    report = validate_aggregation_run_matrix(run_dir, cfg);
    testCase.verifyFalse(report.ok);
    testCase.verifyTrue(any(contains(report.reasons, 'dale_reference_key_invalid')));
end

function testConventionalEsnNeverLabeledDale(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    D = agg.tables.dale_resolution;
    refs = cellstr(string(D.reference_cell_key));
    testCase.verifyFalse(any(contains(refs, 'conventional')));
    % Spot-check a raw cell: conventional baseline family is not Dale
    cfg = load_cfg(run_dir);
    S = load(fullfile(run_dir, 'cells', sprintf('seed_%d__%s.mat', ...
        cfg.seeds(1), cfg.cells{1}.cell_key)), 'cell_result');
    ce = S.cell_result.narma.baselines.conventional_leaky_esn;
    testCase.verifyEqual(ce.model_family, 'conventional_leaky_esn');
    testCase.verifyNotEqual(ce.model_family, 'dale_mesn_control');
end

function testDdeAutonomousDaleNA(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    D = agg.tables.dale_resolution;
    mask = strcmp(cellstr(string(D.task)), 'mg_autonomous') & ...
        strcmp(cellstr(string(D.status)), 'not_applicable_dde');
    testCase.verifyTrue(any(mask));
end

function testDdeUnsupportedNanAccepted(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    report = validate_aggregation_run_matrix(run_dir, cfg);
    testCase.verifyTrue(report.ok, strjoin(report.reasons, '; '));
end

function testDdeFiniteRejected(testCase)
    run_dir = make_synthetic_aggregation_run(struct('dde_finite_autonomous', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    report = validate_aggregation_run_matrix(run_dir, cfg);
    testCase.verifyFalse(report.ok);
    testCase.verifyTrue(any(contains(report.reasons, ...
        'dde_autonomous_finite_values_forbidden')));
end

function testOdeMissingRejected(testCase)
    run_dir = make_synthetic_aggregation_run(struct( ...
        'ode_missing_autonomous', true, 'secondary_enabled', true));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    report = validate_aggregation_run_matrix(run_dir, cfg);
    testCase.verifyFalse(report.ok);
    testCase.verifyTrue(any(contains(report.reasons, 'ode_autonomous')));
end

function testNoInferenceFieldsProduced(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    names = agg.tables.seed_contrast.Properties.VariableNames;
    forbidden = {'p_value', 'pvalue', 'ci_low', 'ci_high', 'cliff_delta', ...
        'cliff', 'bootstrap', 'stderr'};
    for i = 1:numel(forbidden)
        testCase.verifyFalse(any(contains(lower(names), forbidden{i})));
    end
    testCase.verifyTrue(agg.no_inference);
end

function testCsvFlatWritetableCompatible(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', true));
    csv_path = fullfile(run_dir, 'aggregation', 'seed_contrast_table.csv');
    testCase.verifyTrue(isfile(csv_path));
    T = readtable(csv_path);
    testCase.verifyGreaterThan(height(T), 0);
    testCase.verifyTrue(isnumeric(T.delta_raw) || isnumeric(T.seed));
    testCase.verifyTrue(iscellstr(T.contrast_id) || isstring(T.contrast_id) || ...
        iscell(T.contrast_id));
end

function testContentHashesPresent(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', true));
    testCase.verifyTrue(isfield(agg, 'table_content_hashes'));
    h = agg.table_content_hashes;
    for nm = {'raw_cell_table', 'seed_contrast_table', 'dale_resolution_table'}
        testCase.verifyTrue(isfield(h, nm{1}));
        testCase.verifyTrue(ischar(h.(nm{1})) || isstring(h.(nm{1})));
        testCase.verifyGreaterThan(strlength(string(h.(nm{1}))), 0);
    end
end

function testAggregationNeverCallsRunAblationCell(testCase)
    % Absurd marker MC values would never come from a real model; aggregation
    % must preserve them unchanged (fixture cells used as-is).
    marker = 8888;
    run_dir = make_synthetic_aggregation_run(struct('absurd_marker', marker));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    mc = agg.tables.raw_cell.mc_total;
    testCase.verifyTrue(all(mc > marker));
    testCase.verifyTrue(all(mc < marker + 50));
end

function testOriginsNeverInSeedContrastTable(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    agg = aggregate_ablation_results(run_dir, struct('save', false));
    names = lower(agg.tables.seed_contrast.Properties.VariableNames);
    testCase.verifyFalse(any(contains(names, 'origin')));
    testCase.verifyFalse(any(strcmp(names, 'origin_indices')));
    testCase.verifyFalse(any(strcmp(names, 'n_forecast_origins')));
end

%% helpers
function cfg = load_cfg(run_dir)
    S = load(fullfile(run_dir, 'preregistered_config.mat'), 'cfg');
    cfg = S.cfg;
end
