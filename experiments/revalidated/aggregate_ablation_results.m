function aggregate = aggregate_ablation_results(run_dir, options)
%AGGREGATE_ABLATION_RESULTS  Phase 5A matched-seed aggregation orchestrator.
%
%   aggregate = aggregate_ablation_results(run_dir)
%   aggregate = aggregate_ablation_results(run_dir, options)
%
% Loads immutable cell artifacts, validates the expected seed x cell matrix from
% the preregistered config, builds descriptive tables and seed-level contrasts,
% and writes aggregation artifacts. Performs no statistical inference.
%
% Options:
%   save (default true)
%   allow_incomplete_diagnostic (default false)
%
% Publication callers must not supply control_cell_key or custom contrasts.
%
% See also: validate_aggregation_run_matrix, build_aggregation_tables,
%   build_seed_level_contrast_tables, write_aggregation_artifacts,
%   build_matched_aggregation_plan

    if nargin < 2 || isempty(options)
        options = struct();
    end
    reject_publication_forbidden_options(options);

    do_save = logical(local_get(options, 'save', true));
    allow_incomplete = logical(local_get(options, 'allow_incomplete_diagnostic', false));

    run_dir = char(run_dir);
    if ~isfolder(run_dir)
        error('aggregate_ablation_results:MissingRunDir', ...
            'run_dir does not exist: %s', run_dir);
    end

    %% 1. Load preregistered config
    cfg_path = fullfile(run_dir, 'preregistered_config.mat');
    if ~isfile(cfg_path)
        error('aggregate_ablation_results:MissingConfig', ...
            'Missing preregistered_config.mat in %s', run_dir);
    end
    Scfg = load(cfg_path, 'cfg');
    if ~isfield(Scfg, 'cfg') || ~isstruct(Scfg.cfg)
        error('aggregate_ablation_results:InvalidConfig', ...
            'preregistered_config.mat must contain struct cfg.');
    end
    cfg = Scfg.cfg;

    %% 2. Require / rebuild aggregation_plan
    if ~isfield(cfg, 'aggregation_plan') || isempty(cfg.aggregation_plan)
        analysis_set = local_get(cfg, 'active_analysis_set', 'confirmatory');
        cfg.aggregation_plan = build_matched_aggregation_plan(analysis_set);
    else
        analysis_set = local_get(cfg, 'active_analysis_set', ...
            local_get(cfg.aggregation_plan, 'analysis_set', 'confirmatory'));
        rebuilt = build_matched_aggregation_plan(analysis_set);
        if ~strcmp(char(cfg.aggregation_plan.protocol_version), ...
                char(rebuilt.protocol_version))
            error('aggregate_ablation_results:PlanProtocolMismatch', ...
                ['Stored aggregation_plan.protocol_version (%s) does not match ', ...
                 'build_matched_aggregation_plan (%s).'], ...
                char(cfg.aggregation_plan.protocol_version), ...
                char(rebuilt.protocol_version));
        end
    end

    %% 3. Recompute fingerprint; must match stored
    if ~isfield(cfg, 'protocol_fingerprint') || isempty(cfg.protocol_fingerprint)
        error('aggregate_ablation_results:MissingFingerprint', ...
            'cfg.protocol_fingerprint is required.');
    end
    fp_recomputed = compute_protocol_fingerprint(cfg);
    if ~strcmp(char(cfg.protocol_fingerprint), char(fp_recomputed))
        error('aggregate_ablation_results:FingerprintMismatch', ...
            ['Stored protocol_fingerprint does not match recomputed fingerprint.', ...
             ' Stored=%s recomputed=%s'], ...
            char(cfg.protocol_fingerprint), char(fp_recomputed));
    end

    %% 4. Load manifest if present; fingerprint must match
    manifest = load_run_manifest_if_present(run_dir);
    if ~isempty(manifest)
        mfp = extract_manifest_fingerprint(manifest);
        if ~isempty(mfp) && ~strcmp(char(mfp), char(cfg.protocol_fingerprint))
            error('aggregate_ablation_results:ManifestFingerprintMismatch', ...
                'Manifest protocol_fingerprint does not match cfg.');
        end
    end

    %% 5. Validate expected seed x cell matrix
    matrix = validate_aggregation_run_matrix(run_dir, cfg);
    if ~matrix.ok
        if allow_incomplete
            aggregate = build_diagnostic_incomplete_aggregate( ...
                run_dir, cfg, matrix, manifest, do_save);
            return;
        end
        error('aggregate_ablation_results:MissingCells', ...
            'Aggregation matrix validation failed: %s', ...
            strjoin(matrix.reasons, '; '));
    end

    %% 6–7. Build tables and seed-level contrasts
    tables = build_aggregation_tables(matrix, cfg);
    contrasts = build_seed_level_contrast_tables(tables, matrix, cfg);
    tables.seed_contrast = contrasts.seed_contrast;
    tables.benchmark_contrast = contrasts.benchmark_contrast;

    %% 8. Assemble aggregate struct (no inference)
    aggregate = struct();
    aggregate.run_dir = run_dir;
    aggregate.status = 'ok';
    aggregate.inference_status = 'deferred_to_phase_5b';
    aggregate.protocol_version = char(cfg.aggregation_plan.protocol_version);
    aggregate.protocol_fingerprint = char(cfg.protocol_fingerprint);
    aggregate.protocol_tier = char(local_get(cfg, 'protocol_tier', ''));
    aggregate.analysis_set = char(local_get(cfg, 'active_analysis_set', ...
        local_get(cfg.aggregation_plan, 'analysis_set', '')));
    aggregate.independent_unit = char(cfg.aggregation_plan.independent_unit);
    aggregate.seeds = matrix.expected_seeds(:);
    aggregate.cell_keys = matrix.expected_cell_keys(:);
    aggregate.n_seeds = numel(matrix.expected_seeds);
    aggregate.n_cells = numel(matrix.expected_cell_keys);
    aggregate.n_pairs = numel(matrix.expected_pairs);
    aggregate.matrix = matrix;
    aggregate.tables = tables;
    aggregate.aggregation_plan = cfg.aggregation_plan;
    aggregate.manifest = manifest;
    aggregate.no_inference = true;
    aggregate.matched_seed_contrast_structure_complete = true;
    aggregate.aggregation_inference_complete = false;

    %% 9. Write artifacts
    if do_save
        aggregate = write_aggregation_artifacts(run_dir, aggregate, tables, matrix);
    end
