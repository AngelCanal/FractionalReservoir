function run_dir = make_synthetic_calibration_checkpoint(opts)
%MAKE_SYNTHETIC_CALIBRATION_CHECKPOINT  Partial resumable checkpoint fixture.
%
%   run_dir = make_synthetic_calibration_checkpoint()
%   run_dir = make_synthetic_calibration_checkpoint(opts)
%
% Options:
%   n_rows            - number of completed trial rows (default 1)
%   tamper_commit     - write wrong commit SHA
%   tamper_fingerprint - write wrong protocol fingerprint
%   tamper_input_hash - corrupt one input hash
%   duplicate_key     - duplicate a completed trial key
%   corrupt_hash      - corrupt checkpoint_content_hash after write

    if nargin < 1 || isempty(opts)
        opts = struct();
    end

    n_rows = double(local_get(opts, 'n_rows', 1));
    n_rows = max(1, min(512, n_rows));

    root = tempname;
    mkdir(root);
    run_dir = fullfile(root, 'checkpoint_run');
    mkdir(run_dir);

    cfg = mechanism_ablation_config('publication', 'confirmatory');
    [probe_keys, ~] = build_operating_point_calibration_probe_keys(cfg);
    op = cfg.operating_point;
    cal_fp = compute_calibration_protocol_fingerprint(cfg, probe_keys);
    base_fp = compute_protocol_fingerprint(cfg);
    plan = build_checkpoint_plan(cfg, probe_keys, cal_fp, base_fp);
    commit_sha = git_head_sha();

    seeds = op.calibration_seeds(:)';
    input_hashes = struct();
    for is = 1:numel(seeds)
        seed = seeds(is);
        input_seed = seed + op.input_seed_offset;
        stream = RandStream('mt19937ar', 'Seed', input_seed);
        U = op.input_min + (op.input_max - op.input_min) * ...
            rand(stream, op.total_steps, cfg.base.n_inputs);
        input_hashes.(sprintf('seed_%d', seed)) = canonical_sha256(U);
    end

    trial_rows = {};
    completed_keys = {};
    row_idx = 0;
    for ic = 1:16
        cand = op.candidate_order{ic};
        for ip = 1:numel(probe_keys)
            cell_key = probe_keys{ip};
            parts = strsplit(cell_key, '__');
            adapt = strrep(parts{1}, 'adapt-', '');
            std_l = strrep(parts{2}, 'std-', '');
            delay_l = strrep(parts{3}, 'delay-', '');
            for is = 1:numel(seeds)
                row_idx = row_idx + 1;
                if row_idx > n_rows
                    break;
                end
                seed = seeds(is);
                ih = input_hashes.(sprintf('seed_%d', seed));
                packed_dim = synthetic_packed_dimension(cell_key, cfg.base.n);
                trial_rows{row_idx} = struct( ...
                    'protocol_version', op.protocol_version, ...
                    'calibration_protocol_fingerprint', cal_fp, ...
                    'candidate_index', ic, ...
                    'input_scaling', cand.input_scaling, ...
                    'level_of_chaos', cand.level_of_chaos, ...
                    'cell_key', cell_key, ...
                    'adaptation', adapt, ...
                    'std', std_l, ...
                    'delay', delay_l, ...
                    'feature', 'x', ...
                    'calibration_seed', seed, ...
                    'input_seed', seed + op.input_seed_offset, ...
                    'input_hash', ih, ...
                    'network_size', cfg.base.n, ...
                    'dt', cfg.base.dt, ...
                    'washout_steps', op.washout_steps, ...
                    'evaluation_steps', op.evaluation_steps, ...
                    'ode_reltol', op.ode_reltol, ...
                    'ode_abstol', op.ode_abstol, ...
                    'dde_reltol', op.dde_reltol, ...
                    'dde_abstol', op.dde_abstol, ...
                    'mean_rate', 0.4, ...
                    'saturation_fraction', 0.1, ...
                    'silent_fraction', 0.1, ...
                    'dale_violations', 0, ...
                    'n_eval_time_points', op.evaluation_steps, ...
                    'n_neurons', cfg.base.n, ...
                    'n_rate_observations', op.evaluation_steps * cfg.base.n, ...
                    'packed_state_dimension', packed_dim, ...
                    'mean_rate_pass', true, ...
                    'saturation_pass', true, ...
                    'silent_pass', true, ...
                    'dale_pass', true, ...
                    'row_pass', true, ...
                    'status', 'pass');
                completed_keys{row_idx} = build_calibration_trial_key(ic, cell_key, seed); %#ok<AGROW>
            end
            if row_idx >= n_rows
                break;
            end
        end
        if row_idx >= n_rows
            break;
        end
    end

    if isfield(opts, 'duplicate_key') && opts.duplicate_key
        completed_keys{end+1} = completed_keys{1}; %#ok<AGROW>
    end

    trial_table = struct2table(vertcat(trial_rows{:}), 'AsArray', true);

    cp = struct();
    cp.schema_version = 'publication_operating_point_calibration_checkpoint_v1';
    cp.calibration_protocol_version = plan.protocol_version;
    cp.calibration_protocol_fingerprint = plan.calibration_protocol_fingerprint;
    cp.base_publication_config_fingerprint = plan.base_publication_config_fingerprint;
    cp.creation_code_commit_sha = commit_sha;
    cp.candidate_order = plan.candidate_order;
    cp.probe_cell_keys = probe_keys;
    cp.calibration_seeds = seeds;
    cp.input_hashes_by_seed = input_hashes;
    cp.expected_row_count = 512;
    cp.completed_row_count = height(trial_table);
    cp.completed_trial_rows = trial_table;
    cp.completed_trial_keys = completed_keys;
    cp.status = 'in_progress';
    cp.created_utc = '2026-07-16T12:00:00Z';

    if isfield(opts, 'tamper_commit') && opts.tamper_commit
        cp.creation_code_commit_sha = 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
    end
    if isfield(opts, 'tamper_fingerprint') && opts.tamper_fingerprint
        cp.calibration_protocol_fingerprint = 'deadbeef';
    end
    if isfield(opts, 'tamper_input_hash') && opts.tamper_input_hash
        fn = fieldnames(cp.input_hashes_by_seed);
        cp.input_hashes_by_seed.(fn{1}) = 'deadbeef';
    end

    write_calibration_checkpoint(run_dir, cp);

    if isfield(opts, 'corrupt_hash') && opts.corrupt_hash
        path = fullfile(run_dir, 'calibration_checkpoint.mat');
        S = load(path, 'calibration_checkpoint');
        checkpoint = S.calibration_checkpoint;
        checkpoint.checkpoint_content_hash = 'deadbeef';
        calibration_checkpoint = checkpoint; %#ok<NASGU>
        save(path, 'calibration_checkpoint');
    end
