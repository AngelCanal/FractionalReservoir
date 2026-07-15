function cell_result = run_ablation_cell(cell_spec, base_seed, cfg, options)
% run_ablation_cell  Execute primary (and optional secondary) endpoints for one cell.
%
% cell_result includes metrics, QA diagnostics, unsupported-status strings, and
% provenance fields. Never writes legacy result directories.

    if nargin < 4 || isempty(options)
        options = struct();
    end
    verbose = local_get(options, 'verbose', true);
    run_secondary = local_get(options, 'run_secondary', cfg.secondary_enabled);
    param_overrides = local_get(options, 'param_overrides', struct());
    shared_baseline_bundle = local_get(options, 'shared_baseline_bundle', []);

    t_wall0 = tic;
    cell_result = struct();
    cell_result.cell_key = cell_spec.cell_key;
    cell_result.cell_id = cell_spec.cell_id;
    cell_result.base_seed = base_seed;
    cell_result.mode = cell_spec.mode;
    cell_result.protocol_tier = local_get(cfg, 'protocol_tier', '');
    cell_result.protocol_fingerprint = local_get(cfg, 'protocol_fingerprint', '');
    cell_result.pilot_not_for_publication = logical(cfg.pilot_not_for_publication);
    cell_result.analysis_set = local_field(cell_spec, 'analysis_set', ...
        local_get(cfg, 'active_analysis_set', ''));
    cell_result.analysis_role = local_field(cell_spec, 'analysis_role', '');
    cell_result.adaptation_profile_label = local_field(cell_spec, ...
        'adaptation_profile_label', local_field(cell_spec, 'adaptation', ''));
    cell_result.feature_analysis_role = local_field(cell_spec, ...
        'feature_analysis_role', '');
    cell_result.raw_feature_dimension = local_field(cell_spec, ...
        'raw_feature_dimension', NaN);
    cell_result.projected_feature_dimension = local_field(cell_spec, ...
        'projected_feature_dimension', NaN);
    cell_result.dimension_matched = local_field(cell_spec, ...
        'dimension_matched', false);
    cell_result.status = 'ok';
    cell_result.failure_status = '';
    cell_result.unsupported = struct();

    try
        [params, meta] = build_ablation_params(cell_spec, base_seed, cfg, param_overrides);
        cell_result.params_summary = summarize_params(params, meta, cell_spec);
        cell_result.dale_violations_E = meta.sign_violations_E;
        cell_result.dale_violations_I = meta.sign_violations_I;
        cell_result.dale_violations = meta.sign_violations_E + meta.sign_violations_I;

        if ~isempty(shared_baseline_bundle)
            [ok_b, b_report] = validate_seed_matched_baseline_bundle( ...
                shared_baseline_bundle, cfg, base_seed, params.W_in);
            if ~ok_b
                error('run_ablation_cell:SharedBaselineRejected', ...
                    'Shared seed baseline bundle rejected for cell %s: %s', ...
                    cell_spec.cell_key, strjoin(b_report.reasons, ','));
            end
            cell_result.matched_baseline_bundle_id = shared_baseline_bundle.bundle_id;
        else
            cell_result.matched_baseline_bundle_id = '';
            cell_result.matched_baseline_provenance = 'executed_cell_local';
        end

        esn = SRNN_ESN(params);
        L = cfg.lengths;
        if isfield(L, 'ode_solver') && ~isempty(L.ode_solver)
            esn.ode_solver = L.ode_solver;
        elseif cfg.pilot_not_for_publication || ...
                (isfield(cfg, 'protocol_tier') && any(strcmp(cfg.protocol_tier, {'smoke', 'pilot'})))
            esn.ode_solver = @ode45;  % faster integrator for reduced smoke/pilot QA
        end

        solver_train_opts = struct();
        if isfield(L, 'ode_reltol'); solver_train_opts.ode_reltol = L.ode_reltol; end
        if isfield(L, 'ode_abstol'); solver_train_opts.ode_abstol = L.ode_abstol; end
        if isfield(L, 'dde_reltol'); solver_train_opts.dde_reltol = L.dde_reltol; end
        if isfield(L, 'dde_abstol'); solver_train_opts.dde_abstol = L.dde_abstol; end
        solver_train_opts.ode_solver = esn.ode_solver;

        %% QA trajectory (rates, saturation, resources, rank diagnostics)
        qa = collect_qa_diagnostics(esn, params, base_seed, L);
        cell_result.qa = qa;

        %% Primary: linear memory capacity
        mc_opts = struct( ...
            'lags', L.mc_lags, ...
            'washout', L.mc_washout, ...
            'T_train', L.mc_T_train, ...
            'T_val', L.mc_T_val, ...
            'T_test', L.mc_T_test, ...
            'minimum_scored_rows', L.mc_minimum_scored_rows, ...
            'seed_train', base_seed + 10, ...
            'seed_val', base_seed + 11, ...
            'seed_test', base_seed + 12, ...
            'feature_mode', cell_spec.which_states, ...
            'n_chance', local_get(L, 'mc_n_chance', 100));
        if isfield(L, 'lambda_grid') && ~isempty(L.lambda_grid)
            mc_opts.lambda_grid = L.lambda_grid;
        end
        mc = compute_memory_capacity(esn, mc_opts);
        cell_result.memory_capacity = compact_mc(mc);

        %% Primary: NARMA
        narma_opts = struct( ...
            'order', L.narma_order, ...
            'T', L.narma_T, ...
            'washout_steps', L.narma_washout, ...
            'train_ratio', L.train_ratio, ...
            'val_ratio', L.val_ratio, ...
            'seed', base_seed + 20, ...
            'base_seed', base_seed, ...
            'feature_mode', cell_spec.which_states, ...
            'cfg', cfg, ...
            'benchmark_baselines', local_get(cfg, 'benchmark_baselines', struct()));
        if isfield(L, 'lambda_grid') && ~isempty(L.lambda_grid)
            narma_opts.lambda_grid = L.lambda_grid;
        end
        if ~isempty(shared_baseline_bundle)
            narma_opts.shared_baseline_bundle = shared_baseline_bundle;
        end
        narma_opts = merge_structs(narma_opts, solver_train_opts);
        narma = narma_benchmark(esn, narma_opts);
        cell_result.narma = compact_bench(narma);
        if strcmp(narma.status, 'failed_required_baseline')
            cell_result.status = 'failed_primary_endpoint';
            cell_result.failure_status = local_field(narma, 'failure_status', ...
                'narma_required_baseline_failed');
        end

        %% Primary: Mackey-Glass one-step (+ secondary autonomous ODE endpoint)
        mg_opts = struct( ...
            'T', L.mg_T, ...
            'discard', L.mg_discard, ...
            'washout_steps', L.mg_washout, ...
            'train_ratio', L.train_ratio, ...
            'val_ratio', L.val_ratio, ...
            'seed', base_seed + 30, ...
            'base_seed', base_seed, ...
            'feature_mode', cell_spec.which_states, ...
            'do_rollout', logical(L.mg_do_rollout), ...
            'mg_autonomous_rollout', local_get(cfg, 'mg_autonomous_rollout', ...
                build_mg_autonomous_rollout_config(local_get(cfg, 'protocol_tier', 'smoke'))), ...
            'cfg', cfg, ...
            'benchmark_baselines', local_get(cfg, 'benchmark_baselines', struct()));
        if isfield(L, 'lambda_grid') && ~isempty(L.lambda_grid)
            mg_opts.lambda_grid = L.lambda_grid;
        end
        if isfield(L, 'mg_ar_lags')
            mg_opts.ar_lags = L.mg_ar_lags;
        end
        if ~isempty(shared_baseline_bundle)
            mg_opts.shared_baseline_bundle = shared_baseline_bundle;
        end
        if strcmp(cell_spec.mode, 'DDE')
            cell_result.unsupported.dde_autonomous = cfg.unsupported_status.dde_autonomous;
        end
        mg_opts = merge_structs(mg_opts, solver_train_opts);
        mg = mackey_glass_benchmark(esn, mg_opts);
        cell_result.mackey_glass = compact_bench(mg);
        if strcmp(cell_spec.mode, 'DDE')
            cell_result.mackey_glass.autonomous_status = cfg.unsupported_status.dde_autonomous;
            cell_result.mackey_glass.autonomous_nrmse = NaN;
        end
        if strcmp(mg.status, 'failed_required_baseline') && ...
                ~strcmp(cell_result.status, 'failed')
            cell_result.status = 'failed_primary_endpoint';
            cell_result.failure_status = local_field(mg, 'failure_status', ...
                'mackey_glass_required_baseline_failed');
        end
        if strcmp(mg.status, 'failed_required_autonomous_endpoint')
            cell_result.status = 'failed_required_autonomous_endpoint';
            cell_result.failure_status = local_field(mg, 'failure_status', ...
                'failed_required_autonomous_endpoint');
            if isfield(mg, 'rollout') && isfield(mg.rollout, 'failure_reasons')
                cell_result.autonomous_failure_reasons = mg.rollout.failure_reasons;
            end
        end

        %% Primary: empirical convergence
        rng(base_seed + 40);
        U_esp = 2 * rand(L.esp_T, size(params.W_in, 2)) - 1;
        esp_opts = struct( ...
            'n_ic', L.esp_n_ic, ...
            'washout_steps', L.esp_washout, ...
            'min_tail_points', L.esp_min_tail_points, ...
            'input_seed', base_seed + 41, ...
            'ic_seed', base_seed + 42, ...
            'verbose', false);
        esp = verify_echo_state_property(esn, U_esp, esp_opts);
        cell_result.empirical_convergence = compact_empirical_convergence(esp);
        [conv_ok, conv_reason] = validate_empirical_convergence_endpoint( ...
            cell_result.empirical_convergence);
        if ~conv_ok
            cell_result.status = 'failed_primary_endpoint';
            cell_result.failure_status = conv_reason;
            cell_result.error_id = 'run_ablation_cell:NonfiniteConvergence';
        end

        %% Explicit unsupported metrics
        cell_result.unsupported.fisher_memory = cfg.unsupported_status.fisher_memory;
        if strcmp(cell_spec.mode, 'DDE')
            cell_result.unsupported.dde_lle = cfg.unsupported_status.dde_lle;
            cell_result.lle = NaN;
            cell_result.lle_status = cfg.unsupported_status.dde_lle;
        else
            cell_result.lle_status = 'not_requested_in_pilot_primary';
            cell_result.lle = NaN;
        end

        %% Optional secondary (full mode)
        if run_secondary
            cell_result.secondary = run_secondary_endpoints(params, esn, cell_spec, base_seed, L, cfg);
        else
            cell_result.secondary = struct('status', 'skipped');
        end

        cell_result.selected_lambda_narma = local_field(narma, 'selected_lambda', NaN);
        cell_result.selected_lambda_mg = local_field(mg, 'selected_lambda', NaN);
        if isfield(mc, 'lambda_per_lag') && ~isempty(mc.lambda_per_lag)
            cell_result.selected_lambda_mc_median = median(mc.lambda_per_lag(:), 'omitnan');
        else
            cell_result.selected_lambda_mc_median = NaN;
        end

    catch ME
        cell_result.status = 'failed';
        cell_result.failure_status = ME.message;
        cell_result.error_id = ME.identifier;
        if verbose
            fprintf('FAIL %s seed=%d: %s\n', cell_spec.cell_key, base_seed, ME.message);
        end
    end

    cell_result.wall_time_seconds = toc(t_wall0);
    if verbose
        fprintf('[%s] seed=%d status=%s t=%.1fs\n', ...
            cell_spec.cell_key, base_seed, cell_result.status, cell_result.wall_time_seconds);
    end
