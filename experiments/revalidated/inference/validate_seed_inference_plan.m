function result = validate_seed_inference_plan(plan)
%VALIDATE_SEED_INFERENCE_PLAN  Structural checks on frozen inference plan.
%
%   result = validate_seed_inference_plan(plan)
%
% Throws on registry violations. Returns summary counts when valid.

    if nargin < 1 || ~isstruct(plan)
        error('validate_seed_inference_plan:InvalidPlan', 'plan must be a struct.');
    end

    required = { ...
        'protocol_version', ...
        'independent_unit', ...
        'alpha', ...
        'primary_estimator', ...
        'robust_estimator', ...
        'ci_method', ...
        'bootstrap_replicates', ...
        'randomization_test', ...
        'multiplicity_method', ...
        'hypothesis_registry', ...
        'testing_families'};
    for i = 1:numel(required)
        if ~isfield(plan, required{i})
            error('validate_seed_inference_plan:MissingField', ...
                'plan.%s is required.', required{i});
        end
    end

    if ~strcmp(plan.protocol_version, 'seed_level_inference_v1')
        error('validate_seed_inference_plan:BadVersion', ...
            'Unexpected protocol_version: %s.', plan.protocol_version);
    end

    validate_frozen_numerical_fields(plan);

    registry = plan.hypothesis_registry;
    if ~iscell(registry)
        error('validate_seed_inference_plan:BadRegistry', ...
            'hypothesis_registry must be a cell array.');
    end

    testing = {};
    tested_keys = {};
    family_counts = containers.Map('KeyType', 'char', 'ValueType', 'double');

    for i = 1:numel(registry)
        h = registry{i};
        if ~isstruct(h)
            error('validate_seed_inference_plan:BadEntry', ...
                'Registry entry %d must be a struct.', i);
        end
        if strcmp(h.inference_action, 'test_and_holm')
            if isempty(h.source_table) || isempty(h.contrast_id) || isempty(h.endpoint_id)
                error('validate_seed_inference_plan:IncompleteHypothesis', ...
                    'test_and_holm entry %d missing source_table/contrast_id/endpoint_id.', i);
            end
            if isempty(h.multiplicity_family)
                error('validate_seed_inference_plan:MissingFamily', ...
                    'test_and_holm entry %d missing multiplicity_family.', i);
            end
            key = hypothesis_key(h);
            if ismember(key, tested_keys)
                error('validate_seed_inference_plan:DuplicateHypothesis', ...
                    'Duplicate tested hypothesis: %s.', key);
            end
            tested_keys{end+1} = key; %#ok<AGROW>
            testing{end+1} = h; %#ok<AGROW>
            fam = h.multiplicity_family;
            if isKey(family_counts, fam)
                family_counts(fam) = family_counts(fam) + 1;
            else
                family_counts(fam) = 1;
            end
        end
    end

    fam_names = fieldnames(plan.testing_families);
    for i = 1:numel(fam_names)
        fam = plan.testing_families.(fam_names{i});
        fid = fam.family_id;
        if ~isKey(family_counts, fid)
            actual = 0;
        else
            actual = family_counts(fid);
        end
        if actual ~= fam.expected_count
            error('validate_seed_inference_plan:FamilySizeMismatch', ...
                'Family %s expected %d hypotheses, found %d.', ...
                fid, fam.expected_count, actual);
        end
    end

    % Extra families in registry not declared are forbidden
    declared = cellfun(@(fn) plan.testing_families.(fn).family_id, ...
        fam_names, 'UniformOutput', false);
    extra = setdiff(keys(family_counts), declared);
    if ~isempty(extra)
        error('validate_seed_inference_plan:UndeclaredFamily', ...
            'Registry contains undeclared testing family: %s.', extra{1});
    end

    % feature_exploratory must have no testing families
    if isfield(plan, 'analysis_set') && strcmp(plan.analysis_set, 'feature_exploratory')
        if ~isempty(testing)
            error('validate_seed_inference_plan:ExploratoryTestingForbidden', ...
                'feature_exploratory must not contain test_and_holm hypotheses.');
        end
    end

    result = struct();
    result.valid = true;
    result.n_registry_entries = numel(registry);
    result.n_test_and_holm = numel(testing);
    result.family_counts = family_counts;
end

function key = hypothesis_key(h)
    baseline = '';
    if isfield(h, 'baseline_name') && ~isempty(h.baseline_name)
        baseline = char(h.baseline_name);
    end
    horizon = '';
    if isfield(h, 'horizon_rule') && ~isempty(h.horizon_rule)
        horizon = char(h.horizon_rule);
    end
    key = build_inference_hypothesis_key(h.source_table, h.contrast_id, ...
        h.endpoint_id, baseline, horizon);
end

function validate_frozen_numerical_fields(plan)
    if ~isfield(plan, 'alpha') || plan.alpha ~= 0.05
        error('validate_seed_inference_plan:FrozenAlpha', ...
            'alpha must be exactly 0.05.');
    end
    if ~isfield(plan, 'bootstrap_replicates') || plan.bootstrap_replicates ~= 20000
        error('validate_seed_inference_plan:FrozenBootstrap', ...
            'bootstrap_replicates must be exactly 20000.');
    end
    if ~isfield(plan, 'sign_flip_exact_max_n') || plan.sign_flip_exact_max_n ~= 16
        error('validate_seed_inference_plan:FrozenExactMaxN', ...
            'sign_flip_exact_max_n must be exactly 16.');
    end
    if ~isfield(plan, 'sign_flip_monte_carlo_replicates') || ...
            plan.sign_flip_monte_carlo_replicates ~= 100000
        error('validate_seed_inference_plan:FrozenMcReplicates', ...
            'sign_flip_monte_carlo_replicates must be exactly 100000.');
    end
    if ~isfield(plan, 'alternative') || ~strcmp(plan.alternative, 'two_sided')
        error('validate_seed_inference_plan:FrozenAlternative', ...
            'alternative must be two_sided.');
    end
    if ~isfield(plan, 'multiplicity_method') || ...
            ~strcmp(plan.multiplicity_method, 'holm_bonferroni')
        error('validate_seed_inference_plan:FrozenMultiplicity', ...
            'multiplicity_method must be holm_bonferroni.');
    end
    if ~isfield(plan, 'independent_unit') || ~strcmp(plan.independent_unit, 'base_seed')
        error('validate_seed_inference_plan:FrozenIndependentUnit', ...
            'independent_unit must be base_seed.');
    end
end
