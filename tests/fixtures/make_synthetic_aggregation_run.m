function run_dir = make_synthetic_aggregation_run(opts)
%MAKE_SYNTHETIC_AGGREGATION_RUN  Temp seed x cell fixtures for Phase 5A tests.
%
%   run_dir = make_synthetic_aggregation_run()
%   run_dir = make_synthetic_aggregation_run(opts)
%
% Deterministic endpoints (confirmatory arithmetic):
%   mc = 10 + 3*(A==three) + 2*(A==single) + 1*(S==on) + 4*(D==dde)
%       + 0.5*(F==r) + 0.01*seed
% Analogous formulas for NRMSE / wall / convergence / autonomous metrics.
%
% Optional opts fields: analysis_set, protocol_tier, seeds, omit_pair,
% omit_seed, omit_condition, extra_seed, extra_cell_key, duplicate_pair,
% failed_cell, wrong_fingerprint, wrong_analysis_set, include_autonomous,
% secondary_enabled, write_baselines, absurd_marker (spy that cells are not
% recomputed by run_ablation_cell).

    if nargin < 1 || isempty(opts)
        opts = struct();
    end

    analysis_set = char(local_get(opts, 'analysis_set', 'confirmatory'));
    protocol_tier = char(local_get(opts, 'protocol_tier', 'smoke'));
    cfg = mechanism_ablation_config(protocol_tier, analysis_set);

    if isfield(opts, 'secondary_enabled')
        cfg.secondary_enabled = logical(opts.secondary_enabled);
    else
        cfg.secondary_enabled = true;  % tests exercise autonomous columns
    end
    include_autonomous = logical(local_get(opts, 'include_autonomous', true));
    write_baselines = logical(local_get(opts, 'write_baselines', true));
    absurd_marker = double(local_get(opts, 'absurd_marker', 7777));

    if isfield(opts, 'seeds') && ~isempty(opts.seeds)
        cfg.seeds = double(opts.seeds(:))';
    else
        cfg.seeds = double(cfg.seeds(1:min(2, numel(cfg.seeds))));
    end
    cfg.n_seeds = numel(cfg.seeds);
    cfg.n_paired_runs = cfg.n_cells * cfg.n_seeds;
    cfg.aggregation_plan = build_matched_aggregation_plan(analysis_set);
    cfg.protocol_fingerprint = compute_protocol_fingerprint(cfg);

    root = tempname;
    mkdir(root);
    run_dir = fullfile(root, 'synth_agg_run');
    mkdir(run_dir);
    mkdir(fullfile(run_dir, 'cells'));
    if write_baselines
        mkdir(fullfile(run_dir, 'baselines'));
    end

    seeds = cfg.seeds(:);
    cells = cfg.cells;

    % Precompute per-seed compact autonomous control payloads (identical within seed)
    auto_by_seed = containers.Map('KeyType', 'double', 'ValueType', 'any');
    bundle_by_seed = containers.Map('KeyType', 'double', 'ValueType', 'any');
    for is = 1:numel(seeds)
        seed = seeds(is);
        horizons = fixed_horizons(cfg);
        content_hash = sprintf('auto_hash_seed_%d', seed);
        origin_hash = sprintf('origin_hash_seed_%d', seed);
        bundle_id = sprintf('bundle_seed_%d', seed);
        auto = fake_autonomous_controls(seed, horizons, content_hash, origin_hash, bundle_id);
        auto_by_seed(seed) = auto;
        if write_baselines
            bundle = fake_baseline_bundle(cfg, seed, horizons, content_hash, ...
                origin_hash, bundle_id);
            bundle_by_seed(seed) = bundle;
            matched_task_baselines = bundle; %#ok<NASGU>
            save(fullfile(run_dir, 'baselines', ...
                sprintf('seed_%d_matched_task_baselines.mat', seed)), ...
                'matched_task_baselines');
        end
    end

    % Write Cartesian product (then apply mutations)
    for is = 1:numel(seeds)
        seed = seeds(is);
        for ic = 1:numel(cells)
            cell_spec = cells{ic};
            key = char(cell_spec.cell_key);
            if should_omit(opts, seed, key, seeds)
                continue;
            end
            cr = build_cell_result(cfg, cell_spec, seed, include_autonomous, ...
                absurd_marker, auto_by_seed);
            if write_baselines && bundle_by_seed.isKey(seed)
                cr.matched_baseline_bundle_id = char(bundle_by_seed(seed).bundle_id);
            end
            cr = apply_cell_mutations(cr, opts, seed, key);
            fname = sprintf('seed_%d__%s.mat', seed, key);
            cell_result = cr; %#ok<NASGU>
            save(fullfile(run_dir, 'cells', fname), 'cell_result');
        end
    end

    if strcmp(analysis_set, 'sfa_sensitivity') || ...
            logical(local_get(opts, 'include_dale_reference_cells', false))
        write_dale_reference_cells(cfg, seeds, run_dir, include_autonomous, ...
            absurd_marker, auto_by_seed, write_baselines, bundle_by_seed);
    end

    % Extra / duplicate pairs after main write
    if isfield(opts, 'extra_seed') && ~isempty(opts.extra_seed)
        es = double(opts.extra_seed);
        key = char(cells{1}.cell_key);
        if ~auto_by_seed.isKey(es)
            horizons = fixed_horizons(cfg);
            content_hash = sprintf('auto_hash_seed_%d', es);
            origin_hash = sprintf('origin_hash_seed_%d', es);
            bundle_id = sprintf('bundle_seed_%d', es);
            auto_by_seed(es) = fake_autonomous_controls(es, horizons, ...
                content_hash, origin_hash, bundle_id);
        end
        cr = build_cell_result(cfg, cells{1}, es, include_autonomous, ...
            absurd_marker, auto_by_seed);
        cr.base_seed = es;
        cell_result = cr; %#ok<NASGU>
        save(fullfile(run_dir, 'cells', sprintf('seed_%d__%s.mat', es, key)), ...
            'cell_result');
    end
    if isfield(opts, 'extra_cell_key') && ~isempty(opts.extra_cell_key)
        ek = char(opts.extra_cell_key);
        seed = seeds(1);
        cr = build_cell_result(cfg, cells{1}, seed, include_autonomous, ...
            absurd_marker, auto_by_seed);
        cr.cell_key = ek;
        cell_result = cr; %#ok<NASGU>
        save(fullfile(run_dir, 'cells', sprintf('seed_%d__%s.mat', seed, ek)), ...
            'cell_result');
    end
    if isfield(opts, 'duplicate_pair') && ~isempty(opts.duplicate_pair)
        dp = opts.duplicate_pair;
        seed = double(dp.seed);
        key = char(dp.cell_key);
        src = fullfile(run_dir, 'cells', sprintf('seed_%d__%s.mat', seed, key));
        if isfile(src)
            % Second filename that parses to the same numeric seed + key
            % (zero-padded seed) so validate_aggregation_run_matrix sees a
            % duplicate pair_id.
            S = load(src, 'cell_result');
            cell_result = S.cell_result; %#ok<NASGU>
            dup_name = sprintf('seed_%02d__%s.mat', seed, key);
            if strcmp(dup_name, sprintf('seed_%d__%s.mat', seed, key))
                dup_name = sprintf('seed_0%d__%s.mat', seed, key);
            end
            save(fullfile(run_dir, 'cells', dup_name), 'cell_result');
        end
    end

    % Persist cfg last (fingerprint already final unless wrong_fingerprint on cfg)
    if isfield(opts, 'corrupt_cfg_fingerprint') && logical(opts.corrupt_cfg_fingerprint)
        cfg.protocol_fingerprint = 'deadbeef_wrong_fingerprint';
    end

    save(fullfile(run_dir, 'preregistered_config.mat'), 'cfg');
