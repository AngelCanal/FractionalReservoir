function clear_SRNN_persistent()
% clear_SRNN_persistent  Deprecated no-op.
%
% No persistent simulation input data exists in the reservoir RHS.
% This function is retained only for backward compatibility.

    warning('MESN:DeprecatedPersistentClear', ...
        'clear_SRNN_persistent is deprecated; reservoir RHS has no persistent input cache.');
end
