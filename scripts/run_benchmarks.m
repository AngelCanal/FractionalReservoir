function [result, run_dir] = run_benchmarks(options)
% run_benchmarks  Task-performance benchmarks (adaptation ON vs OFF).
%
%   [result, run_dir] = run_benchmarks()
%   [result, run_dir] = run_benchmarks(options)
%
% Options:
%   .dry_run (default false), .save_results (default true), .run_dependencies (default false)
%   .seed, .dt, .common_opts, .make_figures, .run_id, .revalidated_root_override

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
    seed = local_get(options, 'seed', 1);
    common_opts = local_get(options, 'common_opts', ...
        struct('train_ratio', 0.6, 'val_ratio', 0.2, 'washout_steps', 200, 'seed', seed));

    configs = struct();
    configs(1).name = 'adapt_ON';
    configs(1).overrides = struct('dt', dt);
    configs(2).name = 'adapt_OFF';
    configs(2).overrides = struct('dt', dt, 'c_E', 0, 'c_I', 0, 'n_b_E', 0, 'n_b_I', 0);

    bench_names = {'narma10', 'narma20', 'mackeyglass', 'lorenz', 'frequency', 'counting'};
    % Keep manifest params JSON-safe (no struct arrays).
    params_final = struct('dt', dt, 'seed', seed, ...
        'config_names', {{configs.name}}, ...
        'common_opts', common_opts, 'bench_names', {bench_names});

    run_dir = '';
    if save_results
        ctx_opts = struct('master_seed', seed);
        if isfield(options, 'run_id'); ctx_opts.run_id = options.run_id; end
        if isfield(options, 'revalidated_root_override')
            ctx_opts.revalidated_root_override = options.revalidated_root_override;
        end
        ctx = create_run_context('benchmarks', ctx_opts);
        save_run_manifest(ctx, params_final);
        run_dir = ctx.run_dir;
    end

    result = struct();
    result.params = params_final;
    result.run_dir = run_dir;

    if dry_run
        result.status = 'dry_run';
        result.summary = struct();
        return;
    end

    summary = struct();
    for ci = 1:numel(configs)
        name = configs(ci).name;
        params = default_MESN_config(configs(ci).overrides);
        esn = SRNN_ESN(params);

        fprintf('\n=========== Config: %s ===========\n', name);
        b = struct();
        b.narma10 = narma_benchmark(esn, merge_opts(common_opts, struct('order', 10)));
        b.narma20 = narma_benchmark(esn, merge_opts(common_opts, struct('order', 20)));
        b.mackeyglass = mackey_glass_benchmark(esn, merge_opts(common_opts, struct('tau', 17, 'do_rollout', true)));
        b.lorenz = lorenz_benchmark(esn, merge_opts(common_opts, struct('obs_noise', 0.0)));
        b.frequency = frequency_discrimination_benchmark(esn, merge_opts(common_opts, struct('dt', dt)));
        b.counting = stimulus_counting_benchmark(esn, common_opts);
        summary.(name) = b;

        for k = 1:numel(bench_names)
            bn = bench_names{k};
            bb = b.(bn);
            fprintf('  %-12s status=%s  prediction_mode=%s  lambda=%.3g\n', ...
                bn, bb.status, bb.prediction_mode, bb.selected_lambda);
        end
    end

    core_names = {'narma10', 'narma20', 'mackeyglass', 'lorenz'};
    nrmse_on = zeros(numel(core_names), 1);
    nrmse_off = zeros(numel(core_names), 1);
    for k = 1:numel(core_names)
        nrmse_on(k)  = summary.adapt_ON.(core_names{k}).metrics_test.nrmse;
        nrmse_off(k) = summary.adapt_OFF.(core_names{k}).metrics_test.nrmse;
    end

    result.status = 'ok';
    result.summary = summary;
    result.bench_names = core_names;
    result.nrmse_on = nrmse_on;
    result.nrmse_off = nrmse_off;
    result.save_path = '';

    if save_results
        save_path = fullfile(run_dir, 'benchmarks.mat');
        atomic_save_results(save_path, struct( ...
            'summary', summary, 'bench_names', {core_names}, ...
            'core_names', {core_names}, 'nrmse_on', nrmse_on, ...
            'nrmse_off', nrmse_off, 'configs', configs, ...
            'common_opts', common_opts, 'result', result));
        result.save_path = save_path;
        fprintf('\nSaved benchmark results to %s\n', save_path);
    end

    if make_figures
        figure('Color', 'w');
        bar([nrmse_on, nrmse_off]);
        set(gca, 'XTickLabel', core_names);
        ylabel('test NRMSE (lower is better)');
        legend({'adaptation ON', 'adaptation OFF'}, 'Location', 'best');
        title('What adaptation adds: benchmark performance (ridge readout only)');
        grid on;
    end
end

function out = merge_opts(base, extra)
    out = base;
    f = fieldnames(extra);
    for i = 1:numel(f)
        out.(f{i}) = extra.(f{i});
    end
end

function v = local_get(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
