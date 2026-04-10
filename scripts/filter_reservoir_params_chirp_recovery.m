function viable_configs = filter_reservoir_params_chirp_recovery()
% FILTER_RESERVOIR_PARAMS_CHIRP_RECOVERY  Phase 1 hyperparameter search
%
% Runs a dense pairwise scan over 5 parameter pairs using a chirp-recovery
% protocol to filter silent, unstable, and non-recovering reservoirs.
%
% Protocol per configuration:
%   1. Silence Phase 1 (200 steps): u=0, let transients settle
%   2. Chirp Phase     (400 steps): frequency+amplitude sweep
%   3. Silence Phase 2 (200 steps): u=0, evaluate recovery
%
% Outputs:
%   viable_configs - struct array of all passing configurations

    %% Setup paths
    setup_paths();

    %% Setup parallel pool
    % Initialize parallel pool if it doesn't exist
    poolobj = gcp('nocreate');
    if isempty(poolobj)
        fprintf('\nStarting parallel pool to run on all available cores...\n');
        parpool;
    end

    %% Fixed defaults
    defaults = struct();
    defaults.n             = 300;
    defaults.fractionE     = 0.5;
    defaults.naE           = 3;
    defaults.naI           = 2;
    defaults.tauaE         = logspace(log10(0.25), log10(25), 3);
    defaults.tauaI         = logspace(log10(0.25), log10(25), 2);
    defaults.nbE           = 0;
    defaults.nbI           = 0;   % disable STD initially
    defaults.cI            = 0.1;
    defaults.cE            = 0.1; % default adaptation scaling for E
    defaults.rngseed       = 42;
    defaults.inputscaling  = 1.0;
    defaults.spectralradius = 0.9;  % a0thresh -> piecewiseSigmoid 'c' param
    defaults.a0thresh      = 0.4;
    defaults.levelofchaos  = 1.5;
    defaults.taud          = 0.5;

    %% Generate chirp protocol
    [u_full, tu, dt] = make_chirp_protocol();

    %% Results directory
    resultsDir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'results', 'phase1_filter');
    if ~exist(resultsDir, 'dir')
        mkdir(resultsDir);
    end

    %% =====================================================================
    %  PAIR 1: inputscaling vs a0thresh
    %  =====================================================================
    fprintf('\n========== PAIR 1: inputscaling vs a0thresh ==========\n');
    inputscaling_vals = linspace(0.2, 2.5, 10);
    a0thresh_vals     = linspace(0.1, 1.5, 10);

    [results1, pass1] = run_pair_scan('inputscaling', inputscaling_vals, ...
                                       'a0thresh', a0thresh_vals, ...
                                       defaults, u_full, tu, dt);
    save(fullfile(resultsDir, 'pair1_inputscaling_a0thresh.mat'), 'results1', 'pass1', ...
         'inputscaling_vals', 'a0thresh_vals');
    plot_pair_heatmaps(results1, 'inputscaling', inputscaling_vals, ...
                       'a0thresh', a0thresh_vals, 'Pair 1', resultsDir);
    fprintf('  Pair 1 complete: %d / %d passed\n', sum([results1.passed]), numel(results1));

    %% =====================================================================
    %  PAIR 2: spectralradius vs levelofchaos
    %  =====================================================================
    fprintf('\n========== PAIR 2: spectralradius vs levelofchaos ==========\n');
    spectralradius_vals = linspace(0.4, 1.5, 10);
    levelofchaos_vals   = linspace(0.7, 2.5, 10);

    [results2, pass2] = run_pair_scan('spectralradius', spectralradius_vals, ...
                                       'levelofchaos', levelofchaos_vals, ...
                                       defaults, u_full, tu, dt);
    save(fullfile(resultsDir, 'pair2_spectralradius_levelofchaos.mat'), 'results2', 'pass2', ...
         'spectralradius_vals', 'levelofchaos_vals');
    plot_pair_heatmaps(results2, 'spectralradius', spectralradius_vals, ...
                       'levelofchaos', levelofchaos_vals, 'Pair 2', resultsDir);
    fprintf('  Pair 2 complete: %d / %d passed\n', sum([results2.passed]), numel(results2));

    %% =====================================================================
    %  PAIR 3: inputscaling vs cE
    %  =====================================================================
    fprintf('\n========== PAIR 3: inputscaling vs cE ==========\n');
    inputscaling_vals3 = linspace(0.4, 2.0, 10);
    cE_vals3           = logspace(-2, log10(0.5), 10);

    [results3, pass3] = run_pair_scan('inputscaling', inputscaling_vals3, ...
                                       'cE', cE_vals3, ...
                                       defaults, u_full, tu, dt);
    save(fullfile(resultsDir, 'pair3_inputscaling_cE.mat'), 'results3', 'pass3', ...
         'inputscaling_vals3', 'cE_vals3');
    plot_pair_heatmaps(results3, 'inputscaling', inputscaling_vals3, ...
                       'cE', cE_vals3, 'Pair 3', resultsDir);
    fprintf('  Pair 3 complete: %d / %d passed\n', sum([results3.passed]), numel(results3));

    %% =====================================================================
    %  PAIR 4: spectralradius vs cE
    %  =====================================================================
    fprintf('\n========== PAIR 4: spectralradius vs cE ==========\n');
    spectralradius_vals4 = linspace(0.6, 1.4, 10);
    cE_vals4             = logspace(-2, log10(0.4), 10);

    [results4, pass4] = run_pair_scan('spectralradius', spectralradius_vals4, ...
                                       'cE', cE_vals4, ...
                                       defaults, u_full, tu, dt);
    save(fullfile(resultsDir, 'pair4_spectralradius_cE.mat'), 'results4', 'pass4', ...
         'spectralradius_vals4', 'cE_vals4');
    plot_pair_heatmaps(results4, 'spectralradius', spectralradius_vals4, ...
                       'cE', cE_vals4, 'Pair 4', resultsDir);
    fprintf('  Pair 4 complete: %d / %d passed\n', sum([results4.passed]), numel(results4));

    %% =====================================================================
    %  PAIR 5: taud vs inputscaling
    %  =====================================================================
    fprintf('\n========== PAIR 5: taud vs inputscaling ==========\n');
    taud_vals5         = logspace(-2, 0, 10);
    inputscaling_vals5 = linspace(0.5, 2.0, 10);

    [results5, pass5] = run_pair_scan('taud', taud_vals5, ...
                                       'inputscaling', inputscaling_vals5, ...
                                       defaults, u_full, tu, dt);
    save(fullfile(resultsDir, 'pair5_taud_inputscaling.mat'), 'results5', 'pass5', ...
         'taud_vals5', 'inputscaling_vals5');
    plot_pair_heatmaps(results5, 'taud', taud_vals5, ...
                       'inputscaling', inputscaling_vals5, 'Pair 5', resultsDir);
    fprintf('  Pair 5 complete: %d / %d passed\n', sum([results5.passed]), numel(results5));

    %% =====================================================================
    %  Collect all viable configs
    %  =====================================================================
    viable_configs = collect_viable(results1, results2, results3, results4, results5);
    save(fullfile(resultsDir, 'viable_configs.mat'), 'viable_configs');

    fprintf('\n========== SUMMARY ==========\n');
    fprintf('  Total configs tested: %d\n', ...
        numel(results1)+numel(results2)+numel(results3)+numel(results4)+numel(results5));
    fprintf('  Viable configs:       %d\n', numel(viable_configs));
    fprintf('  Results saved to:     %s\n', resultsDir);
    fprintf('=============================\n');
