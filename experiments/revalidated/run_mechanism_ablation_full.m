function [result, run_dir] = run_mechanism_ablation_full(options)
% run_mechanism_ablation_full  Publication-intent paired mechanism ablation.
%
% Requires a frozen operating point. Reduced lengths force protocol_tier='smoke'
% and can never set publication_ready / publication_protocol_complete.

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end
    this_dir = fileparts(mfilename('fullpath'));
    addpath(this_dir);

    cfg = mechanism_ablation_config('publication');
    assert(strcmp(cfg.protocol_tier, 'publication'));
    assert(~cfg.pilot_not_for_publication);

    used_reduced_lengths = local_get(options, 'use_reduced_lengths', false);
    if used_reduced_lengths
        smoke_cfg = mechanism_ablation_config('smoke');
        cfg.lengths = smoke_cfg.lengths;
        cfg.base.n = smoke_cfg.base.n;
        cfg.secondary_enabled = false;
        cfg = force_smoke_protocol(cfg, ...
            'reduced_lengths_for_compute_feasibility_not_publication_inference');
    end

    if ~isfield(options, 'frozen_operating_point') || isempty(options.frozen_operating_point)
        error('run_mechanism_ablation_full:MissingOperatingPoint', ...
            'Pass options.frozen_operating_point from T102 before full runs.');
    end
    cfg.frozen_operating_point = options.frozen_operating_point;
    cfg.protocol_fingerprint = compute_protocol_fingerprint(cfg);

    verbose = local_get(options, 'verbose', true);
    save_results = local_get(options, 'save_results', true);
    max_seeds = local_get(options, 'max_seeds', numel(cfg.seeds));
    max_cells = local_get(options, 'max_cells', numel(cfg.cells));
    run_secondary = local_get(options, 'run_secondary', false); % default off for feasibility
    if used_reduced_lengths
        run_secondary = false;
    end
    seeds = cfg.seeds(1:min(numel(cfg.seeds), max_seeds));
    cells = cfg.cells(1:min(numel(cfg.cells), max_cells));

    run_dir = '';
    ctx = struct();
    if save_results
        ctx_opts = struct('master_seed', seeds(1));
        if isfield(options, 'run_id'); ctx_opts.run_id = options.run_id; end
        if isfield(options, 'revalidated_root_override')
            ctx_opts.revalidated_root_override = options.revalidated_root_override;
        end
        exp_name = 'mechanism_ablation_full';
        if strcmp(cfg.protocol_tier, 'smoke')
            exp_name = 'mechanism_ablation_smoke_via_full';
        end
        ctx = create_run_context(exp_name, ctx_opts);
        run_dir = ctx.run_dir;
        mkdir(fullfile(run_dir, 'cells'));
        save_run_manifest(ctx, cfg, struct( ...
            'stage', 'T103_full', ...
            'protocol_tier', cfg.protocol_tier, ...
            'protocol_fingerprint', cfg.protocol_fingerprint, ...
            'frozen_operating_point', cfg.frozen_operating_point, ...
            'n_seeds_requested', numel(cfg.full_seeds), ...
            'n_seeds_this_run', numel(seeds), ...
            'n_cells', numel(cells), ...
            'use_reduced_lengths', used_reduced_lengths));
        atomic_save_results(fullfile(run_dir, 'preregistered_config.mat'), struct('cfg', cfg));
    end

    cell_index = {};
    cell_results = {};
    n_fail = 0;
    for iseed = 1:numel(seeds)
        seed = seeds(iseed);
        for ic = 1:numel(cells)
            cell_spec = cells{ic};
            if verbose
                fprintf('Full %d/%d seed=%d cell=%s\n', ...
                    (iseed-1)*numel(cells)+ic, numel(seeds)*numel(cells), ...
                    seed, cell_spec.cell_key);
            end
            cr = run_ablation_cell(cell_spec, seed, cfg, struct( ...
                'verbose', verbose, ...
                'run_secondary', run_secondary));
            cell_results{end+1} = cr; %#ok<AGROW>
            if ~strcmp(cr.status, 'ok')
                n_fail = n_fail + 1;
            end
            fname = sprintf('seed_%d__%s.mat', seed, cell_spec.cell_key);
            if save_results
                atomic_save_results(fullfile(run_dir, 'cells', fname), ...
                    struct('cell_result', cr));
            end
            cell_index{end+1} = struct( ...
                'file', fname, ...
                'seed', seed, ...
                'cell_key', cell_spec.cell_key, ...
                'status', cr.status, ...
                'wall_time_seconds', cr.wall_time_seconds); %#ok<AGROW>
        end
    end

    aggregate = struct('status', 'not_computed');
    if save_results && n_fail == 0
        aggregate = aggregate_ablation_results(run_dir, struct( ...
            'control_cell_key', 'adapt-off__std-off__delay-ode_off__feat-x', ...
            'save', true));
    end

    readiness = evaluate_publication_readiness(cfg, struct( ...
        'cell_records', cell_results, ...
        'has_manifest', save_results, ...
        'has_commit_sha', save_results, ...
        'has_artifact_hashes', false, ...
        'run_dir', run_dir));

    % Hard overrides for reduced/smoke masquerading as full.
    if used_reduced_lengths || ~strcmp(cfg.protocol_tier, 'publication')
        readiness.publication_protocol_complete = false;
        readiness.publication_ready = false;
    end

    result = struct();
    result.cfg = cfg;
    result.protocol_tier = cfg.protocol_tier;
    result.protocol_fingerprint = cfg.protocol_fingerprint;
    result.seeds = seeds;
    result.n_seeds_requested = numel(cfg.full_seeds);
    result.n_seeds_completed = numel(seeds);
    result.n_cells = numel(cells);
    result.n_failed = n_fail;
    result.cell_index = cell_index;
    result.aggregate = aggregate;
    result.frozen_operating_point = cfg.frozen_operating_point;
    result.run_dir = run_dir;
    result.structurally_complete = readiness.structurally_complete;
    result.publication_protocol_complete = readiness.publication_protocol_complete;
    result.all_primary_endpoints_finite = readiness.all_primary_endpoints_finite;
    result.all_qa_checks_pass = readiness.all_qa_checks_pass;
    result.artifact_package_complete = readiness.artifact_package_complete;
    result.publication_ready = readiness.publication_ready;
    result.readiness = readiness;
    result.status = ternary(n_fail == 0, 'ok', 'failed_cells');
    result.completion_note = sprintf( ...
        ['Completed %d/%d preregistered seeds and %d/%d cells. ', ...
         'protocol_tier=%s publication_ready=%d structurally_complete=%d.'], ...
        numel(seeds), numel(cfg.full_seeds), numel(cells), cfg.n_cells, ...
        cfg.protocol_tier, result.publication_ready, result.structurally_complete);

    if save_results
        atomic_save_results(fullfile(run_dir, 'full_summary.mat'), struct('result', result));
        save_run_manifest(ctx, cfg, struct( ...
            'stage', 'T103_full_complete', ...
            'status', result.status, ...
            'protocol_tier', cfg.protocol_tier, ...
            'protocol_fingerprint', cfg.protocol_fingerprint, ...
            'structurally_complete', result.structurally_complete, ...
            'publication_protocol_complete', result.publication_protocol_complete, ...
            'all_primary_endpoints_finite', result.all_primary_endpoints_finite, ...
            'all_qa_checks_pass', result.all_qa_checks_pass, ...
            'artifact_package_complete', result.artifact_package_complete, ...
            'publication_ready', result.publication_ready, ...
            'completion_note', result.completion_note, ...
            'n_failed', n_fail));
    end
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
