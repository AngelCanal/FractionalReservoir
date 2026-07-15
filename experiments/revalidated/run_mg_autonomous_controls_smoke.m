function [result, run_dir] = run_mg_autonomous_controls_smoke(options)
% RUN_MG_AUTONOMOUS_CONTROLS_SMOKE  Bounded Phase 4C-B2 matched-controls smoke.
%
% One base seed; ODE-x, ODE-r, DDE; shared seed bundle with autonomous controls.
% New run directory (never overwrites B1 smoke). publication_ready must be false.

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
        ['_tmp_mg_autonomous_4c_b2_' stamp]);
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
        'run_id', ['mg_autonomous_controls_smoke_' stamp]);
    [result, run_dir] = run_mechanism_ablation_smoke(run_opts);

    art = fullfile(run_dir, 'baselines', sprintf('seed_%d_matched_task_baselines.mat', seed));
    if exist(art, 'file') ~= 2
        error('run_mg_autonomous_controls_smoke:MissingBundle', 'Missing seed bundle.');
    end
    S = load(art);
    B = S.matched_task_baselines;
    if ~isfield(B, 'mackey_glass_autonomous')
        error('run_mg_autonomous_controls_smoke:MissingAuto', 'Bundle missing autonomous controls.');
    end
    auto = B.mackey_glass_autonomous;
    for nm = {'persistence', 'linear_autoregression', 'conventional_leaky_esn'}
        if ~strcmp(char(auto.(nm{1}).status), 'computed')
            error('run_mg_autonomous_controls_smoke:ControlFailed', ...
                'Control %s status=%s', nm{1}, auto.(nm{1}).status);
        end
    end

    ode_ctrls = {};
    ode_metrics = {};
    dale_keys = {};
    dde_ctrl = [];
    for i = 1:numel(result.cell_results)
        cr = result.cell_results{i};
        ro = cr.mackey_glass.rollout;
        if strcmp(cr.mode, 'ODE')
            if ~isfield(ro, 'controls')
                error('run_mg_autonomous_controls_smoke:MissingCellControls', ...
                    'ODE cell missing controls.');
            end
            ode_ctrls{end+1} = ro.controls; %#ok<AGROW>
            ode_metrics{end+1} = ro.metrics; %#ok<AGROW>
            dale_keys{end+1} = char(ro.controls.dale_mesn_control.dale_mesn_control_reference); %#ok<AGROW>
        else
            dde_ctrl = ro.controls;
            if ~strcmp(ro.status, 'unsupported_not_computed')
                error('run_mg_autonomous_controls_smoke:DdeRollout', 'DDE rollout bad.');
            end
            if ~strcmp(char(dde_ctrl.applicability), ...
                    'not_applicable_dde_model_rollout_unsupported')
                error('run_mg_autonomous_controls_smoke:DdeApplicability', ...
                    'DDE applicability mismatch.');
            end
            for nm = {'persistence', 'linear_autoregression', 'conventional_leaky_esn'}
                if isfield(dde_ctrl.(nm{1}), 'comparison') && ...
                        isfield(dde_ctrl.(nm{1}).comparison, 'improvement_nrmse_full_horizon')
                    error('run_mg_autonomous_controls_smoke:DdeComparison', ...
                        'DDE must not have numerical model-vs-control comparison.');
                end
            end
        end
    end
    if numel(ode_ctrls) < 2
        error('run_mg_autonomous_controls_smoke:NeedTwoOde', 'Need two ODE cells.');
    end
    if ~strcmp(char(ode_ctrls{1}.content_hash), char(ode_ctrls{2}.content_hash))
        error('run_mg_autonomous_controls_smoke:HashMismatch', ...
            'ODE-x and ODE-r must share autonomous-control content hash.');
    end
    if strcmp(dale_keys{1}, dale_keys{2})
        error('run_mg_autonomous_controls_smoke:DaleKeys', ...
            'ODE-x and ODE-r must have distinct Dale reference keys.');
    end
    % Cell-specific comparisons differ when MESN metrics differ
    c1 = ode_ctrls{1}.persistence.comparison.improvement_nrmse_full_horizon;
    c2 = ode_ctrls{2}.persistence.comparison.improvement_nrmse_full_horizon;
    if ~(isfinite(c1) && isfinite(c2))
        error('run_mg_autonomous_controls_smoke:NonfiniteCmp', 'Comparisons must be finite.');
    end
    if logical(result.publication_ready)
        error('run_mg_autonomous_controls_smoke:MustNotBePublicationReady', ...
            'Smoke must remain publication_ready=false.');
    end

    result.smoke_mg_autonomous_controls = struct( ...
        'content_hash', char(auto.content_hash), ...
        'ode_mesn_full_nrmse', [ode_metrics{1}.pooled_nrmse_full_horizon, ...
            ode_metrics{2}.pooled_nrmse_full_horizon], ...
        'persistence_full_nrmse', auto.persistence.metrics.pooled_nrmse_full_horizon, ...
        'linear_ar_full_nrmse', auto.linear_autoregression.metrics.pooled_nrmse_full_horizon, ...
        'conventional_esn_full_nrmse', ...
            auto.conventional_leaky_esn.metrics.pooled_nrmse_full_horizon, ...
        'median_restricted_valid_horizons', struct( ...
            'mesn_ode', [ode_metrics{1}.median_valid_horizon, ode_metrics{2}.median_valid_horizon], ...
            'persistence', auto.persistence.metrics.median_valid_horizon, ...
            'linear_ar', auto.linear_autoregression.metrics.median_valid_horizon, ...
            'conventional_esn', auto.conventional_leaky_esn.metrics.median_valid_horizon), ...
        'censoring_fractions', struct( ...
            'mesn_ode', [ode_metrics{1}.fraction_right_censored, ...
                ode_metrics{2}.fraction_right_censored], ...
            'persistence', auto.persistence.metrics.fraction_right_censored, ...
            'linear_ar', auto.linear_autoregression.metrics.fraction_right_censored, ...
            'conventional_esn', auto.conventional_leaky_esn.metrics.fraction_right_censored), ...
        'dale_keys', {dale_keys}, ...
        'publication_ready', false);
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
