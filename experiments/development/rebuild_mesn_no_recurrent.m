function [esn_nr, params_nr] = rebuild_mesn_no_recurrent(esn_or_params)
%REBUILD_MESN_NO_RECURRENT  New MESN with W=0; original object unchanged.
%
%   [esn_nr, params_nr] = rebuild_mesn_no_recurrent(esn)
%   [esn_nr, params_nr] = rebuild_mesn_no_recurrent(params)

    if isa(esn_or_params, 'SRNN_ESN')
        params = esn_or_params.exportParams();
        W_orig = esn_or_params.W;
    elseif isstruct(esn_or_params)
        params = esn_or_params;
        W_orig = params.W;
    else
        error('rebuild_mesn_no_recurrent:InvalidInput', ...
            'Input must be an SRNN_ESN or params struct.');
    end

    params_nr = params;
    params_nr.W = zeros(size(params.W));
    esn_nr = SRNN_ESN(params_nr);

    if ~isequal(size(esn_nr.W), size(W_orig))
        error('rebuild_mesn_no_recurrent:SizeMismatch', ...
            'No-recurrent W size mismatch.');
    end
    if any(esn_nr.W(:) ~= 0)
        error('rebuild_mesn_no_recurrent:NonZeroW', ...
            'No-recurrent rebuild must have exactly zero W.');
    end
    if isa(esn_or_params, 'SRNN_ESN')
        if ~isequal(esn_or_params.W, W_orig)
            error('rebuild_mesn_no_recurrent:OriginalMutated', ...
                'Original MESN W must remain unchanged.');
        end
    end
end
