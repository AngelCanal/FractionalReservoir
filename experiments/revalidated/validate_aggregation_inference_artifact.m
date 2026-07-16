function report = validate_aggregation_inference_artifact(run_dir, cfg)
%VALIDATE_AGGREGATION_INFERENCE_ARTIFACT  Independent Phase 5B artifact validation.
%
%   report = validate_aggregation_inference_artifact(run_dir)
%   report = validate_aggregation_inference_artifact(run_dir, cfg)
%
% Reloads all inference artifacts from disk. Does not trust in-memory results.

    if nargin < 1 || isempty(run_dir)
        error('validate_aggregation_inference_artifact:MissingRunDir', ...
            'run_dir is required.');
    end
    run_dir = char(run_dir);

    if nargin < 2 || isempty(cfg)
        cfg_path = fullfile(run_dir, 'preregistered_config.mat');
        if ~isfile(cfg_path)
            error('validate_aggregation_inference_artifact:MissingConfig', ...
                'Missing preregistered_config.mat.');
        end
        Scfg = load(cfg_path, 'cfg');
        cfg = Scfg.cfg;
    end

    checks = {};
    reasons = {};

    inf_dir = fullfile(run_dir, 'aggregation', 'inference');
    manifest_path = fullfile(inf_dir, 'inference_manifest.mat');

    if ~isfile(manifest_path)
        checks{end+1} = make_check('aggregation_inference_artifact_present', false, ...
            'inference_manifest.mat missing'); %#ok<AGROW>
        report = build_report(checks, reasons, '', false, false);
        return;
    end
    checks{end+1} = make_check('aggregation_inference_artifact_present', true, ...
        'inference_manifest.mat present');

    Sm = load(manifest_path, 'inference_manifest');
    manifest = Sm.inference_manifest;

    plan = cfg.aggregation_inference_plan;
    validate_seed_inference_plan(plan);
    plan_hash = canonical_sha256(plan_for_hash(plan));

    fp_ok = isfield(manifest, 'protocol_fingerprint') && ...
        strcmp(char(manifest.protocol_fingerprint), char(cfg.protocol_fingerprint));
    checks{end+1} = make_check('config_fingerprint_match', fp_ok, ...
        sprintf('manifest=%s cfg=%s', char(manifest.protocol_fingerprint), ...
        char(cfg.protocol_fingerprint)));
    if ~fp_ok
        reasons{end+1} = 'protocol_fingerprint_mismatch'; %#ok<AGROW>
    end

    tier_ok = isfield(manifest, 'protocol_tier') && ...
        strcmp(char(manifest.protocol_tier), char(cfg.protocol_tier));
    checks{end+1} = make_check('protocol_tier_match', tier_ok, ...
        sprintf('manifest=%s cfg=%s', char(manifest.protocol_tier), ...
        char(cfg.protocol_tier)));

    plan_hash_ok = isfield(manifest, 'inference_plan_hash') && ...
        strcmp(char(manifest.inference_plan_hash), plan_hash);
    checks{end+1} = make_check('inference_plan_hash_match', plan_hash_ok, ...
        'inference plan hash');
    if ~plan_hash_ok
        reasons{end+1} = 'inference_plan_hash_mismatch'; %#ok<AGROW>
    end

    agg_manifest_path = fullfile(run_dir, 'aggregation', 'aggregation_manifest.mat');
    source_hash_ok = false;
    if isfile(agg_manifest_path)
        Sa = load(agg_manifest_path, 'aggregation_manifest');
        src = Sa.aggregation_manifest.table_content_hashes;
        if isfield(manifest, 'source_phase5a_table_hashes')
            msrc = manifest.source_phase5a_table_hashes;
            source_hash_ok = isfield(src, 'seed_contrast_table') && ...
                isfield(msrc, 'seed_contrast_table') && ...
                strcmp(char(src.seed_contrast_table), char(msrc.seed_contrast_table)) && ...
                isfield(src, 'benchmark_contrast_table') && ...
                isfield(msrc, 'benchmark_contrast_table') && ...
                strcmp(char(src.benchmark_contrast_table), char(msrc.benchmark_contrast_table));
        end
    end
    checks{end+1} = make_check('aggregation_inference_source_hashes_match', ...
        source_hash_ok, 'Phase 5A source table hashes');
    if ~source_hash_ok
        reasons{end+1} = 'source_hash_mismatch'; %#ok<AGROW>
    end

    summary_T = load_inference_table(inf_dir, 'inference_summary_table');
    output_hash_ok = verify_output_hashes(inf_dir, manifest);
    checks{end+1} = make_check('output_table_hashes_match', output_hash_ok, ...
        'recomputed output hashes');
    if ~output_hash_ok
        reasons{end+1} = 'output_hash_mismatch'; %#ok<AGROW>
    end

    seed_ok = verify_seed_set(manifest, summary_T);
    checks{end+1} = make_check('aggregation_inference_seed_set_complete', ...
        seed_ok.pass, seed_ok.detail);
    if ~seed_ok.pass
        reasons{end+1} = 'seed_set_incomplete'; %#ok<AGROW>
    end

    family_ok = verify_families(summary_T, plan, manifest);
    checks{end+1} = make_check('aggregation_inference_families_complete', ...
        family_ok.pass, family_ok.detail);
    if ~family_ok.pass
        reasons{end+1} = 'family_incomplete'; %#ok<AGROW>
    end

    p_ok = verify_p_values(summary_T);
    checks{end+1} = make_check('p_value_ranges_valid', p_ok.pass, p_ok.detail);
    if ~p_ok.pass
        reasons{end+1} = 'p_value_invalid'; %#ok<AGROW>
    end

    holm_ok = verify_holm_arithmetic(summary_T, plan);
    checks{end+1} = make_check('holm_arithmetic_valid', holm_ok.pass, holm_ok.detail);
    if ~holm_ok.pass
        reasons{end+1} = 'holm_arithmetic_mismatch'; %#ok<AGROW>
    end

    est_ok = verify_estimate_only_rows(summary_T);
    checks{end+1} = make_check('estimate_only_rows_valid', est_ok.pass, est_ok.detail);
    if ~est_ok.pass
        reasons{end+1} = 'estimate_only_invalid'; %#ok<AGROW>
    end

    claim_ok = verify_claim_status(summary_T, manifest);
    checks{end+1} = make_check('claim_status_valid', claim_ok.pass, claim_ok.detail);
    if ~claim_ok.pass
        reasons{end+1} = 'claim_status_invalid'; %#ok<AGROW>
    end

    prov_ok = verify_provenance(manifest, summary_T);
    checks{end+1} = make_check('aggregation_inference_provenance_valid', ...
        prov_ok.pass, prov_ok.detail);
    if ~prov_ok.pass
        reasons{end+1} = 'provenance_invalid'; %#ok<AGROW>
    end

    override_ok = isfield(manifest, 'overrides_used') && ~logical(manifest.overrides_used);
    checks{end+1} = make_check('aggregation_inference_no_overrides', override_ok, ...
        sprintf('overrides_used=%d', local_get(manifest, 'overrides_used', true)));

    synth_ok = isfield(manifest, 'synthetic_fixture') && ...
        ~logical(manifest.synthetic_fixture);
    checks{end+1} = make_check('synthetic_fixture_false', synth_ok, ...
        sprintf('synthetic_fixture=%d', local_get(manifest, 'synthetic_fixture', true)));

    no_stream_ok = ~artifact_contains_randstream(inf_dir);
    checks{end+1} = make_check('no_mutable_stream_objects', no_stream_ok, ...
        'RandStream scan');

    dim_ok = verify_dimension_control(inf_dir, manifest);
    checks{end+1} = make_check('dimension_control_valid', dim_ok.pass, dim_ok.detail);

    check_arr = [checks{:}];
    all_pass = all([check_arr.pass]);

    pub_complete = isfield(manifest, 'publication_inference_complete') && ...
        logical(manifest.publication_inference_complete);
    if ~strcmp(char(local_get(manifest, 'protocol_tier', '')), 'publication')
        pub_complete = false;
    end
    aggregation_complete = all_pass && pub_complete;
    checks{end+1} = make_check('aggregation_inference_complete', ...
        aggregation_complete, sprintf('valid=%d pub_complete=%d', all_pass, pub_complete));

    manifest_hash = '';
    if isfield(manifest, 'manifest_hash')
        manifest_hash = char(manifest.manifest_hash);
    end

    report = build_report(check_arr, reasons, manifest_hash, all_pass, aggregation_complete);
    report.publication_inference_complete = pub_complete;
    report.manifest = manifest;
