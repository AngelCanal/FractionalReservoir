function [result, run_dir] = run_mg_autonomous_rollout_smoke(options)
% RUN_MG_AUTONOMOUS_ROLLOUT_SMOKE  Bounded Phase 4C-B1 smoke verification.
%
% One ODE x-feature, one ODE r-feature, one DDE cell; one base seed; smoke
% horizon/origins; shared one-step baseline bundle. Never publication-ready.

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end
    this_dir = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(this_dir));
    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(fullfile(repo_root, 'experiments', 'revalidated')));
    addpath(this_dir);

    cfg = mechanism_ablation_config('smoke');
    seed = cfg.seeds(1);
    keys_want = {};
    for i = 1:numel(cfg.cells)
        c = cfg.cells{i};
        if strcmp(c.mode, 'ODE') && strcmp(c.which_states, 'x') && isempty(keys_want)
            keys_want{end+1} = c.cell_key; %#ok<AGROW>
        end
    end
    for i = 1:numel(cfg.cells)
        c = cfg.cells{i};
        if strcmp(c.mode, 'ODE') && strcmp(c.which_states, 'r') && numel(keys_want) == 1
            keys_want{end+1} = c.cell_key; %#ok<AGROW>
            break;
        end
    end
    for i = 1:numel(cfg.cells)
        c = cfg.cells{i};
        if strcmp(c.mode, 'DDE')
            keys_want{end+1} = c.cell_key; %#ok<AGROW>
            break;
        end
    end

    stamp = datestr(now, 'yyyymmdd_HHMMSS');
    root_override = fullfile(repo_root, 'results', 'revalidated', ...
        ['_tmp_mg_autonomous_4c_b1_' stamp]);
    if isfield(options, 'revalidated_root_override')
        root_override = options.revalidated_root_override;
    end
    if ~exist(root_override, 'dir')
        mkdir(root_override);
    end

    run_opts = struct( ...
        'verbose', local_get(options, 'verbose', true), ...
        'max_seeds', 1, ...
        'cell_keys', {keys_want}, ...
        'save_results', true, ...
        'revalidated_root_override', root_override, ...
        'run_id', ['mg_autonomous_rollout_smoke_' stamp]);
    [result, run_dir] = run_mechanism_ablation_smoke(run_opts);

    % Descriptive verification (pipeline evidence only)
    ode_rollouts = {};
    dde_status = '';
    for i = 1:numel(result.cell_results)
        cr = result.cell_results{i};
        if ~isfield(cr, 'mackey_glass') || ~isfield(cr.mackey_glass, 'rollout')
            error('run_mg_autonomous_rollout_smoke:MissingRollout', ...
                'Cell %s missing rollout.', cr.cell_key);
        end
        ro = cr.mackey_glass.rollout;
        if strcmp(cr.mode, 'ODE')
            if ~strcmp(ro.status, 'computed')
                error('run_mg_autonomous_rollout_smoke:OdeNotComputed', ...
                    'ODE cell %s status=%s', cr.cell_key, ro.status);
            end
            ode_rollouts{end+1} = ro; %#ok<AGROW>
        else
            dde_status = ro.status;
            if ~strcmp(ro.status, 'unsupported_not_computed')
                error('run_mg_autonomous_rollout_smoke:DdeBadStatus', ...
                    'DDE status=%s', ro.status);
            end
            if isfield(ro, 'predictions') && ~isempty(ro.predictions)
                error('run_mg_autonomous_rollout_smoke:DdeHasPreds', ...
                    'DDE must not store predictions.');
            end
        end
    end
    if numel(ode_rollouts) < 2
        error('run_mg_autonomous_rollout_smoke:NeedTwoOde', 'Need two ODE cells.');
    end
    if ~isequal(ode_rollouts{1}.origin_schedule.origin_indices, ...
            ode_rollouts{2}.origin_schedule.origin_indices)
        error('run_mg_autonomous_rollout_smoke:OriginMismatch', ...
            'ODE cells must share the deterministic origin schedule.');
    end
    result.smoke_mg_autonomous = struct( ...
        'ode_metrics', {cellfun(@(r) r.metrics, ode_rollouts, 'UniformOutput', false)}, ...
        'ode_origins', ode_rollouts{1}.origin_schedule.origin_indices, ...
        'dde_status', dde_status, ...
        'publication_ready', logical(result.publication_ready));
    if logical(result.publication_ready)
        error('run_mg_autonomous_rollout_smoke:MustNotBePublicationReady', ...
            'Smoke must remain publication_ready=false.');
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
