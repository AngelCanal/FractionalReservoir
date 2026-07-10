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

    %% (B) Temporal invariance
    params = default_MESN_config(struct('dt', dt));
    esn = SRNN_ESN(params);
    se = measure_shift_equivariance(esn, struct('T', 3000, 'washout', 800, ...
        'shifts', [2 5 10 20 40 80]));

    warp_factors = [0.5 0.75 1.0 1.5 2.0];
    warp_nrmse = zeros(numel(warp_factors), 1);
    rng(seed);
    T_base = 6000;
    u_base = 0.2 * randn(T_base, 1);
    target_delay = 10;
    target = smooth_causal(u_base, 8);
    target = [zeros(target_delay,1); target(1:end-target_delay)];
    esn.resetState();
    train_metrics = esn.trainReadout(u_base, target, ...
        struct('train_ratio', 0.6, 'val_ratio', 0.2, 'washout_steps', 300, ...
               'lambda', params.lambda));
    for wi = 1:numel(warp_factors)
        w = warp_factors(wi);
        u_w = resample_timeline(u_base, w);
        tgt_w = resample_timeline(target, w);
        n = min(size(u_w,1), size(tgt_w,1));
        u_w = u_w(1:n); tgt_w = tgt_w(1:n);
        y_pred = esn.predict(u_w);
        idx = 400:n;
        warp_nrmse(wi) = nrmse(y_pred(idx), tgt_w(idx));
    end

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
            'warp_factors', warp_factors, 'warp_nrmse', warp_nrmse, ...
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
        plot(warp_factors, warp_nrmse, 'bs-', 'LineWidth', 1.5);
        xlabel('time-warp factor'); ylabel('readout NRMSE');
        title('Time-warp robustness (trained at 1.0)'); grid on;
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

function y = smooth_causal(u, w)
    k = ones(w, 1) / w;
    y = filter(k, 1, u);
end

function y = resample_timeline(u, w)
    T = numel(u);
    t = (1:T)';
    tq = (1:1/w:T)';
    y = interp1(t, u, tq, 'linear', 'extrap');
end

function e = nrmse(yp, yt)
    yp = yp(:); yt = yt(:);
    e = sqrt(mean((yp - yt).^2)) / max(std(yt), eps);
end

function v = local_get(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
