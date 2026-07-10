function viable_configs = filter_reservoir_params_chirp_recovery()
% FILTER_RESERVOIR_PARAMS_CHIRP_RECOVERY  3-stage hyperparameter search
%
% Stage 1 – GPU-batched coarse sweep  (Latin Hypercube, semi-implicit Euler)
% Stage 2 – CPU-parallel fine sweep   (ode23s, focused on viable region)
% Stage 3 – Multi-seed validation     (robustness check + ranking)
%
% Discard criteria (applied at every stage):
%   1. Silent networks       – no measurable response to chirp stimulation
%   2. Chaotic chatter       – background activity > 5 % of peak output
%   3. Non-decaying networks – activity does not decay after stimulation
%   4. Unstable / diverging  – NaN, Inf, or extreme values

    %% Setup
    setup_paths();

    resultsDir = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
                          'results', 'phase1_filter');
    if ~exist(resultsDir, 'dir'), mkdir(resultsDir); end

    %% Fixed defaults (parameters NOT searched over)
    defaults        = struct();
    defaults.n      = 300;
    defaults.fractionE = 0.5;
    defaults.naE    = 3;
    defaults.naI    = 2;
    defaults.tauaE  = logspace(log10(0.25), log10(25), 3);
    defaults.tauaI  = logspace(log10(0.25), log10(25), 2);
    defaults.nbE    = 0;
    defaults.nbI    = 0;
    defaults.cI     = 0.1;
    defaults.rngseed = 42;
    defaults.dt     = 1.0;

    ranges = define_param_ranges();
    shared = build_shared_reservoir(defaults);

    %% ==================== STAGE 1: GPU Coarse Sweep =====================
    fprintf('\n==============================================================\n');
    fprintf('  STAGE 1: GPU Coarse Sweep  (LHS + semi-implicit Euler)\n');
    fprintf('==============================================================\n');

    N_coarse = 4000;
    configs_coarse = generate_lhs_configs(N_coarse, ranges);
    [u_short, proto_short] = make_chirp_protocol('short');

    tic;
    [s1_passed, s1_fail, s1_metrics] = gpu_batch_euler_screen( ...
        configs_coarse, u_short, proto_short, shared, defaults);
    t1 = toc;

    n_pass1 = sum(s1_passed);
    fprintf('  Stage 1 complete: %d / %d passed  (%.1f s)\n', n_pass1, N_coarse, t1);

    save(fullfile(resultsDir, 'stage1_coarse.mat'), ...
         'configs_coarse', 's1_passed', 's1_fail', 's1_metrics', 'ranges');
    plot_stage_scatter(configs_coarse, s1_passed, ...
                       'Stage 1: Coarse GPU Sweep', resultsDir, 'stage1');

    if n_pass1 == 0
        warning('filter:NoPass1', 'No configurations passed Stage 1.');
        viable_configs = struct([]);
        return;
    end

    %% ==================== STAGE 2: CPU Fine Sweep =======================
    fprintf('\n==============================================================\n');
    fprintf('  STAGE 2: CPU Fine Sweep  (ode23s in viable region)\n');
    fprintf('==============================================================\n');

    fine_ranges = identify_viable_bounds(configs_coarse, s1_passed, ranges);
    N_fine = 3000;
    configs_fine = generate_lhs_configs(N_fine, fine_ranges);
    [u_full, proto_full] = make_chirp_protocol('full');

    poolobj = gcp('nocreate');
    if isempty(poolobj)
        fprintf('  Starting parallel pool...\n');
        parpool;
    end

    tic;
    [s2_passed, s2_fail, s2_metrics] = run_fine_sweep( ...
        configs_fine, u_full, proto_full, shared, defaults);
    t2 = toc;

    n_pass2 = sum(s2_passed);
    fprintf('  Stage 2 complete: %d / %d passed  (%.1f s)\n', n_pass2, N_fine, t2);

    save(fullfile(resultsDir, 'stage2_fine.mat'), ...
         'configs_fine', 's2_passed', 's2_fail', 's2_metrics', 'fine_ranges');
    plot_stage_scatter(configs_fine, s2_passed, ...
                       'Stage 2: Fine CPU Sweep', resultsDir, 'stage2');

    if n_pass2 == 0
        warning('filter:NoPass2', 'No configurations passed Stage 2.');
        viable_configs = configs_coarse(s1_passed);
        return;
    end

    %% ==================== STAGE 3: Multi-seed Validation ================
    fprintf('\n==============================================================\n');
    fprintf('  STAGE 3: Multi-seed Validation & Ranking\n');
    fprintf('==============================================================\n');

    top_K  = min(100, n_pass2);
    top_configs = select_top_configs(configs_fine, s2_passed, s2_metrics, top_K);

    N_seeds = 5;
    tic;
    stage3 = validate_multi_seed(top_configs, u_full, proto_full, ...
                                  N_seeds, defaults);
    t3 = toc;

    n_robust = sum(stage3.robust);
    fprintf('  Stage 3 complete: %d / %d robust across %d seeds  (%.1f s)\n', ...
            n_robust, top_K, N_seeds, t3);

    viable_configs = stage3.ranked_configs;

    save(fullfile(resultsDir, 'stage3_validation.mat'), 'stage3');
    save(fullfile(resultsDir, 'viable_configs.mat'), 'viable_configs');
    plot_stage3_ranking(stage3, resultsDir);

    %% Summary
    fprintf('\n==============================================================\n');
    fprintf('  SUMMARY\n');
    fprintf('==============================================================\n');
    fprintf('  Stage 1 (GPU coarse):  %4d / %d passed   (%.1f s)\n', n_pass1, N_coarse, t1);
    fprintf('  Stage 2 (CPU fine):    %4d / %d passed   (%.1f s)\n', n_pass2, N_fine, t2);
    fprintf('  Stage 3 (validation):  %4d / %d robust   (%.1f s)\n', n_robust, top_K, t3);
    fprintf('  Final viable configs:  %d\n', numel(viable_configs));
    fprintf('  Total time:            %.1f s\n', t1 + t2 + t3);
    fprintf('  Results saved to:      %s\n', resultsDir);
    fprintf('==============================================================\n');