end

% =============================================================================
function write_dale_reference_cells(cfg, seeds, run_dir, include_autonomous, ...
        absurd_marker, auto_by_seed, write_baselines, bundle_by_seed)
    dale_keys = cfg.benchmark_baselines.dale_mesn_control_keys;
    ref_keys = {dale_keys.feat_x, dale_keys.feat_r};
    ref_specs = cell(size(ref_keys));
    for i = 1:numel(ref_keys)
        ref_specs{i} = find_cell_spec(cfg.cells, ref_keys{i});
        if isempty(ref_specs{i})
            ref_specs{i} = minimal_dale_cell_spec(ref_keys{i});
        end
    end
    for is = 1:numel(seeds)
        seed = seeds(is);
        for ic = 1:numel(ref_specs)
            cell_spec = ref_specs{ic};
            key = char(cell_spec.cell_key);
            fname = fullfile(run_dir, 'cells', sprintf('seed_%d__%s.mat', seed, key));
            if isfile(fname)
                continue;
            end
            cr = build_cell_result(cfg, cell_spec, seed, include_autonomous, ...
                absurd_marker, auto_by_seed);
            if write_baselines && bundle_by_seed.isKey(seed)
                cr.matched_baseline_bundle_id = char(bundle_by_seed(seed).bundle_id);
            end
            cell_result = cr; %#ok<NASGU>
            save(fname, 'cell_result');
        end
    end
