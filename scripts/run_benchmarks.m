%% run_benchmarks
% Task-performance benchmarks for the MESN reservoir with a ridge readout,
% comparing adaptation ON vs OFF (Result 5 of the paper workplan).
%
% The reservoir is trained ONLY on the linear readout (the recurrent weights
% are fixed) -- this is the "learning is local, the ESN learns only on the
% edges" biological-plausibility point. Running the same benchmarks with
% adaptation (SFA + STD) enabled vs disabled quantifies "what adaptation adds
% to the network".
%
% Benchmarks: NARMA-10, NARMA-20, Mackey-Glass (one-step + rollout), Lorenz-63.
%
% Output: results/benchmarks/benchmarks_<timestamp>.mat + comparison figure.

%clear; clc;

if exist('setup_paths', 'file') == 2
    setup_paths();
end

out_dir = fullfile(pwd, 'results', 'benchmarks');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

timestamp = datestr(now, 'yyyymmdd_HHMMSS');
dt = 0.1;

%% Two configurations: adaptation ON (full biology) vs OFF (plain reservoir)
configs = struct();
configs(1).name = 'adapt_ON';
configs(1).overrides = struct('dt', dt);
configs(2).name = 'adapt_OFF';
configs(2).overrides = struct('dt', dt, 'c_E', 0, 'c_I', 0, 'n_b_E', 0, 'n_b_I', 0);

bench_names = {'narma10', 'narma20', 'mackeyglass', 'lorenz'};
summary = struct();

for ci = 1:numel(configs)
    name = configs(ci).name;
    params = default_MESN_config(configs(ci).overrides);
    esn = SRNN_ESN(params);

    fprintf('\n=========== Config: %s ===========\n', name);

    b = struct();
    b.narma10 = narma_benchmark(esn, struct('order', 10));
    b.narma20 = narma_benchmark(esn, struct('order', 20));
    b.mackeyglass = mackey_glass_benchmark(esn, struct('tau', 17, 'do_rollout', true));
    b.lorenz = lorenz_benchmark(esn, struct('obs_noise', 0.0));

    summary.(name) = b;

    % Report test NRMSE
    for k = 1:numel(bench_names)
        bn = bench_names{k};
        fprintf('  %-12s test NRMSE = %.4f\n', bn, b.(bn).metrics_test.nrmse);
    end
    if isfield(b.mackeyglass, 'rollout')
        fprintf('  mackeyglass rollout NRMSE = %.4f\n', b.mackeyglass.rollout.metrics.nrmse);
    end
end

%% Collect test NRMSE into a comparison matrix
nrmse_on = zeros(numel(bench_names), 1);
nrmse_off = zeros(numel(bench_names), 1);
for k = 1:numel(bench_names)
    nrmse_on(k)  = summary.adapt_ON.(bench_names{k}).metrics_test.nrmse;
    nrmse_off(k) = summary.adapt_OFF.(bench_names{k}).metrics_test.nrmse;
end

%% Save
save_path = fullfile(out_dir, sprintf('benchmarks_%s.mat', timestamp));
save(save_path, 'summary', 'bench_names', 'nrmse_on', 'nrmse_off', 'configs');

%% Figure: test NRMSE, adaptation ON vs OFF (lower is better)
figure('Color', 'w');
bar([nrmse_on, nrmse_off]);
set(gca, 'XTickLabel', bench_names);
ylabel('test NRMSE (lower is better)');
legend({'adaptation ON', 'adaptation OFF'}, 'Location', 'best');
title('What adaptation adds: benchmark performance (ridge readout only)');
grid on;

fprintf('\nSaved benchmark results to %s\n', save_path);
