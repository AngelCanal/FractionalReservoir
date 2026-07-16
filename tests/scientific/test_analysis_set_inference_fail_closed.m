function tests = test_analysis_set_inference_fail_closed
% test_analysis_set_inference_fail_closed  Phase 5B-B-R analysis-set policy.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(genpath(fullfile(repo_root, 'tests')));
end

function testFeatureExploratoryPublicationInferenceNeverComplete(testCase)
    run_dir = make_synthetic_aggregation_run(struct( ...
        'protocol_tier', 'publication', ...
        'analysis_set', 'feature_exploratory'));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    inf = run_seed_level_inference(run_dir, struct('save', true));
    testCase.verifyFalse(inf.publication_inference_complete);
    testCase.verifyFalse(inf.aggregation_inference_complete);
    testCase.verifyEqual(inf.inference_execution_status, ...
        'complete_exploratory_noninferential');
    T = inf.inference_summary_table;
    for r = 1:height(T)
        testCase.verifyEqual(char(string(T.executed_action(r))), 'estimate_only');
        testCase.verifyFalse(logical(T.claim_allowed(r)));
        testCase.verifyFalse(isfinite(double(T.p_value(r))));
    end
end

function testFeatureExploratoryPublicationReadinessAlwaysFalse(testCase)
    run_dir = make_synthetic_aggregation_run(struct( ...
        'protocol_tier', 'publication', ...
        'analysis_set', 'feature_exploratory'));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    run_seed_level_inference(run_dir, struct('save', true));
    cfg = load_cfg(run_dir);
    report = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', struct([]), ...
        'run_dir', run_dir, ...
        'has_manifest', true, ...
        'has_commit_sha', true, ...
        'has_artifact_hashes', true, ...
        'aggregation', struct('status', 'ok', ...
            'matched_seed_contrast_structure_complete', true, ...
            'inference_status', 'complete_exploratory_noninferential')));
    testCase.verifyFalse(report.publication_ready);
    idx = find(strcmp({report.checks.name}, ...
        'analysis_set_is_publication_inferential'), 1);
    testCase.verifyFalse(report.checks(idx).pass);
end

function testForgedFeatureExploratoryCompletionRejected(testCase)
    run_dir = make_synthetic_aggregation_run(struct( ...
        'protocol_tier', 'publication', ...
        'analysis_set', 'feature_exploratory'));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    run_seed_level_inference(run_dir, struct('save', true));
    manifest_path = fullfile(run_dir, 'aggregation', 'inference', ...
        'inference_manifest.mat');
    Sm = load(manifest_path, 'inference_manifest');
    Sm.inference_manifest.publication_inference_complete = true;
    save(manifest_path, '-struct', 'Sm');
    val = validate_aggregation_inference_artifact(run_dir);
    testCase.verifyFalse(val.valid);
    testCase.verifyFalse(val.aggregation_inference_complete);
    names = {val.checks.name};
    testCase.verifyTrue(any(strcmp(names, 'feature_exploratory_noninferential')));
    testCase.verifyTrue(any(strcmp(names, 'inference_completion_consistent_with_analysis_set')));
end

function testExpectedCfgSelfReferenceForbidden(testCase)
    cfg = mechanism_ablation_config('publication', 'confirmatory');
    cfg.frozen_operating_point = struct( ...
        'level_of_chaos', 1.0, ...
        'input_scaling', 0.5, ...
        'source', 'synthetic_test_fixture');
    cfg.protocol_fingerprint = compute_protocol_fingerprint(cfg);
    ref = mechanism_ablation_config('publication', 'confirmatory');
    testCase.verifyNotEqual(char(cfg.protocol_fingerprint), ...
        char(compute_protocol_fingerprint(ref)));
    testCase.verifyError(@() evaluate_publication_readiness(cfg, struct( ...
        'expected_cfg', cfg, 'cell_records', struct([]))), ...
        'evaluate_publication_readiness:ExpectedCfgOverrideForbidden');
end

function testValidatePublicationRunExpectedCfgForbidden(testCase)
    run_dir = make_synthetic_aggregation_run(struct('protocol_tier', 'publication'));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    cfg = load_cfg(run_dir);
    testCase.verifyError(@() validate_publication_run(run_dir, struct( ...
        'expected_cfg', cfg)), ...
        'validate_publication_run:ExpectedCfgOverrideForbidden');
end

function testConfirmatoryPublicationInferenceCanComplete(testCase)
    pub_cfg = mechanism_ablation_config('publication', 'confirmatory');
    run_dir = make_synthetic_aggregation_run(struct( ...
        'protocol_tier', 'publication', ...
        'analysis_set', 'confirmatory', ...
        'seeds', pub_cfg.seeds));
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    inf = run_seed_level_inference(run_dir, struct('save', true));
    testCase.verifyTrue(inf.publication_inference_complete);
    testCase.verifyTrue(inf.aggregation_inference_complete);
    val = validate_aggregation_inference_artifact(run_dir);
    testCase.verifyTrue(val.valid);
    testCase.verifyTrue(val.aggregation_inference_complete);
end

