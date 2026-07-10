function result = run_bifurcation_meanfield(options)
% run_bifurcation_meanfield
% Reduced mean-field dynamical regime sweep over IextE (time integration).
%
% This is a dynamical regime sweep, not a bifurcation diagram, unless a
% continuation package supplies equilibria/periodic orbits and stability.
%
%   result = run_bifurcation_meanfield()
%   result = run_bifurcation_meanfield(options)
%
% Options:
%   .Iext_vals       sweep values (default linspace(0,2,40))
%   .tspan           integration interval (default [0,500])
%   .tau_delay       inhibitory delay (default 0.05)
%   .save_results    write results (default true)
%   .out_dir         output directory (default results/meanfield_bifurcation)
%   .make_figures    plot diagnostics (default true)
%   .trajectory_idx  cell indices keeping raw trajectories (default [1,end])
%   .dry_run         skip integration; RHS diagnostics only (default false)

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end

    Iext_vals = local_get_opt(options, 'Iext_vals', linspace(0.0, 2.0, 40));
    tspan = local_get_opt(options, 'tspan', [0, 500]);
    tau_delay = local_get_opt(options, 'tau_delay', 0.05);
    save_results = local_get_opt(options, 'save_results', true);
    make_figures = local_get_opt(options, 'make_figures', true);
    dry_run = local_get_opt(options, 'dry_run', false);
    trajectory_idx = local_get_opt(options, 'trajectory_idx', []);
    out_dir = local_get_opt(options, 'out_dir', ...
        fullfile(pwd, 'results', 'meanfield_bifurcation'));

    mf = meanfield_EI_STD_DDE(struct('tau_delay', tau_delay));
    par = mf.par(:).';
    idx_IextE = find(strcmp(mf.par_names, 'IextE'));
    if isempty(idx_IextE)
        error('run_bifurcation_meanfield:MissingParam', 'IextE not in par_names.');
    end

    if isempty(trajectory_idx)
        trajectory_idx = unique([1, numel(Iext_vals)]);
    end
    trajectory_idx = trajectory_idx(:).';
    trajectory_idx = trajectory_idx(trajectory_idx >= 1 & trajectory_idx <= numel(Iext_vals));

    y0 = [0.1; 0.1; 0.0; 1.0];
    xx0 = [y0, y0];

    result = struct();
    result.analysis_type = 'dynamical_regime_sweep';
    result.is_bifurcation_diagram = false;
    result.parameter_name = 'IextE';
    result.Iext_vals = Iext_vals;
    result.par_template = par;
    result.idx_IextE = idx_IextE;
    result.null_sweep = false;
    result.save_path = '';
    result.mf = mf;

    % For two separated parameter values, RHS at the same state must differ
    % because IextE appears in the E equation.
    if numel(Iext_vals) >= 2
        p_lo = par; p_lo(idx_IextE) = Iext_vals(1);
        p_hi = par; p_hi(idx_IextE) = Iext_vals(end);
        dy_lo = meanfield_EI_STD_DDE_rhs(xx0, p_lo);
        dy_hi = meanfield_EI_STD_DDE_rhs(xx0, p_hi);
        result.rhs_diff_norm = norm(dy_lo - dy_hi);
        result.rhs_differs_across_sweep = result.rhs_diff_norm > 1e-12;
    else
        result.rhs_diff_norm = NaN;
        result.rhs_differs_across_sweep = false;
    end

    if dry_run
        result.mode = 'dry_run';
        result.diagnostics = struct([]);
        result.trajectories = struct([]);
        return;
    end

    has_ddebiftool = exist('set_funcs', 'file') == 2 && exist('df_brnch', 'file') == 2;
    if has_ddebiftool
        result.mode = 'ddebiftool_scaffold';
        result.note = ['DDE-BIFTOOL detected; scaffold only. A bifurcation ', ...
            'diagram requires continuation, branch detection, and stability.'];
        sys_rhs = @(xx, p) meanfield_EI_STD_DDE_rhs(xx, p);
        sys_tau = @(ind, p) p(13);
        funcs = set_funcs('sys_rhs', sys_rhs, 'sys_tau', sys_tau);
        result.diagnostics = struct([]);
        result.trajectories = struct([]);
        if save_results
            if ~exist(out_dir, 'dir'); mkdir(out_dir); end
            save_path = fullfile(out_dir, 'ddebiftool_scaffold.mat');
            atomic_save(save_path, struct( ...
                'mf', mf, 'funcs', funcs, 'idx_IextE', idx_IextE, ...
                'Iext_vals', Iext_vals, 'result', result));
            result.save_path = save_path;
            fprintf('Saved scaffold to %s\n', save_path);
        end
        return;
    end

    result.mode = 'dde23_regime_sweep';
    history = @(t) y0; %#ok<INUSD>
    opts = ddeset('RelTol', 1e-7, 'AbsTol', 1e-9);
    dt_eval = 0.1;
    tt = (tspan(1):dt_eval:tspan(2))';
    keep = tt > (tspan(2) * 0.5);

    n = numel(Iext_vals);
    diagnostics = repmat(struct( ...
        'IextE', NaN, 'varE', NaN, 'varI', NaN, ...
        'domFreqE', NaN, 'domFreqI', NaN, 'regime', ''), n, 1);
    trajectories = repmat(struct( ...
        'index', [], 'IextE', [], 't', [], 'y', []), numel(trajectory_idx), 1);
    traj_write = 0;

    for ii = 1:n
        % Per-grid-cell parameter vector (must be closed over by the RHS)
        par2 = par;
        par2(idx_IextE) = Iext_vals(ii);

        assert(abs(par2(idx_IextE) - Iext_vals(ii)) <= eps(Iext_vals(ii)), ...
            'run_bifurcation_meanfield:ParamMismatch', ...
            'Swept parameter in par2 must equal the current grid value.');

        expected = Iext_vals(ii);
        rhs = @(t, y, Z) meanfield_rhs_closed(t, y, Z, par2, idx_IextE, expected);
        lags = par2(13);
        sol = dde23(rhs, lags, history, tspan, opts);

        yy = deval(sol, tt)';
        E = yy(keep, 1);
        I = yy(keep, 2);
        diagnostics(ii).IextE = Iext_vals(ii);
        diagnostics(ii).varE = var(E, 1);
        diagnostics(ii).varI = var(I, 1);
        diagnostics(ii).domFreqE = local_dominant_freq(E, dt_eval);
        diagnostics(ii).domFreqI = local_dominant_freq(I, dt_eval);
        if diagnostics(ii).varE > 1e-5
            diagnostics(ii).regime = 'oscillatory';
        else
            diagnostics(ii).regime = 'fixed_point';
        end

        if any(trajectory_idx == ii)
            traj_write = traj_write + 1;
            trajectories(traj_write).index = ii;
            trajectories(traj_write).IextE = Iext_vals(ii);
            trajectories(traj_write).t = tt;
            trajectories(traj_write).y = yy;
        end
    end
    if traj_write < numel(trajectories)
        trajectories = trajectories(1:traj_write);
    end

    regimes = {diagnostics.regime};
    result.null_sweep = all(strcmp(regimes, regimes{1}));
    if result.null_sweep
        result.analysis_label = 'null_regime_sweep';
        result.note = sprintf(['Null sweep: all %d cells classified as "%s". ', ...
            'Do not label this output a bifurcation.'], n, regimes{1});
    else
        result.analysis_label = 'dynamical_regime_sweep';
        result.note = 'Regime classification varies across IextE; not a bifurcation diagram.';
    end

    result.diagnostics = diagnostics;
    result.trajectories = trajectories;

    if save_results
        if ~exist(out_dir, 'dir'); mkdir(out_dir); end
        save_path = fullfile(out_dir, sprintf('dde23_sweep_%s.mat', ...
            datestr(now, 'yyyymmdd_HHMMSS')));
        atomic_save(save_path, struct( ...
            'mf', mf, 'par', par, 'Iext_vals', Iext_vals, ...
            'diagnostics', diagnostics, 'trajectories', trajectories, ...
            'result', result));
        result.save_path = save_path;
        fprintf('Saved dde23 regime sweep to %s\n', save_path);
    end

    if make_figures
        figure('Color', 'w');
        subplot(2,1,1);
        plot(Iext_vals, [diagnostics.varE], 'r.-', 'LineWidth', 1.5); hold on;
        plot(Iext_vals, [diagnostics.varI], 'b.-', 'LineWidth', 1.5);
        xlabel('IextE'); ylabel('variance'); grid on; legend('E','I');
        title('Mean-field dynamical regime sweep: variance vs IextE');
        subplot(2,1,2);
        plot(Iext_vals, [diagnostics.domFreqE], 'r.-', 'LineWidth', 1.5); hold on;
        plot(Iext_vals, [diagnostics.domFreqI], 'b.-', 'LineWidth', 1.5);
        xlabel('IextE'); ylabel('dominant frequency (Hz)'); grid on; legend('E','I');
        title('Mean-field dynamical regime sweep: dominant frequency');
    end

    if result.null_sweep
        fprintf('%s\n', result.note);
    end
end

function dy = meanfield_rhs_closed(~, y, Z, par2, idx, expected)
    assert(abs(par2(idx) - expected) <= max(eps(expected), 1e-15), ...
        'run_bifurcation_meanfield:RhsParamMismatch', ...
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
        error('run_bifurcation_meanfield:RefuseOverwrite', ...
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