end

%% =========================================================================
%  HELPER: make_chirp_protocol
%  =========================================================================
function [u_full, tu, dt] = make_chirp_protocol()
% MAKE_CHIRP_PROTOCOL Build the 800-step chirp-recovery input signal.
    t_chirp   = 0:399;
    f_start   = 0.05;
    f_end     = 2.0;
    amp_start = 0.5;
    amp_end   = 3.0;

    amp_t   = amp_start + (amp_end - amp_start) * (t_chirp / 399);
    phase_t = 2*pi*(f_start*t_chirp + (f_end - f_start) * (t_chirp.^2) / (2*400));
    u_chirp = amp_t .* sin(phase_t);

    u_full = [zeros(1,200), u_chirp, zeros(1,200)];
    tu     = 0:799;
    dt     = 1.0;
end

%% =========================================================================
%  HELPER: run_pair_scan
%  =========================================================================
function [results, pass_table] = run_pair_scan(name1, vals1, name2, vals2, ...
                                               defaults, u_full, tu, dt)
% RUN_PAIR_SCAN  Run a 2-D grid scan over two parameters using parallel pool.

    n1 = numel(vals1);
    n2 = numel(vals2);
    total = n1 * n2;

    % Create flattened parameter lists for parfor
    configs_pairs = cell(total, 2);
    for i = 1:n1
        for j = 1:n2
            % Store val1 and val2
            configs_pairs{(j-1)*n1 + i, 1} = vals1(i);
            configs_pairs{(j-1)*n1 + i, 2} = vals2(j);
        end
    end

    % Pre-allocate flat results struct array for parfor
    emptyResult = make_empty_result(name1, name2);
    results_flat = repmat(emptyResult, total, 1);

    fprintf('  Starting parallel grid: %d x %d = %d configs\n', n1, n2, total);

    % Run configurations in parallel
    parfor k = 1:total
        val1 = configs_pairs{k, 1};
        val2 = configs_pairs{k, 2};

        % Override the two scanned parameters
        cfg = defaults;
        cfg.(name1) = val1;
        cfg.(name2) = val2;

        % Execute configuration
        results_flat(k) = run_single_config(cfg, u_full, tu, dt, name1, val1, name2, val2);
        
        % Report progress sporadically
        if mod(k, max(1, round(total/10))) == 0 || k == 1
            fprintf('    [Worker finished task %d/%d] %s=%.4g, %s=%.4g\n', ...
                    k, total, name1, val1, name2, val2);
        end
    end
    fprintf('  Parallel grid computation complete.\n');

    % Reshape results back to 2D
    results = reshape(results_flat, n1, n2);

    % Build pass table
    pass_mask = reshape([results.passed], n1, n2);
    pass_table = table();
    k = 0;
    for i = 1:n1
        for j = 1:n2
            if pass_mask(i,j)
                k = k + 1;
                pass_table(k,:) = struct2table(results(i,j), 'AsArray', true);
            end
        end
    end
