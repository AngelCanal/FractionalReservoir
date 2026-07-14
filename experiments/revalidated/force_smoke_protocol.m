function cfg = force_smoke_protocol(cfg, reason)
% force_smoke_protocol  Downgrade a config to immutable smoke identity.
%
% Reduced-length full runs must never remain publication-tier. This helper sets
% protocol_tier='smoke', tags pilot_not_for_publication, and recomputes the
% protocol fingerprint.

    if nargin < 2 || isempty(reason)
        reason = 'reduced_lengths_forced_smoke_never_publication';
    end

    cfg.protocol_tier = 'smoke';
    cfg.mode = 'smoke';
    cfg.pilot_not_for_publication = true;
    cfg.length_note = char(reason);
    cfg.secondary_enabled = false;
    cfg.protocol_fingerprint = compute_protocol_fingerprint(cfg);
end
