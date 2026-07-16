function tf = is_publication_inferential_analysis_set(analysis_set)
%IS_PUBLICATION_INFERENTIAL_ANALYSIS_SET  Publication-inferential allowlist.
%
%   tf = is_publication_inferential_analysis_set(analysis_set)
%
% Returns true only for confirmatory and sfa_sensitivity. feature_exploratory
% is always descriptive / non-inferential regardless of testing families.

    analysis_set = char(lower(string(analysis_set)));
    tf = strcmp(analysis_set, 'confirmatory') || strcmp(analysis_set, 'sfa_sensitivity');
end