end

%% ========================================================================
%  PARAMETER RANGES
%  ========================================================================
function ranges = define_param_ranges()
    ranges = struct();
    ranges.inputscaling   = struct('lo', 0.05,  'hi', 5.0,   'logscale', false);
    ranges.a0thresh       = struct('lo', 0.05,  'hi', 0.99,  'logscale', false);
    ranges.spectralradius = struct('lo', 0.1,   'hi', 2.5,   'logscale', false);
    ranges.levelofchaos   = struct('lo', 0.3,   'hi', 4.0,   'logscale', false);
    ranges.cE             = struct('lo', 0.001, 'hi', 1.0,   'logscale', true);
    ranges.taud           = struct('lo', 0.01,  'hi', 3.0,   'logscale', true);
end

%% ========================================================================
%  SHARED RESERVOIR (pre-compute W0 normalised + W_in0 unscaled)
%  ========================================================================
function shared = build_shared_reservoir(defaults, seed)
    if nargin < 2, seed = defaults.rngseed; end

    n   = defaults.n;
    n_E = round(n * defaults.fractionE);
    n_I = n - n_E;

    rng(seed);
    W0 = randn(n, n);
    W0(:, 1:n_E)     = abs(W0(:, 1:n_E));
    W0(:, n_E+1:end) = -abs(W0(:, n_E+1:end));
    W0 = W0 - mean(W0, 2);

    rho0    = max(abs(eig(W0)));
    W0_norm = W0 / max(rho0, eps);

    rng(seed + 1);
    W_in0 = 2*rand(n, 1) - 1;
    W_in0(rand(n, 1) > 0.2) = 0;

    shared = struct('W0_norm', W0_norm, 'W_in0', W_in0, ...
                    'n', n, 'n_E', n_E, 'n_I', n_I, ...
                    'naE', defaults.naE, 'naI', defaults.naI, ...
                    'tauaE', defaults.tauaE, 'tauaI', defaults.tauaI);
end

%% ========================================================================
%  LATIN HYPERCUBE CONFIG GENERATOR
%  ========================================================================
function configs = generate_lhs_configs(N, ranges)
    pnames   = fieldnames(ranges);
    n_params = numel(pnames);

    X = lhsdesign(N, n_params, 'Criterion', 'maximin', 'Iterations', 30);

    vals = zeros(N, n_params);
    for i = 1:n_params
        r = ranges.(pnames{i});
        if r.logscale
            vals(:,i) = 10.^(log10(r.lo) + X(:,i) * (log10(r.hi) - log10(r.lo)));
        else
            vals(:,i) = r.lo + X(:,i) * (r.hi - r.lo);
        end
    end

    configs = repmat(struct(), 1, N);
    for i = 1:n_params
        v = num2cell(vals(:,i));
        [configs.(pnames{i})] = v{:};
    end
end