end

%% =========================================================================
%  HELPER: run_single_config
%  =========================================================================
function result = run_single_config(cfg, u_full, tu, dt, name1, val1, name2, val2)
% RUN_SINGLE_CONFIG  Build reservoir, run chirp protocol, compute metrics.

    result = struct();
    result.param1_name  = name1;
    result.param1_value = val1;
    result.param2_name  = name2;
    result.param2_value = val2;

    n   = cfg.n;
    n_E = round(n * cfg.fractionE);
    n_I = n - n_E;

    %% Build weight matrix W
    rng(cfg.rngseed);
    W = randn(n, n);
    W(:, 1:n_E)     = abs(W(:, 1:n_E));       % Dale's law: E positive
    W(:, n_E+1:end) = -abs(W(:, n_E+1:end));   % Dale's law: I negative
    W = W - mean(W, 2);                         % center rows

    % Step 1: Normalize W to unit spectral radius, then scale to desired
    W_eigs   = eig(W);
    rho0     = max(abs(W_eigs));          % spectral radius (max |eig|)
    if rho0 > 0
        W = W / rho0;                     % unit spectral radius
    end

    % Step 2: Apply combined scaling
    % spectralradius controls the base spectral radius
    % levelofchaos provides an additional multiplicative gain
    W = cfg.spectralradius * cfg.levelofchaos * W;

    %% Build input weight matrix W_in
    rng(cfg.rngseed + 1);
    W_in = (2*rand(n, 1) - 1) * cfg.inputscaling;
    W_in(rand(n, 1) > 0.2) = 0;  % 20 % connectivity

    %% Activation function
    S_a = cfg.a0thresh;  % maps a0thresh -> piecewiseSigmoid 'a' param
    S_c = 0.4;
    activation_fn = @(x) piecewiseSigmoid(x, S_a, S_c);

    %% Pack parameters for SRNN_ESN
    params        = struct();
    params.n      = n;
    params.n_E    = n_E;
    params.n_I    = n_I;
    params.W      = W;
    params.W_in   = W_in;
    params.tau_d  = cfg.taud;
    params.n_a_E  = cfg.naE;
    params.n_a_I  = cfg.naI;
    params.tau_a_E = cfg.tauaE;
    params.tau_a_I = cfg.tauaI;
    params.n_b_E  = cfg.nbE;
    params.n_b_I  = cfg.nbI;
    params.c_E    = cfg.cE;
    params.c_I    = cfg.cI;
    params.activation_function = activation_fn;
    params.which_states   = 'x';
    params.include_input  = false;
    params.lambda         = 1e-6;
    params.dt             = dt;

    %% Create ESN and run
    try
        clear_SRNN_persistent();    % reset interpolant cache
        esn = SRNN_ESN(params);
        esn.resetState();

        U = u_full(:);  % column vector (800 x 1)
        [~, Shist] = esn.runReservoir(U);

        %% Extract x-states
        x_all = extract_x_states(Shist, n, n_E, n_I, cfg.naE, cfg.naI, cfg.nbE, cfg.nbI);
        % x_all: (n x T)

    catch ME
        % Simulation failed – mark as fail
        result = fill_failed_result(result, sprintf('sim_error: %s', ME.message));
        return;
    end

    %% Compute metrics
    metrics = compute_reservoir_metrics(x_all, u_full);

    %% Classify
    [passed, recovery_type, fail_reasons] = classify_recovery(metrics);

    %% Pack result
    result.metrics       = metrics;
    result.passed        = passed;
    result.recovery_type = recovery_type;
    result.fail_reasons  = fail_reasons;

    % Store key scalar config values for table export
    result.inputscaling   = cfg.inputscaling;
    result.a0thresh       = cfg.a0thresh;
    result.spectralradius = cfg.spectralradius;
    result.levelofchaos   = cfg.levelofchaos;
    result.cE             = cfg.cE;
    result.taud           = cfg.taud;
