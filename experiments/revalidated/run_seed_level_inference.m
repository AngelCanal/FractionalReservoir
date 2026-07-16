function result = run_seed_level_inference(run_dir, options)
%RUN_SEED_LEVEL_INFERENCE  Phase 5B-B inference from immutable Phase 5A tables.
%
%   result = run_seed_level_inference(run_dir)
%   result = run_seed_level_inference(run_dir, options)
%
% Options:
%   save (default true) — persist inference artifacts under aggregation/inference/
%
% Publication execution rejects options that alter plan, hypotheses, alpha,
% bootstrap count, sign-flip count, seeds, table paths, source hashes, targets,
% claims, or multiplicity families.

    if nargin < 2 || isempty(options)
        options = struct();
    end
    reject_inference_forbidden_options(options);

    do_save = logical(local_get(options, 'save', true));
    run_dir = char(run_dir);

    %% Load config
    cfg_path = fullfile(run_dir, 'preregistered_config.mat');
    if ~isfile(cfg_path)
        error('run_seed_level_inference:MissingConfig', ...
            'Missing preregistered_config.mat in %s', run_dir);
    end
    Scfg = load(cfg_path, 'cfg');
    cfg = Scfg.cfg;

    if ~isfield(cfg, 'aggregation_plan') || isempty(cfg.aggregation_plan)
        error('run_seed_level_inference:MissingAggregationPlan', ...
            'cfg.aggregation_plan is required.');
    end
    if ~isfield(cfg, 'aggregation_inference_plan') || isempty(cfg.aggregation_inference_plan)
        error('run_seed_level_inference:MissingInferencePlan', ...
            'cfg.aggregation_inference_plan is required.');
    end

    fp_recomputed = compute_protocol_fingerprint(cfg);
    if ~isfield(cfg, 'protocol_fingerprint') || ...
            ~strcmp(char(cfg.protocol_fingerprint), char(fp_recomputed))
        error('run_seed_level_inference:FingerprintMismatch', ...
            'Stored protocol_fingerprint does not match recomputed fingerprint.');
    end

    plan = cfg.aggregation_inference_plan;
    validate_seed_inference_plan(plan);

    %% Load Phase 5A manifest
    manifest_path = fullfile(run_dir, 'aggregation', 'aggregation_manifest.mat');
    if ~isfile(manifest_path)
        error('run_seed_level_inference:MissingManifest', ...
            'Missing aggregation_manifest.mat.');
    end
    Sm = load(manifest_path, 'aggregation_manifest');
    agg_manifest = Sm.aggregation_manifest;

    if ~logical(local_get(agg_manifest, 'matched_seed_contrast_structure_complete', false))
        error('run_seed_level_inference:StructureIncomplete', ...
            'matched_seed_contrast_structure_complete must be true.');
    end
    if ~strcmp(char(local_get(agg_manifest, 'inference_status', '')), 'deferred_to_phase_5b')
        error('run_seed_level_inference:WrongInferenceStatus', ...
            'Phase 5A inference_status must be deferred_to_phase_5b.');
    end

    expected_seeds = double(local_get(agg_manifest, 'expected_seeds', []));
    expected_seeds = expected_seeds(:);
    source_hashes = local_get(agg_manifest, 'table_content_hashes', struct());

    %% Load contrast tables
    seed_T = load_table(run_dir, 'seed_contrast_table');
    bench_T = load_table(run_dir, 'benchmark_contrast_table');

    seed_hash = hash_table_content(seed_T);
    bench_hash = hash_table_content(bench_T);
    if isfield(source_hashes, 'seed_contrast_table') && ...
            ~strcmp(char(source_hashes.seed_contrast_table), seed_hash)
        error('run_seed_level_inference:SeedTableHashMismatch', ...
            'seed_contrast_table content hash does not match Phase 5A manifest.');
    end
    if isfield(source_hashes, 'benchmark_contrast_table') && ...
            ~strcmp(char(source_hashes.benchmark_contrast_table), bench_hash)
        error('run_seed_level_inference:BenchmarkTableHashMismatch', ...
            'benchmark_contrast_table content hash does not match Phase 5A manifest.');
    end

    protocol_tier = char(local_get(cfg, 'protocol_tier', ''));
    analysis_set = char(local_get(cfg, 'active_analysis_set', ...
        local_get(plan, 'analysis_set', 'confirmatory')));
    switch analysis_set
        case {'confirmatory', 'sfa_sensitivity', 'feature_exploratory'}
            % ok
        otherwise
            error('run_seed_level_inference:UnknownAnalysisSet', ...
                ['active_analysis_set must be ''confirmatory'', ', ...
                 '''sfa_sensitivity'', or ''feature_exploratory'', got %s.'], ...
                analysis_set);
    end
    is_publication = strcmp(protocol_tier, 'publication');
    is_diagnostic_tier = any(strcmp(protocol_tier, {'smoke', 'pilot'}));

    %% Build estimands and attach per-seed effects
    estimands = build_estimands_from_tables(seed_T, bench_T, analysis_set);
    estimands = populate_estimand_effects(estimands, seed_T, bench_T, analysis_set);
    n_estimands = numel(estimands);

    inference_plan_hash = canonical_sha256(plan_for_hash(plan));
    summaries = repmat(empty_summary(), n_estimands, 1);

    for i = 1:n_estimands
        e = estimands(i);
        cls = classify_inference_action(estimand_registry_key(e), plan);
        planned_action = cls.planned_action;
        multiplicity_family = cls.multiplicity_family;

        if is_diagnostic_tier
            executed_action = 'diagnostic_only_not_for_publication';
        else
            executed_action = planned_action;
        end

        [seed_ids, effects, effect_source] = extract_seed_effects(e, seed_T, bench_T);
        seed_val = validate_seed_effect_vector(seed_ids, effects, expected_seeds, ...
            protocol_tier, planned_action);

        effect_summary = compute_paired_effect_summary(effects, 1);

        % Bootstrap (all tiers for descriptive CI)
        boot_ns = struct( ...
            'protocol_version', plan.protocol_version, ...
            'analysis_set', analysis_set, ...
            'hypothesis_key', e.hypothesis_key, ...
            'operation', 'bootstrap');
        [boot_stream, boot_prov] = derive_inference_rng_seed(boot_ns, plan.rng_master_seed);
        boot = bootstrap_seed_effect_ci(effects, plan.bootstrap_replicates, ...
            plan.alpha, boot_stream, boot_ns);

        row = empty_summary();
        row.inference_protocol_version = plan.protocol_version;
        row.phase5a_protocol_version = char(local_get(cfg.aggregation_plan, ...
            'protocol_version', 'matched_seed_contrasts_v1'));
        row.protocol_fingerprint = char(cfg.protocol_fingerprint);
        row.analysis_set = analysis_set;
        row.protocol_tier = protocol_tier;
        row.source_table = e.source_table;
        row.hypothesis_key = e.hypothesis_key;
        row.contrast_id = e.contrast_id;
        row.endpoint_id = e.endpoint_id;
        row.baseline_name = e.baseline_name;
        row.horizon = e.horizon;
        row.multiplicity_family = multiplicity_family;
        row.planned_action = planned_action;
        row.executed_action = executed_action;
        row.effect_source_column = effect_source;
        row.n_seeds = seed_val.n_seeds;
        row.seed_ids = sort(seed_ids(:))';
        row.sorted_seed_list_hash = canonical_sha256(row.seed_ids);
        row.seed_effect_vector_hash = canonical_sha256(effects(:));
        row.expected_seed_count = numel(expected_seeds);
        row.seed_validation_status = 'ok';

        row.mean_oriented_effect = effect_summary.mean_oriented_effect;
        row.median_oriented_effect = effect_summary.median_oriented_effect;
        row.std_oriented_effect = std(effects, 0);
        row.min_oriented_effect = min(effects);
        row.max_oriented_effect = max(effects);
        row.common_language_favorable_probability = ...
            effect_summary.common_language_favorable_probability;
        row.rank_biserial = effect_summary.rank_biserial;
        row.rank_biserial_status = effect_summary.rank_biserial_status;
        row.dz = effect_summary.dz;
        row.dz_status = effect_summary.dz_status;

        row.bootstrap_mean_ci_lower = boot.mean_ci(1);
        row.bootstrap_mean_ci_upper = boot.mean_ci(2);
        row.bootstrap_median_ci_lower = boot.median_ci(1);
        row.bootstrap_median_ci_upper = boot.median_ci(2);
        row.bootstrap_mean_se = boot.mean_bootstrap_se;
        row.bootstrap_median_se = boot.median_bootstrap_se;
        row.bootstrap_replicates = boot.n_replicates;
        row.bootstrap_rng_digest = boot_prov.digest;
        row.bootstrap_rng_seed = boot_prov.derived_seed;

        if strcmp(executed_action, 'test_and_holm') && is_publication
            flip_ns = struct( ...
                'protocol_version', plan.protocol_version, ...
                'analysis_set', analysis_set, ...
                'hypothesis_key', e.hypothesis_key, ...
                'operation', 'sign_flip');
            [flip_stream, flip_prov] = derive_inference_rng_seed(flip_ns, plan.rng_master_seed);
            flip = paired_sign_flip_test(effects, struct( ...
                'exact_max_n', plan.sign_flip_exact_max_n, ...
                'mc_replicates', plan.sign_flip_monte_carlo_replicates, ...
                'stream', flip_stream));
            row.p_value = flip.p_value;
            row.sign_flip_method = flip.method;
            row.sign_flip_observed_statistic = flip.observed_statistic;
            row.sign_flip_assignments = flip.permutations_evaluated;
            row.sign_flip_monte_carlo_se = local_get(flip, 'monte_carlo_se', NaN);
            row.sign_flip_rng_digest = flip_prov.digest;
            row.sign_flip_rng_seed = flip_prov.derived_seed;
        else
            row.p_value = NaN;
            row.p_adjusted = NaN;
            row.holm_rank = NaN;
            row.holm_reject = false;
            row.sign_flip_method = '';
            row.sign_flip_observed_statistic = NaN;
            row.sign_flip_assignments = 0;
            row.sign_flip_monte_carlo_se = NaN;
            row.sign_flip_rng_digest = '';
            row.sign_flip_rng_seed = NaN;
        end

        summaries(i) = row;
    end

    %% Holm correction (publication test_and_holm only)
    if is_publication
        summaries = apply_holm_families(summaries, plan);
    end

    %% Claim status
    for i = 1:n_estimands
        summaries(i) = assign_claim_status(summaries(i), is_publication, is_diagnostic_tier);
    end

    %% Dimension control check (sfa_sensitivity)
    dim_control = run_dimension_control_check(seed_T, expected_seeds, plan, analysis_set);

    %% Assemble output structs
    inference_summary_table = struct2table(summaries);
    multiplicity_table = build_multiplicity_table(summaries, plan);
    resampling_provenance_table = build_resampling_provenance_table(summaries);
    dimension_control_diagnostic = dim_control;

    [publication_inference_complete, aggregation_inference_complete, ...
        inference_execution_status] = resolve_inference_completion( ...
        analysis_set, protocol_tier, is_publication, is_diagnostic_tier, dim_control);

    aggregate_seed_inference = struct();
    aggregate_seed_inference.summaries = summaries;
    aggregate_seed_inference.inference_execution_status = inference_execution_status;
    aggregate_seed_inference.publication_inference_complete = publication_inference_complete;
    aggregate_seed_inference.protocol_tier = protocol_tier;
    aggregate_seed_inference.analysis_set = analysis_set;

    result = struct();
    result.run_dir = run_dir;
    result.status = 'ok';
    result.inference_status = 'complete';
    result.inference_execution_status = inference_execution_status;
    result.publication_inference_complete = publication_inference_complete;
    result.aggregation_inference_complete = aggregation_inference_complete;
    result.protocol_tier = protocol_tier;
    result.analysis_set = analysis_set;
    result.inference_summary_table = inference_summary_table;
    result.multiplicity_table = multiplicity_table;
    result.resampling_provenance_table = resampling_provenance_table;
    result.dimension_control_diagnostic = dimension_control_diagnostic;
    result.aggregate_seed_inference = aggregate_seed_inference;
    result.inference_plan_hash = inference_plan_hash;
    result.source_table_hashes = struct( ...
        'seed_contrast_table', seed_hash, ...
        'benchmark_contrast_table', bench_hash);
    result.expected_seeds = expected_seeds;
    result.expected_seed_hash = canonical_sha256(expected_seeds);
    result.n_estimands = n_estimands;

    if do_save
        written = write_inference_artifacts(run_dir, result, cfg, plan, agg_manifest);
        result.inference_manifest = written.inference_manifest;
        result.inference_manifest_hash = written.manifest_hash;
        result.output_table_hashes = written.output_table_hashes;
    end
end

% =============================================================================
function reject_inference_forbidden_options(options)
    forbidden = { ...
        'plan', 'hypotheses', 'alpha', 'bootstrap_replicates', ...
        'sign_flip_monte_carlo_replicates', 'sign_flip_exact_max_n', ...
        'seeds', 'expected_seeds', 'table_paths', 'source_hashes', ...
        'targets', 'claims', 'multiplicity_families', 'inference_plan', ...
        'aggregation_inference_plan', 'allow_overrides', 'synthetic_fixture'};
    for i = 1:numel(forbidden)
        if isfield(options, forbidden{i}) && ~isempty(options.(forbidden{i}))
            error('run_seed_level_inference:ForbiddenOption', ...
                'Option ''%s'' is forbidden for publication inference execution.', ...
                forbidden{i});
        end
    end
end

function T = load_table(run_dir, base_name)
    mat_path = fullfile(run_dir, 'aggregation', [base_name, '.mat']);
    if ~isfile(mat_path)
        error('run_seed_level_inference:MissingTable', 'Missing %s', mat_path);
    end
    S = load(mat_path);
    if isfield(S, base_name)
        T = S.(base_name);
    else
        fn = fieldnames(S);
        T = S.(fn{1});
    end
end

function estimands = build_estimands_from_tables(seed_T, bench_T, analysis_set)
    estimands = struct([]);

    if ~isempty(seed_T) && height(seed_T) > 0
        keys = {};
        for r = 1:height(seed_T)
            row = seed_T(r, :);
            if ~strcmp(char(string(row.analysis_set)), analysis_set)
                continue;
            end
            hkey = build_inference_hypothesis_key('seed_contrast', ...
                char(string(row.contrast_id)), char(string(row.endpoint_id)), '', '');
            if ~ismember(hkey, keys)
                keys{end+1} = hkey; %#ok<AGROW>
                estimands = [estimands; make_estimand('seed_contrast', hkey, ...
                    char(string(row.contrast_id)), char(string(row.endpoint_id)), ...
                    '', '', NaN, analysis_set)]; %#ok<AGROW>
            end
        end
    end

    if ~isempty(bench_T) && height(bench_T) > 0
        keys = {};
        if ~isempty(estimands)
            keys = {estimands.hypothesis_key};
        end
        for r = 1:height(bench_T)
            row = bench_T(r, :);
            if ~strcmp(char(string(row.analysis_set)), analysis_set)
                continue;
            end
            baseline = char(string(row.baseline_name));
            hnum = row.horizon;
            if isnan(hnum)
                horizon_key = '';
            else
                horizon_key = sprintf('%g', double(hnum));
            end
            hkey = build_inference_hypothesis_key('benchmark_contrast', ...
                char(string(row.contrast_id)), char(string(row.endpoint_id)), ...
                baseline, horizon_key);
            if ~ismember(hkey, keys)
                keys{end+1} = hkey; %#ok<AGROW>
                estimands = [estimands; make_estimand('benchmark_contrast', hkey, ...
                    char(string(row.contrast_id)), char(string(row.endpoint_id)), ...
                    baseline, horizon_key, hnum, analysis_set)]; %#ok<AGROW>
            end
        end
    end
end

function e = make_estimand(source_table, hkey, contrast_id, endpoint_id, ...
        baseline_name, horizon, horizon_numeric, analysis_set)
    e = struct();
    e.source_table = source_table;
    e.hypothesis_key = hkey;
    e.contrast_id = contrast_id;
    e.endpoint_id = endpoint_id;
    e.baseline_name = baseline_name;
    e.horizon = horizon;
    e.horizon_numeric = horizon_numeric;
    e.analysis_set = analysis_set;
end

function key = estimand_registry_key(estimand)
    horizon_rule = estimand.horizon;
    if strcmp(estimand.endpoint_id, 'mg_autonomous_fixed_horizon_nrmse')
        horizon_rule = 'fixed_horizon';
    end
    key = build_inference_hypothesis_key(estimand.source_table, ...
        estimand.contrast_id, estimand.endpoint_id, estimand.baseline_name, ...
        horizon_rule);
end

function rule = horizon_to_rule(row)
    ep = char(row.endpoint_id);
    if strcmp(ep, 'mg_autonomous_fixed_horizon_nrmse')
        rule = 'fixed_horizon';
        return;
    end
    h = row.horizon;
    if isnan(h) || isempty(h)
        rule = '';
    else
        rule = '';
    end
end

function [seed_ids, effects, effect_source] = extract_seed_effects(estimand, seed_T, bench_T)
    if strcmp(estimand.source_table, 'seed_contrast')
        mask = col_eq(seed_T.contrast_id, estimand.contrast_id) & ...
            col_eq(seed_T.endpoint_id, estimand.endpoint_id) & ...
            col_eq(seed_T.analysis_set, estimand.analysis_set);
        sub = seed_T(mask, :);
        effect_source = 'effect_oriented';
    else
        mask = col_eq(bench_T.contrast_id, estimand.contrast_id) & ...
            col_eq(bench_T.endpoint_id, estimand.endpoint_id) & ...
            col_eq(bench_T.baseline_name, estimand.baseline_name) & ...
            col_eq(bench_T.analysis_set, estimand.analysis_set);
        if isnan(estimand.horizon_numeric)
            hcol = bench_T.horizon;
            mask = mask & isnan(hcol);
        else
            mask = mask & bench_T.horizon == estimand.horizon_numeric;
        end
        sub = bench_T(mask, :);
        effect_source = 'comparison_value';
    end

    if height(sub) == 0
        error('run_seed_level_inference:NoRows', ...
            'No rows for hypothesis %s.', estimand.hypothesis_key);
    end

    if any(~col_eq(sub.status, 'ok'))
        error('run_seed_level_inference:BadRowStatus', ...
            'Non-ok status for hypothesis %s.', estimand.hypothesis_key);
    end

    seed_ids = double(sub.seed);
    if strcmp(effect_source, 'effect_oriented')
        effects = double(sub.effect_oriented);
        om = unique(sub.orientation_multiplier);
        if numel(om) ~= 1
            error('run_seed_level_inference:InconsistentOrientation', ...
                'Inconsistent orientation_multiplier for %s.', estimand.hypothesis_key);
        end
    else
        effects = double(sub.comparison_value);
    end

    [seed_ids, ord] = sort(seed_ids);
    effects = effects(ord);
end

function mask = col_eq(col, value)
    if iscell(col)
        mask = strcmp(col, char(value));
    elseif isstring(col)
        mask = col == string(value);
    elseif iscategorical(col)
        mask = col == categorical(string(value));
    else
        mask = string(col) == string(value);
    end
end

function estimands = populate_estimand_effects(estimands, seed_T, bench_T, analysis_set)
    for i = 1:numel(estimands)
        estimands(i).analysis_set = analysis_set;
    end
end

function summaries = apply_holm_families(summaries, plan)
    fam_names = fieldnames(plan.testing_families);
    for f = 1:numel(fam_names)
        fam = plan.testing_families.(fam_names{f});
        fam_id = fam.family_id;
        expected_count = fam.expected_count;

        idx = [];
        keys = {};
        for i = 1:numel(summaries)
            if strcmp(summaries(i).executed_action, 'test_and_holm') && ...
                    strcmp(summaries(i).multiplicity_family, fam_id)
                idx(end+1) = i; %#ok<AGROW>
                keys{end+1} = summaries(i).hypothesis_key; %#ok<AGROW>
            end
        end

        if numel(idx) ~= expected_count
            error('run_seed_level_inference:FamilySizeMismatch', ...
                'Family %s expected %d hypotheses, found %d.', ...
                fam_id, expected_count, numel(idx));
        end
        if numel(unique(keys)) ~= numel(keys)
            error('run_seed_level_inference:DuplicateFamilyHypothesis', ...
                'Duplicate hypotheses in family %s.', fam_id);
        end

        raw_p = [summaries(idx).p_value]';
        holm = holm_bonferroni_adjust(raw_p, plan.alpha);
        for j = 1:numel(idx)
            summaries(idx(j)).p_adjusted = holm.p_adjusted(j);
            summaries(idx(j)).holm_rank = holm.holm_ranks(j);
            summaries(idx(j)).holm_reject = holm.holm_reject(j);
        end
    end
end

function row = assign_claim_status(row, is_publication, is_diagnostic_tier)
    if is_diagnostic_tier
        row.claim_status = 'diagnostic_only_not_for_publication';
        row.claim_allowed = false;
        return;
    end

    if strcmp(row.executed_action, 'estimate_only')
        row.claim_status = 'estimate_only';
        row.claim_allowed = false;
        return;
    end

    if ~strcmp(row.executed_action, 'test_and_holm') || ~is_publication
        row.claim_status = 'not_statistically_resolved';
        row.claim_allowed = false;
        return;
    end

    if row.holm_reject && row.mean_oriented_effect > 0 && ...
            row.bootstrap_mean_ci_lower > 0
        row.claim_status = 'favorable_supported';
        row.claim_allowed = true;
    elseif row.holm_reject && row.mean_oriented_effect < 0 && ...
            row.bootstrap_mean_ci_upper < 0
        row.claim_status = 'significant_unfavorable';
        row.claim_allowed = false;
    else
        row.claim_status = 'not_statistically_resolved';
        row.claim_allowed = false;
    end
end

function dim = run_dimension_control_check(seed_T, expected_seeds, plan, analysis_set)
    dim = struct();
    dim.analysis_set = analysis_set;
    dim.contrast_id = 'single_moment_vs_three_identical_equivalence_check';
    dim.label = plan.dimension_control_equivalence.label;
    dim.overall_pass = true;
    dim.status = 'not_applicable';
    dim.endpoint_results = struct([]);

    if ~strcmp(analysis_set, 'sfa_sensitivity')
        return;
    end

    dim.status = 'evaluated';
    cfg_equiv = plan.dimension_control_equivalence;
    gated = cfg_equiv.gated_endpoint_ids;

    for e = 1:numel(gated)
        ep = gated{e};
        mask = col_eq(seed_T.contrast_id, ...
            'single_moment_vs_three_identical_equivalence_check') & ...
            col_eq(seed_T.endpoint_id, ep) & ...
            col_eq(seed_T.analysis_set, analysis_set);
        sub = seed_T(mask, :);
        if height(sub) ~= numel(expected_seeds)
            error('run_seed_level_inference:DimensionControlSeedCount', ...
                'Dimension control endpoint %s has %d rows, expected %d.', ...
                ep, height(sub), numel(expected_seeds));
        end
        seed_ids = double(sub.seed);
        treatment = double(sub.treatment_mean_within_seed);
        control = double(sub.control_mean_within_seed);
        r = evaluate_dimension_control_equivalence(treatment, control, ...
            seed_ids, ep, cfg_equiv);
        dim.endpoint_results = [dim.endpoint_results; r]; %#ok<AGROW>
        if r.gated && ~r.pass
            dim.overall_pass = false;
        end
    end

    if ~dim.overall_pass
        dim.status = 'failed';
    else
        dim.status = 'passed';
    end
end

function T = build_multiplicity_table(summaries, plan)
    rows = {};
    fam_names = fieldnames(plan.testing_families);
    for f = 1:numel(fam_names)
        fam = plan.testing_families.(fam_names{f});
        for i = 1:numel(summaries)
            s = summaries(i);
            if strcmp(s.multiplicity_family, fam.family_id)
                rows{end+1} = struct( ...
                    'family_id', fam.family_id, ...
                    'hypothesis_key', s.hypothesis_key, ...
                    'p_value', s.p_value, ...
                    'p_adjusted', s.p_adjusted, ...
                    'holm_rank', s.holm_rank, ...
                    'holm_reject', s.holm_reject, ...
                    'executed_action', s.executed_action); %#ok<AGROW>
            end
        end
    end
    if isempty(rows)
        T = table();
    else
        T = struct2table([rows{:}]');
    end
end

function T = build_resampling_provenance_table(summaries)
    rows = struct([]);
    for i = 1:numel(summaries)
        s = summaries(i);
        rows(i).hypothesis_key = s.hypothesis_key; %#ok<AGROW>
        rows(i).bootstrap_replicates = s.bootstrap_replicates;
        rows(i).bootstrap_rng_digest = s.bootstrap_rng_digest;
        rows(i).bootstrap_rng_seed = s.bootstrap_rng_seed;
        rows(i).sign_flip_method = s.sign_flip_method;
        rows(i).sign_flip_assignments = s.sign_flip_assignments;
        rows(i).sign_flip_rng_digest = s.sign_flip_rng_digest;
        rows(i).sign_flip_rng_seed = s.sign_flip_rng_seed;
    end
    if isempty(rows)
        T = table();
    else
        T = struct2table(rows);
    end
end

function p = plan_for_hash(plan)
    p = plan;
    if isfield(p, 'hypothesis_registry')
        p = rmfield(p, 'hypothesis_registry');
    end
    p.registry_hash = canonical_sha256(plan.hypothesis_registry);
end

function hex = hash_table_content(T)
    if isempty(T) || height(T) == 0
        hex = canonical_sha256(struct( ...
            'empty', true, ...
            'varnames', {T.Properties.VariableNames}));
        return;
    end
    drop = {};
    vn = T.Properties.VariableNames;
    for i = 1:numel(vn)
        if contains(lower(vn{i}), 'timestamp') || contains(lower(vn{i}), 'created_utc')
            drop{end+1} = vn{i}; %#ok<AGROW>
        end
    end
    if ~isempty(drop)
        T = removevars(T, drop);
    end
    try
        S = table2struct(T);
    catch
        S = struct('nrows', height(T), 'varnames', {T.Properties.VariableNames});
    end
    hex = canonical_sha256(S);
end

function s = empty_summary()
    s = struct( ...
        'inference_protocol_version', '', ...
        'phase5a_protocol_version', '', ...
        'protocol_fingerprint', '', ...
        'analysis_set', '', ...
        'protocol_tier', '', ...
        'source_table', '', ...
        'hypothesis_key', '', ...
        'contrast_id', '', ...
        'endpoint_id', '', ...
        'baseline_name', '', ...
        'horizon', '', ...
        'multiplicity_family', '', ...
        'planned_action', '', ...
        'executed_action', '', ...
        'effect_source_column', '', ...
        'n_seeds', 0, ...
        'seed_ids', [], ...
        'sorted_seed_list_hash', '', ...
        'seed_effect_vector_hash', '', ...
        'expected_seed_count', 0, ...
        'seed_validation_status', '', ...
        'mean_oriented_effect', NaN, ...
        'median_oriented_effect', NaN, ...
        'std_oriented_effect', NaN, ...
        'min_oriented_effect', NaN, ...
        'max_oriented_effect', NaN, ...
        'common_language_favorable_probability', NaN, ...
        'rank_biserial', NaN, ...
        'rank_biserial_status', '', ...
        'dz', NaN, ...
        'dz_status', '', ...
        'bootstrap_mean_ci_lower', NaN, ...
        'bootstrap_mean_ci_upper', NaN, ...
        'bootstrap_median_ci_lower', NaN, ...
        'bootstrap_median_ci_upper', NaN, ...
        'bootstrap_mean_se', NaN, ...
        'bootstrap_median_se', NaN, ...
        'bootstrap_replicates', 0, ...
        'bootstrap_rng_digest', '', ...
        'bootstrap_rng_seed', NaN, ...
        'p_value', NaN, ...
        'p_adjusted', NaN, ...
        'holm_rank', NaN, ...
        'holm_reject', false, ...
        'sign_flip_method', '', ...
        'sign_flip_observed_statistic', NaN, ...
        'sign_flip_assignments', 0, ...
        'sign_flip_monte_carlo_se', NaN, ...
        'sign_flip_rng_digest', '', ...
        'sign_flip_rng_seed', NaN, ...
        'claim_status', '', ...
        'claim_allowed', false);
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