%% ========================================================================
%  CHIRP PROTOCOL
%  ========================================================================
function [u_full, protocol] = make_chirp_protocol(mode)
    switch lower(mode)
        case 'short'
            T1 = 100;  T2 = 200;  T3 = 100;
        case 'full'
            T1 = 200;  T2 = 400;  T3 = 200;
        otherwise
            error('Unknown protocol mode: %s', mode);
    end

    t_chirp   = 0:(T2-1);
    f_start   = 0.05;   f_end   = 2.0;
    amp_start = 0.5;     amp_end = 3.0;
    amp_t   = amp_start + (amp_end - amp_start) * (t_chirp / max(T2-1,1));
    phase_t = 2*pi*(f_start*t_chirp + (f_end - f_start) * t_chirp.^2 / (2*T2));
    u_chirp = amp_t .* sin(phase_t);

    u_full = [zeros(1,T1), u_chirp, zeros(1,T3)];

    protocol.T_silence1 = T1;
    protocol.T_chirp    = T2;
    protocol.T_silence2 = T3;
    protocol.T_total    = T1 + T2 + T3;
    protocol.dt         = 1.0;
    protocol.tu         = 0:(protocol.T_total - 1);
end

%% ========================================================================
%  STAGE 1 – GPU-BATCHED SEMI-IMPLICIT EULER SCREEN
%  ========================================================================
function [passed, fail_reasons, metrics] = gpu_batch_euler_screen( ...
        configs, u_full, protocol, shared, defaults)

    N = numel(configs);
    batch_sz = 4096;

    use_gpu = false;
    try
        gd = gpuDevice;
        if gd.DeviceAvailable
            use_gpu = true;
            fprintf('  GPU: %s  (%.1f GB free)\n', gd.Name, gd.AvailableMemory/1e9);
        end
    catch
    end
    if ~use_gpu
        fprintf('  No GPU detected – falling back to CPU vectorised screening.\n');
    end

    W0_dev    = to_dev(shared.W0_norm, use_gpu);
    W_in0_dev = to_dev(shared.W_in0,   use_gpu);
    u_dev     = to_dev(u_full(:)',      use_gpu);
    tau_aE_3d = reshape(to_dev(shared.tauaE, use_gpu), 1, shared.naE, 1);
    tau_aI_3d = reshape(to_dev(shared.tauaI, use_gpu), 1, shared.naI, 1);

    n = shared.n;  n_E = shared.n_E;  n_I = shared.n_I;
    naE = shared.naE;  naI = shared.naI;
    cI_s = single(defaults.cI);
    S_c  = single(0.4);
    dt_s = single(protocol.dt);
    T1 = protocol.T_silence1;
    T2 = protocol.T_chirp;
    T3 = protocol.T_silence2;

    all_is = [configs.inputscaling];
    all_a0 = [configs.a0thresh];
    all_sr = [configs.spectralradius];
    all_lc = [configs.levelofchaos];
    all_cE = [configs.cE];
    all_td = [configs.taud];

    passed       = false(1, N);
    fail_reasons = cell(1, N);
    metrics      = struct( ...
        'pre_settle_level',   nan(1, N), ...
        'chirp_response_std', nan(1, N), ...
        'chirp_response_amp', nan(1, N), ...
        'max_abs_all',        nan(1, N), ...
        'post_mean_abs',      nan(1, N), ...
        'recovery_slope',     nan(1, N));

    for bs = 1:batch_sz:N
        be  = min(bs + batch_sz - 1, N);
        B   = be - bs + 1;
        idx = bs:be;
        fprintf('    Batch %d – %d / %d ... ', bs, be, N);

        w_sc  = to_dev(all_sr(idx) .* all_lc(idx), use_gpu);
        S_a   = to_dev(all_a0(idx), use_gpu);
        c_E_b = to_dev(all_cE(idx), use_gpu);
        td_b  = to_dev(all_td(idx), use_gpu);
        W_in_b = W_in0_dev .* to_dev(all_is(idx), use_gpu);

        x   = zeros(n,   B,           'like', W0_dev);
        a_E = zeros(n_E, naE, B,      'like', W0_dev);
        a_I = zeros(n_I, naI, B,      'like', W0_dev);

        % ---- Phase 1: pre-stimulus silence ----
        settle_n   = min(50, T1);
        settle_sum = zeros(1, B, 'like', W0_dev);
        max_p1     = zeros(1, B, 'like', W0_dev);

        for t = 1:T1
            [x, a_E, a_I] = euler_step_batch(x, a_E, a_I, single(0), ...
                W0_dev, W_in_b, w_sc, S_a, S_c, c_E_b, cI_s, ...
                td_b, tau_aE_3d, tau_aI_3d, n_E, n_I, dt_s);
            max_p1 = max(max_p1, max(abs(x), [], 1));
            if t > T1 - settle_n
                settle_sum = settle_sum + mean(abs(x), 1);
            end
        end
        pre_settle = settle_sum / settle_n;

        % ---- Phase 2: chirp stimulation ----
        cnt    = single(0);
        mu_x   = zeros(n, B, 'like', W0_dev);
        M2_x   = zeros(n, B, 'like', W0_dev);
        max_ch = zeros(1, B, 'like', W0_dev);

        for t = 1:T2
            u_t = u_dev(T1 + t);
            [x, a_E, a_I] = euler_step_batch(x, a_E, a_I, u_t, ...
                W0_dev, W_in_b, w_sc, S_a, S_c, c_E_b, cI_s, ...
                td_b, tau_aE_3d, tau_aI_3d, n_E, n_I, dt_s);
            cnt   = cnt + 1;
            d1    = x - mu_x;
            mu_x  = mu_x + d1 / cnt;
            d2    = x - mu_x;
            M2_x  = M2_x + d1 .* d2;
            max_ch = max(max_ch, max(abs(x), [], 1));
        end
        c_std = mean(sqrt(M2_x / max(cnt - 1, 1)), 1);
        c_amp = max_ch;

        % ---- Phase 3: post-stimulus silence ----
        T3h     = max(round(T3 / 2), 1);
        e_sum   = zeros(1, B, 'like', W0_dev);
        l_sum   = zeros(1, B, 'like', W0_dev);
        max_p3  = zeros(1, B, 'like', W0_dev);

        for t = 1:T3
            [x, a_E, a_I] = euler_step_batch(x, a_E, a_I, single(0), ...
                W0_dev, W_in_b, w_sc, S_a, S_c, c_E_b, cI_s, ...
                td_b, tau_aE_3d, tau_aI_3d, n_E, n_I, dt_s);
            ma = mean(abs(x), 1);
            if t <= T3h
                e_sum = e_sum + ma;
            else
                l_sum = l_sum + ma;
            end
            max_p3 = max(max_p3, max(abs(x), [], 1));
        end
        post_early = e_sum / T3h;
        post_late  = l_sum / max(T3 - T3h, 1);

        % ---- Classification ----
        max_all = max(max(max_p1, max_ch), max_p3);
        g_nan   = any(isnan(x), 1);

        is_silent     = (c_amp < 0.05) | (c_std < 0.02);
        has_chatter   = (post_late > 0.05 * max_all) | (pre_settle > 0.05 * max_all);
        rec_sl        = post_late ./ max(post_early, single(1e-6));
        no_decay      = rec_sl >= 1.0;
        is_unstable   = max_all > 15;

        bp = gather(~g_nan & ~is_silent & ~has_chatter & ~no_decay & ~is_unstable);

        g_pre  = double(gather(pre_settle));
        g_cstd = double(gather(c_std));
        g_camp = double(gather(c_amp));
        g_max  = double(gather(max_all));
        g_post = double(gather(post_late));
        g_rsl  = double(gather(rec_sl));

        g_nan_c = gather(g_nan);
        g_sil   = gather(is_silent);
        g_cht   = gather(has_chatter);
        g_ndc   = gather(no_decay);
        g_ust   = gather(is_unstable);

        passed(idx) = bp;
        metrics.pre_settle_level(idx)   = g_pre;
        metrics.chirp_response_std(idx) = g_cstd;
        metrics.chirp_response_amp(idx) = g_camp;
        metrics.max_abs_all(idx)        = g_max;
        metrics.post_mean_abs(idx)      = g_post;
        metrics.recovery_slope(idx)     = g_rsl;

        for k = 1:B
            reasons = {};
            if g_nan_c(k), reasons{end+1} = 'nan_inf';          end %#ok<AGROW>
            if g_sil(k),   reasons{end+1} = 'silent';           end %#ok<AGROW>
            if g_cht(k),   reasons{end+1} = 'chatter_gt_5pct';  end %#ok<AGROW>
            if g_ndc(k),   reasons{end+1} = 'no_decay';         end %#ok<AGROW>
            if g_ust(k),   reasons{end+1} = 'unstable';         end %#ok<AGROW>
            fail_reasons{idx(k)} = reasons;
        end
        fprintf('%d passed\n', sum(bp));
    end
end

%% ========================================================================
%  BATCHED SEMI-IMPLICIT EULER STEP  (GPU or CPU)
%  ========================================================================
function [x, a_E, a_I] = euler_step_batch(x, a_E, a_I, u_scalar, ...
        W0, W_in_b, w_sc, S_a, S_c, c_E_b, cI, tau_d, ...
        tau_aE, tau_aI, n_E, n_I, dt)
    B = size(x, 2);

    x_eff = x;
    if ~isempty(a_E)
        sa = reshape(sum(a_E, 2), n_E, B);
        x_eff(1:n_E, :) = x_eff(1:n_E, :) - c_E_b .* sa;
    end
    if ~isempty(a_I)
        sa = reshape(sum(a_I, 2), n_I, B);
        x_eff(n_E+1:end, :) = x_eff(n_E+1:end, :) - cI .* sa;
    end

    r   = piecewise_sigmoid_batch(x_eff, S_a, S_c);
    Wr  = w_sc .* (W0 * r);
    u_e = W_in_b * u_scalar;

    x = (x + dt * (Wr + u_e) ./ tau_d) ./ (1 + dt ./ tau_d);

    if ~isempty(a_E)
        rE = reshape(r(1:n_E, :), n_E, 1, B);
        a_E = (a_E + dt * rE ./ tau_aE) ./ (1 + dt ./ tau_aE);
    end
    if ~isempty(a_I)
        rI = reshape(r(n_E+1:end, :), n_I, 1, B);
        a_I = (a_I + dt * rI ./ tau_aI) ./ (1 + dt ./ tau_aI);
    end
end

%% ========================================================================
%  BATCHED PIECEWISE SIGMOID  (branch-free, GPU-compatible)
%  ========================================================================
function y = piecewise_sigmoid_batch(x, S_a, S_c)
% x: (n,B),  S_a: (1,B) or scalar,  S_c: scalar
    a  = S_a / 2;
    k  = single(0.5) ./ max(1 - 2*a, single(1e-6));
    x1 = S_c + a - 1;
    x2 = S_c - a;
    x3 = S_c + a;
    x4 = S_c + 1 - a;

    m_lq = (x >= x1) & (x < x2);
    m_li = (x >= x2) & (x <= x3);
    m_rq = (x > x3)  & (x <= x4);
    m_rs = (x > x4);

    y = m_lq .* (k .* (x - x1).^2) ...
      + m_li .* ((x - S_c) + single(0.5)) ...
      + m_rq .* (1 - k .* (x - x4).^2) ...
      + single(1) .* m_rs;
end

%% ========================================================================
%  IDENTIFY VIABLE BOUNDS FROM STAGE 1
%  ========================================================================
function fine = identify_viable_bounds(configs, passed, orig)
    pnames = fieldnames(orig);
    pass_idx = find(passed);

    fine = struct();
    for i = 1:numel(pnames)
        p  = pnames{i};
        ro = orig.(p);
        if isempty(pass_idx)
            fine.(p) = ro;
            continue;
        end
        vals = [configs(pass_idx).(p)];
        lo = min(vals);  hi = max(vals);
        span   = hi - lo;
        margin = 0.15 * span;

        % Guarantee a minimum width of 20 % of the original range
        orig_span = ro.hi - ro.lo;
        if ro.logscale
            orig_span = log10(ro.hi) - log10(ro.lo);
        end
        if ro.logscale
            lo_log = log10(lo) - 0.15*(log10(hi)-log10(lo));
            hi_log = log10(hi) + 0.15*(log10(hi)-log10(lo));
            if (hi_log - lo_log) < 0.20 * orig_span
                centre = (log10(lo)+log10(hi)) / 2;
                half   = 0.10 * orig_span;
                lo_log = centre - half;
                hi_log = centre + half;
            end
            fine.(p) = struct('lo', max(10^lo_log, ro.lo), ...
                              'hi', min(10^hi_log, ro.hi), ...
                              'logscale', true);
        else
            lo2 = lo - margin;
            hi2 = hi + margin;
            if (hi2 - lo2) < 0.20 * orig_span
                centre = (lo + hi) / 2;
                half   = 0.10 * orig_span;
                lo2 = centre - half;
                hi2 = centre + half;
            end
            fine.(p) = struct('lo', max(lo2, ro.lo), ...
                              'hi', min(hi2, ro.hi), ...
                              'logscale', false);
        end
    end
end

%% ========================================================================
%  STAGE 2 – CPU FINE SWEEP  (parfor + ode23s)
%  ========================================================================
function [passed, fail_reasons, metrics_cells] = run_fine_sweep( ...
        configs, u_full, protocol, shared, defaults)

    N  = numel(configs);
    tu = protocol.tu;
    dt = protocol.dt;

    tmp_passed = false(1, N);
    tmp_fail   = cell(1, N);
    tmp_met    = cell(1, N);

    fprintf('  Running %d configs with parfor + ode23s ...\n', N);
    parfor k = 1:N
        r = run_single_config_ode(configs(k), u_full, tu, dt, shared, defaults);
        tmp_passed(k) = r.passed;
        tmp_fail{k}   = r.fail_reasons;
        tmp_met{k}    = r.metrics;
    end

    passed       = tmp_passed;
    fail_reasons = tmp_fail;
    metrics_cells = tmp_met;
end

%% ========================================================================
%  SINGLE CONFIG – FULL ODE23s SIMULATION
%  ========================================================================
function result = run_single_config_ode(cfg, u_full, tu, dt, shared, defaults)
    n   = shared.n;
    n_E = shared.n_E;
    n_I = shared.n_I;

    W    = cfg.spectralradius * cfg.levelofchaos * shared.W0_norm;
    W_in = shared.W_in0 * cfg.inputscaling;

    S_a = cfg.a0thresh;
    S_c = 0.4;
    activation_fn = @(x) piecewiseSigmoid(x, S_a, S_c);

    params              = struct();
    params.n            = n;
    params.n_E          = n_E;
    params.n_I          = n_I;
    params.E_indices    = 1:n_E;
    params.I_indices    = (n_E+1):n;
    params.W            = W;
    params.W_in         = W_in;
    params.tau_d        = cfg.taud;
    params.n_a_E        = defaults.naE;
    params.n_a_I        = defaults.naI;
    params.tau_a_E      = defaults.tauaE;
    params.tau_a_I      = defaults.tauaI;
    params.n_b_E        = defaults.nbE;
    params.n_b_I        = defaults.nbI;
    params.c_E          = cfg.cE;
    params.c_I          = defaults.cI;
    params.activation_function = activation_fn;
    params.which_states = 'x';
    params.include_input = false;
    params.lambda       = 1e-6;
    params.dt           = dt;

    result = struct('passed', false, 'fail_reasons', {{}}, ...
                    'metrics', struct(), 'quality_score', 0, ...
                    'config', cfg);
    try
        esn = SRNN_ESN(params);
        esn.resetState();
        U = u_full(:);
        [~, Shist] = esn.runReservoir(U);
        x_all = extract_x_states(Shist, n, n_E, n_I, ...
                    defaults.naE, defaults.naI, defaults.nbE, defaults.nbI);
    catch ME
        result.fail_reasons = {sprintf('sim_error: %s', ME.message)};
        result.metrics = empty_metrics();
        return;
    end

    m = compute_reservoir_metrics(x_all, u_full);
    [p, reasons] = classify_recovery(m);

    result.passed        = p;
    result.fail_reasons  = reasons;
    result.metrics       = m;
    result.quality_score = compute_quality_score(m);
end

%% ========================================================================
%  EXTRACT x-STATES FROM FULL STATE HISTORY
%  ========================================================================
function x_all = extract_x_states(Shist, n, n_E, n_I, naE, naI, nbE, nbI)
    offset = n_E*naE + n_I*naI + n_E*nbE + n_I*nbI;
    x_all  = Shist(:, offset+1 : offset+n)';
end

%% ========================================================================
%  RESERVOIR METRICS (full protocol)
%  ========================================================================
function m = compute_reservoir_metrics(x_all, u_full)
    T = size(x_all, 2);
    assert(T >= 800, 'Expected >= 800 time steps, got %d', T);

    x_s1 = x_all(:, 1:200);
    x_ch = x_all(:, 201:600);
    x_s2 = x_all(:, 601:800);

    m.pre_settle_level   = mean(abs(x_s1(:, end-49:end)), 'all');
    m.chirp_response_std = mean(std(x_ch, 0, 2));
    m.chirp_response_amp = mean(max(abs(x_ch), [], 2));
    m.max_abs_all        = max(abs(x_all), [], 'all');
    m.post_mean_abs      = mean(abs(x_s2(:, end-49:end)), 'all');
    m.post_std           = mean(std(x_s2(:, end-49:end), 0, 2));
    m.recovery_ratio     = m.post_mean_abs / max(m.chirp_response_amp, eps);

    post_early = mean(abs(x_s2(:, 1:50)),    'all');
    post_late  = mean(abs(x_s2(:, 151:200)), 'all');
    m.recovery_slope = post_late / max(post_early, eps);

    u_ch = u_full(201:600);  u_ch = u_ch(:);
    mean_xch = mean(x_ch, 1)';
    if std(mean_xch) > 1e-12 && std(u_ch) > 1e-12
        R = corrcoef(u_ch, mean_xch);
        m.responsiveness_corr = R(1,2);
    else
        m.responsiveness_corr = 0;
    end
    m.has_nan_inf = any(~isfinite(x_all(:)));
end

%% ========================================================================
%  CLASSIFY RECOVERY  (updated 5 % chatter rule)
%  ========================================================================
function [passed, fail_reasons] = classify_recovery(m)
    fail_reasons = {};
    if m.has_nan_inf
        passed = false;
        fail_reasons = {'nan_inf'};
        return;
    end

    % A. Silent during stimulation
    if m.chirp_response_std <= 0.05
        fail_reasons{end+1} = 'silent_std';
    end
    if m.chirp_response_amp <= 0.10
        fail_reasons{end+1} = 'silent_amp';
    end

    % B. Unstable
    if m.max_abs_all >= 15
        fail_reasons{end+1} = 'unstable';
    end

    % C. Pre-stimulus chatter exceeds 5 % of peak output
    if m.pre_settle_level > 0.05 * m.max_abs_all
        fail_reasons{end+1} = 'pre_chatter_gt_5pct';
    end

    % D. Post-stimulus chatter exceeds 5 % of peak output
    if m.post_mean_abs > 0.05 * m.max_abs_all
        fail_reasons{end+1} = 'post_chatter_gt_5pct';
    end

    % E. Does not decay after stimulation
    if m.recovery_slope >= 1.0
        fail_reasons{end+1} = 'no_decay';
    end

    passed = isempty(fail_reasons);
end

%% ========================================================================
%  QUALITY SCORE  (higher = better)
%  ========================================================================
function s = compute_quality_score(m)
    if ~isstruct(m) || ~isfield(m, 'has_nan_inf') || m.has_nan_inf
        s = 0; return;
    end
    resp  = abs(m.responsiveness_corr);
    recov = max(1 - m.recovery_ratio, 0);
    amp   = min(m.chirp_response_amp / 5, 1);
    s     = resp * recov * amp;
    if ~isfinite(s), s = 0; end
end

%% ========================================================================
%  SELECT TOP CONFIGS FROM STAGE 2
%  ========================================================================
function top = select_top_configs(configs, passed, metrics_cells, K)
    pidx   = find(passed);
    scores = zeros(size(pidx));
    for i = 1:numel(pidx)
        scores(i) = compute_quality_score(metrics_cells{pidx(i)});
    end
    [~, ord] = sort(scores, 'descend');
    K = min(K, numel(ord));
    sel = pidx(ord(1:K));
    top = configs(sel);
end

%% ========================================================================
%  STAGE 3 – MULTI-SEED VALIDATION
%  ========================================================================
function s3 = validate_multi_seed(top_configs, u_full, protocol, N_seeds, defaults)
    K     = numel(top_configs);
    seeds = defaults.rngseed + (0:N_seeds-1) * 1000;
    tu    = protocol.tu;
    dt    = protocol.dt;

    shared_all = cell(1, N_seeds);
    for s = 1:N_seeds
        shared_all{s} = build_shared_reservoir(defaults, seeds(s));
    end

    total   = K * N_seeds;
    flat_p  = false(1, total);
    flat_sc = zeros(1, total);

    fprintf('  Validating %d configs x %d seeds = %d runs ...\n', K, N_seeds, total);
    parfor fi = 1:total
        [ki, si] = ind2sub([K, N_seeds], fi);
        r = run_single_config_ode(top_configs(ki), u_full, tu, dt, ...
                                   shared_all{si}, defaults);
        flat_p(fi)  = r.passed;
        flat_sc(fi) = r.quality_score;
    end

    seed_passed = reshape(flat_p,  K, N_seeds);
    seed_scores = reshape(flat_sc, K, N_seeds);

    robust      = all(seed_passed, 2);
    mean_scores = mean(seed_scores, 2);

    [sorted_ms, ord] = sort(mean_scores, 'descend');

    ranked = struct([]);
    for i = 1:K
        ki = ord(i);
        c  = top_configs(ki);
        entry = struct('inputscaling',   c.inputscaling, ...
                        'a0thresh',       c.a0thresh, ...
                        'spectralradius', c.spectralradius, ...
                        'levelofchaos',   c.levelofchaos, ...
                        'cE',             c.cE, ...
                        'taud',           c.taud, ...
                        'quality_score',  sorted_ms(i), ...
                        'robustness',     mean(seed_passed(ki,:)), ...
                        'rank',           i);
        if isempty(ranked)
            ranked = entry;
        else
            ranked(end+1) = entry; %#ok<AGROW>
        end
    end

    s3 = struct('configs', {top_configs}, ...
                'seed_passed',  seed_passed, ...
                'seed_scores',  seed_scores, ...
                'robust',       robust, ...
                'mean_scores',  mean_scores, ...
                'ranked_configs', ranked, ...
                'seeds',        seeds);
end

%% ========================================================================
%  EMPTY METRICS STUB  (for failed simulations)
%  ========================================================================
function m = empty_metrics()
    m = struct('pre_settle_level', NaN, 'chirp_response_std', NaN, ...
               'chirp_response_amp', NaN, 'max_abs_all', NaN, ...
               'post_mean_abs', NaN, 'post_std', NaN, ...
               'recovery_ratio', NaN, 'recovery_slope', NaN, ...
               'responsiveness_corr', NaN, 'has_nan_inf', true);
end

%% ========================================================================
%  PLOTTING – CORNER SCATTER (Stages 1 & 2)
%  ========================================================================
function plot_stage_scatter(configs, passed, fig_title, resultsDir, prefix)
    pnames = {'inputscaling','a0thresh','spectralradius','levelofchaos','cE','taud'};
    np = numel(pnames);

    vals = zeros(numel(configs), np);
    for i = 1:np
        vals(:, i) = [configs.(pnames{i})];
    end

    pidx = find(passed);
    fidx = find(~passed);
    max_fail = 800;
    if numel(fidx) > max_fail
        fidx = fidx(randperm(numel(fidx), max_fail));
    end

    fig = figure('Color','w','Position',[50 50 1400 1200],'Name',fig_title);
    for r = 1:np
        for c = 1:np
            subplot(np, np, (r-1)*np + c);
            if r == c
                histogram(vals(pidx, r), 20, 'FaceColor', [0.1 0.7 0.2], ...
                    'FaceAlpha', 0.6, 'EdgeColor', 'none');
                hold on;
                histogram(vals(:, r), 40, 'FaceColor', [0.6 0.6 0.6], ...
                    'FaceAlpha', 0.2, 'EdgeColor', 'none');
                hold off;
                if r == 1, ylabel('count','FontSize',6); end
                title(strrep(pnames{r},'_','\_'),'FontSize',7);
            elseif r > c
                scatter(vals(fidx, c), vals(fidx, r), 3, ...
                    [0.78 0.22 0.22], '.', 'MarkerEdgeAlpha', 0.12);
                hold on;
                scatter(vals(pidx, c), vals(pidx, r), 10, ...
                    [0.1 0.7 0.2], 'filled', 'MarkerFaceAlpha', 0.55);
                hold off;
            else
                axis off; continue;
            end
            set(gca, 'FontSize', 5);
            if r == np, xlabel(strrep(pnames{c},'_','\_'),'FontSize',6); end
            if c == 1 && r ~= c, ylabel(strrep(pnames{r},'_','\_'),'FontSize',6); end
        end
    end
    sgtitle(sprintf('%s  (%d/%d pass)', fig_title, numel(pidx), numel(configs)), ...
            'FontSize', 12, 'FontWeight', 'bold');
    saveas(fig, fullfile(resultsDir, [prefix '_corner.png']));
    savefig(fig, fullfile(resultsDir, [prefix '_corner.fig']));
end

%% ========================================================================
%  PLOTTING – STAGE 3 RANKING BAR CHART
%  ========================================================================
function plot_stage3_ranking(s3, resultsDir)
    rc  = s3.ranked_configs;
    K   = min(30, numel(rc));

    scores = [rc(1:K).quality_score];
    robust = [rc(1:K).robustness];

    fig = figure('Color', 'w', 'Position', [100 100 900 500], ...
                 'Name', 'Stage 3 Ranking');
    b = barh(1:K, scores, 'FaceColor', 'flat');

    cmap = zeros(K, 3);
    for i = 1:K
        frac = robust(i);
        cmap(i,:) = frac * [0.1 0.75 0.2] + (1-frac) * [0.85 0.2 0.15];
    end
    b.CData = cmap;

    set(gca, 'YDir', 'reverse', 'FontSize', 8);
    xlabel('Mean quality score');
    ylabel('Rank');
    title(sprintf('Top %d configs  (green = robust, red = fragile)', K));
    ylim([0.5 K+0.5]);

    saveas(fig, fullfile(resultsDir, 'stage3_ranking.png'));
    savefig(fig, fullfile(resultsDir, 'stage3_ranking.fig'));
end

%% ========================================================================
%  UTILITY – move array to device (single precision)
%  ========================================================================
function arr = to_dev(arr, use_gpu)
    arr = single(arr);
    if use_gpu, arr = gpuArray(arr); end
end