end

%% =========================================================================
%  HELPER: extract_x_states
%  =========================================================================
function x_all = extract_x_states(Shist, n, n_E, n_I, naE, naI, nbE, nbI)
% EXTRACT_X_STATES  Pull out x (dendritic) states from full state history.
%   Returns x_all as (n x T).

    len_aE = n_E * naE;
    len_aI = n_I * naI;
    len_bE = n_E * nbE;
    len_bI = n_I * nbI;
    x_start = len_aE + len_aI + len_bE + len_bI + 1;
    x_end   = x_start + n - 1;

    x_all = Shist(:, x_start:x_end)';   % (n x T)
end

%% =========================================================================
%  HELPER: compute_reservoir_metrics
%  =========================================================================
function metrics = compute_reservoir_metrics(x_all, u_full)
% COMPUTE_RESERVOIR_METRICS  Compute all filtering metrics.
%   x_all: (n x T), u_full: (1 x T) or (T x 1)

    T = size(x_all, 2);
    assert(T >= 800, 'Expected at least 800 time steps, got %d', T);

    x_silence1 = x_all(:, 1:200);
    x_chirp    = x_all(:, 201:600);
    x_silence2 = x_all(:, 601:800);

    % 1. Pre-settle level (last 50 steps of silence 1)
    metrics.pre_settle_level = mean(abs(x_silence1(:, end-49:end)), 'all');

    % 2. Chirp response std
    metrics.chirp_response_std = mean(std(x_chirp, 0, 2));

    % 3. Chirp response amplitude
    metrics.chirp_response_amp = mean(max(abs(x_chirp), [], 2));

    % 4. Max absolute value over entire run
    metrics.max_abs_all = max(abs(x_all), [], 'all');

    % 5. Post-stimulus mean absolute (last 50 steps)
    metrics.post_mean_abs = mean(abs(x_silence2(:, end-49:end)), 'all');

    % 6. Post-stimulus std (last 50 steps)
    metrics.post_std = mean(std(x_silence2(:, end-49:end), 0, 2));

    % 7. Recovery ratio
    metrics.recovery_ratio = metrics.post_mean_abs / max(metrics.chirp_response_amp, eps);

    % 8. Recovery slope (early vs late post-stim)
    post_early = mean(abs(x_silence2(:, 1:50)), 'all');
    post_late  = mean(abs(x_silence2(:, 151:200)), 'all');
    metrics.recovery_slope = post_late / max(post_early, eps);

    % 9. Responsiveness: correlation between input chirp and mean reservoir
    u_chirp = u_full(201:600);
    u_chirp = u_chirp(:);
    mean_x_chirp = mean(x_chirp, 1)';  % (400 x 1)
    if std(mean_x_chirp) > 1e-12 && std(u_chirp) > 1e-12
        R = corrcoef(u_chirp, mean_x_chirp);
        metrics.responsiveness_corr = R(1,2);
    else
        metrics.responsiveness_corr = 0;
    end

    % Check for NaN / Inf
    metrics.has_nan_inf = any(~isfinite(x_all(:)));
