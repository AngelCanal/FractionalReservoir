function make_paper_figures(options)
% make_paper_figures
% One-command regeneration of the MESN paper figures.
%
% By default this loads the most recent saved result (*.mat) from each results
% subfolder and exports canonical figures to results/figures/paper/. With
% options.regenerate = true it first re-runs every analysis script (slow).
%
% Usage:
%   make_paper_figures();
%   make_paper_figures(struct('regenerate', true));
%   make_paper_figures(struct('dpi', 300, 'format', 'pdf'));
%
% Options:
%   .regenerate (default false) re-run analysis scripts before plotting
%   .dpi        (default 200)
%   .format     (default 'png')  'png' or 'pdf'
%
% Figure map (see the paper workplan):
%   Fig 2: ESP phase diagram                 (results/esp_phase)
%   Fig 3: LLE vs parameter grid             (results/parameter_grid)
%   Fig 4: non-normality vs memory           (results/parameter_grid)
%   Fig 5: timescale spectrum + invariance   (results/timescale_invariance)
%   Fig 6: reduced-model bifurcation         (results/meanfield_bifurcation)
%   Fig 7: benchmark performance             (results/benchmarks)
% (Fig 1 is the hand-drawn model schematic and is not generated here.)

    if nargin < 1 || isempty(options)
        options = struct();
    end
    regenerate = getfielddef(options, 'regenerate', false);
    dpi = getfielddef(options, 'dpi', 200);
    fmt = getfielddef(options, 'format', 'png');

    if exist('setup_paths', 'file') == 2
        setup_paths();
    end

    root = pwd;
    res = fullfile(root, 'results');
    fig_dir = fullfile(res, 'figures', 'paper');
    if ~exist(fig_dir, 'dir'); mkdir(fig_dir); end

    if regenerate
        fprintf('Regenerating all analyses (this is slow)...\n');
        run(fullfile(root, 'scripts', 'run_esp_phase_diagram.m'));
        run(fullfile(root, 'scripts', 'run_parameter_grid.m'));
        run(fullfile(root, 'scripts', 'run_timescale_invariance.m'));
        run(fullfile(root, 'scripts', 'run_meanfield_adaptation_bifurcation.m'));
        run(fullfile(root, 'scripts', 'run_benchmarks.m'));
    end

    %% Fig 2: ESP phase diagram
    d = latest_mat(fullfile(res, 'esp_phase'));
    if ~isempty(d)
        S = load(d);
        f = figure('Color', 'w', 'Visible', 'on');
        imagesc(S.chaos_vals, S.adapt_vals, double(S.ESP')); hold on;
        set(gca, 'YDir', 'normal');
        colormap(gca, [0.85 0.4 0.4; 0.4 0.7 0.9]);
        cb = colorbar; cb.Ticks = [0.25 0.75]; cb.TickLabels = {'ESP fails', 'ESP holds'};
        contour(S.chaos_vals, S.adapt_vals, S.BND', [1 1], 'k-', 'LineWidth', 2);
        xlabel('level\_of\_chaos'); ylabel('adaptation scale (\times baseline)');
        title('Fig 2: ESP phase diagram with analytical boundary');
        export_fig_local(f, fig_dir, 'fig2_esp_phase', fmt, dpi);
    end

    %% Figs 3-4: parameter grid (LLE, non-normality, memory)
    d = latest_mat(fullfile(res, 'parameter_grid'));
    if ~isempty(d)
        S = load(d);
        r = S.results;
        LLE = arrayfun(@(s) s.LLE, r(:));
        MC = arrayfun(@(s) s.MC_total, r(:));
        kreiss = arrayfun(@(s) safe_nn(s.specW, 'kreiss_lb'), r(:));
        dep = arrayfun(@(s) safe_nn(s.specW, 'departure_F_norm'), r(:));
        esp = arrayfun(@(s) double(s.esp_holds), r(:));

        f = figure('Color', 'w');
        scatter(kreiss, LLE, 30, esp, 'filled'); yline(0, 'r--');
        xlabel('Kreiss constant (lower bound) of W'); ylabel('largest Lyapunov exponent');
        colorbar; title('Fig 3: LLE vs non-normality (color = ESP holds)'); grid on;
        export_fig_local(f, fig_dir, 'fig3_lle_nonnormality', fmt, dpi);

        f = figure('Color', 'w');
        scatter(dep, MC, 30, LLE, 'filled');
        xlabel('departure from normality (normalised)'); ylabel('total memory capacity');
        cb = colorbar; ylabel(cb, 'LLE');
        title('Fig 4: memory vs non-normality'); grid on;
        export_fig_local(f, fig_dir, 'fig4_memory_nonnormality', fmt, dpi);
    end

    %% Fig 5: timescale spectrum + invariance
    d = latest_mat(fullfile(res, 'timescale_invariance'));
    if ~isempty(d)
        S = load(d);
        f = figure('Color', 'w');
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
        plot(S.pa_on.lags, S.pa_on.xcorr_mean, 'r', 'LineWidth', 1.5, 'DisplayName', 'adapt ON');
        plot(S.pa_off.lags, S.pa_off.xcorr_mean, 'k', 'LineWidth', 1.5, 'DisplayName', 'adapt OFF');
        xline(0, 'k--'); xlabel('lag (<0 leads)'); ylabel('mean |xcorr|');
        legend('show'); grid on; title('phase advance');
        sgtitle('Fig 5: multi-timescale representation and temporal invariance');
        export_fig_local(f, fig_dir, 'fig5_timescale_invariance', fmt, dpi);
    end

    %% Fig 6: reduced-model bifurcation
    d = latest_mat_prefix(fullfile(res, 'meanfield_bifurcation'), 'adaptation_');
    if ~isempty(d)
        S = load(d);
        f = figure('Color', 'w');
        subplot(1,2,1); hold on;
        plot(S.ca_vals, S.Emin, 'b.-'); plot(S.ca_vals, S.Emax, 'r.-');
        xlabel('adaptation strength c_a'); ylabel('E(t) range'); grid on;
        legend('min E', 'max E'); title('bifurcation vs adaptation');
        subplot(1,2,2);
        imagesc(S.delay_grid, S.ca_grid, S.REGIME); set(gca, 'YDir', 'normal');
        colormap(gca, [0.4 0.7 0.9; 0.85 0.4 0.4]);
        cb = colorbar; cb.Ticks = [0.25 0.75]; cb.TickLabels = {'fixed point', 'oscillation'};
        xlabel('\tau_{delay}'); ylabel('c_a'); title('regime map');
        sgtitle('Fig 6: reduced mean-field bifurcation');
        export_fig_local(f, fig_dir, 'fig6_meanfield_bifurcation', fmt, dpi);
    end

    %% Fig 7: benchmarks
    d = latest_mat(fullfile(res, 'benchmarks'));
    if ~isempty(d)
        S = load(d);
        f = figure('Color', 'w');
        bar([S.nrmse_on, S.nrmse_off]);
        set(gca, 'XTickLabel', S.bench_names);
        ylabel('test NRMSE'); legend({'adaptation ON', 'adaptation OFF'});
        title('Fig 7: benchmark performance (ridge readout only)'); grid on;
        export_fig_local(f, fig_dir, 'fig7_benchmarks', fmt, dpi);
    end

    fprintf('Paper figures written to %s\n', fig_dir);
end

% -------------------------------------------------------------------------
function p = latest_mat(folder)
    p = latest_mat_prefix(folder, '');
end

function p = latest_mat_prefix(folder, prefix)
    p = '';
    if ~exist(folder, 'dir'); return; end
    files = dir(fullfile(folder, [prefix '*.mat']));
    if isempty(files); return; end
    [~, ord] = sort([files.datenum], 'descend');
    p = fullfile(folder, files(ord(1)).name);
end

function v = safe_nn(specW, field)
    if isstruct(specW) && isfield(specW, 'nonnormality') && ...
            isfield(specW.nonnormality, field)
        v = specW.nonnormality.(field);
    else
        v = NaN;
    end
end

function export_fig_local(f, dir_out, name, fmt, dpi)
    fname = fullfile(dir_out, sprintf('%s.%s', name, fmt));
    try
        exportgraphics(f, fname, 'Resolution', dpi);
    catch
        % Fallback for older MATLAB
        print(f, fname, ['-d' fmt], sprintf('-r%d', dpi));
    end
end

function v = getfielddef(s, f, d)
    if isfield(s, f); v = s.(f); else; v = d; end
end
