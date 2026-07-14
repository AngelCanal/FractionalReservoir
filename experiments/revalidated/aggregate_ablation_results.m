function aggregate = aggregate_ablation_results(run_dir, options)
% aggregate_ablation_results  Build paired seed tables and bootstrap CIs from cells.
%
% Reads immutable per-seed cell files; never silently recomputes missing values.

    if nargin < 2 || isempty(options)
        options = struct();
    end
    control_key = local_get(options, 'control_cell_key', ...
        'adapt-off__std-off__delay-ode_off__feat-x');
    n_boot = local_get(options, 'n_bootstrap', 2000);
    alpha = local_get(options, 'alpha', 0.05);
    do_save = local_get(options, 'save', true);

    cells_dir = fullfile(run_dir, 'cells');
    files = dir(fullfile(cells_dir, 'seed_*.mat'));
    if isempty(files)
        error('aggregate_ablation_results:NoCells', 'No cell files in %s', cells_dir);
    end

    rows = {};
    for i = 1:numel(files)
        S = load(fullfile(cells_dir, files(i).name), 'cell_result');
        cr = S.cell_result;
        if ~strcmp(cr.status, 'ok')
            error('aggregate_ablation_results:FailedCell', ...
                'Refusing to aggregate failed cell %s', files(i).name);
        end
        rows{end+1} = struct( ...
            'seed', cr.base_seed, ...
            'cell_key', cr.cell_key, ...
            'mode', cr.mode, ...
            'MC_total', cr.memory_capacity.MC_total, ...
            'narma_test_nrmse', cr.narma.test_nrmse, ...
            'mg_test_nrmse', cr.mackey_glass.test_nrmse, ...
            'esp_median_slope', cr.empirical_convergence.median_pair_slope, ...
            'wall_time_seconds', cr.wall_time_seconds, ...
            'file', files(i).name); %#ok<AGROW>
    end
    T = [rows{:}];
    seeds = unique([T.seed], 'stable');
    keys = unique({T.cell_key}, 'stable');

    % Completeness check
    expected = numel(seeds) * numel(keys);
    if numel(T) ~= expected
        error('aggregate_ablation_results:MissingCells', ...
            'Expected %d cells, found %d', expected, numel(T));
    end

    control_mask = strcmp({T.cell_key}, control_key);
    if ~any(control_mask)
        error('aggregate_ablation_results:MissingControl', ...
            'Control cell %s not found', control_key);
    end

    paired = struct([]);
    for ik = 1:numel(keys)
        key = keys{ik};
        if strcmp(key, control_key)
            continue;
        end
        d_mc = zeros(numel(seeds), 1);
        d_narma = zeros(numel(seeds), 1);
        d_mg = zeros(numel(seeds), 1);
        for is = 1:numel(seeds)
            seed = seeds(is);
            a = T(strcmp({T.cell_key}, key) & [T.seed] == seed);
            c = T(strcmp({T.cell_key}, control_key) & [T.seed] == seed);
            if isempty(a) || isempty(c)
                error('aggregate_ablation_results:UnpairedSeed', ...
                    'Missing pair for seed %d key %s', seed, key);
            end
            d_mc(is) = a.MC_total - c.MC_total;
            d_narma(is) = a.narma_test_nrmse - c.narma_test_nrmse;
            d_mg(is) = a.mg_test_nrmse - c.mg_test_nrmse;
        end
        entry = struct();
        entry.cell_key = key;
        entry.control_cell_key = control_key;
        entry.seeds = seeds(:);
        entry.delta_MC = d_mc;
        entry.delta_narma_nrmse = d_narma;
        entry.delta_mg_nrmse = d_mg;
        entry.MC = summarize_effect(d_mc, n_boot, alpha);
        entry.narma = summarize_effect(d_narma, n_boot, alpha);
        entry.mg = summarize_effect(d_mg, n_boot, alpha);
        if isempty(paired)
            paired = entry;
        else
            paired(end+1) = entry; %#ok<AGROW>
        end
    end

    aggregate = struct();
    aggregate.run_dir = run_dir;
    aggregate.control_cell_key = control_key;
    aggregate.seeds = seeds(:);
    aggregate.cell_keys = keys(:);
    aggregate.raw_rows = T;
    aggregate.paired = paired;
    aggregate.n_bootstrap = n_boot;
    aggregate.ci_level = 1 - alpha;
    aggregate.resampling_unit = 'seed';
    aggregate.multiple_comparison = struct( ...
        'method', 'holm_bonferroni', ...
        'family', 'secondary_endpoints', ...
        'note', 'Apply when secondary endpoints are present in the cell files.');
    aggregate.status = 'ok';

    if do_save
        atomic_save_results(fullfile(run_dir, 'aggregate_paired.mat'), ...
            struct('aggregate', aggregate));
    end
end

function s = summarize_effect(d, n_boot, alpha)
    d = d(:);
    s = struct();
    s.n = numel(d);
    s.mean = mean(d);
    s.median = median(d);
    s.std = std(d);
    s.ci95_bootstrap_mean = bootstrap_ci(d, @mean, n_boot, alpha);
    s.ci95_bootstrap_median = bootstrap_ci(d, @median, n_boot, alpha);
    s.cliff_delta = cliff_delta(d);
    s.effect_size_note = 'cliff_delta on paired differences vs zero reference';
end

function ci = bootstrap_ci(x, stat_fn, n_boot, alpha)
    rng(1729);
    n = numel(x);
    stats = zeros(n_boot, 1);
    for b = 1:n_boot
        idx = randi(n, n, 1);
        stats(b) = stat_fn(x(idx));
    end
    stats = sort(stats);
    lo = max(1, floor(alpha/2 * n_boot));
    hi = min(n_boot, ceil((1 - alpha/2) * n_boot));
    ci = [stats(lo), stats(hi)];
end

function d = cliff_delta(diffs)
% Cliff's delta treating paired diffs vs 0 as two groups {diff} vs {0}*n.
    x = diffs(:);
    y = zeros(size(x));
    nx = numel(x);
    ny = numel(y);
    gt = 0;
    lt = 0;
    for i = 1:nx
        gt = gt + sum(x(i) > y);
        lt = lt + sum(x(i) < y);
    end
    d = (gt - lt) / (nx * ny);
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
