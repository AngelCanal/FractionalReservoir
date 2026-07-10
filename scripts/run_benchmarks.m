%% run_benchmarks
% Task-performance benchmarks for the MESN reservoir with a ridge readout,
% comparing adaptation ON vs OFF (Result 5 of the paper workplan).
%
% Uses standardized chronological train/validation/test splits via
% trainReadout, held-out test prediction with known train+val context, and
% named baselines. Never tunes on test metrics.
%
% Benchmarks: NARMA-10, NARMA-20, Mackey-Glass (one-step + rollout), Lorenz-63,
% frequency discrimination, stimulus counting.
%
% Output: results/benchmarks/benchmarks_<timestamp>.mat + comparison figure.

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

common_opts = struct('train_ratio', 0.6, 'val_ratio', 0.2, 'washout_steps', 200, 'seed', 1);

bench_names = {'narma10', 'narma20', 'mackeyglass', 'lorenz', 'frequency', 'counting'};
summary = struct();

for ci = 1:numel(configs)
    name = configs(ci).name;
    params = default_MESN_config(configs(ci).overrides);
    esn = SRNN_ESN(params);

    fprintf('\n=========== Config: %s ===========\n', name);

    b = struct();
    b.narma10 = narma_benchmark(esn, merge_opts(common_opts, struct('order', 10)));
    b.narma20 = narma_benchmark(esn, merge_opts(common_opts, struct('order', 20)));
    b.mackeyglass = mackey_glass_benchmark(esn, merge_opts(common_opts, struct('tau', 17, 'do_rollout', true)));
    b.lorenz = lorenz_benchmark(esn, merge_opts(common_opts, struct('obs_noise', 0.0)));
    b.frequency = frequency_discrimination_benchmark(esn, merge_opts(common_opts, struct('dt', dt)));
    b.counting = stimulus_counting_benchmark(esn, common_opts);

    summary.(name) = b;

    for k = 1:numel(bench_names)
        bn = bench_names{k};
        bb = b.(bn);
        fprintf('  %-12s status=%s  prediction_mode=%s  lambda=%.3g\n', ...
            bn, bb.status, bb.prediction_mode, bb.selected_lambda);
        fprintf('             split after washout: train=%d val=%d test=%d\n', ...
            bb.split.n_train_after_washout, bb.split.n_val, bb.split.n_test);
        if isfield(bb.metrics_test, 'nrmse')
            fprintf('             test NRMSE=%.4f', bb.metrics_test.nrmse);
            if isfield(bb, 'baselines') && isfield(bb.baselines, 'persistence')
                fprintf('  (persist=%.4f, linAR=%.4f)', ...
                    bb.baselines.persistence.metrics_test.nrmse, ...
                    bb.baselines.linear_ar.metrics_test.nrmse);
            elseif isfield(bb, 'baselines') && isfield(bb.baselines, 'target_mean')
                fprintf('  (mean=%.4f, linAR=%.4f)', ...
                    bb.baselines.target_mean.metrics_test.nrmse, ...
                    bb.baselines.linear_input_ar.metrics_test.nrmse);
            end
            fprintf('\n');
        elseif isfield(bb.metrics_test, 'accuracy')
            fprintf('             test accuracy=%.4f', bb.metrics_test.accuracy);
            if isfield(bb, 'baselines') && isfield(bb.baselines, 'majority_class')
                fprintf('  (majority=%.4f, linCls=%.4f)', ...
                    bb.baselines.majority_class.metrics_test.accuracy, ...
                    bb.baselines.linear_classifier.metrics_test.accuracy);
            end
            fprintf('\n');
        end
    end
    if isfield(b.mackeyglass, 'rollout') && strcmp(b.mackeyglass.rollout.status, 'computed')
        fprintf('  mackeyglass rollout NRMSE = %.4f (%s)\n', ...
            b.mackeyglass.rollout.metrics.nrmse, b.mackeyglass.rollout.prediction_mode);
    end
end

%% Collect regression test NRMSE for the core four tasks
core_names = {'narma10', 'narma20', 'mackeyglass', 'lorenz'};
nrmse_on = zeros(numel(core_names), 1);
nrmse_off = zeros(numel(core_names), 1);
for k = 1:numel(core_names)
    nrmse_on(k)  = summary.adapt_ON.(core_names{k}).metrics_test.nrmse;
    nrmse_off(k) = summary.adapt_OFF.(core_names{k}).metrics_test.nrmse;
end

%% Save
save_path = fullfile(out_dir, sprintf('benchmarks_%s.mat', timestamp));
save(save_path, 'summary', 'bench_names', 'core_names', 'nrmse_on', 'nrmse_off', 'configs', 'common_opts');

%% Figure: test NRMSE, adaptation ON vs OFF (lower is better)
figure('Color', 'w');
bar([nrmse_on, nrmse_off]);
set(gca, 'XTickLabel', core_names);
ylabel('test NRMSE (lower is better)');
legend({'adaptation ON', 'adaptation OFF'}, 'Location', 'best');
title('What adaptation adds: benchmark performance (ridge readout only)');
grid on;

fprintf('\nSaved benchmark results to %s\n', save_path);

function out = merge_opts(base, extra)
    out = base;
    f = fieldnames(extra);
    for i = 1:numel(f)
        out.(f{i}) = extra.(f{i});
    end
end
