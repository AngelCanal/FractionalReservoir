function [calibration, run_dir] = calibrate_operating_point(options)
% calibrate_operating_point  T102 shared operating-point calibration (no fishing).
%
% Uses only calibration seeds (never final test seeds). Applies one shared
% (input_scaling, level_of_chaos) rule to all paired mechanism conditions.
% Saves every tried configuration, including failures.

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end
    this_dir = fileparts(mfilename('fullpath'));
    addpath(this_dir);

    cfg = mechanism_ablation_config('pilot');
    if isfield(options, 'cfg')
        cfg = options.cfg;
    end
    op = cfg.operating_point;
    seeds = op.calibration_seeds;
    assert(isempty(intersect(seeds, cfg.publication_seeds)), ...
        'Calibration seeds must not overlap publication inference seeds.');

    save_results = local_get(options, 'save_results', true);
    verbose = local_get(options, 'verbose', true);
    % Use a representative subset of cells spanning mechanisms (not outcome-selected)
    probe_keys = local_get(options, 'probe_cell_keys', { ...
        'adapt-off__std-off__delay-ode_off__feat-x', ...
        'adapt-single_moment_matched__std-off__delay-ode_off__feat-x', ...
        'adapt-three_timescales__std-off__delay-ode_off__feat-x', ...
        'adapt-off__std-on__delay-ode_off__feat-x', ...
        'adapt-three_timescales__std-on__delay-ode_off__feat-x', ...
        'adapt-off__std-off__delay-dde_on__feat-x', ...
        'adapt-three_timescales__std-on__delay-dde_on__feat-x'});

    cells = cfg.cells;
    keep = false(size(cells));
    for i = 1:numel(cells)
        keep(i) = any(strcmp(cells{i}.cell_key, probe_keys));
    end
    cells = cells(keep);
    assert(~isempty(cells), 'No probe cells matched.');

    run_dir = '';
    if save_results
        ctx_opts = struct('master_seed', seeds(1));
        if isfield(options, 'run_id'); ctx_opts.run_id = options.run_id; end
        if isfield(options, 'revalidated_root_override')
            ctx_opts.revalidated_root_override = options.revalidated_root_override;
        end
        ctx = create_run_context('operating_point_calibration', ctx_opts);
        run_dir = ctx.run_dir;
        save_run_manifest(ctx, cfg, struct( ...
            'stage', 'T102_calibration', ...
            'calibration_seeds', seeds, ...
            'probe_cell_keys', {probe_keys}, ...
            'rule', op.rule));
    end

    trials = {};
    chosen = [];
    for isc = 1:numel(op.candidate_input_scaling)
        for ilc = 1:numel(op.candidate_level_of_chaos)
            iscale = op.candidate_input_scaling(isc);
            loc = op.candidate_level_of_chaos(ilc);
            trial = struct();
            trial.input_scaling = iscale;
            trial.level_of_chaos = loc;
            trial.per_cell = {};
            trial.all_pass = true;
            trial.reason = '';

            for ic = 1:numel(cells)
                for iseed = 1:numel(seeds)
                    cell_spec = cells{ic};
                    seed = seeds(iseed);
                    ov = struct('input_scaling', iscale, 'level_of_chaos', loc);
                    [params, meta] = build_ablation_params(cell_spec, seed, cfg, ov);
                    esn = SRNN_ESN(params);
                    if cfg.pilot_not_for_publication
                        esn.ode_solver = @ode45;
                    end
                    diag = probe_operating_point(esn, params, seed, cfg.lengths);
                    row = struct( ...
                        'cell_key', cell_spec.cell_key, ...
                        'seed', seed, ...
                        'mean_rate', diag.mean_rate, ...
                        'saturation_fraction', diag.saturation_fraction, ...
                        'silent_fraction', diag.silent_fraction, ...
                        'dale_violations', meta.sign_violations_E + meta.sign_violations_I, ...
                        'pass', false);
                    row.pass = ...
                        diag.mean_rate >= op.mean_rate_band(1) && ...
                        diag.mean_rate <= op.mean_rate_band(2) && ...
                        diag.saturation_fraction <= op.saturation_fraction_max && ...
                        diag.silent_fraction <= op.silent_fraction_max && ...
                        row.dale_violations == 0;
                    if ~row.pass
                        trial.all_pass = false;
                    end
                    trial.per_cell{end+1} = row; %#ok<AGROW>
                    if verbose
                        fprintf('calib is=%.2f loc=%.2f %s seed=%d pass=%d rate=%.3f sat=%.3f\n', ...
                            iscale, loc, cell_spec.cell_key, seed, row.pass, ...
                            diag.mean_rate, diag.saturation_fraction);
                    end
                end
            end

            if ~trial.all_pass
                trial.reason = 'outside_preregistered_bands_on_at_least_one_probe';
            else
                trial.reason = 'accepted_shared_operating_point';
            end
            trials{end+1} = trial; %#ok<AGROW>

            if trial.all_pass && isempty(chosen)
                chosen = struct('input_scaling', iscale, 'level_of_chaos', loc);
                % Continue enumerating remaining candidates so failures are recorded
            end
        end
    end

    calibration = struct();
    calibration.calibration_seeds = seeds;
    calibration.probe_cell_keys = probe_keys;
    calibration.bands = struct( ...
        'mean_rate_band', op.mean_rate_band, ...
        'saturation_fraction_max', op.saturation_fraction_max, ...
        'silent_fraction_max', op.silent_fraction_max);
    calibration.rule = op.rule;
    calibration.trials = trials;
    calibration.frozen_operating_point = chosen;
    calibration.status = ternary(~isempty(chosen), 'frozen', 'no_feasible_point');
    calibration.run_dir = run_dir;
    calibration.no_outcome_fishing = true;
    calibration.note = [ ...
        'Selection used only rate/saturation/silent bands on calibration seeds; ', ...
        'no task test NRMSE or memory scores entered the decision.'];

    if save_results
        atomic_save_results(fullfile(run_dir, 'calibration.mat'), ...
            struct('calibration', calibration));
        save_run_manifest(ctx, cfg, struct( ...
            'stage', 'T102_calibration_complete', ...
            'status', calibration.status, ...
            'frozen_operating_point', chosen, ...
            'n_trials', numel(trials)));
    end
end

function diag = probe_operating_point(esn, params, seed, L)
    rng(seed + 99);
    T = max(local_get(L, 'esp_T', 120), 80);
    U = 2 * rand(T, size(params.W_in, 2)) - 1;
    run_opts = struct('reset_before', true, 'update_internal_state', false, ...
        'ode_reltol', local_get(L, 'ode_reltol', 1e-4), ...
        'ode_abstol', local_get(L, 'ode_abstol', 1e-6), ...
        'dde_reltol', local_get(L, 'dde_reltol', 1e-4), ...
        'dde_abstol', local_get(L, 'dde_abstol', 1e-6), ...
        'ode_solver', esn.ode_solver);
    [~, S_hist] = esn.runReservoir(U, run_opts);
    stride = max(1, floor(size(S_hist, 1) / 40));
    idx = 1:stride:size(S_hist, 1);
    rates = zeros(params.n, numel(idx));
    for k = 1:numel(idx)
        rates(:, k) = esn.computeRates(S_hist(idx(k), :)');
    end
    diag = struct();
    diag.mean_rate = mean(rates(:));
    diag.saturation_fraction = mean(rates(:) >= 0.99);
    diag.silent_fraction = mean(rates(:) <= 0.01);
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end

function out = ternary(cond, a, b)
    if cond
        out = a;
    else
        out = b;
    end
end
