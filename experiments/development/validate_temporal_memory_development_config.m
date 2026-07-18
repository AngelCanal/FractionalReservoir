function report = validate_temporal_memory_development_config(cfg)
% validate_temporal_memory_development_config  Fail-closed development protocol.
%
%   report = validate_temporal_memory_development_config(cfg)
%
% Rejects unknown protocol versions, publication tiers, publication readiness,
% forbidden seeds (including v1 test seed 9003 and reserved future-v2 seeds),
% missing/duplicate cells, geometry drift, include_input=true, operating-point
% changes, absent fingerprints, and nondeterministic fingerprint contamination.

    if nargin < 1 || ~isstruct(cfg)
        error('validate_temporal_memory_development_config:InvalidCfg', ...
            'cfg must be a struct.');
    end

    checks = {};
    reasons = {};

    expected = temporal_memory_development_config();

    % --- protocol identity ---
    ver_ok = isfield(cfg, 'protocol_version') && ...
        strcmp(char(cfg.protocol_version), 'temporal_memory_diagnostic_v1');
    checks{end+1} = make_check('known_protocol_version', ver_ok, ...
        'temporal_memory_diagnostic_v1'); %#ok<*AGROW>
    if ~ver_ok
        reasons{end+1} = 'unknown_or_missing_protocol_version';
    end

    tier_ok = isfield(cfg, 'protocol_tier') && ...
        strcmp(char(cfg.protocol_tier), 'development');
    checks{end+1} = make_check('protocol_tier_is_development', tier_ok, ...
        local_str(cfg, 'protocol_tier'));
    if ~tier_ok
        reasons{end+1} = 'publication_or_nondevelopment_protocol_tier';
    end

    pub_tier_forbidden = ~(isfield(cfg, 'protocol_tier') && ...
        strcmp(char(cfg.protocol_tier), 'publication'));
    checks{end+1} = make_check('publication_tier_rejected', pub_tier_forbidden, ...
        local_str(cfg, 'protocol_tier'));
    if ~pub_tier_forbidden
        reasons{end+1} = 'publication_protocol_tier';
    end

    ready_ok = isfield(cfg, 'publication_ready') && ~logical(cfg.publication_ready);
    checks{end+1} = make_check('publication_ready_false', ready_ok, ...
        sprintf('%d', local_get(cfg, 'publication_ready', true)));
    if ~ready_ok
        reasons{end+1} = 'publication_ready_true';
    end

    can_ok = isfield(cfg, 'can_satisfy_publication_readiness') && ...
        ~logical(cfg.can_satisfy_publication_readiness);
    checks{end+1} = make_check('cannot_satisfy_publication_readiness', can_ok, '');
    if ~can_ok
        reasons{end+1} = 'can_satisfy_publication_readiness_true';
    end

    ev_ok = isfield(cfg, 'publication_evidence') && ~logical(cfg.publication_evidence);
    checks{end+1} = make_check('publication_evidence_false', ev_ok, '');
    if ~ev_ok
        reasons{end+1} = 'publication_evidence_true';
    end

    arch_ok = isfield(cfg, 'architecture_version') && ...
        strcmp(char(cfg.architecture_version), 'nonfractional_mesn_v1');
    checks{end+1} = make_check('architecture_nonfractional_mesn_v1', arch_ok, ...
        local_str(cfg, 'architecture_version'));
    if ~arch_ok
        reasons{end+1} = 'architecture_version_mismatch';
    end

    % --- seeds ---
    model_ok = isfield(cfg, 'model_seeds') && ...
        isequal(cfg.model_seeds(:)', [1729, 2718, 31415]);
    checks{end+1} = make_check('development_model_seeds_exact', model_ok, ...
        '[1729,2718,31415]');
    if ~model_ok
        reasons{end+1} = 'development_model_seeds_mismatch';
    end

    task_ok = isfield(cfg, 'task_seeds') && ...
        isequal(cfg.task_seeds.train, 12001) && ...
        isequal(cfg.task_seeds.validation, 12002) && ...
        isequal(cfg.task_seeds.test, 12003);
    checks{end+1} = make_check('development_task_seeds_exact', task_ok, ...
        '12001/12002/12003');
    if ~task_ok
        reasons{end+1} = 'development_task_seeds_mismatch';
    end

    shuf_ok = isfield(cfg, 'shuffle_seeds') && ...
        isequal(cfg.shuffle_seeds.train, 12101) && ...
        isequal(cfg.shuffle_seeds.validation, 12102) && ...
        isequal(cfg.shuffle_seeds.test, 12103);
    checks{end+1} = make_check('development_shuffle_seeds_exact', shuf_ok, ...
        '12101/12102/12103');
    if ~shuf_ok
        reasons{end+1} = 'development_shuffle_seeds_mismatch';
    end

    seed_9003_ok = ~config_uses_seed(cfg, 9003);
    checks{end+1} = make_check('v1_test_seed_9003_forbidden', seed_9003_ok, ...
        '9003 not in executed roles');
    if ~seed_9003_ok
        reasons{end+1} = 'v1_test_seed_9003_used';
    end

    reserved = flatten_reserved(expected.reserved_future_v2);
    reserved_ok = ~any_executed_seed_in_set(cfg, reserved);
    checks{end+1} = make_check('reserved_v2_seeds_not_executed', reserved_ok, ...
        sprintf('n_reserved=%d', numel(reserved)));
    if ~reserved_ok
        reasons{end+1} = 'reserved_v2_seed_in_executed_role';
    end

    task_vals = [cfg.task_seeds.train, cfg.task_seeds.validation, cfg.task_seeds.test];
    overlap_ok = isempty(intersect(cfg.model_seeds(:)', task_vals));
    checks{end+1} = make_check('task_model_seed_disjoint', overlap_ok, '');
    if ~overlap_ok
        reasons{end+1} = 'development_task_model_seed_overlap';
    end

    shuf_vals = [cfg.shuffle_seeds.train, cfg.shuffle_seeds.validation, ...
        cfg.shuffle_seeds.test];
    shuf_model_ok = isempty(intersect(cfg.model_seeds(:)', shuf_vals));
    checks{end+1} = make_check('shuffle_model_seed_disjoint', shuf_model_ok, '');
    if ~shuf_model_ok
        reasons{end+1} = 'development_shuffle_model_seed_overlap';
    end

    shuf_task_ok = isempty(intersect(task_vals, shuf_vals));
    checks{end+1} = make_check('shuffle_task_seed_disjoint', shuf_task_ok, '');
    if ~shuf_task_ok
        reasons{end+1} = 'development_shuffle_task_seed_overlap';
    end

    retired_ok = isfield(cfg, 'retired_from_future_publication') && ...
        isequal(sort(cfg.retired_from_future_publication(:)'), [10007, 10009]);
    checks{end+1} = make_check('seeds_10007_10009_retired', retired_ok, ...
        '[10007,10009]');
    if ~retired_ok
        reasons{end+1} = 'retirement_of_10007_10009_missing';
    end

    % --- cells ---
    expected_names = expected.diagnostic_cell_names;
    cells_ok = isfield(cfg, 'cells') && numel(cfg.cells) == 8 && ...
        isfield(cfg, 'diagnostic_cell_names') && ...
        isequal(cfg.diagnostic_cell_names, expected_names);
    checks{end+1} = make_check('exactly_eight_diagnostic_cells', cells_ok, ...
        sprintf('n=%d', local_numel_cells(cfg)));
    if ~cells_ok
        reasons{end+1} = 'missing_or_wrong_diagnostic_cells';
    end

    dup_ok = true;
    if isfield(cfg, 'cells')
        keys = cell(1, numel(cfg.cells));
        for i = 1:numel(cfg.cells)
            keys{i} = char(cfg.cells{i}.cell_key);
        end
        dup_ok = numel(keys) == numel(unique(keys));
    end
    checks{end+1} = make_check('no_duplicate_cells', dup_ok, '');
    if ~dup_ok
        reasons{end+1} = 'duplicate_diagnostic_cells';
    end

    % --- geometry ---
    lags_ok = isfield(cfg, 'lags') && isequal(cfg.lags(:)', 1:50);
    checks{end+1} = make_check('exactly_fifty_lags', lags_ok, ...
        sprintf('n=%d', local_numel_field(cfg, 'lags')));
    if ~lags_ok
        reasons{end+1} = 'changed_lag_set';
    end

    len_ok = isfield(cfg, 'lengths') && ...
        isequal(cfg.lengths.washout_steps, 200) && ...
        isequal(cfg.lengths.train_samples, 4000) && ...
        isequal(cfg.lengths.validation_samples, 1000) && ...
        isequal(cfg.lengths.test_samples, 2000);
    checks{end+1} = make_check('lengths_unchanged', len_ok, '');
    if ~len_ok
        reasons{end+1} = 'changed_lengths';
    end

    inc_ok = isfield(cfg, 'include_input') && ~logical(cfg.include_input) && ...
        isfield(cfg, 'base') && isfield(cfg.base, 'include_input') && ...
        ~logical(cfg.base.include_input);
    checks{end+1} = make_check('include_input_false', inc_ok, '');
    if ~inc_ok
        reasons{end+1} = 'include_input_true';
    end

    op_ok = isfield(cfg, 'frozen_operating_point') && ...
        abs(cfg.frozen_operating_point.input_scaling - 0.25) < 1e-15 && ...
        abs(cfg.frozen_operating_point.level_of_chaos - 0.60) < 1e-15 && ...
        isfield(cfg, 'base') && ...
        abs(cfg.base.input_scaling - 0.25) < 1e-15 && ...
        abs(cfg.base.level_of_chaos - 0.60) < 1e-15 && ...
        isequal(cfg.base.n, 40) && ...
        abs(cfg.base.dt - 0.1) < 1e-15 && ...
        abs(cfg.base.tau_d - 0.55) < 1e-15;
    checks{end+1} = make_check('operating_point_unchanged', op_ok, ...
        'n=40,dt=0.1,tau_d=0.55,is=0.25,loc=0.60');
    if ~op_ok
        reasons{end+1} = 'raw_operating_point_changed';
    end

    % --- fingerprint ---
    fp_present = isfield(cfg, 'protocol_fingerprint') && ...
        ~isempty(char(cfg.protocol_fingerprint));
    checks{end+1} = make_check('protocol_fingerprint_present', fp_present, '');
    if ~fp_present
        reasons{end+1} = 'absent_protocol_fingerprint';
    end

    fp_match = false;
    if fp_present
        recomputed = compute_temporal_memory_development_fingerprint(cfg);
        fp_match = strcmp(char(cfg.protocol_fingerprint), char(recomputed));
    end
    checks{end+1} = make_check('protocol_fingerprint_matches', fp_match, '');
    if fp_present && ~fp_match
        reasons{end+1} = 'protocol_fingerprint_mismatch';
    end

    nondet_ok = fingerprint_ignores_runtime_fields(cfg);
    checks{end+1} = make_check('fingerprint_excludes_runtime_fields', nondet_ok, ...
        'timestamps/paths/hostnames excluded');
    if ~nondet_ok
        reasons{end+1} = 'nondeterministic_fingerprint_fields';
    end

    report = struct();
    report.ok = isempty(reasons);
    report.checks = [checks{:}];
    report.failure_reasons = reasons;
    report.protocol_version = local_str(cfg, 'protocol_version');
    report.protocol_fingerprint = '';
    if fp_present
        report.protocol_fingerprint = char(cfg.protocol_fingerprint);
    end

    if ~report.ok
        error('validate_temporal_memory_development_config:Failed', ...
            'Development protocol validation failed: %s', ...
            strjoin(reasons, ', '));
    end
end

function c = make_check(name, pass, detail)
    c = struct('name', name, 'pass', logical(pass), 'detail', char(string(detail)));
end

function v = local_get(S, name, default)
    if isstruct(S) && isfield(S, name)
        v = S.(name);
    else
        v = default;
    end
end

function s = local_str(S, name)
    if isstruct(S) && isfield(S, name)
        s = char(string(S.(name)));
    else
        s = '<missing>';
    end
end

function n = local_numel_cells(cfg)
    if isfield(cfg, 'cells')
        n = numel(cfg.cells);
    else
        n = 0;
    end
end

function n = local_numel_field(cfg, name)
    if isfield(cfg, name)
        n = numel(cfg.(name));
    else
        n = 0;
    end
end

function tf = config_uses_seed(cfg, seed)
    executed = executed_seed_values(cfg);
    tf = any(executed == seed);
end

function tf = any_executed_seed_in_set(cfg, seed_set)
    executed = executed_seed_values(cfg);
    tf = ~isempty(intersect(executed, seed_set(:)'));
end

function vals = executed_seed_values(cfg)
% Seeds that this protocol would execute (model / task / shuffle roles only).
    vals = [];
    if isfield(cfg, 'model_seeds')
        vals = [vals, cfg.model_seeds(:)'];
    end
    if isfield(cfg, 'seeds')
        vals = [vals, cfg.seeds(:)'];
    end
    if isfield(cfg, 'task_seeds')
        vals = [vals, flatten_numeric_struct(cfg.task_seeds)];
    end
    if isfield(cfg, 'shuffle_seeds')
        vals = [vals, flatten_numeric_struct(cfg.shuffle_seeds)];
    end
    vals = unique(vals);
end

function vals = flatten_numeric_struct(S)
    vals = [];
    if isnumeric(S)
        vals = S(:)';
        return;
    end
    if ~isstruct(S) || numel(S) ~= 1
        return;
    end
    fn = fieldnames(S);
    for i = 1:numel(fn)
        vals = [vals, flatten_numeric_struct(S.(fn{i}))]; %#ok<AGROW>
    end
end

function vals = flatten_reserved(R)
    vals = flatten_numeric_struct(R);
end

function tf = fingerprint_ignores_runtime_fields(cfg)
    cfg2 = cfg;
    cfg2.created_utc = '2099-01-01T00:00:00Z';
    cfg2.run_dir = 'C:\tmp\should_not_affect_fingerprint';
    cfg2.output_root = '/ignored/output';
    cfg2.host_name = 'ignored-host';
    cfg2.results_path = fullfile(tempdir, 'ignored_results');
    fp1 = compute_temporal_memory_development_fingerprint(cfg);
    fp2 = compute_temporal_memory_development_fingerprint(cfg2);
    tf = strcmp(char(fp1), char(fp2));
end
