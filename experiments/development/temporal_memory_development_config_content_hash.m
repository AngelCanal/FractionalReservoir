function hex = temporal_memory_development_config_content_hash(cfg)
%TEMPORAL_MEMORY_DEVELOPMENT_CONFIG_CONTENT_HASH  Semantic config identity hash.
%
%   hex = temporal_memory_development_config_content_hash(cfg)
%
% Matches freshly reconstructed temporal_memory_development_config scientific
% payload (excludes timestamps / host metadata / fingerprint self-reference).

    if nargin < 1 || ~isstruct(cfg)
        error('temporal_memory_development_config_content_hash:Invalid', ...
            'cfg must be a struct.');
    end
    % Reuse the fingerprint payload definition for exact scientific binding.
    hex = compute_temporal_memory_development_fingerprint(cfg);
end
