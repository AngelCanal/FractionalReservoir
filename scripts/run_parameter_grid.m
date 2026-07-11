function [result, run_dir] = run_parameter_grid(options)
% run_parameter_grid  Multi-parameter grid characterisation of the MESN.
%
%   [result, run_dir] = run_parameter_grid()
%   [result, run_dir] = run_parameter_grid(options)
%
% Options: .dry_run, .save_results, .run_dependencies (default false),
%          .grid_params, .dt, .T_total, .T_washout, .do_lyapunov, .do_esp,
%          .do_memory, .do_nonnormality, .make_figures, .run_id, .seed

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
    seed = local_get(options, 'seed', 123);

    grid_params = local_get(options, 'grid_params', struct( ...
        'tau_d', [0.30, 0.55, 0.90], ...
        'c_E', (0.1/7) * [0, 1, 2, 4], ...
        'level_of_chaos', linspace(0.9, 2.7, 8)));
    cI_over_cE = local_get(options, 'cI_over_cE', (0.1/4) / (0.1/7));
    dt = local_get(options, 'dt', 0.1);
    T_total = local_get(options, 'T_total', 4000);
    T_washout = local_get(options, 'T_washout', 1000);
    do_lyapunov = local_get(options, 'do_lyapunov', true);
    lya_method = local_get(options, 'lya_method', 'benettin');
    do_esp = local_get(options, 'do_esp', true);
    do_memory = local_get(options, 'do_memory', true);
    do_nonnormality = local_get(options, 'do_nonnormality', true);
    ode_opts = odeset('RelTol', 1e-6, 'AbsTol', 1e-8);

    rng(seed);
    U = 0.2 * randn(T_total, 1);

    pnames = fieldnames(grid_params);
    n_dims = numel(pnames);
    dim_sizes = cellfun(@(f) numel(grid_params.(f)), pnames);
    n_cells = prod(dim_sizes);

    params_final = struct('grid_params', grid_params, 'dt', dt, ...
        'T_total', T_total, 'T_washout', T_washout, 'seed', seed, ...
        'do_lyapunov', do_lyapunov, 'do_esp', do_esp, ...
        'do_memory', do_memory, 'do_nonnormality', do_nonnormality, ...
        'n_cells', n_cells);

    run_dir = '';
    if save_results
        ctx_opts = struct('master_seed', seed);
        if isfield(options, 'run_id'); ctx_opts.run_id = options.run_id; end
        if isfield(options, 'revalidated_root_override')
            ctx_opts.revalidated_root_override = options.revalidated_root_override;
        end
        ctx = create_run_context('parameter_grid', ctx_opts);
        save_run_manifest(ctx, params_final);
        run_dir = ctx.run_dir;
    end

    result = struct('params', params_final, 'run_dir', run_dir);
    if dry_run
        result.status = 'dry_run';
        result.n_cells = n_cells;
        return;
    end

    fprintf('Parameter grid: %d dimensions, sizes [%s], %d networks total\n', ...
        n_dims, num2str(dim_sizes(:)'), n_cells);

    results_cell = cell(n_cells, 1);
    parfor lin = 1:n_cells
        sub = cell(1, n_dims);
        [sub{:}] = ind2sub(dim_sizes(:)', lin);

        overrides = struct('dt', dt, 'which_states', 'x', 'include_input', false);
        pv = struct();
        for d = 1:n_dims
            name = pnames{d};
            val = grid_params.(name)(sub{d});
            overrides.(name) = val;
            pv.(name) = val;
        end
        if isfield(overrides, 'c_E')
            overrides.c_I = overrides.c_E * cI_over_cE;
            pv.c_I = overrides.c_I;
        end

        params = default_MESN_config(overrides);
        layout = state_layout(params);
        params.N_sys_eqs = layout.n_total;
        esn = SRNN_ESN(params);
        esn.resetState();
        [X_feat, S_hist] = esn.runReservoir(U);
        x_post = X_feat((T_washout+1):end, :);

        LLE = nan;
        LE_spectrum = [];
        lya_status = 'not_requested';
        if do_lyapunov
            if ~isempty(params.lags)
                lya_status = 'unsupported_not_computed';
            else
                t_out = (0:(T_total-1))' * dt;
                fs = 1 / dt;
                T_interval = [t_out(T_washout+1), t_out(end)];
                t_ex = t_out;
                u_ex = params.W_in * U';
                u_fun = make_input_interpolant(t_ex, u_ex);
                rhs_func = @(t, S) SRNN_reservoir(t, S, u_fun, params);
                lr = compute_lyapunov_exponents(lya_method, S_hist, t_out, dt, fs, ...
                    T_interval, params, ode_opts, @ode23s, rhs_func, t_ex, u_ex);
                lya_status = 'computed';
                if isfield(lr, 'LLE')
                    LLE = lr.LLE;
                elseif isfield(lr, 'LE_spectrum') && ~isempty(lr.LE_spectrum)
                    LE_spectrum = lr.LE_spectrum;
                    LLE = lr.LE_spectrum(1);
                end
            end
        end

        [regime, regime_diag] = classify_dynamical_regime(x_post, dt, LLE);
        % Non-normality on structurally varying continuous-time generators
        % (J_eff at a post-washout state). Grid cells differ in tau_d, c_E,
        % and W scaling, so (-I+WG)/tau_d is not a mere scalar family.
        nn_opts = struct('do_nonnormality', false, ...
            'do_transient', false, 'n_eta', 12, 'n_omega', 61);
        if do_nonnormality && isempty(params.lags)
            S_sample = S_hist(min(T_washout + 1, size(S_hist, 1)), :).';
            nn_opts.do_nonnormality = true;
            nn_opts.A_ct = compute_J_eff(S_sample, params);
        end
        specW = compute_spectral_properties(params.W, params, nn_opts);

        esp_holds = NaN; esp_spread = NaN;
        if do_esp
            esp = verify_echo_state_property(esn, U, struct('n_ic', 10, ...
                'washout_steps', T_washout, 'eps_tol', 1e-3, 'feature_mode', 'x', ...
                'verbose', false));
            esp_holds = esp.esp_holds;
            esp_spread = esp.final_spread;
        end

        MC_total = NaN;
        if do_memory
            try
                mc = compute_memory_capacity(esn, struct('T', 4000, 'K_max', 120, ...
                    'washout', 200, 'lambda', params.lambda, 'feature_mode', 'x'));
                MC_total = mc.MC_total;
            catch
                MC_total = NaN;
            end
        end

        r = struct();
        r.param_values = pv;
        r.LLE = LLE;
        r.lya_status = lya_status;
        r.LE_spectrum = LE_spectrum;
        r.regime = regime;
        r.regime_diag = regime_diag;
        r.specW = specW;
        r.esp_holds = esp_holds;
        r.esp_spread = esp_spread;
        r.MC_total = MC_total;
        results_cell{lin} = r;
    end

    results = repmat(struct( ...
        'param_values', struct(), 'LLE', nan, 'LE_spectrum', [], ...
        'regime', '', 'regime_diag', struct(), 'specW', struct(), ...
        'esp_holds', NaN, 'esp_spread', NaN, 'MC_total', NaN), n_cells, 1);
    for i = 1:n_cells
        ri = results_cell{i};
        results(i).param_values = ri.param_values;
        results(i).LLE = ri.LLE;
        results(i).LE_spectrum = ri.LE_spectrum;
        results(i).regime = ri.regime;
        results(i).regime_diag = ri.regime_diag;
        results(i).specW = ri.specW;
        results(i).esp_holds = ri.esp_holds;
        results(i).esp_spread = ri.esp_spread;
        results(i).MC_total = ri.MC_total;
    end

    result.status = 'ok';
    result.results = results;
    result.grid_params = grid_params;
    result.pnames = pnames;
    result.dim_sizes = dim_sizes;
    result.save_path = '';

    if save_results
        save_path = fullfile(run_dir, 'grid.mat');
        atomic_save_results(save_path, struct( ...
            'grid_params', grid_params, 'pnames', {pnames}, ...
            'dim_sizes', dim_sizes, 'results', results, ...
            'dt', dt, 'U', U, 'T_total', T_total, 'T_washout', T_washout, ...
            'lya_method', lya_method, 'result', result));
        result.save_path = save_path;
        fprintf('Saved parameter grid to %s\n', save_path);
    end

    if make_figures
        LLEs = arrayfun(@(s) s.LLE, results(:));
        MCs  = arrayfun(@(s) s.MC_total, results(:));
        kreiss = arrayfun(@(s) getfield_safe(s.specW, 'nonnormality', 'kreiss_lb'), results(:));
        esp_flags = arrayfun(@(s) double(s.esp_holds), results(:));
        figure('Color', 'w');
        subplot(1,2,1);
        scatter(kreiss, LLEs, 30, esp_flags, 'filled');
        xlabel('Kreiss constant (lower bound) of W');
        ylabel('Largest Lyapunov exponent');
        yline(0, 'r--'); grid on; colorbar;
        title('LLE vs non-normality (color = ESP holds)');
        subplot(1,2,2);
        scatter(kreiss, MCs, 30, LLEs, 'filled');
        xlabel('Kreiss constant (lower bound) of W');
        ylabel('Total linear memory capacity');
        grid on; cb = colorbar; ylabel(cb, 'LLE');
        title('Memory vs non-normality');
    end
end

function v = getfield_safe(s, f1, f2)
    if isfield(s, f1) && isstruct(s.(f1)) && isfield(s.(f1), f2)
        v = s.(f1).(f2);
    else
        v = NaN;
    end
end

function v = local_get(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