end

%% =========================================================================
%  HELPER: classify_recovery
%  =========================================================================
function [passed, recovery_type, fail_reasons] = classify_recovery(m)
% CLASSIFY_RECOVERY  Apply the full filtering logic.

    fail_reasons = {};
    passed = true;
    recovery_type = "fail";

    % Handle NaN/Inf
    if m.has_nan_inf
        passed = false;
        fail_reasons{end+1} = 'nan_inf';
        return;
    end

    %% A. Not silent during stimulation
    if m.chirp_response_std <= 0.08
        fail_reasons{end+1} = 'silent_std';
    end
    if m.chirp_response_amp <= 0.15
        fail_reasons{end+1} = 'silent_amp';
    end

    %% B. Not unstable
    if m.max_abs_all >= 15
        fail_reasons{end+1} = 'unstable_max';
    end

    %% D. Settling sanity
    if m.pre_settle_level >= 0.5 * m.chirp_response_amp
        fail_reasons{end+1} = 'transient_dominated';
    end

    %% C. Recovery classification
    % Type 1: background chatter
    type1 = (m.post_mean_abs < 0.25 * m.chirp_response_amp) && ...
            (m.post_std < 0.15 * m.chirp_response_amp) && ...
            (m.recovery_slope < 1.0);

    % Type 2: nearly silent
    type2 = (m.post_mean_abs < 0.05) && (m.post_std < 0.03);

    if type1
        recovery_type = "chatter";
    elseif type2
        recovery_type = "silent";
    else
        fail_reasons{end+1} = 'bad_recovery';
    end

    if ~isempty(fail_reasons)
        passed = false;
        recovery_type = "fail";
    end
end

%% =========================================================================
%  HELPER: fill_failed_result
%  =========================================================================
function result = fill_failed_result(result, reason)
    result.metrics       = struct('pre_settle_level', NaN, ...
                                  'chirp_response_std', NaN, ...
                                  'chirp_response_amp', NaN, ...
                                  'max_abs_all', NaN, ...
                                  'post_mean_abs', NaN, ...
                                  'post_std', NaN, ...
                                  'recovery_ratio', NaN, ...
                                  'recovery_slope', NaN, ...
                                  'responsiveness_corr', NaN, ...
                                  'has_nan_inf', true);
    result.passed        = false;
    result.recovery_type = "fail";
    result.fail_reasons  = {reason};
    result.inputscaling  = NaN;
    result.a0thresh      = NaN;
    result.spectralradius = NaN;
    result.levelofchaos  = NaN;
    result.cE            = NaN;
    result.taud          = NaN;
end

%% =========================================================================
%  HELPER: make_empty_result
%  =========================================================================
function r = make_empty_result(name1, name2)
    r = struct();
    r.param1_name  = name1;
    r.param1_value = NaN;
    r.param2_name  = name2;
    r.param2_value = NaN;
    r.metrics       = struct();
    r.passed        = false;
    r.recovery_type = "fail";
    r.fail_reasons  = {};
    r.inputscaling  = NaN;
    r.a0thresh      = NaN;
    r.spectralradius = NaN;
    r.levelofchaos  = NaN;
    r.cE            = NaN;
    r.taud          = NaN;
