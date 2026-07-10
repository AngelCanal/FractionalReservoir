classdef SpyESN < SRNN_ESN
    % SpyESN  Records the number of input rows passed to runReservoir.

    properties
        last_U_rows = 0
        run_count = 0
    end

    methods
        function obj = SpyESN(params)
            obj@SRNN_ESN(params);
        end

        function [X_features, S_history, info] = runReservoir(obj, U, options)
            if nargin < 3
                options = struct();
            end
            obj.last_U_rows = size(U, 1);
            obj.run_count = obj.run_count + 1;
            [X_features, S_history, info] = runReservoir@SRNN_ESN(obj, U, options);
        end
    end
end
