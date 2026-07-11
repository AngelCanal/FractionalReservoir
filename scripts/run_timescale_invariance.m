function [result, run_dir] = run_timescale_invariance(options)
% run_timescale_invariance  Multi-timescale, invariance, and response-lag analysis.
%
%   [result, run_dir] = run_timescale_invariance()
%   [result, run_dir] = run_timescale_invariance(options)
%
% Options: .dry_run, .save_results, .run_dependencies (default false),
%          .dt, .n_a_list, .make_figures, .run_id, .revalidated_root_override

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end

    dry_run = local_get(options, 'dry_run', false);
    save_results = local_get(options, 'save_results', true);
    run_dependencies = local_get(options, 'run_dependencies', false); %#ok<NASGU>
    make_figures = local_get(options, 'make_figures', true);
    dt = local_get(options, 'dt', 0.1);
    n_a_list = local_get(options, 'n_a_list', [1, 2, 3, 5]);
    seed = local_get(options, 'seed', 7);

    params_final = struct('dt', dt, 'n_a_list', n_a_list, 'seed', seed);
    run_dir = '';
    if save_results
        ctx_opts = struct('master_seed', seed);
        if isfield(options, 'run_id'); ctx_opts.run_id = options.run_id; end
        if isfield(options, 'revalidated_root_override')
            ctx_opts.revalidated_root_override = options.revalidated_root_override;
        end
        ctx = create_run_context('timescale_invariance', ctx_opts);
        save_run_manifest(ctx, params_final);
        run_dir = ctx.run_dir;
    end

    result = struct('params', params_final, 'run_dir', run_dir);
    if dry_run
        result.status = 'dry_run';
        return;
    end

    %% (A) Timescale spectrum vs number of SFA timescales
    specA = struct('n_a_E', num2cell(n_a_list), ...
        'MC_total', [], 'MC_spectrum', [], 'MC_lags', [], ...
        'Fisher_curve', [], 'Fisher_lags', [], 'Fisher_tau', [], 'MC_tau', []);

    for ii = 1:numel(n_a_list)
        na = n_a_list(ii);
        overrides = struct('dt', dt, 'n_a_E', na, ...
            'tau_a_E', logspace(log10(0.25), log10(25), na));
        params = default_MESN_config(overrides);
        esn = SRNN_ESN(params);

        mc = compute_memory_capacity(esn, struct('T', 5000, 'K_max', 200, ...
            'washout', 300, 'lambda', params.lambda, 'feature_mode', 'x'));
        fisher = struct('FI_curve', nan(200, 1), 'lags', (1:200)', ...
            'status', 'quarantined_not_computed', 'scientifically_valid', false);
        mc_fit = fit_memory_decay(mc.lags, mc.MC_spectrum, struct());

        specA(ii).MC_total = mc.MC_total;
        specA(ii).MC_spectrum = mc.MC_spectrum;
        specA(ii).MC_lags = mc.lags;
        specA(ii).Fisher_curve = fisher.FI_curve;
        specA(ii).Fisher_lags = fisher.lags;
        specA(ii).MC_tau = extract_tau(mc_fit);
        specA(ii).Fisher_tau = nan;
        fprintf('n_a_E=%d: MC_total=%.2f  MC_tau=%.1f  Fisher=quarantined\n', ...
            na, mc.MC_total, specA(ii).MC_tau);
    end

    %% (B) Temporal invariance + held-out time-warp generalization
    params = default_MESN_config(struct('dt', dt));
    esn = SRNN_ESN(params);
    se = measure_shift_equivariance(esn, struct('T', 3000, 'washout', 800, ...
        'shifts', [2 5 10 20 40 80]));

    % Preregistered warp protocol (stored before simulation inside evaluator)
    train_warps = local_get(options, 'train_warps', 1.0);
    val_warps = local_get(options, 'val_warps', 1.0);
    test_warps = local_get(options, 'test_warps', [0.5 0.75 1.0 1.5 2.0]);
    warp_opts = struct( ...
        'T_base', local_get(options, 'warp_T_base', 3000), ...
        'seed_train', seed, ...
        'seed_val', seed + 101, ...
        'seed_test', seed + 202, ...
        'train_warps', train_warps, ...
        'val_warps', val_warps, ...
        'test_warps', test_warps, ...
        'washout_steps', 300, ...
        'context_len', 80);
    esn_warp = SRNN_ESN(params);
    warp = evaluate_time_warp_generalization(esn_warp, warp_opts);
    warp_factors = warp.test_warps;
    warp_nrmse = warp.nrmse_by_warp;
    train_metrics = warp.train_metrics;

    %% (C) Response lag
    rng(21);
    U = 0.2 * randn(4000, 1);
    params_on = default_MESN_config(struct('dt', dt));
    esn_on = SRNN_ESN(params_on); esn_on.which_states = 'x';
    esn_on.resetState();
    X_on = esn_on.runReservoir(U);
    pa_on = compute_response_lag(X_on, U, struct('max_lag', 40, 'washout', 800, 'dt', dt));

    params_off = default_MESN_config(struct('dt', dt, 'c_E', 0, 'c_I', 0, ...
        'n_b_E', 0, 'n_b_I', 0));
    esn_off = SRNN_ESN(params_off); esn_off.which_states = 'x';
    esn_off.resetState();
    X_off = esn_off.runReservoir(U);
    pa_off = compute_response_lag(X_off, U, struct('max_lag', 40, 'washout', 800, 'dt', dt));

    result.status = 'ok';
    result.specA = specA;
    result.n_a_list = n_a_list;
    result.se = se;
    result.warp = warp;
    result.warp_factors = warp_factors;
    result.warp_nrmse = warp_nrmse;
    result.train_metrics = train_metrics;
    result.pa_on = pa_on;
    result.pa_off = pa_off;
    result.dt = dt;
    result.save_path = '';

    if save_results
        save_path = fullfile(run_dir, 'timescale.mat');
        atomic_save_results(save_path, struct( ...
            'specA', specA, 'n_a_list', n_a_list, 'se', se, ...
            'warp', warp, 'warp_factors', warp_factors, 'warp_nrmse', warp_nrmse, ...
            'train_metrics', train_metrics, 'pa_on', pa_on, 'pa_off', pa_off, ...
            'dt', dt, 'result', result));
        result.save_path = save_path;
        fprintf('Saved timescale/invariance results to %s\n', save_path);
    end

    if make_figures
        figure('Color', 'w');
        subplot(2,2,1); hold on;
        for ii = 1:numel(n_a_list)
            plot(specA(ii).MC_lags, specA(ii).MC_spectrum, 'LineWidth', 1.3, ...
                'DisplayName', sprintf('n_a=%d', n_a_list(ii)));
        end
        xlabel('lag k'); ylabel('MC_k'); title('Memory spectrum vs SFA timescales');
        legend('show'); grid on;
        subplot(2,2,2);
        plot(se.shifts, se.nrmse_per_shift, 'ko-', 'LineWidth', 1.5);
        xlabel('shift (samples)'); ylabel('equivariance NRMSE');
        title('Temporal (shift) invariance'); grid on;
        subplot(2,2,3);
        plot(warp_factors, warp_nrmse, 'bs-', 'LineWidth', 1.5); hold on;
        plot(warp_factors, [warp.results.nrmse_persistence], 'k--');
        plot(warp_factors, [warp.results.nrmse_linear_history], 'g-.');
        xlabel('time-warp factor'); ylabel('NRMSE');
        title('Held-out time-warp generalization'); legend('MESN','persistence','lin-hist'); grid on;
        subplot(2,2,4); hold on;
        plot(pa_on.lags, mean(abs(pa_on.correlation_by_lag), 1), 'r', 'LineWidth', 1.5, ...
            'DisplayName', 'adapt ON');
        plot(pa_off.lags, mean(abs(pa_off.correlation_by_lag), 1), 'k', 'LineWidth', 1.5, ...
            'DisplayName', 'adapt OFF');
        xline(0, 'k--');
        xlabel('lag (samples; <0 = feature lags / past input)'); ylabel('mean |xcorr|');
        title('Response lag'); legend('show'); grid on;
    end
end

function tau = extract_tau(fit)
    tau = NaN;
    if isstruct(fit)
        if isfield(fit, 'exponential') && isfield(fit.exponential, 'tau')
            tau = fit.exponential.tau;
        elseif isfield(fit, 'best') && isfield(fit.best, 'tau')
            tau = fit.best.tau;
        elseif isfield(fit, 'tau')
            tau = fit.tau;
        end
    end
end

function v = local_get(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