end

% =============================================================================
function report = build_report(checks, reasons, manifest_hash, valid, aggregation_complete)
    report = struct();
    report.valid = valid;
    report.aggregation_inference_complete = aggregation_complete;
    report.publication_inference_complete = false;
    report.checks = checks;
    report.reasons = reasons;
    report.manifest_hash = manifest_hash;
end

function c = make_check(name, pass, detail)
    c = struct('name', name, 'pass', logical(pass), 'detail', char(string(detail)));
end

function T = load_inference_table(inf_dir, base_name)
    mat_path = fullfile(inf_dir, [base_name, '.mat']);
    if ~isfile(mat_path)
        T = table();
        return;
    end
    S = load(mat_path);
    if isfield(S, base_name)
        T = S.(base_name);
    else
        fn = fieldnames(S);
        T = S.(fn{1});
    end
end

function ok = verify_output_hashes(inf_dir, manifest)
    ok = true;
    if ~isfield(manifest, 'output_table_hashes')
        ok = false;
        return;
    end
    stored = manifest.output_table_hashes;
    names = {'inference_summary_table', 'multiplicity_table', ...
        'resampling_provenance_table'};
    for i = 1:numel(names)
        nm = names{i};
        T = load_inference_table(inf_dir, nm);
        recomputed = hash_inference_table(T);
        if ~isfield(stored, nm) || ~strcmp(char(stored.(nm)), recomputed)
            ok = false;
            return;
        end
    end
