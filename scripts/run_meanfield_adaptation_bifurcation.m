function result = run_meanfield_adaptation_bifurcation(options)
% run_meanfield_adaptation_bifurcation
% Dynamical regime sweep of the reduced E-I-STD-DDE mean-field model over
% adaptation strength c_a and inhibitory delay tau_delay.
%
% This is a time-integration regime sweep, not a bifurcation diagram.
% A bifurcation diagram requires equilibrium/periodic-orbit continuation,
% branch detection, and stability information (e.g. DDE-BIFTOOL).
%
%   result = run_meanfield_adaptation_bifurcation()
%   result = run_meanfield_adaptation_bifurcation(options)
%
% Options:
%   .ca_vals / .ca_grid / .delay_grid   sweep grids
%   .tspan, .save_results, .out_dir, .make_figures, .dry_run
%   .trajectory_cells   [ic,id] rows of 2D cells to keep raw trajectories

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end

    ca_vals = local_get_opt(options, 'ca_vals', linspace(0.0, 3.0, 40));
    ca_grid = local_get_opt(options, 'ca_grid', linspace(0.0, 3.0, 24));
    delay_grid = local_get_opt(options, 'delay_grid', linspace(0.0, 0.20, 24));
    tspan = local_get_opt(options, 'tspan', [0, 600]);
    save_results = local_get_opt(options, 'save_results', true);
    make_figures = local_get_opt(options, 'make_figures', true);
    dry_run = local_get_opt(options, 'dry_run', false);
    trajectory_cells = local_get_opt(options, 'trajectory_cells', [1, 1]);
    out_dir = local_get_opt(options, 'out_dir', ...
        fullfile(pwd, 'results', 'meanfield_bifurcation'));
    osc_thresh = local_get_opt(options, 'osc_thresh', 1e-5);

    y0 = [0.1; 0.1; 0.0; 1.0];
    xx0 = [y0, y0];
    mf0 = meanfield_EI_STD_DDE(struct('c_a', ca_vals(1), 'tau_delay', 0.05));
    idx_ca = find(strcmp(mf0.par_names, 'c_a'));
    if isempty(idx_ca)
        error('run_meanfield_adaptation_bifurcation:MissingParam', ...
            'c_a not in par_names.');
    end

    result = struct();
    result.analysis_type = 'dynamical_regime_sweep';
    result.is_bifurcation_diagram = false;
    result.parameter_names = {'c_a', 'tau_delay'};
    result.ca_vals = ca_vals;
    result.ca_grid = ca_grid;
    result.delay_grid = delay_grid;
    result.null_sweep = false;
    result.save_path = '';
    result.osc_thresh = osc_thresh;

    % RHS must differ for separated c_a at the same state (c_a enters inE)
    if numel(ca_vals) >= 2
        p_lo = mf0.par(:).'; p_lo(idx_ca) = ca_vals(1);
        p_hi = mf0.par(:).'; p_hi(idx_ca) = ca_vals(end);
        xx_a = xx0; xx_a(3, 1) = 0.5;
        dy_lo = meanfield_EI_STD_DDE_rhs(xx_a, p_lo);
        dy_hi = meanfield_EI_STD_DDE_rhs(xx_a, p_hi);
        result.rhs_diff_norm = norm(dy_lo - dy_hi);
        result.rhs_differs_across_sweep = result.rhs_diff_norm > 1e-12;
    else
        result.rhs_diff_norm = NaN;
        result.rhs_differs_across_sweep = false;
    end

    if dry_run
        result.mode = 'dry_run';
        result.Emin = [];
        result.Emax = [];
        result.Evar = [];
        result.Efreq = [];
        result.VAR = [];
        result.REGIME = [];
        result.trajectories = struct([]);
        return;
    end

    result.mode = 'dde23_regime_sweep';
    history = @(t) y0; %#ok<INUSD>
    opts = ddeset('RelTol', 1e-7, 'AbsTol', 1e-9);
    dt_eval = 0.05;
    tt = (tspan(1):dt_eval:tspan(2))';
    keep = tt > 0.6 * tspan(2);

    %% (1) 1D regime sweep vs adaptation strength c_a
    Emin = nan(numel(ca_vals), 1);
    Emax = nan(numel(ca_vals), 1);
    Evar = nan(numel(ca_vals), 1);
    Efreq = nan(numel(ca_vals), 1);
    traj_1d = struct('c_a', {}, 't', {}, 'y', {});

    for ii = 1:numel(ca_vals)
        mf = meanfield_EI_STD_DDE(struct('c_a', ca_vals(ii), 'tau_delay', 0.05));
        par2 = mf.par(:).';
        assert(abs(par2(idx_ca) - ca_vals(ii)) <= max(eps(ca_vals(ii)), 1e-15), ...
            'run_meanfield_adaptation_bifurcation:ParamMismatch', ...
            'par2(c_a) must equal the current grid value.');

        expected = ca_vals(ii);
        rhs = @(t, y, Z) meanfield_rhs_closed(t, y, Z, par2, idx_ca, expected);
        sol = dde23(rhs, mf.lags, history, tspan, opts);
        yy = deval(sol, tt)';
        E = yy(keep, 1);
        Emin(ii) = min(E);
        Emax(ii) = max(E);
        Evar(ii) = var(E, 1);
        Efreq(ii) = local_dominant_freq(E, dt_eval);

        if ii == 1 || ii == numel(ca_vals)
            traj_1d(end+1).c_a = ca_vals(ii); %#ok<AGROW>
            traj_1d(end).t = tt;
            traj_1d(end).y = yy;
        end
    end

    %% (2) 2D regime map in (c_a, tau_delay)
    VAR = nan(numel(ca_grid), numel(delay_grid));
    n_keep = size(trajectory_cells, 1);
    trajectories = repmat(struct( ...
        'ic', [], 'id', [], 'c_a', [], 'tau_delay', [], 't', [], 'y', []), ...
        n_keep, 1);
    traj_write = 0;

    for ic = 1:numel(ca_grid)
        for id = 1:numel(delay_grid)
            d = delay_grid(id);
            d_eff = d;
            if d_eff <= 0
                d_eff = 1e-4;
            end
            mf = meanfield_EI_STD_DDE(struct('c_a', ca_grid(ic), 'tau_delay', d_eff));
            par2 = mf.par(:).';
            assert(abs(par2(idx_ca) - ca_grid(ic)) <= max(eps(ca_grid(ic)), 1e-15), ...
                'run_meanfield_adaptation_bifurcation:ParamMismatch', ...
                'par2(c_a) must equal the current grid value.');

            expected = ca_grid(ic);
            rhs = @(t, y, Z) meanfield_rhs_closed(t, y, Z, par2, idx_ca, expected);
            try
                sol = dde23(rhs, mf.lags, history, tspan, opts);
                yy = deval(sol, tt)';
                E = yy(keep, 1);
                VAR(ic, id) = var(E, 1);

                keep_traj = false;
                for k = 1:n_keep
                    if trajectory_cells(k, 1) == ic && trajectory_cells(k, 2) == id
                        keep_traj = true;
                        break;
                    end
                end
                if keep_traj
                    traj_write = traj_write + 1;
                    trajectories(traj_write).ic = ic;
                    trajectories(traj_write).id = id;
                    trajectories(traj_write).c_a = ca_grid(ic);
                    trajectories(traj_write).tau_delay = d;
                    trajectories(traj_write).t = tt;
                    trajectories(traj_write).y = yy;
                end
            catch
                VAR(ic, id) = NaN;
            end
        end
    end
    if traj_write < numel(trajectories)
        trajectories = trajectories(1:max(traj_write, 0));
    end

    REGIME = double(VAR > osc_thresh);
    finite_regimes = REGIME(isfinite(VAR));
    result.null_sweep = ~isempty(finite_regimes) && all(finite_regimes == finite_regimes(1));
    if result.null_sweep
        result.analysis_label = 'null_regime_sweep';
        result.note = sprintf(['Null sweep: all finite cells share regime code %g. ', ...
            'Do not label this output a bifurcation.'], finite_regimes(1));
    else
        result.analysis_label = 'dynamical_regime_sweep';
        result.note = 'Regime map from time integration; not a bifurcation diagram.';
    end

    result.Emin = Emin;
    result.Emax = Emax;
    result.Evar = Evar;
    result.Efreq = Efreq;
    result.VAR = VAR;
    result.REGIME = REGIME;
    result.trajectories = trajectories;
    result.trajectories_1d = traj_1d;
    result.tspan = tspan;

    if save_results
        if ~exist(out_dir, 'dir'); mkdir(out_dir); end
        timestamp = datestr(now, 'yyyymmdd_HHMMSS');
        save_path = fullfile(out_dir, sprintf('adaptation_%s.mat', timestamp));
        atomic_save(save_path, struct( ...
            'ca_vals', ca_vals, 'Emin', Emin, 'Emax', Emax, 'Evar', Evar, ...
            'Efreq', Efreq, 'ca_grid', ca_grid, 'delay_grid', delay_grid, ...
            'VAR', VAR, 'REGIME', REGIME, 'osc_thresh', osc_thresh, ...
            'tspan', tspan, 'trajectories', trajectories, ...
            'trajectories_1d', traj_1d, 'result', result));
        result.save_path = save_path;
        fprintf('Saved mean-field dynamical regime sweep to %s\n', save_path);
    end

    if make_figures
        figure('Color', 'w');
        subplot(1,2,1); hold on;
        plot(ca_vals, Emin, 'b.-', 'LineWidth', 1.2);
        plot(ca_vals, Emax, 'r.-', 'LineWidth', 1.2);
        xlabel('adaptation strength c_a');
        ylabel('E(t) range [min, max] (post-transient)');
        title('Mean-field dynamical regime sweep vs adaptation');
        legend('min E', 'max E', 'Location', 'best'); grid on;

        subplot(1,2,2);
        imagesc(delay_grid, ca_grid, REGIME);
        set(gca, 'YDir', 'normal');
        colormap(gca, [0.4 0.7 0.9; 0.85 0.4 0.4]);
        cb = colorbar; cb.Ticks = [0.25 0.75];
        cb.TickLabels = {'fixed point', 'oscillation'};
        xlabel('inhibitory delay \tau_{delay}');
        ylabel('adaptation strength c_a');
        title('Regime map (c_a, \tau_{delay})');
    end

    if result.null_sweep
        fprintf('%s\n', result.note);
    end