end

function spec = find_cell_spec(cells, key)
    spec = [];
    for i = 1:numel(cells)
        if strcmp(char(cells{i}.cell_key), key)
            spec = cells{i};
            return;
        end
    end
end

function spec = minimal_dale_cell_spec(key)
    spec = struct('cell_key', key, 'cell_id', 0);
end

function tf = should_omit(opts, seed, key, ~)
    tf = false;
    if isfield(opts, 'omit_seed') && ~isempty(opts.omit_seed) && ...
            double(opts.omit_seed) == double(seed)
        tf = true;
        return;
    end
    if isfield(opts, 'omit_condition') && ~isempty(opts.omit_condition) && ...
            strcmp(char(opts.omit_condition), key)
        tf = true;
        return;
    end
    if isfield(opts, 'omit_pair') && ~isempty(opts.omit_pair)
        op = opts.omit_pair;
        if double(op.seed) == double(seed) && strcmp(char(op.cell_key), key)
            tf = true;
            return;
        end
    end
    if isfield(opts, 'omit_dale_ref_for_seed') && ...
            double(opts.omit_dale_ref_for_seed) == double(seed)
        dale_x = 'adapt-off__std-off__delay-ode_off__feat-x';
        dale_r = 'adapt-off__std-off__delay-ode_off__feat-r';
        if any(strcmp(key, {dale_x, dale_r}))
            tf = true;
            return;
        end
    end
end

function cr = apply_cell_mutations(cr, opts, seed, key)
    if isfield(opts, 'failed_cell') && ~isempty(opts.failed_cell)
        fc = opts.failed_cell;
        if double(fc.seed) == double(seed) && strcmp(char(fc.cell_key), key)
            cr.status = 'failed';
        end
    end
    if isfield(opts, 'wrong_fingerprint') && logical(opts.wrong_fingerprint)
        pair = local_get(opts, 'wrong_fingerprint_pair', []);
        if isempty(pair)
            cr.protocol_fingerprint = 'deadbeef_cell_fp';
        elseif double(pair.seed) == double(seed) && strcmp(char(pair.cell_key), key)
            cr.protocol_fingerprint = 'deadbeef_cell_fp';
        end
    end
    if isfield(opts, 'wrong_fingerprint_pair') && ~isempty(opts.wrong_fingerprint_pair)
        pair = opts.wrong_fingerprint_pair;
        if double(pair.seed) == double(seed) && strcmp(char(pair.cell_key), key)
            cr.protocol_fingerprint = 'deadbeef_cell_fp';
        end
    end
    if isfield(opts, 'wrong_analysis_set_pair') && ~isempty(opts.wrong_analysis_set_pair)
        pair = opts.wrong_analysis_set_pair;
        if double(pair.seed) == double(seed) && strcmp(char(pair.cell_key), key)
            cr.analysis_set = 'feature_exploratory';
        end
    elseif isfield(opts, 'wrong_analysis_set') && logical(opts.wrong_analysis_set)
        cr.analysis_set = 'feature_exploratory';
    end
    if isfield(opts, 'dde_finite_autonomous') && logical(opts.dde_finite_autonomous)
        if strcmp(cr.mode, 'DDE')
            cr.mackey_glass.rollout.status = 'unsupported_not_computed';
            cr.mackey_glass.rollout.metrics = struct( ...
                'pooled_nrmse_full_horizon', 0.5, ...
                'median_valid_horizon', 5, ...
                'fraction_right_censored', 0.1);
        end
    end
    if isfield(opts, 'ode_missing_autonomous') && logical(opts.ode_missing_autonomous)
        if strcmp(cr.mode, 'ODE')
            cr.mackey_glass.rollout.status = '';
            cr.mackey_glass.rollout.metrics = struct();
        end
    end
    if isfield(opts, 'hash_mismatch_seed') && ...
            double(opts.hash_mismatch_seed) == double(seed)
        % Break identical compact hashes within seed by mutating content_hash
        % on one mode/feature only (first ODE feat-x).
        if strcmp(cr.mode, 'ODE') && endsWith(key, 'feat-x')
            cr.mackey_glass.rollout.controls.content_hash = 'mutated_hash';
            cr.mackey_glass.autonomous_control_content_hash = 'mutated_hash';
        end
    end
    if isfield(opts, 'cross_feature_dale') && logical(opts.cross_feature_dale)
        if endsWith(key, 'feat-x')
            bad = 'adapt-off__std-off__delay-ode_off__feat-r';
            cr = set_dale_refs(cr, bad);
        end
    end
    if isfield(opts, 'missing_dale_ref_key') && logical(opts.missing_dale_ref_key)
        cr = set_dale_refs(cr, 'adapt-off__std-off__delay-ode_off__feat-MISSING');
    end
    if isfield(opts, 'label_conventional_as_dale') && logical(opts.label_conventional_as_dale)
        if isfield(cr.narma, 'baselines') && isfield(cr.narma.baselines, 'dale_mesn_control')
            cr.narma.baselines.dale_mesn_control.model_family = 'conventional_leaky_esn';
            cr.narma.baselines.dale_mesn_control.dale_mesn_control_reference = ...
                'conventional_leaky_esn';
        end
    end