end

function out = verify_seed_set(manifest, summary_T)
    out = struct('pass', true, 'detail', 'ok');
    if ~istable(summary_T) || height(summary_T) == 0
        out.pass = false;
        out.detail = 'empty_summary';
        return;
    end
    expected = double(manifest.expected_seeds(:));
    for r = 1:height(summary_T)
        row = summary_T(r, :);
        if iscell(row.seed_ids)
            sids = double(row.seed_ids{1}(:));
        else
            sids = double(row.seed_ids(:));
        end
        if numel(sids) ~= numel(expected)
            out.pass = false;
            out.detail = sprintf('row_%d_seed_count', r);
            return;
        end
        if ~isempty(setdiff(expected, sids)) || ~isempty(setdiff(sids, expected))
            out.pass = false;
            out.detail = sprintf('row_%d_seed_mismatch', r);
            return;
        end
        if numel(unique(sids)) ~= numel(sids)
            out.pass = false;
            out.detail = sprintf('row_%d_duplicate_seed', r);
            return;
        end
    end
end

function out = verify_families(summary_T, plan, manifest)
    out = struct('pass', true, 'detail', 'ok');
    if ~strcmp(char(local_get(manifest, 'protocol_tier', '')), 'publication')
        return;
    end
    fn = fieldnames(plan.testing_families);
    for i = 1:numel(fn)
        fam = plan.testing_families.(fn{i});
        expected = fam.expected_count;
        observed = 0;
        if istable(summary_T)
            for r = 1:height(summary_T)
                row = summary_T(r, :);
                if strcmp(char(row.executed_action), 'test_and_holm') && ...
                        strcmp(char(row.multiplicity_family), fam.family_id)
                    observed = observed + 1;
                end
            end
        end
        if observed ~= expected
            out.pass = false;
            out.detail = sprintf('%s expected=%d observed=%d', ...
                fam.family_id, expected, observed);
            return;
        end
    end
