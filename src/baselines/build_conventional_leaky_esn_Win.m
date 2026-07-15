function [Win, info] = build_conventional_leaky_esn_Win(mesn_Win, input_scaling)
% BUILD_CONVENTIONAL_LEAKY_ESN_WIN  Match MESN input support/direction + scale.
%
%   [Win, info] = build_conventional_leaky_esn_Win(mesn_Win, input_scaling)
%
% Copies nonzero support and signs from the MESN W_in template. Nonzero entries
% are normalized by their mean absolute value, then multiplied by input_scaling.
% Zero rows remain zero. No extra input channel is introduced.

    if nargin < 2 || ~isscalar(input_scaling) || ~isfinite(input_scaling)
        error('build_conventional_leaky_esn_Win:InvalidScale', ...
            'input_scaling must be a finite scalar.');
    end
    if isempty(mesn_Win) || ~isnumeric(mesn_Win)
        error('build_conventional_leaky_esn_Win:InvalidTemplate', ...
            'mesn_Win must be a numeric matrix.');
    end

    template = mesn_Win;
    Win = zeros(size(template));
    support = find(template ~= 0);
    if isempty(support)
        error('build_conventional_leaky_esn_Win:EmptySupport', ...
            'MESN W_in template has no nonzero entries.');
    end
    nz = template(support);
    denom = mean(abs(nz));
    if ~(isfinite(denom) && denom > 0)
        error('build_conventional_leaky_esn_Win:BadNorm', ...
            'Cannot normalize MESN input template.');
    end
    Win(support) = (nz / denom) * input_scaling;

    support_indices = find(any(Win ~= 0, 2));
    info = struct();
    info.input_support_indices = support_indices(:);
    info.input_nonzero_count = numel(support_indices);
    info.input_scaling = input_scaling;
    info.normalization = 'mean_abs_nonzero_then_scale';
    info.reuse_mesn_input_support = true;
    info.reuse_mesn_input_direction = true;
end