end

function dy = meanfield_rhs_closed(~, y, Z, par2, idx, expected)
    assert(abs(par2(idx) - expected) <= max(eps(expected), 1e-15), ...
        'run_meanfield_adaptation_bifurcation:RhsParamMismatch', ...
        'RHS closed over wrong parameter value (expected %g, got %g).', ...
        expected, par2(idx));
    dy = meanfield_EI_STD_DDE_rhs([y, Z], par2);
end

function f0 = local_dominant_freq(x, dt)
    x = x(:) - mean(x, 'omitnan');
    if numel(x) < 64
        f0 = 0;
        return;
    end
    fs = 1 / dt;
    nfft = 2^nextpow2(numel(x));
    X = fft(x, nfft);
    P1 = abs(X(1:nfft/2+1)).^2;
    f = fs * (0:nfft/2) / nfft;
    if numel(P1) > 1
        [~, idx] = max(P1(2:end));
        f0 = f(idx + 1);
    else
        f0 = 0;
    end
end

function atomic_save(path, S)
    if exist(path, 'file')
        error('run_meanfield_adaptation_bifurcation:RefuseOverwrite', ...
            'Refusing to overwrite existing result file: %s', path);
    end
    tmp = [path, '.tmp'];
    save(tmp, '-struct', 'S');
    movefile(tmp, path);
end

function v = local_get_opt(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