end

% =============================================================================
function reject_publication_forbidden_options(options)
    forbidden = { ...
        'control_cell_key', ...
        'contrasts', ...
        'contrast_definitions', ...
        'custom_contrasts', ...
        'n_bootstrap', ...
        'alpha'};
    for i = 1:numel(forbidden)
        if isfield(options, forbidden{i}) && ~isempty(options.(forbidden{i}))
            error('aggregate_ablation_results:ForbiddenOption', ...
                ['Option ''%s'' is forbidden for Phase 5A publication aggregation. ', ...
                 'Use cfg.aggregation_plan only; inference is deferred to Phase 5B.'], ...
                forbidden{i});
        end
    end
end

function manifest = load_run_manifest_if_present(run_dir)
    manifest = [];
    mat_path = fullfile(run_dir, 'manifest.mat');
    json_path = fullfile(run_dir, 'manifest.json');
    if isfile(mat_path)
        S = load(mat_path);
        if isfield(S, 'manifest')
            manifest = S.manifest;
        else
            manifest = S;
        end
        return;
    end
    if isfile(json_path)
        txt = fileread(json_path);
        manifest = jsondecode(txt);
    end
end

function fp = extract_manifest_fingerprint(manifest)
    fp = '';
    if ~isstruct(manifest)
        return;
    end
    if isfield(manifest, 'extra') && isstruct(manifest.extra) && ...
            isfield(manifest.extra, 'protocol_fingerprint')
        fp = char(manifest.extra.protocol_fingerprint);
        return;
    end
    if isfield(manifest, 'params') && isstruct(manifest.params) && ...
            isfield(manifest.params, 'protocol_fingerprint')
        fp = char(manifest.params.protocol_fingerprint);
        return;
    end
    if isfield(manifest, 'protocol_fingerprint')
        fp = char(manifest.protocol_fingerprint);
    end
end

function aggregate = build_diagnostic_incomplete_aggregate( ...
        run_dir, cfg, matrix, manifest, do_save)
% Smoke / diagnostic path only: never produce inferential summaries.
    tables = struct();
    try
        tables = build_aggregation_tables(matrix, cfg);
    catch
        tables.raw_cell = table();
        tables.autonomous_fixed_horizon = table();
        tables.unique_seed_baseline = table();
        tables.dale_resolution = table();
    end
    tables.seed_contrast = table();
    tables.benchmark_contrast = table();

    aggregate = struct();
    aggregate.run_dir = run_dir;
    aggregate.status = 'diagnostic_incomplete_not_for_inference';
    aggregate.inference_status = 'deferred_to_phase_5b';
    aggregate.protocol_version = char(local_get(cfg.aggregation_plan, ...
        'protocol_version', 'matched_seed_contrasts_v1'));
    aggregate.protocol_fingerprint = char(local_get(cfg, 'protocol_fingerprint', ''));
    aggregate.protocol_tier = char(local_get(cfg, 'protocol_tier', ''));
    aggregate.analysis_set = char(local_get(cfg, 'active_analysis_set', ''));
    aggregate.independent_unit = 'base_seed';
    aggregate.seeds = local_get(matrix, 'expected_seeds', []);
    aggregate.cell_keys = local_get(matrix, 'expected_cell_keys', {});
    aggregate.matrix = matrix;
    aggregate.tables = tables;
    aggregate.aggregation_plan = cfg.aggregation_plan;
    aggregate.manifest = manifest;
    aggregate.no_inference = true;
    aggregate.matched_seed_contrast_structure_complete = false;
    aggregate.aggregation_inference_complete = false;
    aggregate.failure_reasons = matrix.reasons;

    if do_save
        aggregate = write_aggregation_artifacts(run_dir, aggregate, tables, matrix);
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