end

function plan = build_checkpoint_plan(cfg, probe_keys, cal_fp, base_fp)
    op = cfg.operating_point;
    plan = struct();
    plan.protocol_version = op.protocol_version;
    plan.calibration_protocol_fingerprint = cal_fp;
    plan.base_publication_config_fingerprint = base_fp;
    plan.network_size = op.network_size;
    plan.n_inputs = cfg.base.n_inputs;
    plan.dt = op.dt;
    plan.calibration_seeds = op.calibration_seeds(:)';
    plan.probe_cell_keys = probe_keys;
    plan.candidate_order = op.candidate_order;
    plan.input_min = op.input_min;
    plan.input_max = op.input_max;
    plan.input_seed_offset = op.input_seed_offset;
    plan.washout_steps = op.washout_steps;
    plan.evaluation_steps = op.evaluation_steps;
    plan.total_steps = op.total_steps;
end

function dim = synthetic_packed_dimension(cell_key, n)
    if contains(cell_key, 'adapt-off') && contains(cell_key, 'std-off')
        dim = n;
    elseif contains(cell_key, 'dde_on')
        dim = n + round(n * 0.5) * 3 + round(n * 0.5);
    else
        dim = n + round(n * 0.5) * 3 + round(n * 0.5) * 2;
    end
end

function sha = git_head_sha()
    sha = '';
    try
        [status, out] = system('git rev-parse HEAD');
        if status == 0
            sha = strtrim(out);
        end
    catch
        sha = '';
    end
    if isempty(sha)
        sha = 'unknown_commit';
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