end

function cr = set_dale_refs(cr, key)
    dale = pending_dale(key);
    if isfield(cr, 'narma') && isfield(cr.narma, 'baselines')
        cr.narma.baselines.dale_mesn_control = dale;
    end
    if isfield(cr, 'mackey_glass') && isfield(cr.mackey_glass, 'baselines')
        cr.mackey_glass.baselines.dale_mesn_control = dale;
    end
    if isfield(cr, 'mackey_glass') && isfield(cr.mackey_glass, 'rollout') && ...
            isfield(cr.mackey_glass.rollout, 'controls')
        cr.mackey_glass.rollout.controls.dale_mesn_control = dale;
    end
end

function cr = build_cell_result(cfg, cell_spec, seed, include_autonomous, ...
        absurd_marker, auto_by_seed)
    key = char(cell_spec.cell_key);
    factors = parse_key(key);
    mode = 'ODE';
    if strcmp(factors.D, 'dde_on')
        mode = 'DDE';
    end

    ep = synthetic_endpoints(factors, seed, absurd_marker);
    horizons = fixed_horizons(cfg);
    dale_feature = factors.F;
    if strcmp(dale_feature, 'all')
        dale_feature = 'x';
    end
    dale_key = dale_mesn_control_reference_key(dale_feature, ...
        cfg.benchmark_baselines.dale_mesn_control_keys);

    cr = struct();
    cr.cell_key = key;
    cr.cell_id = double(local_get(cell_spec, 'cell_id', 0));
    cr.base_seed = seed;
    cr.mode = mode;
    cr.adaptation = factors.A;
    cr.std = factors.S;
    cr.delay = factors.D;
    cr.which_states = factors.F;
    cr.protocol_tier = char(cfg.protocol_tier);
    cr.protocol_fingerprint = char(cfg.protocol_fingerprint);
    cr.analysis_set = char(cfg.active_analysis_set);
    cr.pilot_not_for_publication = logical(cfg.pilot_not_for_publication);
    cr.status = 'ok';
    cr.dale_violations = 0;
    cr.wall_time_seconds = ep.wall_time;
    cr.matched_baseline_bundle_id = sprintf('bundle_seed_%d', seed);

    cr.memory_capacity = struct('MC_total', ep.mc);
    cr.narma = struct( ...
        'test_nrmse', ep.narma_nrmse, ...
        'baselines', compact_onestep_baselines(seed, dale_key, 'narma'));
    cr.mackey_glass = struct( ...
        'test_nrmse', ep.mg_nrmse, ...
        'baselines', compact_onestep_baselines(seed, dale_key, 'mg'));

    cr.empirical_convergence = struct( ...
        'classification', 'empirically_contracting_on_test_set', ...
        'classification_reason', 'synthetic', ...
        'median_pair_slope', ep.convergence, ...
        'mean_pair_slope', ep.convergence, ...
        'final_max_spread', 1e-3, ...
        'final_median_spread', 1e-3, ...
        'convergence_ratio', 0.1);

    cr.qa = struct( ...
        'mean_rate', 0.4, ...
        'saturation_fraction', 0.1, ...
        'silent_fraction', 0.1, ...
        'resource_in_unit_interval', true);

    if strcmp(mode, 'DDE')
        cr.lle = NaN;
        cr.lle_status = 'unsupported_not_computed';
        cr.unsupported = struct('dde_lle', 'unsupported_not_computed');
        cr.mackey_glass.rollout = struct( ...
            'status', 'unsupported_not_computed', ...
            'protocol_version', cfg.mg_autonomous_rollout.protocol_version, ...
            'mode', 'DDE', ...
            'reason', 'DDE autonomous continuation is not implemented', ...
            'predictions', [], ...
            'metrics', [], ...
            'evaluation_provenance', struct('mode', 'unsupported'), ...
            'controls', dde_na_controls(auto_by_seed, seed, dale_key));
        cr.mackey_glass.autonomous_status = 'unsupported_not_computed';
    else
        cr.lle = NaN;
        cr.lle_status = 'not_requested';
        cr.unsupported = struct();
        if include_autonomous
            ctrl = auto_by_seed(seed);
            ctrl.dale_mesn_control = pending_dale(dale_key);
            ctrl.bundle_id = sprintf('bundle_seed_%d', seed);
            cr.mackey_glass.rollout = struct( ...
                'status', 'computed', ...
                'protocol_version', cfg.mg_autonomous_rollout.protocol_version, ...
                'role', cfg.mg_autonomous_rollout.role, ...
                'mode', 'ODE', ...
                'forecast_horizon_steps', cfg.mg_autonomous_rollout.forecast_horizon_steps, ...
                'fixed_report_horizons', horizons(:), ...
                'normalization_scale', 1.0, ...
                'normalization_reference', cfg.mg_autonomous_rollout.normalization_reference, ...
                'metrics', struct( ...
                    'pooled_nrmse_full_horizon', ep.auto_full, ...
                    'pooled_nrmse_at_fixed_horizons', ep.auto_fixed(:), ...
                    'median_valid_horizon', ep.auto_vh, ...
                    'fraction_right_censored', ep.auto_frac, ...
                    'fixed_report_horizons', horizons(:)), ...
                'evaluation_provenance', struct( ...
                    'mode', 'executed_shared_seed_bundle', ...
                    'test_target_override_used', false, ...
                    'origin_override_used', false, ...
                    'model_refit_for_rollout', false, ...
                    'lambda_reselected_for_rollout', false, ...
                    'autonomous_performance_used_for_selection', false, ...
                    'first_prediction_alignment_verified', true, ...
                    'object_state_unchanged', true), ...
                'controls', ctrl);
            cr.mackey_glass.autonomous_status = 'computed';
            cr.mackey_glass.autonomous_control_content_hash = ctrl.content_hash;
        else
            cr.mackey_glass.rollout = struct( ...
                'status', 'skipped', 'mode', 'ODE', 'metrics', []);
        end
    end
