function [result, run_dir] = make_paper_figures(options)
% make_paper_figures
% Rebuild MESN publication figures from explicit validated result paths only.
%
%   [result, run_dir] = make_paper_figures(options)
%
% Required:
%   .result_paths OR .manifest_path with fields (all explicit absolute paths):
%       .validation_controls   (Fig 1) optional until packaged
%       .ablation_aggregate    (Figs 3–4) aggregate_paired.mat from T103
%       .ablation_run_dir      directory of immutable cell results (preferred)
%       .meanfield             (optional Fig 5) regime-sweep .mat
%
% Legacy fields esp_phase/parameter_grid/... are accepted only when
% options.allow_legacy_paths=true and are labeled non-publication.
%
% Plotting performs no simulations. Missing G7 data yields placeholder panels
% and status 'incomplete_awaiting_g7' rather than inventing evidence.

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end

    dpi = local_get(options, 'dpi', 200);
    fmt = local_get(options, 'format', 'png');
    save_results = local_get(options, 'save_results', true);
    dry_run = local_get(options, 'dry_run', false);
    allow_legacy = local_get(options, 'allow_legacy_paths', false);
    fig_dir = local_get(options, 'fig_dir', ...
        fullfile(pwd, 'results', 'figures', 'paper_revalidated'));

    result = struct();
    result.status = 'ok';
    run_dir = '';

    if dry_run
        paths = resolve_validated_figure_paths(options, allow_legacy);
        result.result_paths = paths;
        result.status = 'dry_run';
        return;
    end

    paths = resolve_validated_figure_paths(options, allow_legacy);
    result.result_paths = paths;

    if save_results
        ctx_opts = struct();
        if isfield(options, 'run_id'); ctx_opts.run_id = options.run_id; end
        if isfield(options, 'revalidated_root_override')
            ctx_opts.revalidated_root_override = options.revalidated_root_override;
        end
        ctx = create_run_context('paper_figures_validated', ctx_opts);
        save_run_manifest(ctx, struct('result_paths', paths, 'dpi', dpi, 'format', fmt));
        run_dir = ctx.run_dir;
        fig_dir = fullfile(run_dir, 'figures');
        if ~exist(fig_dir, 'dir'); mkdir(fig_dir); end
    else
        if ~exist(fig_dir, 'dir'); mkdir(fig_dir); end
    end

    exported = {};
    panel_status = struct();

    %% Figure 1 — Model and validation controls
    [f1, st1] = fig1_validation_controls(paths);
    export_fig_local(f1, fig_dir, 'fig1_validation_controls', fmt, dpi);
    close(f1);
    exported{end+1} = 'fig1_validation_controls'; %#ok<AGROW>
    panel_status.fig1 = st1;

    %% Figure 2 — Empirical convergence and local dynamics
    [f2, st2] = fig2_convergence_dynamics(paths);
    export_fig_local(f2, fig_dir, 'fig2_empirical_convergence', fmt, dpi);
    close(f2);
    exported{end+1} = 'fig2_empirical_convergence'; %#ok<AGROW>
    panel_status.fig2 = st2;

    %% Figure 3 — Paired temporal capacity ablations
    [f3, st3] = fig3_paired_capacity(paths);
    export_fig_local(f3, fig_dir, 'fig3_paired_capacity', fmt, dpi);
    close(f3);
    exported{end+1} = 'fig3_paired_capacity'; %#ok<AGROW>
    panel_status.fig3 = st3;

    %% Figure 4 — Learning benchmarks
    [f4, st4] = fig4_learning_benchmarks(paths);
    export_fig_local(f4, fig_dir, 'fig4_learning_benchmarks', fmt, dpi);
    close(f4);
    exported{end+1} = 'fig4_learning_benchmarks'; %#ok<AGROW>
    panel_status.fig4 = st4;

    %% Optional Figure 5 — Mean-field regime sweep
    if isfield(paths, 'meanfield') && ~isempty(paths.meanfield)
        [f5, st5] = fig5_meanfield_regime(paths);
        export_fig_local(f5, fig_dir, 'fig5_meanfield_regime_sweep', fmt, dpi);
        close(f5);
        exported{end+1} = 'fig5_meanfield_regime_sweep'; %#ok<AGROW>
        panel_status.fig5 = st5;
    else
        panel_status.fig5 = 'skipped_no_path';
    end

    incomplete = any(structfun(@(s) contains(string(s), 'incomplete') || ...
        contains(string(s), 'unsupported'), panel_status));
    if incomplete
        result.status = 'incomplete_awaiting_g7';
    end

    result.exported = exported;
    result.panel_status = panel_status;
    result.fig_dir = fig_dir;
    result.run_dir = run_dir;
    fprintf('Validated paper figures written to %s (status=%s)\n', ...
        fig_dir, result.status);
