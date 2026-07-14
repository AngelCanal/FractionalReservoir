function fingerprint = compute_protocol_fingerprint(cfg)
% compute_protocol_fingerprint  SHA-256 of scientifically frozen protocol fields.
%
%   fingerprint = compute_protocol_fingerprint(cfg)
%
% Serializes only scientifically relevant frozen fields in stable alphabetical
% field order. Excludes timestamps, paths, hostnames, runtime metadata, and the
% fingerprint field itself. Function handles are canonicalized to stable names
% via func2str (e.g. @ode45 -> "ode45").

    if nargin < 1 || ~isstruct(cfg)
        error('compute_protocol_fingerprint:InvalidCfg', ...
            'cfg must be a struct.');
    end

    payload = fingerprint_payload(cfg);
    canon = canonicalize_for_fingerprint(payload);
    fingerprint = sha256_hex(canon);
end

function payload = fingerprint_payload(cfg)
% Whitelist scientifically frozen fields. Omitted deliberately: created_utc,
% protocol_fingerprint, paths, hostnames, runtime counts of executed cells, etc.

    include = { ...
        'protocol_tier', ...
        'active_analysis_set', ...
        'experiment_name', ...
        'preregistration_doc', ...
        'mode', ...
        'factors', ...
        'adaptation_profiles', ...
        'feature_policy', ...
        'analysis_set_definitions', ...
        'cells_by_analysis_set', ...
        'c_total_E', ...
        'c_total_I', ...
        'tau_a_I_frozen', ...
        'c_a_I_frozen', ...
        'moment_matched_tau_E', ...
        'manipulated_mechanism', ...
        'fairness_rule', ...
        'base', ...
        'pilot_seeds', ...
        'full_n_seeds', ...
        'full_seeds', ...
        'seeds', ...
        'primary_endpoints', ...
        'secondary_endpoints', ...
        'exclusions', ...
        'lengths', ...
        'secondary_enabled', ...
        'pilot_not_for_publication', ...
        'operating_point', ...
        'cells', ...
        'n_cells', ...
        'n_confirmatory_cells_per_seed', ...
        'n_sfa_sensitivity_cells_per_seed', ...
        'n_seeds', ...
        'n_paired_runs', ...
        'multiple_comparison', ...
        'unsupported_status', ...
        'frozen_operating_point', ...
        'length_note', ...
        'temporal_learning_gate' ...
        };

    payload = struct();
    for i = 1:numel(include)
        name = include{i};
        if isfield(cfg, name)
            payload.(name) = cfg.(name);
        end
    end
end

function out = canonicalize_for_fingerprint(value)
    if isa(value, 'function_handle')
        out = func2str(value);
        return;
    end

    if ischar(value) || (isstring(value) && isscalar(value))
        out = char(value);
        return;
    end

    if isstring(value)
        out = cellstr(value);
        return;
    end

    if islogical(value) || isnumeric(value)
        out = value;
        return;
    end

    if iscell(value)
        out = cell(size(value));
        for i = 1:numel(value)
            out{i} = canonicalize_for_fingerprint(value{i});
        end
        return;
    end

    if isstruct(value)
        if numel(value) ~= 1
            out = cell(size(value));
            for i = 1:numel(value)
                out{i} = canonicalize_for_fingerprint(value(i));
            end
            return;
        end
        f = sort(fieldnames(value));
        out = struct();
        for i = 1:numel(f)
            out.(f{i}) = canonicalize_for_fingerprint(value.(f{i}));
        end
        return;
    end

    % Fallback: stable textual form for exotic types.
    out = char(string(value));
end

function hex = sha256_hex(value)
    text = canonical_text(value);
    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(uint8(unicode2native(text, 'UTF-8')));
    digest = typecast(md.digest(), 'uint8');
    hex = lower(sprintf('%02x', digest));
end

function text = canonical_text(value)
    safe = to_json_safe_sorted(value);
    text = jsonencode(safe);
end

function out = to_json_safe_sorted(value)
    if isa(value, 'function_handle')
        out = func2str(value);
        return;
    end
    if isstruct(value)
        if numel(value) ~= 1
            out = cell(size(value));
            for i = 1:numel(value)
                out{i} = to_json_safe_sorted(value(i));
            end
            return;
        end
        f = sort(fieldnames(value));
        out = struct();
        for i = 1:numel(f)
            out.(f{i}) = to_json_safe_sorted(value.(f{i}));
        end
        return;
    end
    if iscell(value)
        out = cell(size(value));
        for i = 1:numel(value)
            out{i} = to_json_safe_sorted(value{i});
        end
        return;
    end
    if isstring(value)
        if isscalar(value)
            out = char(value);
        else
            out = cellstr(value);
        end
        return;
    end
    out = value;
end