end

function ep = synthetic_endpoints(factors, seed, absurd_marker)
% Confirmatory arithmetic (exact contrasts):
%   SFA three vs single: delta = 1
%   STD on vs off: delta = 1
%   delay dde vs ode: delta = 4
%   combined three/on/dde vs off/off/ode: delta = 8
%   DiD A x S (additive): 0
    A3 = double(strcmp(factors.A, 'three_timescales'));
    A1 = double(strcmp(factors.A, 'single_moment_matched'));
    Son = double(strcmp(factors.S, 'on'));
    Dde = double(strcmp(factors.D, 'dde_on'));
    Fr = double(strcmp(factors.F, 'r'));
    base = absurd_marker;  % unmistakable non-model marker
    seed_term = 0.01 * double(seed);

    ep = struct();
    ep.mc = base + 10 + 3*A3 + 2*A1 + 1*Son + 4*Dde + 0.5*Fr + seed_term;
    % NRMSE: lower better; same factorial skeleton scaled
    ep.narma_nrmse = 2 + 0.3*A3 + 0.2*A1 + 0.1*Son + 0.4*Dde + 0.05*Fr + seed_term;
    ep.mg_nrmse = 3 + 0.3*A3 + 0.2*A1 + 0.1*Son + 0.4*Dde + 0.05*Fr + seed_term;
    ep.wall_time = 100 + 3*A3 + 2*A1 + 1*Son + 4*Dde + 0.5*Fr + seed_term;
    % more_negative favorable: more negative when treatment mechanisms on
    ep.convergence = -1 - 0.3*A3 - 0.2*A1 - 0.1*Son - 0.4*Dde - 0.05*Fr - seed_term;
    ep.auto_full = 1.5 + 0.3*A3 + 0.2*A1 + 0.1*Son + 0.05*Fr + seed_term;  % ODE only
    ep.auto_vh = 20 + 3*A3 + 2*A1 + 1*Son + 0.5*Fr + seed_term;
    ep.auto_frac = 0.2 + 0.01*A3 + 0.005*Fr;
    % Distinct fixed-horizon NRMSE values
    ep.auto_fixed = [ep.auto_full * 0.8; ep.auto_full * 1.1];
