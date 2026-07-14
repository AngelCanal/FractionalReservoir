function [ok, reason] = validate_empirical_convergence_endpoint(s)
% validate_empirical_convergence_endpoint  Gate compacted convergence fields.
%
% Nonfinite required slopes/spreads cannot coexist with a non-inconclusive
% classification when a cell claims status ok.

    ok = true;
    reason = '';
    required_always = {'classification', 'classification_reason'};
    for i = 1:numel(required_always)
        if ~isfield(s, required_always{i}) || isempty(s.(required_always{i}))
            ok = false;
            reason = sprintf('missing_convergence_field:%s', required_always{i});
            return;
        end
    end
    class_ok = ismember(s.classification, { ...
        'empirically_contracting_on_test_set', ...
        'not_contracting_on_test_set', ...
        'inconclusive'});
    if ~class_ok
        ok = false;
        reason = 'invalid_convergence_classification';
        return;
    end
    if isfield(s, 'esp_holds')
        ok = false;
        reason = 'unsupported_field_esp_holds';
        return;
    end
    % Reject legacy mismatched slope names if present without canonical fields.
    if (isfield(s, 'median_slope') || isfield(s, 'mean_slope') || isfield(s, 'slope_mean')) && ...
            ~(isfield(s, 'median_pair_slope') && isfield(s, 'mean_pair_slope'))
        ok = false;
        reason = 'legacy_slope_field_without_canonical_pair_slopes';
        return;
    end
    if strcmp(s.classification, 'inconclusive')
        return;
    end
    if ~(isfield(s, 'median_pair_slope') && isfield(s, 'mean_pair_slope') && ...
            isfinite(s.median_pair_slope) && isfinite(s.mean_pair_slope))
        ok = false;
        reason = 'nonfinite_required_pair_slope';
        return;
    end
    if ~(isfield(s, 'final_max_spread') && isfield(s, 'final_median_spread') && ...
            isfinite(s.final_max_spread) && isfinite(s.final_median_spread))
        ok = false;
        reason = 'nonfinite_required_spread';
        return;
    end
end
