function key = dale_mesn_control_reference_key(feature_mode, keys)
% DALE_MESN_CONTROL_REFERENCE_KEY  Feature-matched Dale-only paired cell key.
%
%   key = dale_mesn_control_reference_key(feature_mode, keys)

    fm = char(feature_mode);
    if nargin < 2 || isempty(keys)
        keys = struct( ...
            'feat_x', 'adapt-off__std-off__delay-ode_off__feat-x', ...
            'feat_r', 'adapt-off__std-off__delay-ode_off__feat-r');
    end
    switch fm
        case 'x'
            key = keys.feat_x;
        case 'r'
            key = keys.feat_r;
        otherwise
            error('dale_mesn_control_reference_key:BadFeature', ...
                'Unsupported feature_mode %s for Dale-only reference.', fm);
    end
end