end

function paths = resolve_validated_figure_paths(options, allow_legacy)
    if isfield(options, 'manifest_path') && ~isempty(options.manifest_path)
        S = load(options.manifest_path);
        if isfield(S, 'result_paths')
            paths = S.result_paths;
        elseif isfield(S, 'paths')
            paths = S.paths;
        else
            error('make_paper_figures:AmbiguousManifest', ...
                'Manifest must contain result_paths.');
        end
    elseif isfield(options, 'result_paths')
        paths = options.result_paths;
    else
        error('make_paper_figures:MissingPaths', ...
            'Require options.result_paths or options.manifest_path (no latest-file lookup).');
    end

    % Prefer new validated keys; legacy only if explicitly allowed
    has_new = isfield(paths, 'ablation_aggregate') || isfield(paths, 'ablation_run_dir');
    has_legacy = isfield(paths, 'esp_phase');
    if ~has_new && has_legacy && ~allow_legacy
        error('make_paper_figures:LegacyPathsBlocked', ...
            ['Legacy esp_phase/parameter_grid paths are not publication inputs. ', ...
             'Pass ablation_aggregate/ablation_run_dir from results/revalidated, ', ...
             'or set allow_legacy_paths=true for diagnostic-only plots.']);
    end

    if isfield(paths, 'ablation_aggregate') && ~isempty(paths.ablation_aggregate)
        paths.ablation_aggregate = require_explicit_result_path( ...
            paths.ablation_aggregate, 'ablation_aggregate');
    end
    if isfield(paths, 'ablation_run_dir') && ~isempty(paths.ablation_run_dir)
        if ~isfolder(paths.ablation_run_dir)
            error('make_paper_figures:MissingRunDir', ...
                'ablation_run_dir not found: %s', paths.ablation_run_dir);
        end
    end
    if isfield(paths, 'validation_controls') && ~isempty(paths.validation_controls)
        paths.validation_controls = require_explicit_result_path( ...
            paths.validation_controls, 'validation_controls');
    end
    if isfield(paths, 'meanfield') && ~isempty(paths.meanfield)
        paths.meanfield = require_explicit_result_path(paths.meanfield, 'meanfield');
    end
end

function [f, status] = fig1_validation_controls(paths)
    f = figure('Color', 'w', 'Visible', 'off', 'Position', [100 100 1000 700]);
    status = 'incomplete_awaiting_packaged_controls';
    if isfield(paths, 'validation_controls') && ~isempty(paths.validation_controls)
        S = load(paths.validation_controls);
        status = 'ok';
        % Expected optional fields: dale_counts, jac_errors, isolation_pass, lle_controls
        subplot(2,2,1);
        if isfield(S, 'dale_sign_counts')
            bar(S.dale_sign_counts); title('Dale sign counts');
        else
            text(0.1, 0.5, 'Dale counts: supply validation_controls.mat');
            axis off;
        end
        subplot(2,2,2);
        if isfield(S, 'jacobian_fd_errors')
            histogram(S.jacobian_fd_errors); title('Jacobian FD errors');
        else
            text(0.1, 0.5, 'Jacobian FD: supply validation_controls.mat');
            axis off;
        end
        subplot(2,2,3);
        if isfield(S, 'input_isolation_pass')
            bar(double(S.input_isolation_pass)); title('Input isolation');
        else
            text(0.1, 0.5, 'Input isolation: supply validation_controls.mat');
            axis off;
        end
        subplot(2,2,4);
        if isfield(S, 'lle_controls')
            plot(S.lle_controls.true_exponents, S.lle_controls.estimated, 'ko');
            hold on; plot([-1 1], [-1 1], 'r--');
            title('ODE LLE controls'); xlabel('true'); ylabel('estimated');
        else
            text(0.1, 0.5, 'LLE controls: supply validation_controls.mat');
            axis off;
        end
    else
        for k = 1:4
            subplot(2,2,k);
            text(0.05, 0.5, sprintf(['Fig1 panel %d incomplete:\n', ...
                'pass result_paths.validation_controls'], k), 'FontSize', 9);
            axis off;
        end
    end
    sgtitle({'Fig 1: Model and validation controls', ...
        'Requires explicit validated control artifacts (no simulations here)'});