function testSfaSensitivityRequiresDimensionControlPass(testCase)
    dim_pass = struct('overall_pass', true);
    dim_fail = struct('overall_pass', false);
    [pub_pass, agg_pass, status_pass] = resolve_inference_completion( ...
        'sfa_sensitivity', 'publication', true, false, dim_pass);
    [pub_fail, agg_fail, status_fail] = resolve_inference_completion( ...
        'sfa_sensitivity', 'publication', true, false, dim_fail);
    testCase.verifyTrue(pub_pass);
    testCase.verifyTrue(agg_pass);
    testCase.verifyEqual(status_pass, 'complete');
    testCase.verifyFalse(pub_fail);
    testCase.verifyFalse(agg_fail);
    testCase.verifyEqual(status_fail, 'complete_dimension_control_failed');
end

function testUnknownAnalysisSetRejected(testCase)
    testCase.verifyError(@() resolve_runner_analysis_set(struct( ...
        'analysis_set', 'custom_family')), ...
        'resolve_runner_analysis_set:InvalidAnalysisSet');
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    cfg = load_cfg(run_dir);
    cfg.active_analysis_set = 'unknown_set';
    cfg.protocol_fingerprint = compute_protocol_fingerprint(cfg);
    save(fullfile(run_dir, 'preregistered_config.mat'), 'cfg');
    testCase.verifyError(@() run_seed_level_inference(run_dir, struct('save', false)), ...
        'run_seed_level_inference:UnknownAnalysisSet');
end

function testManifestCfgAnalysisSetMismatchRejected(testCase)
    run_dir = make_synthetic_aggregation_run(struct());
    cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
    aggregate_ablation_results(run_dir, struct('save', true));
    run_seed_level_inference(run_dir, struct('save', true));
    manifest_path = fullfile(run_dir, 'aggregation', 'inference', ...
        'inference_manifest.mat');
    Sm = load(manifest_path, 'inference_manifest');
    Sm.inference_manifest.analysis_set = 'sfa_sensitivity';
    save(manifest_path, '-struct', 'Sm');
    val = validate_aggregation_inference_artifact(run_dir);
    testCase.verifyFalse(val.valid);
    idx = find(strcmp({val.checks.name}, 'analysis_set_cfg_match'), 1);
    testCase.verifyFalse(val.checks(idx).pass);
end

function testProtocolFingerprintsDifferAcrossAnalysisSets(testCase)
    fp_c = compute_protocol_fingerprint(mechanism_ablation_config('publication', ...
        'confirmatory'));
    fp_s = compute_protocol_fingerprint(mechanism_ablation_config('publication', ...
        'sfa_sensitivity'));
    fp_f = compute_protocol_fingerprint(mechanism_ablation_config('publication', ...
        'feature_exploratory'));
    testCase.verifyNotEqual(fp_c, fp_s);
    testCase.verifyNotEqual(fp_c, fp_f);
    testCase.verifyNotEqual(fp_s, fp_f);
end

function testInferentialAnalysisSetHelper(testCase)
    testCase.verifyTrue(is_publication_inferential_analysis_set('confirmatory'));
    testCase.verifyTrue(is_publication_inferential_analysis_set('sfa_sensitivity'));
    testCase.verifyFalse(is_publication_inferential_analysis_set('feature_exploratory'));
    testCase.verifyFalse(is_publication_inferential_analysis_set('unknown'));
end

function testSmokePilotRemainNonpublication(testCase)
    for tier = {'smoke', 'pilot'}
        run_dir = make_synthetic_aggregation_run(struct( ...
            'protocol_tier', tier{1}, ...
            'analysis_set', 'confirmatory'));
        cleanup = onCleanup(@() rmdir(fileparts(run_dir), 's')); %#ok<NASGU>
        aggregate_ablation_results(run_dir, struct('save', true));
        inf = run_seed_level_inference(run_dir, struct('save', true));
        testCase.verifyFalse(inf.publication_inference_complete);
        cfg = load_cfg(run_dir);
        report = evaluate_publication_readiness(cfg, struct( ...
            'cell_records', struct([]), ...
            'run_dir', run_dir, ...
            'aggregation', struct('status', 'ok', ...
                'matched_seed_contrast_structure_complete', true, ...
                'inference_status', 'complete')));
        testCase.verifyFalse(report.publication_ready);
    end
end

function testReducedViaFullPreservesAnalysisSet(testCase)
    smoke_c = mechanism_ablation_config('smoke', 'confirmatory');
    smoke_s = mechanism_ablation_config('smoke', 'sfa_sensitivity');
    testCase.verifyNotEqual( ...
        compute_protocol_fingerprint(smoke_c), ...
        compute_protocol_fingerprint(smoke_s));
    testCase.verifyEqual(smoke_s.active_analysis_set, 'sfa_sensitivity');
end

function testAllAnalysisSetsReachableThroughConfig(testCase)
    for as = {'confirmatory', 'sfa_sensitivity', 'feature_exploratory'}
        cfg = mechanism_ablation_config('publication', as{1});
        testCase.verifyEqual(cfg.active_analysis_set, as{1});
        testCase.verifyEqual(cfg.aggregation_plan.analysis_set, as{1});
        testCase.verifyEqual(cfg.aggregation_inference_plan.analysis_set, as{1});
    end
end

function cfg = load_cfg(run_dir)
    S = load(fullfile(run_dir, 'preregistered_config.mat'), 'cfg');
    cfg = S.cfg;
end
