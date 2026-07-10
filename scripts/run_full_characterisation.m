function [result, run_dir] = run_full_characterisation(options)
% run_full_characterisation  Modular MESN characterisation suite.
%
%   [result, run_dir] = run_full_characterisation()
%   [result, run_dir] = run_full_characterisation(options)
%
% Options:
%   .flags              subset toggles (stability/esp/memory/...)
%   .dry_run            create context/manifest only (default false)
%   .save_results       write under results/revalidated (default true)
%   .run_dependencies   if true, may call parameter_sweep / meanfield (default false)
%   .seed, .T, .run_id, .revalidated_root_override

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end

    dry_run = local_get(options, 'dry_run', false);
    save_results = local_get(options, 'save_results', true);
    run_dependencies = local_get(options, 'run_dependencies', false);
    seed = local_get(options, 'seed', 123);
    T = local_get(options, 'T', 4000);

    flags = local_get(options, 'flags', struct());
    flags = set_flag(flags, 'stability', true);
    flags = set_flag(flags, 'esp', true);
    flags = set_flag(flags, 'memory', true);
    flags = set_flag(flags, 'kernel_rank', true);
    flags = set_flag(flags, 'benchmarks', true);
    flags = set_flag(flags, 'bio', true);
    flags = set_flag(flags, 'parameter_sweep', false);
    flags = set_flag(flags, 'meanfield_bifurcation', false);

    [params, meta] = default_MESN_config(struct());
    params_final = struct('flags', flags, 'params', params, 'seed', seed, 'T', T);

    run_dir = '';
    if save_results
        ctx_opts = struct('master_seed', seed);
        if isfield(options, 'run_id'); ctx_opts.run_id = options.run_id; end
        if isfield(options, 'revalidated_root_override')
            ctx_opts.revalidated_root_override = options.revalidated_root_override;
        end
        ctx = create_run_context('full_characterisation', ctx_opts);
        save_run_manifest(ctx, params_final);
        run_dir = ctx.run_dir;
    end

    result = struct('flags', flags, 'params', params, 'meta', meta, ...
        'run_dir', run_dir);
    if dry_run
        result.status = 'dry_run';
        return;
    end

    dt = params.dt;
    rng(seed);
    U = 0.2 * randn(T, 1);
    t = (0:(T-1))' * dt;
    esn = SRNN_ESN(params);
    esn.resetState();
    [X_feat, S_hist] = esn.runReservoir(U);

    if save_results
        atomic_save_results(fullfile(run_dir, 'reference_run.mat'), struct( ...
            'params', params, 'meta', meta, 'U', U, 't', t, ...
            'X_feat', X_feat, 'S_hist', S_hist));
    end

    if flags.stability
        result.spectral_W = compute_spectral_properties(params.W, params);
    end
    if flags.esp
        esp_opts = struct('n_ic', 20, 'washout_steps', 500, 'eps_tol', 1e-3, ...
            'ic_scale', 0.1, 'feature_mode', 'x');
        result.esp = verify_echo_state_property(esn, U, esp_opts);
    end
    if flags.memory
        mc_opts = struct('T', 5000, 'K_max', 200, 'washout', 200, ...
            'lambda', params.lambda, 'feature_mode', 'x');
        result.memory.MC = compute_memory_capacity(esn, mc_opts);
        nmc_opts = struct('T', 5000, 'K_max', 100, 'washout', 200, ...
            'lambda', params.lambda, 'degrees', [2 3], ...
            'include_cross_terms', false, 'feature_mode', 'x');
        result.memory.NMC = compute_nonlinear_memory_capacity(esn, nmc_opts);
        result.memory.Fisher = struct( ...
            'status', 'quarantined_not_computed', ...
            'scientifically_valid', false, 'lags', [], 'FI_curve', []);
        result.memory.Fisher_fit = struct('status', 'quarantined_not_computed');
        result.memory.MC_fit = fit_memory_decay(result.memory.MC.lags, ...
            result.memory.MC.MC_spectrum, struct());
    end
    if flags.kernel_rank
        kr_opts = struct('M', 150, 'L', 200, 'washout', 50, ...
            'input_type', 'binary', 'feature_mode', 'x');
        result.kernel = compute_kernel_rank(esn, kr_opts);
    end
    if flags.benchmarks
        if run_dependencies
            [bench, ~] = run_benchmarks(struct( ...
                'save_results', false, 'make_figures', false, 'seed', seed));
            result.bench = bench.summary;
        else
            result.bench = struct('status', 'skipped_run_dependencies_false');
        end
    end
    if flags.bio
        result.bio.coding = compute_coding_statistics(esn, S_hist, ...
            struct('time_stride', 5));
        result.bio.adapt_std = compute_adaptation_STD_statistics(esn, S_hist, ...
            struct('time_stride', 5));
    end

    if flags.parameter_sweep
        if run_dependencies
            [sw, ~] = run_parameter_sweep(struct( ...
                'save_results', false, 'make_figures', false, 'seed', seed, ...
                'sweep', struct('param_name', 'level_of_chaos', ...
                'values', linspace(0.7, 2.5, 5))));
            result.parameter_sweep = sw;
        else
            result.parameter_sweep = struct('status', 'skipped_run_dependencies_false');
        end
    end
    if flags.meanfield_bifurcation
        if run_dependencies
            result.meanfield = run_bifurcation_meanfield(struct( ...
                'save_results', false, 'make_figures', false, ...
                'Iext_vals', linspace(0, 2, 5), 'tspan', [0, 50]));
        else
            result.meanfield = struct('status', 'skipped_run_dependencies_false');
        end
    end

    result.status = 'ok';
    result.save_path = '';
    if save_results
        save_path = fullfile(run_dir, 'characterisation_results.mat');
        atomic_save_results(save_path, struct('result', result));
        result.save_path = save_path;
        fprintf('Characterisation complete. Results saved under %s\n', run_dir);
    end
end

function flags = set_flag(flags, name, default)
    if ~isfield(flags, name) || isempty(flags.(name))
        flags.(name) = default;
    end
end

function v = local_get(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