end

function [f, status] = fig2_convergence_dynamics(paths)
    f = figure('Color', 'w', 'Visible', 'off', 'Position', [100 100 1000 700]);
    agg = try_load_aggregate(paths);
    if isempty(agg)
        status = 'incomplete_awaiting_g7';
        for k = 1:4
            subplot(2,2,k);
            text(0.05, 0.5, 'Incomplete: need ablation_aggregate from G7', 'FontSize', 9);
            axis off;
        end
        sgtitle('Fig 2: Empirical convergence and local dynamics (incomplete)');
        return;
    end
    status = 'ok_from_aggregate';
    rows = agg.raw_rows;
    ode = rows(strcmp({rows.mode}, 'ODE'));
    dde = rows(strcmp({rows.mode}, 'DDE'));

    subplot(2,2,1);
    plot_seed_points([ode.esp_median_slope], 'ODE empirical slope');
    subtitle_mode('ODE', numel(unique([ode.seed])), agg.run_dir);

    subplot(2,2,2);
    plot_seed_points([dde.esp_median_slope], 'DDE empirical slope (history IC)');
    subtitle_mode('DDE', numel(unique([dde.seed])), agg.run_dir);

    subplot(2,2,3);
    text(0.05, 0.6, {'ODE LLE: attach only from ODE Lyapunov controls', ...
        'Never plot finite-dimensional DDE LLE'}, 'FontSize', 10);
    axis off; title('ODE LLE (separate evidence)');

    subplot(2,2,4);
    text(0.05, 0.6, {'quasi-static J_eff diagnostic is ODE-only', ...
        'Not an ESP theorem; see J_eff_notes.md'}, 'FontSize', 10);
    axis off; title('J_{eff} scope reminder');

    sgtitle('Fig 2: Empirical convergence and local dynamics');
end

function [f, status] = fig3_paired_capacity(paths)
    f = figure('Color', 'w', 'Visible', 'off', 'Position', [100 100 1100 700]);
    agg = try_load_aggregate(paths);
    if isempty(agg) || ~isfield(agg, 'paired') || isempty(agg.paired)
        status = 'incomplete_awaiting_g7';
        text(0.1, 0.5, ['Fig 3 incomplete: require aggregate_paired.mat from ', ...
            '>=30-seed T103 run (G7). Pilot data are not for publication.']);
        axis off;
        title('Fig 3: Paired temporal capacity ablations');
        return;
    end
    if numel(agg.seeds) < 30
        status = 'incomplete_awaiting_g7';
        text(0.1, 0.5, sprintf(['Fig 3 incomplete for publication: n_seeds=%d < 30 (G7). ', ...
            'Pilot/partial aggregates must not support mechanism claims.'], numel(agg.seeds)));
        axis off;
        title('Fig 3: Paired temporal capacity ablations');
        return;
    end
    status = 'ok';
    P = agg.paired;
    n = numel(P);
    med = arrayfun(@(p) p.MC.median, P);
    lo = arrayfun(@(p) p.MC.ci95_bootstrap_median(1), P);
    hi = arrayfun(@(p) p.MC.ci95_bootstrap_median(2), P);
    subplot(1,2,1); hold on;
    errorbar(1:n, med, med-lo, hi-med, 'o', 'LineWidth', 1.2);
    yline(0, 'k--');
    set(gca, 'XTick', 1:n, 'XTickLabel', {P.cell_key}, 'XTickLabelRotation', 45);
    ylabel('\Delta MC vs control (seed median, 95% bootstrap CI)');
    title('Paired MC effect sizes');
    subtitle_mode('mixed', numel(agg.seeds), agg.run_dir);
    subplot(1,2,2); hold on;
    for i = 1:min(n, 6)
        swarmchart(i*ones(size(P(i).delta_MC)), P(i).delta_MC, 12, 'filled');
    end
    yline(0, 'k--');
    ylabel('per-seed \Delta MC'); title('Seed-level paired differences');
    sgtitle({'Fig 3: Paired temporal capacity ablations', ...
        sprintf('resampling unit=seed; n_seeds=%d; manifest=%s', ...
        numel(agg.seeds), agg.run_dir)});
