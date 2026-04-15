function fig_paths = plot_characterisation_results(run_dir, options)
% plot_characterisation_results
% Regenerate plots from a run produced by scripts/run_full_characterisation.m.
%
% Usage:
%   plot_characterisation_results();                 % plots latest run under results/characterisation/
%   plot_characterisation_results(run_dir);          % run_dir is a timestamp folder OR full path
%   plot_characterisation_results(run_dir, opts);    % control saving/visibility
%
% Inputs:
%   run_dir  - (optional) either:
%              - timestamp folder name (e.g. '20260415_145713'), or
%              - full path to that folder.
%   options  - struct (optional)
%       .save_figures    (default true)   save PNGs into <run_dir>/figures/
%       .close_figures   (default false)  close figures after saving
%       .visible         (default true)   figure visibility
%       .format          (default 'png')  exportgraphics format
%       .dpi             (default 200)
%
% Output:
%   fig_paths - cellstr of written figure paths (empty if save_figures=false)
%
% Notes:
% - This script only uses data saved in characterisation_results.mat (and
%   reference_run.mat if present). It does not re-run any simulations.

    if nargin < 1
        run_dir = '';
    end
    if nargin < 2 || isempty(options)
        options = struct();
    end

    save_figures = getFieldOrDefault(options, 'save_figures', true);
    close_figures = getFieldOrDefault(options, 'close_figures', false);
    visible = getFieldOrDefault(options, 'visible', true);
    fmt = getFieldOrDefault(options, 'format', 'png');
    dpi = getFieldOrDefault(options, 'dpi', 200);
    force_light = getFieldOrDefault(options, 'force_light_theme', true);
    bg = getFieldOrDefault(options, 'background_color', 'white');
    fg = getFieldOrDefault(options, 'foreground_color', 'black');

    % Resolve run directory
    repo_root = pwd;
    runs_root = fullfile(repo_root, 'results', 'characterisation');
    if isempty(run_dir)
        run_path = find_latest_run(runs_root);
    else
        if exist(run_dir, 'dir') == 7
            run_path = run_dir;
        else
            run_path = fullfile(runs_root, run_dir);
        end
    end
    if exist(run_path, 'dir') ~= 7
        error('plot_characterisation_results:RunNotFound', 'Run folder not found: %s', run_path);
    end

    res_file = fullfile(run_path, 'characterisation_results.mat');
    if exist(res_file, 'file') ~= 2
        error('plot_characterisation_results:MissingResults', 'Missing file: %s', res_file);
    end

    S = load(res_file, 'results');
    results = S.results;

    ref_file = fullfile(run_path, 'reference_run.mat');
    ref = struct();
    if exist(ref_file, 'file') == 2
        ref = load(ref_file);
    end

    fig_dir = fullfile(run_path, 'figures');
    if save_figures && exist(fig_dir, 'dir') ~= 7
        mkdir(fig_dir);
    end
    fig_paths = {};

    % If MATLAB is in dark mode, explicitly force a consistent light theme for
    % figures/axes so exports look correct.
    theme = struct('force_light', force_light, 'bg', bg, 'fg', fg);

    % -------------------------
    % 1) Stability / spectrum
    % -------------------------
    if isfield(results, 'spectral_W') && isfield(results.spectral_W, 'eigvals')
        f = newfig('Spectral properties', visible);
        tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

        ax1 = nexttile(tl, 1);
        if exist('plot_eigenvalues', 'file') == 2
            plot_eigenvalues(results.spectral_W.eigvals, ax1, 0);
        else
            plot(ax1, real(results.spectral_W.eigvals), imag(results.spectral_W.eigvals), 'k.');
            xlabel(ax1, 'Re(\lambda)'); ylabel(ax1, 'Im(\lambda)'); axis(ax1, 'equal'); grid(ax1, 'on');
        end
        title(ax1, 'W eigenvalues', 'Interpreter', 'none');

        ax2 = nexttile(tl, 2);
        vals = [results.spectral_W.spectral_radius, results.spectral_W.spectral_abscissa, results.spectral_W.spectral_gap_abscissa];
        bar(ax2, vals);
        set(ax2, 'XTickLabel', {'\rho(W)', 'max Re(\lambda)', 'gap(Re)'});
        grid(ax2, 'on');
        title(ax2, 'Summary', 'Interpreter', 'none');

        apply_theme(f, theme);
        fig_paths = [fig_paths; maybe_save(f, fig_dir, 'stability_spectrum', save_figures, fmt, dpi, theme)]; %#ok<AGROW>
        if close_figures, close(f); end
    end

    % -------------------------
    % 2) ESP convergence
    % -------------------------
    if isfield(results, 'esp') && isfield(results.esp, 'convergence_curve')
        f = newfig('Echo state property', visible);
        ax = axes(f); %#ok<LAXES>
        t_idx = results.esp.t_idx(:);
        curve = results.esp.convergence_curve(:);
        semilogy(ax, t_idx, max(curve, eps), 'LineWidth', 1.5);
        grid(ax, 'on');
        xlabel(ax, 'time index');
        ylabel(ax, 'max spread (log scale)');
        ttl = sprintf('ESP: final=%.3e, tol=%.3e, holds=%d', ...
            results.esp.final_spread, getFieldOrDefault(results.esp.options, 'eps_tol', nan), results.esp.esp_holds);
        title(ax, ttl, 'Interpreter', 'none');

        apply_theme(f, theme);
        fig_paths = [fig_paths; maybe_save(f, fig_dir, 'esp_convergence', save_figures, fmt, dpi, theme)]; %#ok<AGROW>
        if close_figures, close(f); end
    end

    % -------------------------
    % 3) Memory metrics
    % -------------------------
    if isfield(results, 'memory')
        mem = results.memory;

        if isfield(mem, 'MC') && isfield(mem.MC, 'MC_spectrum')
            f = newfig('Memory capacity', visible);
            tl = tiledlayout(f, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

            ax1 = nexttile(tl, 1);
            plot(ax1, mem.MC.lags, mem.MC.MC_spectrum, 'k-', 'LineWidth', 1.3);
            grid(ax1, 'on');
            xlabel(ax1, 'lag k'); ylabel(ax1, 'MC(k)');
            title(ax1, sprintf('Linear MC (total=%.2f)', mem.MC.MC_total), 'Interpreter', 'none');

            ax2 = nexttile(tl, 2);
            plot(ax2, mem.MC.lags, cumsum(mem.MC.MC_spectrum), 'LineWidth', 1.3);
            grid(ax2, 'on');
            xlabel(ax2, 'lag k'); ylabel(ax2, 'cumulative MC');
            title(ax2, 'Cumulative capacity', 'Interpreter', 'none');

            ax3 = nexttile(tl, 3);
            if isfield(mem, 'MC_fit') && isfield(mem.MC_fit, 'best_model')
                fit = mem.MC_fit;
                yy = max(fit.y, 1e-12);
                loglog(ax3, fit.lags, yy, 'k.', 'MarkerSize', 10); hold(ax3, 'on');
                bm = fit.(fit.best_model);
                loglog(ax3, fit.lags, max(bm.yhat, 1e-12), 'r-', 'LineWidth', 1.5);
                grid(ax3, 'on'); xlabel(ax3, 'lag k'); ylabel(ax3, 'MC(k)');
                title(ax3, sprintf('Decay fit (best=%s)', fit.best_model), 'Interpreter', 'none');
                legend(ax3, 'data', 'fit', 'Location', 'best');
            else
                axis(ax3, 'off');
                text(ax3, 0.1, 0.5, 'No MC fit saved.', 'Units', 'normalized');
            end

            ax4 = nexttile(tl, 4);
            if isfield(mem, 'Fisher') && isfield(mem.Fisher, 'FI_curve')
                plot(ax4, mem.Fisher.lags, mem.Fisher.FI_curve, 'LineWidth', 1.3);
                grid(ax4, 'on'); xlabel(ax4, 'lag k'); ylabel(ax4, 'FI(k)');
                title(ax4, 'Fisher memory curve', 'Interpreter', 'none');
            else
                axis(ax4, 'off');
                text(ax4, 0.1, 0.5, 'No Fisher curve saved.', 'Units', 'normalized');
            end

            apply_theme(f, theme);
            fig_paths = [fig_paths; maybe_save(f, fig_dir, 'memory_linear_mc', save_figures, fmt, dpi, theme)]; %#ok<AGROW>
            if close_figures, close(f); end
        end

        if isfield(mem, 'NMC') && isfield(mem.NMC, 'NMC_legendre')
            f = newfig('Nonlinear memory capacity', visible);
            ax = axes(f); %#ok<LAXES>
            imagesc(ax, mem.NMC.lags, mem.NMC.degrees, mem.NMC.NMC_legendre);
            axis(ax, 'xy');
            colormap(ax, parula);
            colorbar(ax);
            xlabel(ax, 'lag k'); ylabel(ax, 'degree');
            title(ax, sprintf('NMC (total=%.2f)', mem.NMC.total_capacity), 'Interpreter', 'none');

            apply_theme(f, theme);
            fig_paths = [fig_paths; maybe_save(f, fig_dir, 'memory_nonlinear_nmc', save_figures, fmt, dpi, theme)]; %#ok<AGROW>
            if close_figures, close(f); end
        end

        if isfield(mem, 'Fisher_fit') && isfield(mem, 'Fisher') && isfield(mem.Fisher, 'FI_curve')
            f = newfig('Fisher decay fit', visible);
            ax = axes(f); %#ok<LAXES>
            fit = mem.Fisher_fit;
            yy = max(fit.y, 1e-12);
            loglog(ax, fit.lags, yy, 'k.', 'MarkerSize', 10); hold(ax, 'on');
            bm = fit.(fit.best_model);
            loglog(ax, fit.lags, max(bm.yhat, 1e-12), 'r-', 'LineWidth', 1.5);
            grid(ax, 'on');
            xlabel(ax, 'lag k'); ylabel(ax, 'FI(k)');
            title(ax, sprintf('Fisher decay fit (best=%s)', fit.best_model), 'Interpreter', 'none');
            legend(ax, 'data', 'fit', 'Location', 'best');

            apply_theme(f, theme);
            fig_paths = [fig_paths; maybe_save(f, fig_dir, 'memory_fisher_fit', save_figures, fmt, dpi, theme)]; %#ok<AGROW>
            if close_figures, close(f); end
        end
    end

    % -------------------------
    % 4) Kernel/generalisation rank
    % -------------------------
    if isfield(results, 'kernel') && isfield(results.kernel, 'sv_KR')
        k = results.kernel;
        f = newfig('Kernel and generalisation rank', visible);
        tl = tiledlayout(f, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

        ax1 = nexttile(tl, 1);
        semilogy(ax1, k.sv_KR, 'k-', 'LineWidth', 1.3);
        grid(ax1, 'on'); xlabel(ax1, 'index'); ylabel(ax1, 'singular value');
        title(ax1, sprintf('KR sv (KR=%d)', k.KR), 'Interpreter', 'none');

        ax2 = nexttile(tl, 2);
        semilogy(ax2, k.sv_GR, 'k-', 'LineWidth', 1.3);
        grid(ax2, 'on'); xlabel(ax2, 'index'); ylabel(ax2, 'singular value');
        title(ax2, sprintf('GR sv (GR=%d)', k.GR), 'Interpreter', 'none');

        ax3 = nexttile(tl, 3);
        bar(ax3, [k.KR, k.GR]);
        set(ax3, 'XTickLabel', {'KR', 'GR'});
        grid(ax3, 'on');
        title(ax3, 'Ranks', 'Interpreter', 'none');

        apply_theme(f, theme);
        fig_paths = [fig_paths; maybe_save(f, fig_dir, 'kernel_rank', save_figures, fmt, dpi, theme)]; %#ok<AGROW>
        if close_figures, close(f); end
    end

    % -------------------------
    % 5) Benchmarks
    % -------------------------
    if isfield(results, 'bench')
        bench = results.bench;
        names = fieldnames(bench);
        for i = 1:numel(names)
            bn = names{i};
            b = bench.(bn);
            if ~isstruct(b) || ~isfield(b, 'y_pred_test')
                continue;
            end

            f = newfig(['Benchmark: ', bn], visible);
            tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

            ax1 = nexttile(tl, 1);
            if isfield(b, 'u')
                plot(ax1, b.u, 'Color', [0.2 0.2 0.2], 'LineWidth', 1.0);
                grid(ax1, 'on'); xlabel(ax1, 't'); ylabel(ax1, 'u(t)');
                title(ax1, 'Input', 'Interpreter', 'none');
            else
                axis(ax1, 'off');
                text(ax1, 0.1, 0.5, 'No input stored for this benchmark.', 'Units', 'normalized');
            end

            ax2 = nexttile(tl, 2);
            y_true = [];
            if isfield(b, 'y_test')
                y_true = b.y_test;
            elseif isfield(b, 'y')
                y_true = b.y;
            end
            y_pred = b.y_pred_test;
            y_pred = y_pred(:);
            if ~isempty(y_true)
                y_true = y_true(:);
                n = min(numel(y_true), numel(y_pred));
                plot(ax2, y_true(1:n), 'k-', 'LineWidth', 1.2); hold(ax2, 'on');
                plot(ax2, y_pred(1:n), 'r--', 'LineWidth', 1.2);
                grid(ax2, 'on'); xlabel(ax2, 't'); ylabel(ax2, 'y(t)');

                nrmse = nan;
                if isfield(b, 'metrics_test') && isfield(b.metrics_test, 'nrmse')
                    nrmse = b.metrics_test.nrmse;
                end
                title(ax2, sprintf('%s (test NRMSE=%.4f)', bn, nrmse), 'Interpreter', 'none');
                legend(ax2, 'true', 'pred', 'Location', 'best');
            else
                plot(ax2, y_pred, 'r--', 'LineWidth', 1.2);
                grid(ax2, 'on'); xlabel(ax2, 't'); ylabel(ax2, 'y_{pred}(t)');
                title(ax2, sprintf('%s (no stored y_{test})', bn), 'Interpreter', 'none');
            end

            apply_theme(f, theme);
            fig_paths = [fig_paths; maybe_save(f, fig_dir, ['bench_', bn], save_figures, fmt, dpi, theme)]; %#ok<AGROW>
            if close_figures, close(f); end
        end
    end

    % -------------------------
    % 6) Biological coding statistics
    % -------------------------
    if isfield(results, 'bio')
        bio = results.bio;

        if isfield(bio, 'coding') && isfield(bio.coding, 'mean_rate_all')
            c = bio.coding;
            f = newfig('Coding statistics', visible);
            tl = tiledlayout(f, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

            ax1 = nexttile(tl, 1);
            histogram(ax1, c.mean_rate_all, 40, 'FaceColor', [0.2 0.2 0.2], 'EdgeColor', 'none');
            grid(ax1, 'on'); xlabel(ax1, 'mean rate'); ylabel(ax1, 'count');
            title(ax1, sprintf('All (silent frac=%.2f)', c.silent_fraction_all), 'Interpreter', 'none');

            ax2 = nexttile(tl, 2);
            if isfield(c, 'mean_rate_E')
                histogram(ax2, c.mean_rate_E, 30, 'FaceColor', [0.2 0.5 0.9], 'EdgeColor', 'none'); hold(ax2, 'on');
            end
            if isfield(c, 'mean_rate_I')
                histogram(ax2, c.mean_rate_I, 30, 'FaceColor', [0.9 0.3 0.3], 'EdgeColor', 'none');
            end
            grid(ax2, 'on'); xlabel(ax2, 'mean rate'); ylabel(ax2, 'count');
            title(ax2, 'E vs I', 'Interpreter', 'none');
            legend(ax2, {'E', 'I'}, 'Location', 'best');

            ax3 = nexttile(tl, 3);
            if isfield(c, 'EI_balance_ratio')
                histogram(ax3, c.EI_balance_ratio, 40, 'FaceColor', [0.3 0.3 0.3], 'EdgeColor', 'none');
                grid(ax3, 'on'); xlabel(ax3, '|I_E| / |I_I|'); ylabel(ax3, 'count');
                title(ax3, 'E/I balance ratio', 'Interpreter', 'none');
            else
                axis(ax3, 'off');
            end

            ax4 = nexttile(tl, 4);
            if isfield(c, 'population_sparseness')
                axis(ax4, 'off');
                text(ax4, 0.05, 0.70, sprintf('Population sparseness: %.3f', c.population_sparseness), 'Units', 'normalized');
                text(ax4, 0.05, 0.55, sprintf('Pop mean rate: %.3f', c.rate_mean_population), 'Units', 'normalized');
                text(ax4, 0.05, 0.40, sprintf('Pop std rate: %.3f', c.rate_std_population), 'Units', 'normalized');
            else
                axis(ax4, 'off');
            end

            apply_theme(f, theme);
            fig_paths = [fig_paths; maybe_save(f, fig_dir, 'bio_coding_statistics', save_figures, fmt, dpi, theme)]; %#ok<AGROW>
            if close_figures, close(f); end
        end

        if isfield(bio, 'adapt_std') && isfield(bio.adapt_std, 'time_indices')
            a = bio.adapt_std;
            dt = nan;
            if isfield(results, 'params') && isfield(results.params, 'dt')
                dt = results.params.dt;
            elseif isfield(ref, 'params') && isfield(ref.params, 'dt')
                dt = ref.params.dt;
            end
            t = a.time_indices(:);
            if isfinite(dt)
                t = t * dt;
            end

            f = newfig('Adaptation / STD statistics', visible);
            tl = tiledlayout(f, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

            ax1 = nexttile(tl, 1);
            plot(ax1, t, a.r_mean_t, 'k-', 'LineWidth', 1.2); hold(ax1, 'on');
            if isfield(a, 'transition_times') && ~isempty(a.transition_times)
                tt = a.transition_times(:);
                if isfinite(dt)
                    tt = tt * dt;
                end
                yl = ylim(ax1);
                for j = 1:numel(tt)
                    plot(ax1, [tt(j) tt(j)], yl, 'r--');
                end
            end
            grid(ax1, 'on');
            xlabel(ax1, ternary(isfinite(dt), 'time (s)', 'time index'));
            ylabel(ax1, 'mean rate');
            title(ax1, 'Population rate (transitions marked)', 'Interpreter', 'none');

            ax2 = nexttile(tl, 2);
            plot(ax2, t, a.aE_mean_t, 'LineWidth', 1.2); hold(ax2, 'on');
            plot(ax2, t, a.aI_mean_t, 'LineWidth', 1.2);
            grid(ax2, 'on');
            xlabel(ax2, ternary(isfinite(dt), 'time (s)', 'time index'));
            ylabel(ax2, 'mean a');
            title(ax2, 'Adaptation means', 'Interpreter', 'none');
            legend(ax2, {'a_E', 'a_I'}, 'Location', 'best');

            ax3 = nexttile(tl, 3);
            plot(ax3, t, a.bE_mean_t, 'LineWidth', 1.2); hold(ax3, 'on');
            plot(ax3, t, a.bI_mean_t, 'LineWidth', 1.2);
            grid(ax3, 'on');
            xlabel(ax3, ternary(isfinite(dt), 'time (s)', 'time index'));
            ylabel(ax3, 'mean b');
            title(ax3, sprintf('STD means (corr bE-rate=%.2f, bI-rate=%.2f)', a.corr_bE_r, a.corr_bI_r), 'Interpreter', 'none');
            legend(ax3, {'b_E', 'b_I'}, 'Location', 'best');

            apply_theme(f, theme);
            fig_paths = [fig_paths; maybe_save(f, fig_dir, 'bio_adaptation_std', save_figures, fmt, dpi, theme)]; %#ok<AGROW>
            if close_figures, close(f); end
        end
    end

    fprintf('Done. Run folder: %s\n', run_path);
    if save_figures
        fprintf('Figures saved to: %s\n', fig_dir);
    end
end

function run_path = find_latest_run(runs_root)
    if exist(runs_root, 'dir') ~= 7
        error('plot_characterisation_results:MissingRunsRoot', 'Missing folder: %s', runs_root);
    end
    d = dir(runs_root);
    d = d([d.isdir]);
    names = {d.name};
    names = names(~ismember(names, {'.', '..'}));
    if isempty(names)
        error('plot_characterisation_results:NoRunsFound', 'No runs found under %s', runs_root);
    end
    % Timestamp folders are yyyymmdd_HHMMSS; lexical sort works.
    names = sort(names);
    run_path = fullfile(runs_root, names{end});
end

function f = newfig(fig_name, visible)
    vis = ternary(visible, 'on', 'off');
    f = figure('Color', 'w', 'Name', fig_name, 'Visible', vis);
end

function out = maybe_save(fig_handle, fig_dir, base_name, do_save, fmt, dpi, theme)
    out = {};
    if ~do_save
        return;
    end
    fname = sprintf('%s.%s', base_name, fmt);
    fpath = fullfile(fig_dir, fname);
    if nargin >= 7 && isstruct(theme) && isfield(theme, 'bg')
        try
            exportgraphics(fig_handle, fpath, 'Resolution', dpi, 'BackgroundColor', theme.bg);
        catch
            exportgraphics(fig_handle, fpath, 'Resolution', dpi);
        end
    else
        exportgraphics(fig_handle, fpath, 'Resolution', dpi);
    end
    out = {fpath};
end

function apply_theme(fig_handle, theme)
    if ~isstruct(theme) || ~isfield(theme, 'force_light') || ~theme.force_light
        return;
    end
    if ~ishandle(fig_handle)
        return;
    end

    set(fig_handle, 'Color', theme.bg);

    ax_all = findall(fig_handle, 'Type', 'axes');
    for i = 1:numel(ax_all)
        ax = ax_all(i);
        try
            set(ax, 'Color', theme.bg);
        catch
        end
        try
            set(ax, 'XColor', theme.fg, 'YColor', theme.fg, 'ZColor', theme.fg);
        catch
        end
        try
            set(ax, 'GridColor', theme.fg, 'MinorGridColor', theme.fg);
        catch
        end
        try
            set(ax, 'ColorOrder', lines);
        catch
        end
    end

    txt_all = findall(fig_handle, 'Type', 'text');
    for i = 1:numel(txt_all)
        try
            set(txt_all(i), 'Color', theme.fg);
        catch
        end
    end

    lg_all = findall(fig_handle, 'Type', 'legend');
    for i = 1:numel(lg_all)
        try
            set(lg_all(i), 'TextColor', theme.fg, 'Color', theme.bg, 'EdgeColor', theme.fg);
        catch
        end
    end

    cb_all = findall(fig_handle, 'Type', 'colorbar');
    for i = 1:numel(cb_all)
        try
            set(cb_all(i), 'Color', theme.fg);
        catch
        end
    end
end

function value = getFieldOrDefault(s, field, default_value)
    if isstruct(s) && isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

function out = ternary(cond, a, b)
    if cond
        out = a;
    else
        out = b;
    end
end