end

function factors = parse_key(key)
    factors = struct('A', '', 'S', '', 'D', '', 'F', '');
    tok = regexp(char(key), '^adapt-(.+)__std-(.+)__delay-(.+)__feat-(.+)$', ...
        'tokens', 'once');
    if ~isempty(tok)
        factors.A = tok{1};
        factors.S = tok{2};
        factors.D = tok{3};
        factors.F = tok{4};
    end
end

function h = fixed_horizons(cfg)
    h = double(cfg.mg_autonomous_rollout.fixed_report_horizons(:));
    if numel(h) < 2
        h = [1; max(5, cfg.mg_autonomous_rollout.forecast_horizon_steps)];
    else
        h = h(1:min(2, numel(h)));
        if h(1) == h(end)
            h(end) = h(1) + 4;
        end
    end
end

function dale = pending_dale(key)
    dale = struct();
    dale.name = 'dale_mesn_control';
    dale.status = 'pending_paired_aggregation';
    dale.model_family = 'dale_mesn_control';
    dale.dale_mesn_control_reference = char(key);
    dale.comparison = struct('numerical_superiority_claim', false);
    dale.provenance = struct('dale_mesn_control_reference', char(key));
end

function b = compact_onestep_baselines(seed, dale_key, task)
    b = struct();
    n0 = 0.9 + 0.001 * double(seed);
    if strcmp(task, 'narma')
        b.training_target_mean = struct('status', 'computed', ...
            'metrics_test', struct('nrmse', n0 + 0.05));
        b.linear_input_history = struct('status', 'computed', ...
            'metrics_test', struct('nrmse', n0 + 0.02));
        b.conventional_leaky_esn = struct( ...
            'status', 'computed', ...
            'model_family', 'conventional_leaky_esn', ...
            'metrics_test', struct('nrmse', n0));
    else
        b.persistence = struct('status', 'computed', ...
            'metrics_test', struct('nrmse', n0 + 0.04));
        b.linear_autoregression = struct('status', 'computed', ...
            'metrics_test', struct('nrmse', n0 + 0.03));
        b.conventional_leaky_esn = struct( ...
            'status', 'computed', ...
            'model_family', 'conventional_leaky_esn', ...
            'metrics_test', struct('nrmse', n0));
    end
    b.dale_mesn_control = pending_dale(dale_key);
end

