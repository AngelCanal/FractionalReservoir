function [result, run_dir] = run_esp_phase_diagram(options)
% run_esp_phase_diagram  Empirical state-convergence phase diagram (ODE).
%
% Sweeps (level_of_chaos, adaptation scale) and reports the three empirical
% classifications from verify_echo_state_property:
%   empirically_contracting_on_test_set
%   not_contracting_on_test_set
%   inconclusive
%
% Optionally overlays a quasi_static_fast_gain_diagnostic contour
%   ||W||_2 * g_max = 1
% sampled along driven trajectories with frozen a,b at each sample. This is
% NOT a full MESN/DDE ESP theorem. It is at most a sufficient condition for
% the frozen fast subsystem at trajectory-sampled gain unless a uniform
% reachable-set bound is supplied (see J_eff_notes.md).
%
% DDE / nonempty lags: only empirical convergence diagnostics are reported;
% no finite-dimensional LLE and no Jacobian/gain contour.
%
%   [result, run_dir] = run_esp_phase_diagram()
%   [result, run_dir] = run_esp_phase_diagram(options)

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end

    dry_run = local_get(options, 'dry_run', false);
    save_results = local_get(options, 'save_results', true);
    make_figures = local_get(options, 'make_figures', true);
    chaos_vals = local_get(options, 'chaos_vals', linspace(0.8, 3.0, 12));
    adapt_vals = local_get(options, 'adapt_vals', linspace(0.0, 4.0, 12));
    dt = local_get(options, 'dt', 0.1);
    T = local_get(options, 'T', 3000);
    washout = local_get(options, 'washout', 800);
    seed = local_get(options, 'seed', 123);
    base_c_E = local_get(options, 'base_c_E', 0.1/7);
    base_c_I = local_get(options, 'base_c_I', 0.1/4);
    use_delay = local_get(options, 'use_delay', false);
    delay_lag = local_get(options, 'delay_lag', 0.05);

    stream = RandStream('mt19937ar', 'Seed', seed);
    U = 0.2 * randn(stream, T, 1);

    esp_opts = struct('n_ic', 12, 'washout_steps', washout, 'eps_tol', 1e-3, ...
        'ic_scale', 0.1, 'feature_mode', 'x', 'verbose', false);

    n_c = numel(chaos_vals);
    n_a = numel(adapt_vals);
    n_cells = n_c * n_a;

    classification = strings(n_cells, 1);
    final_spread = nan(n_cells, 1);
    g_max = nan(n_cells, 1);
    W_norm2 = nan(n_cells, 1);
    boundary = nan(n_cells, 1);
    diagnostic_name = 'quasi_static_fast_gain_diagnostic';

    params_final = struct( ...
        'chaos_vals', chaos_vals, 'adapt_vals', adapt_vals, ...
        'dt', dt, 'T', T, 'washout', washout, 'seed', seed, ...
        'use_delay', use_delay, 'diagnostic_name', diagnostic_name);
    run_dir = '';
    if save_results
        ctx_opts = struct('master_seed', seed);
        if isfield(options, 'run_id'); ctx_opts.run_id = options.run_id; end
        if isfield(options, 'revalidated_root_override')
            ctx_opts.revalidated_root_override = options.revalidated_root_override;
        end
        ctx = create_run_context('esp_phase', ctx_opts);
        save_run_manifest(ctx, params_final);
        run_dir = ctx.run_dir;
    end

    result = struct('params', params_final, 'run_dir', run_dir);
    if dry_run
        result.status = 'dry_run';
        return;
    end

    fprintf('Empirical convergence phase diagram: %d x %d = %d cells (delay=%d)\n', ...
        n_c, n_a, n_cells, use_delay);

    for lin = 1:n_cells
        [ic, ia] = ind2sub([n_c, n_a], lin);

        overrides = struct();
        overrides.dt = dt;
        overrides.level_of_chaos = chaos_vals(ic);
        overrides.c_E = base_c_E * adapt_vals(ia);
        overrides.c_I = base_c_I * adapt_vals(ia);
        overrides.which_states = 'x';
        overrides.include_input = false;
        if use_delay
            overrides.lags = delay_lag;
        else
            overrides.lags = [];
        end

        params = default_MESN_config(overrides);
        esn = SRNN_ESN(params);

        esp = verify_echo_state_property(esn, U, esp_opts);
        classification(lin) = string(esp.classification);
        final_spread(lin) = esp.final_spread;

        % ODE-only frozen-subsystem diagnostic; never for DDE
        if isempty(params.lags)
            esn.which_states = 'all';
            esn.resetState();
            [~, S_hist] = esn.runReservoir(U);
            g_max(lin) = local_gain_stats(params, S_hist, washout);
            W_norm2(lin) = norm(params.W, 2);
            boundary(lin) = W_norm2(lin) * g_max(lin);
        end
    end

    CLASS = reshape(classification, n_c, n_a);
    SPREAD = reshape(final_spread, n_c, n_a);
    GMAX = reshape(g_max, n_c, n_a);
    WN2 = reshape(W_norm2, n_c, n_a);
    BND = reshape(boundary, n_c, n_a);
    % Numeric map for plotting: contracting=1, inconclusive=0, not= -1
    CLASS_NUM = nan(n_c, n_a);
    for i = 1:n_c
        for j = 1:n_a
            CLASS_NUM(i, j) = class_to_num(CLASS(i, j));
        end
    end

    result.status = 'ok';
    result.chaos_vals = chaos_vals;
    result.adapt_vals = adapt_vals;
    result.classification = CLASS;
    result.classification_numeric = CLASS_NUM;
    result.SPREAD = SPREAD;
    result.GMAX = GMAX;
    result.WN2 = WN2;
    result.BND = BND;
    result.diagnostic_name = diagnostic_name;
    result.use_delay = use_delay;
    % Legacy alias for figure loaders that expect ESP grid: do NOT interpret
    % as theorem; maps contracting -> 1, else 0
    result.ESP = CLASS_NUM > 0.5;

    if save_results
        save_path = fullfile(run_dir, 'esp_phase.mat');
        atomic_save_results(save_path, struct( ...
            'chaos_vals', chaos_vals, 'adapt_vals', adapt_vals, ...
            'classification', CLASS, 'classification_numeric', CLASS_NUM, ...
            'ESP', result.ESP, 'SPREAD', SPREAD, 'GMAX', GMAX, 'WN2', WN2, 'BND', BND, ...
            'diagnostic_name', diagnostic_name, 'use_delay', use_delay, ...
            'U', U, 'dt', dt, 'washout', washout, 'esp_opts', esp_opts, ...
            'base_c_E', base_c_E, 'base_c_I', base_c_I, 'result', result));
        result.save_path = save_path;
        fprintf('Saved empirical convergence phase diagram to %s\n', save_path);
    end

    if make_figures
        figure('Color', 'w');
        imagesc(chaos_vals, adapt_vals, CLASS_NUM'); hold on;
        set(gca, 'YDir', 'normal');
        colormap(gca, [0.85 0.4 0.4; 0.85 0.85 0.5; 0.4 0.7 0.9]);
        caxis([-1 1]);
        cb = colorbar;
        cb.Ticks = [-1 0 1];
        cb.TickLabels = { ...
            'not_contracting_on_test_set', ...
            'inconclusive', ...
            'empirically_contracting_on_test_set'};
        if ~use_delay && any(isfinite(BND(:)))
            contour(chaos_vals, adapt_vals, BND', [1 1], 'k-', 'LineWidth', 2);
            title({ ...
                'Empirical state convergence (color)', ...
                'black: quasi\_static\_fast\_gain\_diagnostic ||W||_2 g_{max}=1', ...
                '(frozen a,b; trajectory-sampled; not an ESP theorem)'});
        else
            title('Empirical state convergence (DDE: no Jacobian/LLE contour)');
        end
        xlabel('level\_of\_chaos  (spectral scaling of W)');
        ylabel('adaptation scale  (\times baseline c_E, c_I)');
        grid on;
    end
end

function v = class_to_num(c)
    switch char(c)
        case 'empirically_contracting_on_test_set'
            v = 1;
        case 'not_contracting_on_test_set'
            v = -1;
        otherwise
            v = 0;
    end
end

function g_stat = local_gain_stats(params, S_hist, washout)
% Trajectory-sampled peak of b_j * phi'(q_j) for quasi_static_fast_gain_diagnostic.
    n = params.n;
    phi_prime = params.activation_function_derivative;
    T = size(S_hist, 1);
    t0 = min(washout + 1, T);
    g_peak = 0;
    for tt = t0:T
        S = S_hist(tt, :)';
        state = unpack_state(S, params);
        b_E = state.b_E;
        b_I = state.b_I;
        x_eff = compute_effective_q(state, params);
        b = ones(n, 1);
        if ~isempty(b_E); b(params.E_indices) = b_E; end
        if ~isempty(b_I); b(params.I_indices) = b_I; end
        g = b .* phi_prime(x_eff);
        g_peak = max(g_peak, max(g));
    end
    g_stat = g_peak;
end

function v = local_get(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
