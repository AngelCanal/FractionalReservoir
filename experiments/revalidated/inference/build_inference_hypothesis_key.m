function key = build_inference_hypothesis_key(source_table, contrast_id, ...
        endpoint_id, baseline_name, horizon_rule)
%BUILD_INFERENCE_HYPOTHESIS_KEY  Canonical hypothesis key for registry lookup.
%
%   key = build_inference_hypothesis_key(source_table, contrast_id, endpoint_id)
%   key = build_inference_hypothesis_key(..., baseline_name, horizon_rule)
%
% Keys match validate_seed_inference_plan / build_seed_inference_plan registry
% entries. horizon_rule is the registry field ('fixed_horizon' or '').

    if nargin < 4 || isempty(baseline_name)
        baseline_name = '';
    else
        baseline_name = char(baseline_name);
    end
    if nargin < 5 || isempty(horizon_rule)
        horizon_rule = '';
    else
        horizon_rule = char(horizon_rule);
    end

    parts = {char(source_table), char(contrast_id), char(endpoint_id), ...
        baseline_name, horizon_rule};
    key = strjoin(parts, '|');
end