function ctrl = fake_autonomous_controls(seed, horizons, content_hash, origin_hash, bundle_id)
    m = @(scale) struct( ...
        'pooled_nrmse_full_horizon', 0.55 * scale, ...
        'pooled_nrmse_at_fixed_horizons', [0.4; 0.7] * scale, ...
        'median_valid_horizon', 10 + seed * 0, ...
        'fraction_right_censored', 0.25, ...
        'fixed_report_horizons', horizons(:));
    mk = @(name, scale) struct( ...
        'name', name, ...
        'status', 'computed', ...
        'metrics', m(scale), ...
        'fixed_report_horizons', horizons(:), ...
        'first_step_alignment', struct('verified', true), ...
        'comparison', struct());
    ctrl = struct();
    ctrl.protocol_version = 'matched_mg_autonomous_controls_v1';
    ctrl.status = 'computed';
    ctrl.base_seed = seed;
    ctrl.bundle_id = bundle_id;
    ctrl.content_hash = content_hash;
    ctrl.origin_schedule_hash = origin_hash;
    ctrl.normalization_scale = 1.0;
    ctrl.persistence = mk('persistence', 1.0);
    ctrl.linear_autoregression = mk('linear_autoregression', 1.05);
    ctrl.conventional_leaky_esn = mk('conventional_leaky_esn', 1.1);
    ctrl.dale_mesn_control = pending_dale( ...
        'adapt-off__std-off__delay-ode_off__feat-x');
    ctrl.evaluation_provenance = struct( ...
        'mode', 'executed_shared_seed_bundle', ...
        'publication_shared_bundle', true);
    ctrl.comparisons_attached = false;
    ctrl.applicability = 'ode';
    ctrl.fixed_report_horizons = horizons(:);
end

function ctrl = dde_na_controls(auto_by_seed, seed, dale_key)
    if auto_by_seed.isKey(seed)
        base = auto_by_seed(seed);
    else
        base = fake_autonomous_controls(seed, [1; 5], 'h', 'o', 'b');
    end
    ctrl = base;
    na = 'not_applicable_dde_model_rollout_unsupported';
    for nm = {'persistence', 'linear_autoregression', 'conventional_leaky_esn'}
        ctrl.(nm{1}).status = na;
        ctrl.(nm{1}).comparison = struct();
        ctrl.(nm{1}).metrics = struct();
    end
    ctrl.dale_mesn_control = pending_dale(dale_key);
    ctrl.dale_mesn_control.status = na;
    ctrl.status = na;
    ctrl.comparisons_attached = false;
    ctrl.applicability = na;
end

function bundle = fake_baseline_bundle(cfg, seed, horizons, content_hash, ...
        origin_hash, bundle_id)
    n0 = 0.9 + 0.001 * double(seed);
    nb = struct( ...
        'training_target_mean', struct('metrics_test', struct('nrmse', n0 + 0.05)), ...
        'linear_input_history', struct('metrics_test', struct('nrmse', n0 + 0.02)), ...
        'conventional_leaky_esn', struct('metrics_test', struct('nrmse', n0)));
    mb = struct( ...
        'persistence', struct('metrics_test', struct('nrmse', n0 + 0.04)), ...
        'linear_autoregression', struct('metrics_test', struct('nrmse', n0 + 0.03)), ...
        'conventional_leaky_esn', struct('metrics_test', struct('nrmse', n0)));
    ac = fake_autonomous_controls(seed, horizons, content_hash, origin_hash, bundle_id);
    bundle = struct();
    bundle.schema_version = 'seed_matched_baseline_bundle_v2';
    bundle.protocol_version = 'matched_task_baselines_v1';
    bundle.protocol_tier = char(cfg.protocol_tier);
    bundle.protocol_fingerprint = char(cfg.protocol_fingerprint);
    bundle.base_seed = seed;
    bundle.bundle_id = bundle_id;
    bundle.narma_task_data_hash = sprintf('narma_td_%d', seed);
    bundle.narma_split_hash = sprintf('narma_sp_%d', seed);
    bundle.mackey_glass_task_data_hash = sprintf('mg_td_%d', seed);
    bundle.mackey_glass_split_hash = sprintf('mg_sp_%d', seed);
    bundle.linear_ar_fitted_model_hash = sprintf('lar_%d', seed);
    bundle.conventional_esn_fitted_model_hash = sprintf('cesn_%d', seed);
    bundle.autonomous_control_content_hash = content_hash;
    bundle.origin_schedule_hash = origin_hash;
    bundle.evaluation_provenance = struct('mode', 'executed_shared_seed_bundle');
    bundle.narma = struct('baselines', nb);
    bundle.mackey_glass_onestep = struct('baselines', mb);
    bundle.mackey_glass_autonomous = ac;
    bundle.baseline_result_status = 'computed';
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