end

function out = verify_p_values(summary_T)
    out = struct('pass', true, 'detail', 'ok');
    if ~istable(summary_T)
        return;
    end
    for r = 1:height(summary_T)
        row = summary_T(r, :);
        if strcmp(char(row.executed_action), 'test_and_holm')
            p = double(row.p_value);
            if ~isfinite(p) || p < 0 || p > 1
                out.pass = false;
                out.detail = sprintf('row_%d_bad_raw_p', r);
                return;
            end
        end
    end
end

function out = verify_holm_arithmetic(summary_T, plan)
    out = struct('pass', true, 'detail', 'ok');
    if ~istable(summary_T)
        return;
    end
    fn = fieldnames(plan.testing_families);
    for f = 1:numel(fn)
        fam = plan.testing_families.(fn{f});
        idx = [];
        raw_p = [];
        stored_adj = [];
        for r = 1:height(summary_T)
            row = summary_T(r, :);
            if strcmp(char(row.executed_action), 'test_and_holm') && ...
                    strcmp(char(row.multiplicity_family), fam.family_id)
                idx(end+1) = r; %#ok<AGROW>
                raw_p(end+1) = double(row.p_value); %#ok<AGROW>
                stored_adj(end+1) = double(row.p_adjusted); %#ok<AGROW>
            end
        end
        if isempty(idx)
            continue;
        end
        holm = holm_bonferroni_adjust(raw_p(:), plan.alpha);
        if max(abs(holm.p_adjusted - stored_adj(:))) > 1e-12
            out.pass = false;
            out.detail = sprintf('family_%s_adjusted_mismatch', fam.family_id);
            return;
        end
    end
end

function out = verify_estimate_only_rows(summary_T)
    out = struct('pass', true, 'detail', 'ok');
    if ~istable(summary_T)
        return;
    end
    for r = 1:height(summary_T)
        row = summary_T(r, :);
        if strcmp(char(row.executed_action), 'estimate_only') || ...
                strcmp(char(row.planned_action), 'estimate_only')
            if isfinite(double(row.p_value))
                out.pass = false;
                out.detail = sprintf('row_%d_estimate_only_finite_p', r);
                return;
            end
            if logical(row.holm_reject)
                out.pass = false;
                out.detail = sprintf('row_%d_estimate_only_reject', r);
                return;
            end
        end
    end
end

function out = verify_claim_status(summary_T, manifest)
    out = struct('pass', true, 'detail', 'ok');
    if ~istable(summary_T)
        return;
    end
    is_pub = strcmp(char(local_get(manifest, 'protocol_tier', '')), 'publication');
    for r = 1:height(summary_T)
        row = summary_T(r, :);
        status = char(row.claim_status);
        allowed = logical(row.claim_allowed);
        if strcmp(char(row.executed_action), 'diagnostic_only_not_for_publication')
            if allowed || ~strcmp(status, 'diagnostic_only_not_for_publication')
                out.pass = false;
                out.detail = sprintf('row_%d_diagnostic_claim', r);
                return;
            end
            continue;
        end
        if strcmp(char(row.executed_action), 'estimate_only')
            if allowed || ~strcmp(status, 'estimate_only')
                out.pass = false;
                out.detail = sprintf('row_%d_estimate_claim', r);
                return;
            end
            continue;
        end
        if strcmp(char(row.executed_action), 'test_and_holm') && is_pub
            expected_allowed = strcmp(status, 'favorable_supported');
            if allowed ~= expected_allowed
                out.pass = false;
                out.detail = sprintf('row_%d_claim_allowed_mismatch', r);
                return;
            end
            if allowed
                if ~(logical(row.holm_reject) && double(row.mean_oriented_effect) > 0 && ...
                        double(row.bootstrap_mean_ci_lower) > 0)
                    out.pass = false;
                    out.detail = sprintf('row_%d_favorable_claim_invalid', r);
                    return;
                end
            end
        end
    end
