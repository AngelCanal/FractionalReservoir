function cmp = baseline_model_comparison(model_nrmse, baseline_nrmse)
% BASELINE_MODEL_COMPARISON  Directed MESN-vs-baseline metric summary.
%
%   cmp = baseline_model_comparison(model_nrmse, baseline_nrmse)
%
% improvement_nrmse = baseline_nrmse - model_nrmse (>0 => MESN better)
% ratio_nrmse = model_nrmse / baseline_nrmse (<1 => MESN better)

    cmp = struct();
    cmp.model_nrmse = model_nrmse;
    cmp.baseline_nrmse = baseline_nrmse;
    cmp.improvement_nrmse = baseline_nrmse - model_nrmse;
    if isfinite(baseline_nrmse) && baseline_nrmse ~= 0 && isfinite(model_nrmse)
        cmp.ratio_nrmse = model_nrmse / baseline_nrmse;
    else
        cmp.ratio_nrmse = NaN;
    end
    cmp.sign_convention = [ ...
        'improvement_nrmse = baseline_nrmse - model_nrmse; ', ...
        'improvement_nrmse > 0 means MESN better; ', ...
        'ratio_nrmse = model_nrmse / baseline_nrmse; ', ...
        'ratio_nrmse < 1 means MESN better'];
end
