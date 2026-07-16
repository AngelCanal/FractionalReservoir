function [publication_inference_complete, aggregation_inference_complete, ...
        inference_execution_status] = resolve_inference_completion( ...
        analysis_set, protocol_tier, is_publication, is_diagnostic_tier, dim_control)
%RESOLVE_INFERENCE_COMPLETION  Analysis-set explicit inference completion policy.
%
%   [publication_inference_complete, aggregation_inference_complete, ...
%       inference_execution_status] = resolve_inference_completion(...)

    publication_inference_complete = false;
    aggregation_inference_complete = false;
    inference_execution_status = 'complete';

    switch analysis_set
        case 'feature_exploratory'
            inference_execution_status = 'complete_exploratory_noninferential';
            return;

        case 'confirmatory'
            if is_diagnostic_tier
                return;
            end
            if is_publication
                publication_inference_complete = true;
                aggregation_inference_complete = true;
            end

        case 'sfa_sensitivity'
            if is_diagnostic_tier
                return;
            end
            if is_publication
                if dim_control.overall_pass
                    publication_inference_complete = true;
                    aggregation_inference_complete = true;
                else
                    inference_execution_status = 'complete_dimension_control_failed';
                end
            end

        otherwise
            error('resolve_inference_completion:UnknownAnalysisSet', ...
                'Unknown analysis_set: %s', analysis_set);
    end
end
