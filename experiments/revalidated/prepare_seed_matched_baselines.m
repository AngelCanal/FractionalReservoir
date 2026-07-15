function [bundle, artifact_path] = prepare_seed_matched_baselines(cfg, base_seed, cells, run_dir, save_results, options)
% PREPARE_SEED_MATCHED_BASELINES  Assert shared W_in, compute once, persist, lock.
%
%   [bundle, artifact_path] = prepare_seed_matched_baselines(cfg, base_seed, ...
%       cells, run_dir, save_results, options)
%
% Must run before any per-cell work for this seed (including parfor). Rejects
% caller-supplied unvalidated baseline overrides.

    if nargin < 5 || isempty(save_results)
        save_results = false;
    end
    if nargin < 6 || isempty(options)
        options = struct();
    end
    if nargin < 4
        run_dir = '';
    end

    reject_baseline_overrides(options, 'prepare_seed_matched_baselines');

    param_overrides = local_get(options, 'param_overrides', struct());
    reference_W_in = assert_shared_paired_W_in(cfg, base_seed, cells, param_overrides);

    bundle = compute_seed_matched_baseline_bundle(cfg, base_seed, reference_W_in);
    [ok, report] = validate_seed_matched_baseline_bundle( ...
        bundle, cfg, base_seed, reference_W_in);
    if ~ok
        error('prepare_seed_matched_baselines:BundleInvalid', ...
            'Shared seed baseline bundle failed validation: %s', ...
            strjoin(report.reasons, ','));
    end

    artifact_path = '';
    if logical(save_results) && ~isempty(run_dir)
        base_dir = fullfile(char(run_dir), 'baselines');
        if ~isfolder(base_dir)
            mkdir(base_dir);
        end
        artifact_path = fullfile(base_dir, sprintf('seed_%d_matched_task_baselines.mat', base_seed));
        atomic_save_results(artifact_path, struct('matched_task_baselines', bundle));
        % Make read-only so cells cannot mutate the shared artifact.
        try
            fileattrib(artifact_path, '-w');
        catch
            warning('prepare_seed_matched_baselines:ReadOnlyFailed', ...
                'Could not clear write permission on %s', artifact_path);
        end
    end
end

function W_in = assert_shared_paired_W_in(cfg, base_seed, cells, param_overrides)
    if isempty(cells)
        error('prepare_seed_matched_baselines:NoCells', 'cells must be nonempty.');
    end
    [p0, ~] = build_ablation_params(cells{1}, base_seed, cfg, param_overrides);
    W_in = p0.W_in;
    ref_hash = hash_numeric_array(W_in);
    for i = 2:numel(cells)
        [p, ~] = build_ablation_params(cells{i}, base_seed, cfg, param_overrides);
        h = hash_numeric_array(p.W_in);
        if ~strcmp(h, ref_hash) || ~isequal(p.W_in, W_in)
            error('prepare_seed_matched_baselines:MatchedInputMismatch', ...
                ['Paired mechanism cells must share W_in for seed %d. ', ...
                 'Cell %s differs from %s.'], ...
                base_seed, cells{i}.cell_key, cells{1}.cell_key);
        end
    end
end

function reject_baseline_overrides(options, runner_id)
    forbidden = { ...
        'baseline_bundle_override', ...
        'matched_baseline_bundles', ...
        'precomputed_baseline_bundles', ...
        'shared_baseline_bundle_override'};
    for i = 1:numel(forbidden)
        if isfield(options, forbidden{i}) && ~isempty(options.(forbidden{i}))
            error(sprintf('%s:BaselineOverrideForbidden', runner_id), ...
                '%s is forbidden; shared baselines must be computed internally.', ...
                forbidden{i});
        end
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
