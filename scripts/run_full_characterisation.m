%% run_full_characterisation
% Master orchestration script for MESN reservoir characterisation suite.
%
% This script is intentionally modular: toggle flags to run subsets of
% analyses. Many components can be compute-heavy (Lyapunov, sweeps).

clear; clc;

if exist('setup_paths', 'file') == 2
    setup_paths();
end

timestamp = datestr(now, 'yyyymmdd_HHMMSS');
out_dir = fullfile(pwd, 'results', 'characterisation', timestamp);
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

% -------------------------
% Flags
% -------------------------
flags = struct();
flags.stability = true;
flags.esp = true;
flags.memory = true;
flags.kernel_rank = true;
flags.benchmarks = true;
flags.bio = true;
flags.parameter_sweep = false;     % can take long
flags.meanfield_bifurcation = false; % optional (DDE-BIFTOOL or dde23 sweep)

% -------------------------
% Reference config and representative drive
% -------------------------
[params, meta] = default_MESN_config(struct());
esn = SRNN_ESN(params);

dt = params.dt;
T = 4000;
rng(123);
U = 0.2 * randn(T, 1);
t = (0:(T-1))' * dt;

esn.resetState();
[X_feat, S_hist] = esn.runReservoir(U);

save(fullfile(out_dir, 'reference_run.mat'), 'params', 'meta', 'U', 't', 'X_feat', 'S_hist');

results = struct();
results.flags = flags;
results.params = params;

% -------------------------
% Stability / ESP
% -------------------------
if flags.stability
    results.spectral_W = compute_spectral_properties(params.W, params);
end

if flags.esp
    esp_opts = struct('n_ic', 20, 'washout_steps', 500, 'eps_tol', 1e-3, 'ic_scale', 0.1, 'feature_mode', 'x');
    results.esp = verify_echo_state_property(esn, U, esp_opts);
end

% -------------------------
% Memory metrics
% -------------------------
if flags.memory
    mc_opts = struct('T', 5000, 'K_max', 200, 'washout', 200, 'lambda', params.lambda, 'feature_mode', 'x');
    results.memory.MC = compute_memory_capacity(esn, mc_opts);

    nmc_opts = struct('T', 5000, 'K_max', 100, 'washout', 200, 'lambda', params.lambda, ...
        'degrees', [2 3], 'include_cross_terms', false, 'feature_mode', 'x');
    results.memory.NMC = compute_nonlinear_memory_capacity(esn, nmc_opts);

    fisher_opts = struct('K_max', 200, 'washout_steps', 500, 'sample_stride', 10, 'use_states', 'x', 'dt', dt);
    results.memory.Fisher = compute_fisher_memory_curve(esn, U, fisher_opts);

    results.memory.Fisher_fit = fit_memory_decay(results.memory.Fisher.lags, results.memory.Fisher.FI_curve, struct());
    results.memory.MC_fit = fit_memory_decay(results.memory.MC.lags, results.memory.MC.MC_spectrum, struct());
end

% -------------------------
% Kernel Rank / Generalisation Rank
% -------------------------
if flags.kernel_rank
    kr_opts = struct('M', 150, 'L', 200, 'washout', 50, 'input_type', 'binary', 'feature_mode', 'x');
    results.kernel = compute_kernel_rank(esn, kr_opts);
end

% -------------------------
% Benchmarks
% -------------------------
if flags.benchmarks
    results.bench.narma10 = narma_benchmark(esn, struct('order', 10));
    results.bench.narma20 = narma_benchmark(esn, struct('order', 20));
    results.bench.mg = mackey_glass_benchmark(esn, struct('tau', 17, 'do_rollout', true));
    results.bench.lorenz = lorenz_benchmark(esn, struct('obs_noise', 0.0));
    results.bench.counting = stimulus_counting_benchmark(esn, struct());
    results.bench.freq = frequency_discrimination_benchmark(esn, struct('dt', dt));
end

% -------------------------
% Biological coding statistics
% -------------------------
if flags.bio
    results.bio.coding = compute_coding_statistics(esn, S_hist, struct('time_stride', 5));
    results.bio.adapt_std = compute_adaptation_STD_statistics(esn, S_hist, struct('time_stride', 5));
end

% -------------------------
% Optional: parameter sweep and mean-field
% -------------------------
if flags.parameter_sweep
    % Note: run_parameter_sweep.m is a standalone script and may take long.
    run(fullfile(pwd, 'scripts', 'run_parameter_sweep.m'));
end

if flags.meanfield_bifurcation
    run(fullfile(pwd, 'scripts', 'run_bifurcation_meanfield.m'));
end

save(fullfile(out_dir, 'characterisation_results.mat'), 'results');
fprintf('Characterisation complete. Results saved under %s\n', out_dir);