end

function qa = collect_qa_diagnostics(esn, params, base_seed, L)
    rng(base_seed + 50);
    T = max(L.esp_T, 200);
    U = 2 * rand(T, size(params.W_in, 2)) - 1;
    run_opts = struct('reset_before', true, 'update_internal_state', false, ...
        'ode_reltol', local_get(L, 'ode_reltol', 1e-6), ...
        'ode_abstol', local_get(L, 'ode_abstol', 1e-8), ...
        'dde_reltol', local_get(L, 'dde_reltol', 1e-6), ...
        'dde_abstol', local_get(L, 'dde_abstol', 1e-8));
    [X, S_hist, ~] = esn.runReservoir(U, run_opts);

    % S_hist is (T x n_state); rates sampled on a stride for speed
    stride = max(1, floor(size(S_hist, 1) / 50));
    sample_idx = 1:stride:size(S_hist, 1);
    rates = zeros(params.n, numel(sample_idx));
    for k = 1:numel(sample_idx)
        rates(:, k) = esn.computeRates(S_hist(sample_idx(k), :)');
    end
    sat = mean(rates(:) >= 0.99);
    silent = mean(rates(:) <= 0.01);
    mean_rate = mean(rates(:));

    layout = state_layout(params);
    resource_min = 1;
    resource_max = 0;
    resource_ok = true;
    if ~isempty(layout.idx_b_E) || ~isempty(layout.idx_b_I)
        b_idx = [layout.idx_b_E(:); layout.idx_b_I(:)];
        B = S_hist(:, b_idx);
        resource_min = min(B(:));
        resource_max = max(B(:));
        resource_ok = (resource_min >= -1e-7) && (resource_max <= 1 + 1e-7);
    end

    % Feature effective rank / condition on post-washout features
    wash = min(L.esp_washout, size(X, 1) - 2);
    Xw = X(wash+1:end, :);
    Xw = Xw - mean(Xw, 1);
    s = std(Xw, 0, 1);
    s(s < sqrt(eps)) = 1;
    Z = Xw ./ s;
    sv = svd(Z, 'econ');
    p = sv / sum(sv);
    p = p(p > 0);
    eff_rank = exp(-sum(p .* log(p)));
    cond_num = sv(1) / max(sv(end), eps);

    qa = struct();
    qa.mean_rate = mean_rate;
    qa.saturation_fraction = sat;
    qa.silent_fraction = silent;
    qa.state_min = min(S_hist(:));
    qa.state_max = max(S_hist(:));
    qa.resource_min = resource_min;
    qa.resource_max = resource_max;
    qa.resource_in_unit_interval = resource_ok;
    qa.feature_effective_rank = eff_rank;
    qa.feature_condition_number = cond_num;
    qa.n_feature_rows = size(Xw, 1);
    qa.n_features = size(Xw, 2);
end

function secondary = run_secondary_endpoints(params, esn, cell_spec, base_seed, L, cfg)
    secondary = struct();
    secondary.status = 'ok';
    try
        nmc = compute_nonlinear_memory_capacity(esn, struct( ...
            'washout', L.mc_washout, ...
            'T_train', L.mc_T_train, ...
            'T_val', L.mc_T_val, ...
            'T_test', L.mc_T_test, ...
            'seed_train', base_seed + 60, ...
            'feature_mode', cell_spec.which_states));
        secondary.nonlinear_capacity_total = local_field(nmc, 'MC_total', NaN);
    catch ME
        secondary.nonlinear_capacity_status = ME.message;
        secondary.nonlinear_capacity_total = NaN;
    end

    try
        fd = frequency_discrimination_benchmark(params, struct( ...
            'T', min(L.narma_T, 1200), ...
            'washout_steps', L.narma_washout, ...
            'seed', base_seed + 70, ...
            'feature_mode', cell_spec.which_states));
        secondary.frequency_discrimination = compact_bench(fd);
    catch ME
        secondary.frequency_discrimination_status = ME.message;
    end

    try
        sc = stimulus_counting_benchmark(params, struct( ...
            'T', min(L.narma_T, 1200), ...
            'washout_steps', L.narma_washout, ...
            'seed', base_seed + 80, ...
            'feature_mode', cell_spec.which_states));
        secondary.stimulus_counting = compact_bench(sc);
    catch ME
        secondary.stimulus_counting_status = ME.message;
    end

    try
        kr = compute_kernel_rank(esn, struct( ...
            'seed', base_seed + 90, ...
            'feature_mode', cell_spec.which_states));
        secondary.effective_rank = local_field(kr, 'KR_effective_rank', NaN);
    catch ME
        secondary.effective_rank_status = ME.message;
        secondary.effective_rank = NaN;
    end

    if strcmp(cell_spec.mode, 'ODE')
        secondary.autonomous_ode_horizon_status = 'reported_in_mackey_glass_if_enabled';
    else
        secondary.autonomous_ode_horizon = NaN;
        secondary.autonomous_ode_horizon_status = cfg.unsupported_status.dde_autonomous;
    end
end

function s = compact_mc(mc)
    s = struct();
    s.MC_total = local_field(mc, 'MC_total', NaN);
    s.MC_area = local_field(mc, 'MC_total', NaN);
    if isfield(mc, 'MC_spectrum')
        s.MC_spectrum = mc.MC_spectrum(:);
    else
        s.MC_spectrum = [];
    end
    if isfield(mc, 'lags')
        s.lags = mc.lags(:);
    else
        s.lags = [];
    end
    s.lambda_per_lag = local_field(mc, 'lambda_per_lag', []);
end

function s = compact_bench(b)
    s = struct();
    s.status = local_field(b, 'status', 'ok');
    s.test_nrmse = extract_nrmse(b, 'test');
    s.val_nrmse = extract_nrmse(b, 'val');
    s.train_nrmse = extract_nrmse(b, 'train');
    s.selected_lambda = local_field(b, 'selected_lambda', NaN);
    if isfield(b, 'baselines')
        s.baselines = compact_baselines(b.baselines);
    end
    if isfield(b, 'configuration') && isfield(b.configuration, 'resolved_lambda_grid')
        s.resolved_lambda_grid = b.configuration.resolved_lambda_grid;
    end
    if isfield(b, 'base_seed')
        s.base_seed = b.base_seed;
    end
    if isfield(b, 'failure_status')
        s.failure_status = b.failure_status;
    end
    if isfield(b, 'rollout') || isfield(b, 'autonomous')
        if isfield(b, 'rollout')
            s.rollout = compact_mg_rollout(b.rollout);
            if isfield(b.rollout, 'status')
                s.autonomous_status = b.rollout.status;
            end
            if strcmp(local_field(b.rollout, 'status', ''), 'computed')
                s.autonomous_nrmse = extract_nested_nrmse(b.rollout.metrics);
            else
                s.autonomous_nrmse = NaN;
            end
        else
            s.autonomous_nrmse = extract_nested_nrmse(b.autonomous);
        end
    end
end

function r = compact_mg_rollout(rollout)
% Retain structured autonomous summary needed for later aggregation.
    r = struct();
    keep = {'status', 'protocol_version', 'role', 'mode', 'reason', ...
        'origin_schedule', 'forecast_horizon_steps', 'fixed_report_horizons', ...
        'normalization_reference', 'normalization_scale', 'per_origin', ...
        'metrics', 'evaluation_provenance', 'failure_reasons', 'error_id', ...
        'controls'};
    for i = 1:numel(keep)
        if isfield(rollout, keep{i})
            r.(keep{i}) = rollout.(keep{i});
        end
    end
    if isfield(r, 'per_origin') && ~isempty(r.per_origin)
        n_po = numel(r.per_origin);
        slim_cells = cell(n_po, 1);
        for o = 1:n_po
            po = r.per_origin(o);
            slim = struct();
            for f = {'origin_global_index', 'origin_test_relative_index', 'horizon', ...
                    'full_horizon_nrmse', 'rmse', 'valid_horizon_steps', ...
                    'first_threshold_exceedance_step', 'right_censored', ...
                    'valid_error_threshold', 'threshold_sensitivity'}
                if isfield(po, f{1})
                    slim.(f{1}) = po.(f{1});
                end
            end
            slim_cells{o} = slim;
        end
        r.per_origin = [slim_cells{:}];
        r.per_origin = r.per_origin(:);
    end
    if strcmp(local_field(r, 'status', ''), 'unsupported_not_computed')
        r.predictions = [];
        r.metrics = [];
    end
end

function b = compact_baselines(baselines)
% Keep aggregation-facing baseline fields; full candidate tables live in the
% seed baseline artifact only.
    b = baselines;
    if ~(isfield(b, 'protocol_version') && ...
            strcmp(char(b.protocol_version), 'matched_task_baselines_v1')) && ...
            ~isfield(b, 'conventional_leaky_esn')
        return;
    end
    required = {'conventional_leaky_esn', 'dale_mesn_control'};
    for i = 1:numel(required)
        if ~isfield(b, required{i})
            error('compact_bench:MissingBaseline', ...
                'Required baseline %s dropped before compaction.', required{i});
        end
    end
    if isfield(b, 'conventional_leaky_esn')
        ce = b.conventional_leaky_esn;
        keep = {'name','status','role','protocol_version','model_family', ...
            'feature_dimension','include_input','train_rows','validation_rows', ...
            'test_rows','metrics','metrics_train','metrics_val','metrics_test', ...
            'selected_lambda','ridge_diagnostics','hyperparameters','provenance', ...
            'reservoir_seed','spectral_radius','achieved_spectral_radius', ...
            'leak_rate','input_scaling','input_support_indices', ...
            'input_nonzero_count','selected_candidate_index', ...
            'selected_at_candidate_boundary','finite_state_trajectory', ...
            'recurrent_dale_constrained','has_sfa','has_std','has_delay', ...
            'comparison','fitted_model_hash','train_prediction_hash', ...
            'validation_prediction_hash','test_prediction_hash'};
        ce2 = struct();
        for k = 1:numel(keep)
            if isfield(ce, keep{k})
                ce2.(keep{k}) = ce.(keep{k});
            end
        end
        if isfield(ce2, 'ridge_diagnostics') && isstruct(ce2.ridge_diagnostics)
            rd = ce2.ridge_diagnostics;
            for f = {'coefficients','feature_mean','feature_scale'}
                if isfield(rd, f{1})
                    rd = rmfield(rd, f{1});
                end
            end
            ce2.ridge_diagnostics = rd;
        end
        b.conventional_leaky_esn = ce2;
    end
    for nm = {'linear_input_history','linear_autoregression', ...
            'linear_input_ar','linear_ar','training_target_mean','persistence', ...
            'target_mean'}
        if isfield(b, nm{1}) && isstruct(b.(nm{1}))
            bi = b.(nm{1});
            for drop = {'candidate_selection_table','lambda_selection_table', ...
                    'fitted_model','predictions','W_res','W_in'}
                if isfield(bi, drop{1})
                    bi = rmfield(bi, drop{1});
                end
            end
            if isfield(bi, 'ridge_diagnostics') && isstruct(bi.ridge_diagnostics)
                rd = bi.ridge_diagnostics;
                for f = {'coefficients','feature_mean','feature_scale'}
                    if isfield(rd, f{1})
                        rd = rmfield(rd, f{1});
                    end
                end
                bi.ridge_diagnostics = rd;
            end
            b.(nm{1}) = bi;
        end
    end
end

function v = extract_nrmse(b, split_name)
    v = NaN;
    candidates = { ...
        sprintf('metrics_%s', split_name), ...
        sprintf('%s_metrics', split_name), ...
        split_name};
    for i = 1:numel(candidates)
        f = candidates{i};
        if isfield(b, f)
            m = b.(f);
            v = extract_nested_nrmse(m);
            return;
        end
    end
    if isfield(b, 'metrics') && isfield(b.metrics, split_name)
        v = extract_nested_nrmse(b.metrics.(split_name));
    end
end

function v = extract_nested_nrmse(m)
    v = NaN;
    if ~isstruct(m)
        if isnumeric(m) && isscalar(m)
            v = m;
        end
        return;
    end
    if isfield(m, 'nrmse'); v = m.nrmse; return; end
    if isfield(m, 'NRMSE'); v = m.NRMSE; return; end
    if isfield(m, 'test_nrmse'); v = m.test_nrmse; return; end
end

function s = summarize_params(params, meta, cell_spec)
    if nargin < 3
        cell_spec = struct();
    end
    s = struct();
    s.n = params.n;
    s.n_a_E = params.n_a_E;
    s.n_a_I = params.n_a_I;
    s.n_b_E = params.n_b_E;
    s.n_b_I = params.n_b_I;
    s.lags = params.lags;
    s.which_states = params.which_states;
    s.input_scaling = meta.input_scaling;
    s.level_of_chaos = meta.level_of_chaos;
    if isfield(params, 'tau_a_E'); s.tau_a_E = params.tau_a_E; end
    if isfield(params, 'tau_a_I'); s.tau_a_I = params.tau_a_I; end
    if isfield(params, 'c_total_E'); s.c_total_E = params.c_total_E; end
    if isfield(params, 'c_total_I'); s.c_total_I = params.c_total_I; end
    if isfield(params, 'c_a_E'); s.c_a_E = params.c_a_E; end
    if isfield(params, 'c_a_I'); s.c_a_I = params.c_a_I; end
    if isfield(params, 'input_mask_mode'); s.input_mask_mode = params.input_mask_mode; end
    if isfield(params, 'input_driven_indices')
        s.input_driven_indices = params.input_driven_indices;
    end
    if isfield(params, 'input_nnz_per_channel')
        s.input_nnz_per_channel = params.input_nnz_per_channel;
    end
    if isfield(params, 'adaptation_initialization_mode')
        s.adaptation_initialization_mode = params.adaptation_initialization_mode;
    end
    if isfield(params, 'adaptation_profile_label')
        s.adaptation_profile_label = params.adaptation_profile_label;
    elseif isfield(cell_spec, 'adaptation_profile_label')
        s.adaptation_profile_label = cell_spec.adaptation_profile_label;
    end
    if isfield(params, 'analysis_set'); s.analysis_set = params.analysis_set; end
    if isfield(params, 'analysis_role'); s.analysis_role = params.analysis_role; end
    if isfield(params, 'feature_analysis_role')
        s.feature_analysis_role = params.feature_analysis_role;
    end
    if isfield(params, 'raw_feature_dimension')
        s.raw_feature_dimension = params.raw_feature_dimension;
    end
    if isfield(params, 'projected_feature_dimension')
        s.projected_feature_dimension = params.projected_feature_dimension;
    end
    if isfield(params, 'dimension_matched')
        s.dimension_matched = params.dimension_matched;
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end

function v = local_field(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end

function out = merge_structs(a, b)
    out = a;
    if isempty(b); return; end
    fn = fieldnames(b);
    for i = 1:numel(fn)
        out.(fn{i}) = b.(fn{i});
    end
end