end

function out = verify_provenance(manifest, summary_T)
    out = struct('pass', true, 'detail', 'ok');
    if ~strcmp(char(local_get(manifest, 'provenance_mode', '')), ...
            'executed_from_immutable_phase5a_tables')
        out.pass = false;
        out.detail = 'provenance_mode';
        return;
    end
    if logical(local_get(manifest, 'global_rng_mutated', true))
        out.pass = false;
        out.detail = 'global_rng_mutated';
        return;
    end
    if ~istable(summary_T)
        return;
    end
    digests = {};
    for r = 1:height(summary_T)
        row = summary_T(r, :);
        bd = char(row.bootstrap_rng_digest);
        if ~isempty(bd)
            if ismember(bd, digests)
                out.pass = false;
                out.detail = 'duplicate_bootstrap_rng_digest';
                return;
            end
            digests{end+1} = bd; %#ok<AGROW>
        end
        fd = char(row.sign_flip_rng_digest);
        if ~isempty(fd)
            if ismember(fd, digests)
                out.pass = false;
                out.detail = 'duplicate_sign_flip_rng_digest';
                return;
            end
            digests{end+1} = fd; %#ok<AGROW>
        end
    end
end

function out = verify_dimension_control(inf_dir, manifest)
    out = struct('pass', true, 'detail', 'ok');
    if ~strcmp(char(local_get(manifest, 'analysis_set', '')), 'sfa_sensitivity')
        out.detail = 'not_applicable';
        return;
    end
    path = fullfile(inf_dir, 'dimension_control_diagnostic.mat');
    if ~isfile(path)
        out.pass = false;
        out.detail = 'missing_dimension_control';
        return;
    end
    if strcmp(char(local_get(manifest, 'protocol_tier', '')), 'publication') && ...
            isfield(manifest, 'publication_inference_complete') && ...
            logical(manifest.publication_inference_complete)
        S = load(path, 'dimension_control_diagnostic');
        d = S.dimension_control_diagnostic;
        if isfield(d, 'overall_pass') && ~logical(d.overall_pass)
            out.pass = false;
            out.detail = 'dimension_control_failed_but_complete';
        end
    end
end

function tf = artifact_contains_randstream(inf_dir)
    tf = false;
    files = dir(fullfile(inf_dir, '*.mat'));
    for i = 1:numel(files)
        try
            S = load(fullfile(inf_dir, files(i).name));
            if struct_has_randstream(S)
                tf = true;
                return;
            end
        catch
        end
    end
end

function tf = struct_has_randstream(s)
    tf = false;
    if isa(s, 'RandStream')
        tf = true;
        return;
    end
    if isstruct(s)
        fn = fieldnames(s);
        for i = 1:numel(fn)
            if struct_has_randstream(s.(fn{i}))
                tf = true;
                return;
            end
        end
    elseif iscell(s)
        for i = 1:numel(s)
            if struct_has_randstream(s{i})
                tf = true;
                return;
            end
        end
    end
end

function p = plan_for_hash(plan)
    p = plan;
    if isfield(p, 'hypothesis_registry')
        p = rmfield(p, 'hypothesis_registry');
    end
    p.registry_hash = canonical_sha256(plan.hypothesis_registry);
end

function hex = hash_inference_table(T)
    if isempty(T) || height(T) == 0
        hex = canonical_sha256(struct( ...
            'empty', true, ...
            'varnames', {T.Properties.VariableNames}));
        return;
    end
    S = table2struct(T);
    hex = canonical_sha256(S);
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
