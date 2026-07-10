function [result, run_dir] = make_paper_figures(options)
% make_paper_figures
% Export MESN paper figures from explicit immutable result paths.
%
%   [result, run_dir] = make_paper_figures(options)
%
% Required (one of):
%   .result_paths  struct with fields:
%       .esp_phase, .parameter_grid, .timescale_invariance, .meanfield, .benchmarks
%   .manifest_path  .mat containing result_paths (or paths)
%
% Options:
%   .run_dependencies (default false) if true, may re-run experiments first
%   .dpi, .format, .save_results, .dry_run, .fig_dir, .run_id, ...
%
% Finding the "latest" result file is intentionally unsupported.

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end

    run_dependencies = local_get(options, 'run_dependencies', false);
    dpi = local_get(options, 'dpi', 200);
    fmt = local_get(options, 'format', 'png');
    save_results = local_get(options, 'save_results', true);
    dry_run = local_get(options, 'dry_run', false);
    fig_dir = local_get(options, 'fig_dir', ...
        fullfile(pwd, 'results', 'figures', 'paper'));

    result = struct();
    result.status = 'ok';
    run_dir = '';

    if run_dependencies
        error('make_paper_figures:DependenciesNotAutoWired', ...
            ['run_dependencies=true requires callers to supply regenerated ', ...
             'result_paths after running experiments explicitly. ', ...
             'Automatic re-run of expensive experiments is disabled by default.']);
    end

    if dry_run
        % Validate path resolution rules without plotting
        if isfield(options, 'result_paths') || isfield(options, 'manifest_path')
            paths = resolve_paper_result_paths(options);
            result.result_paths = paths;
        end
        result.status = 'dry_run';
        result.run_dir = '';
        run_dir = '';
        return;
    end

    paths = resolve_paper_result_paths(options);
    result.result_paths = paths;

    if save_results
        ctx_opts = struct();
        if isfield(options, 'run_id'); ctx_opts.run_id = options.run_id; end
        if isfield(options, 'revalidated_root_override')
            ctx_opts.revalidated_root_override = options.revalidated_root_override;
        end
        ctx = create_run_context('paper_figures', ctx_opts);
        save_run_manifest(ctx, struct('result_paths', paths, 'dpi', dpi, 'format', fmt));
        run_dir = ctx.run_dir;
        fig_dir = fullfile(run_dir, 'figures');
        if ~exist(fig_dir, 'dir'); mkdir(fig_dir); end
    else
        if ~exist(fig_dir, 'dir'); mkdir(fig_dir); end
    end

    exported = {};

    %% Fig 2: ESP phase diagram
    S = load(paths.esp_phase);
    f = figure('Color', 'w', 'Visible', 'off');
    imagesc(S.chaos_vals, S.adapt_vals, double(S.ESP')); hold on;
    set(gca, 'YDir', 'normal');
    colormap(gca, [0.85 0.4 0.4; 0.4 0.7 0.9]);
    cb = colorbar; cb.Ticks = [0.25 0.75]; cb.TickLabels = {'ESP fails', 'ESP holds'};
    if isfield(S, 'BND')
        contour(S.chaos_vals, S.adapt_vals, S.BND', [1 1], 'k-', 'LineWidth', 2);
    end
    xlabel('level\_of\_chaos'); ylabel('adaptation scale (\times baseline)');
    title('Fig 2: ESP phase diagram with analytical boundary');
    export_fig_local(f, fig_dir, 'fig2_esp_phase', fmt, dpi);
    close(f);
    exported{end+1} = 'fig2_esp_phase'; %#ok<AGROW>

    %% Figs 3-4: parameter grid
    S = load(paths.parameter_grid);
    r = S.results;
    LLE = arrayfun(@(s) s.LLE, r(:));
    MC = arrayfun(@(s) s.MC_total, r(:));
    kreiss = arrayfun(@(s) safe_nn(s.specW, 'kreiss_lb'), r(:));
    dep = arrayfun(@(s) safe_nn(s.specW, 'departure_F_norm'), r(:));
    esp = arrayfun(@(s) double(s.esp_holds), r(:));

    f = figure('Color', 'w', 'Visible', 'off');
    scatter(kreiss, LLE, 30, esp, 'filled'); yline(0, 'r--');
    xlabel('Kreiss constant (lower bound) of W'); ylabel('largest Lyapunov exponent');
    colorbar; title('Fig 3: LLE vs non-normality (color = ESP holds)'); grid on;
    export_fig_local(f, fig_dir, 'fig3_lle_nonnormality', fmt, dpi);
    close(f);
    exported{end+1} = 'fig3_lle_nonnormality'; %#ok<AGROW>

    f = figure('Color', 'w', 'Visible', 'off');
    scatter(dep, MC, 30, LLE, 'filled');
    xlabel('departure from normality (normalised)'); ylabel('total memory capacity');
    cb = colorbar; ylabel(cb, 'LLE');
    title('Fig 4: memory vs non-normality'); grid on;
    export_fig_local(f, fig_dir, 'fig4_memory_nonnormality', fmt, dpi);
    close(f);
    exported{end+1} = 'fig4_memory_nonnormality'; %#ok<AGROW>

    %% Fig 5: timescale spectrum + invariance
    S = load(paths.timescale_invariance);
    f = figure('Color', 'w', 'Visible', 'off');
    subplot(1,3,1); hold on;
    for ii = 1:numel(S.n_a_list)
        plot(S.specA(ii).MC_lags, S.specA(ii).MC_spectrum, 'LineWidth', 1.3, ...
            'DisplayName', sprintf('n_a=%d', S.n_a_list(ii)));
    end
    xlabel('lag k'); ylabel('MC_k'); legend('show'); grid on;
    title('memory spectrum');
    subplot(1,3,2);
    plot(S.se.shifts, S.se.nrmse_per_shift, 'ko-', 'LineWidth', 1.5);
    xlabel('shift'); ylabel('equivariance NRMSE'); grid on; title('temporal invariance');
    subplot(1,3,3); hold on;
    if isfield(S.pa_on, 'correlation_by_lag')
        y_on = mean(abs(S.pa_on.correlation_by_lag), 1);
        y_off = mean(abs(S.pa_off.correlation_by_lag), 1);
    else
        y_on = S.pa_on.xcorr_mean;
        y_off = S.pa_off.xcorr_mean;
    end
    plot(S.pa_on.lags, y_on, 'r', 'LineWidth', 1.5, 'DisplayName', 'adapt ON');
    plot(S.pa_off.lags, y_off, 'k', 'LineWidth', 1.5, 'DisplayName', 'adapt OFF');
    xline(0, 'k--'); xlabel('lag (<0 = feature lags)'); ylabel('mean |xcorr|');
    legend('show'); grid on; title('response lag');
    sgtitle('Fig 5: multi-timescale representation and temporal invariance');
    export_fig_local(f, fig_dir, 'fig5_timescale_invariance', fmt, dpi);
    close(f);
    exported{end+1} = 'fig5_timescale_invariance'; %#ok<AGROW>

    %% Fig 6: dynamical regime sweep
    S = load(paths.meanfield);
    f = figure('Color', 'w', 'Visible', 'off');
    subplot(1,2,1); hold on;
    plot(S.ca_vals, S.Emin, 'b.-'); plot(S.ca_vals, S.Emax, 'r.-');
    xlabel('adaptation strength c_a'); ylabel('E(t) range'); grid on;
    legend('min E', 'max E'); title('regime sweep vs adaptation');
    subplot(1,2,2);
    imagesc(S.delay_grid, S.ca_grid, S.REGIME); set(gca, 'YDir', 'normal');
    colormap(gca, [0.4 0.7 0.9; 0.85 0.4 0.4]);
    cb = colorbar; cb.Ticks = [0.25 0.75]; cb.TickLabels = {'fixed point', 'oscillation'};
    xlabel('\tau_{delay}'); ylabel('c_a'); title('regime map (time integration)');
    sgtitle('Fig 6: reduced mean-field dynamical regime sweep');
    export_fig_local(f, fig_dir, 'fig6_meanfield_regime_sweep', fmt, dpi);
    close(f);
    exported{end+1} = 'fig6_meanfield_regime_sweep'; %#ok<AGROW>

    %% Fig 7: benchmarks
    S = load(paths.benchmarks);
    f = figure('Color', 'w', 'Visible', 'off');
    bar([S.nrmse_on, S.nrmse_off]);
    set(gca, 'XTickLabel', S.bench_names);
    ylabel('test NRMSE'); legend({'adaptation ON', 'adaptation OFF'});
    title('Fig 7: benchmark performance (ridge readout only)'); grid on;
    export_fig_local(f, fig_dir, 'fig7_benchmarks', fmt, dpi);
    close(f);
    exported{end+1} = 'fig7_benchmarks'; %#ok<AGROW>

    result.exported = exported;
    result.fig_dir = fig_dir;
    result.run_dir = run_dir;
    fprintf('Paper figures written to %s\n', fig_dir);
end

function export_fig_local(f, dir_out, name, fmt, dpi)
    fname = fullfile(dir_out, sprintf('%s.%s', name, fmt));
    if exist(fname, 'file')
        error('make_paper_figures:RefuseOverwrite', ...
            'Refusing to overwrite existing figure: %s', fname);
    end
    tmp = [fname, '.tmp.', fmt];
    try
        exportgraphics(f, tmp, 'Resolution', dpi);
    catch
        print(f, tmp, ['-d' fmt], sprintf('-r%d', dpi));
    end
    movefile(tmp, fname);
end

function v = safe_nn(specW, field)
    if isstruct(specW) && isfield(specW, 'nonnormality') && ...
            isfield(specW.nonnormality, field)
        v = specW.nonnormality.(field);
    else
        v = NaN;
    end
end

function v = local_get(s, f, d)
    if isfield(s, f) && ~isempty(s.(f))
        v = s.(f);
    else
        v = d;
    end
end