end

function [f, status] = fig4_learning_benchmarks(paths)
    f = figure('Color', 'w', 'Visible', 'off', 'Position', [100 100 1100 700]);
    agg = try_load_aggregate(paths);
    if isempty(agg)
        status = 'incomplete_awaiting_g7';
        text(0.1, 0.5, 'Fig 4 incomplete: need G7 ablation aggregate with baselines.');
        axis off; title('Fig 4: Learning benchmarks');
        return;
    end
    if numel(agg.seeds) < 30
        status = 'incomplete_awaiting_g7';
        text(0.1, 0.5, sprintf(['Fig 4 incomplete for publication: n_seeds=%d < 30 (G7).'], ...
            numel(agg.seeds)));
        axis off; title('Fig 4: Learning benchmarks');
        return;
    end
    status = 'ok';
    rows = agg.raw_rows;
    keys = unique({rows.cell_key}, 'stable');
    subplot(1,2,1); hold on;
    for i = 1:numel(keys)
        m = rows(strcmp({rows.cell_key}, keys{i}));
        swarmchart(i*ones(size(m)), [m.narma_test_nrmse], 10, 'filled');
    end
    set(gca, 'XTick', 1:numel(keys), 'XTickLabel', keys, 'XTickLabelRotation', 45);
    ylabel('NARMA test NRMSE'); title('Seed distributions');
    subplot(1,2,2); hold on;
    for i = 1:numel(keys)
        m = rows(strcmp({rows.cell_key}, keys{i}));
        swarmchart(i*ones(size(m)), [m.mg_test_nrmse], 10, 'filled');
    end
    set(gca, 'XTick', 1:numel(keys), 'XTickLabel', keys, 'XTickLabelRotation', 45);
    ylabel('MG one-step test NRMSE'); title('Teacher-forced (ODE/DDE)');
    sgtitle({'Fig 4: Learning benchmarks', ...
        'ODE autonomous horizons must be plotted separately when present; DDE autonomous unsupported'});
end

function [f, status] = fig5_meanfield_regime(paths)
    f = figure('Color', 'w', 'Visible', 'off');
    S = load(paths.meanfield);
    status = 'ok_regime_sweep_not_bifurcation';
    if isfield(S, 'REGIME')
        imagesc(S.delay_grid, S.ca_grid, S.REGIME);
        set(gca, 'YDir', 'normal');
        xlabel('\tau_{delay}'); ylabel('c_a');
        title('Dynamical regime sweep (not a bifurcation diagram)');
        colorbar;
    else
        text(0.1, 0.5, 'meanfield file missing REGIME map');
        axis off;
        status = 'incomplete';
    end
    sgtitle('Fig 5 (optional): mean-field regime sweep');
end

function agg = try_load_aggregate(paths)
    agg = [];
    if isfield(paths, 'ablation_aggregate') && ~isempty(paths.ablation_aggregate)
        S = load(paths.ablation_aggregate);
        if isfield(S, 'aggregate')
            agg = S.aggregate;
        end
        return;
    end
    if isfield(paths, 'ablation_run_dir') && ~isempty(paths.ablation_run_dir)
        p = fullfile(paths.ablation_run_dir, 'aggregate_paired.mat');
        if exist(p, 'file')
            S = load(p);
            if isfield(S, 'aggregate')
                agg = S.aggregate;
            end
        end
    end
end

function plot_seed_points(vals, ttl)
    vals = vals(:);
    swarmchart(ones(size(vals)), vals, 12, 'filled');
    ylabel(ttl); grid on;
end

function subtitle_mode(mode, n_seeds, manifest_id)
    title(sprintf('%s | n_{seeds}=%d | %s', mode, n_seeds, manifest_id), ...
        'Interpreter', 'none', 'FontSize', 8);
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

function v = local_get(s, f, d)
    if isfield(s, f) && ~isempty(s.(f))
        v = s.(f);
    else
        v = d;
    end
end
