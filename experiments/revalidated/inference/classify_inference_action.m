function out = classify_inference_action(hypothesis_key, plan)
%CLASSIFY_INFERENCE_ACTION  Allowlist-based test vs estimate-only classification.
%
%   out = classify_inference_action(hypothesis_key, plan)
%
% Exact registry match with inference_action=test_and_holm -> test_and_holm.
% Every unmatched key -> estimate_only. Never infer from contrast_role, endpoint
% role, baseline type, or table position.

    if nargin < 2 || ~isstruct(plan)
        error('classify_inference_action:InvalidPlan', 'plan must be a struct.');
    end

    registry = plan.hypothesis_registry;
    planned_action = 'estimate_only';
    registry_entry = [];
    multiplicity_family = '';

    for i = 1:numel(registry)
        h = registry{i};
        key = registry_hypothesis_key(h);
        if strcmp(key, hypothesis_key) && strcmp(h.inference_action, 'test_and_holm')
            planned_action = 'test_and_holm';
            registry_entry = h;
            if isfield(h, 'multiplicity_family')
                multiplicity_family = char(h.multiplicity_family);
            end
            break;
        end
    end

    out = struct();
    out.hypothesis_key = hypothesis_key;
    out.planned_action = planned_action;
    out.registry_entry = registry_entry;
    out.multiplicity_family = multiplicity_family;
end

function key = registry_hypothesis_key(h)
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