end

%% =========================================================================
%  HELPER: collect_viable
%  =========================================================================
function viable = collect_viable(varargin)
% COLLECT_VIABLE  Gather all passed configs across all pairs.
    viable = struct([]);
    for k = 1:nargin
        R = varargin{k};
        for idx = 1:numel(R)
            if R(idx).passed
                if isempty(viable)
                    viable = R(idx);
                else
                    viable(end+1) = R(idx); %#ok<AGROW>
                end
            end
        end
    end
    if isempty(viable)
        viable = struct([]);
    end
end

%% =========================================================================
%  HELPER: plot_pair_heatmaps
%  =========================================================================
function plot_pair_heatmaps(results, name1, vals1, name2, vals2, pair_label, resultsDir)
% PLOT_PAIR_HEATMAPS  Create 2x2 heatmap figure for a parameter pair.

    n1 = numel(vals1);
    n2 = numel(vals2);

    % Extract matrices
    pass_map  = reshape([results.passed], n1, n2);

    chirp_std_map   = NaN(n1, n2);
    rec_ratio_map   = NaN(n1, n2);
    post_mean_map   = NaN(n1, n2);

    for i = 1:n1
        for j = 1:n2
            m = results(i,j).metrics;
            if isstruct(m) && isfield(m, 'chirp_response_std')
                chirp_std_map(i,j) = m.chirp_response_std;
                rec_ratio_map(i,j) = m.recovery_ratio;
                post_mean_map(i,j) = m.post_mean_abs;
            end
        end
    end

    fig = figure('Color', 'w', 'Position', [100 100 1200 900], ...
                 'Name', pair_label);

    % 1. Pass/fail
    subplot(2,2,1);
    imagesc(vals2, vals1, double(pass_map));
    colormap(gca, [0.85 0.2 0.2; 0.2 0.7 0.3]);
    colorbar('Ticks', [0.25, 0.75], 'TickLabels', {'Fail','Pass'});
    xlabel(name2, 'Interpreter', 'none');
    ylabel(name1, 'Interpreter', 'none');
    title([pair_label ': Pass / Fail']);
    set(gca, 'YDir', 'normal');

    % 2. Chirp response std
    subplot(2,2,2);
    imagesc(vals2, vals1, chirp_std_map);
    colormap(gca, parula);
    colorbar;
    xlabel(name2, 'Interpreter', 'none');
    ylabel(name1, 'Interpreter', 'none');
    title([pair_label ': chirp\_response\_std']);
    set(gca, 'YDir', 'normal');

    % 3. Recovery ratio
    subplot(2,2,3);
    h = imagesc(vals2, vals1, rec_ratio_map);
    set(h, 'AlphaData', ~isnan(rec_ratio_map));
    colormap(gca, hot);
    colorbar;
    xlabel(name2, 'Interpreter', 'none');
    ylabel(name1, 'Interpreter', 'none');
    title([pair_label ': recovery\_ratio']);
    set(gca, 'YDir', 'normal');

    % 4. Post mean abs
    subplot(2,2,4);
    h2 = imagesc(vals2, vals1, post_mean_map);
    set(h2, 'AlphaData', ~isnan(post_mean_map));
    colormap(gca, cool);
    colorbar;
    xlabel(name2, 'Interpreter', 'none');
    ylabel(name1, 'Interpreter', 'none');
    title([pair_label ': post\_mean\_abs']);
    set(gca, 'YDir', 'normal');

    sgtitle(pair_label, 'FontSize', 14, 'FontWeight', 'bold');

    % Save figure
    safeName = strrep(lower(pair_label), ' ', '_');
    saveas(fig, fullfile(resultsDir, [safeName '_heatmaps.png']));
    savefig(fig, fullfile(resultsDir, [safeName '_heatmaps.fig']));
    fprintf('  Saved heatmaps for %s\n', pair_label);
end
