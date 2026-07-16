function analysis_set = resolve_runner_analysis_set(options)
%RESOLVE_RUNNER_ANALYSIS_SET  Validated analysis_set for mechanism runners.
%
%   analysis_set = resolve_runner_analysis_set(options)
%
% Default: confirmatory. Allowed: confirmatory | sfa_sensitivity |
% feature_exploratory. Rejects unknown values before run directory creation.

    analysis_set = 'confirmatory';
    if nargin >= 1 && isstruct(options) && isfield(options, 'analysis_set') && ...
            ~isempty(options.analysis_set)
        analysis_set = char(lower(string(options.analysis_set)));
    end

    switch analysis_set
        case {'confirmatory', 'sfa_sensitivity', 'feature_exploratory'}
            % ok
        otherwise
            error('resolve_runner_analysis_set:InvalidAnalysisSet', ...
                ['options.analysis_set must be ''confirmatory'', ', ...
                 '''sfa_sensitivity'', or ''feature_exploratory'', got %s.'], ...
                analysis_set);
    end
end
