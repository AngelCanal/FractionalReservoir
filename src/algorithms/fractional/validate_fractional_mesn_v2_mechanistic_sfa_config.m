function cfg = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_in)
%VALIDATE_FRACTIONAL_MESN_V2_MECHANISTIC_SFA_CONFIG Validate SFA-enabled engine config.
%
%   cfg = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg_in)
%
% Returns a new normalized scalar struct. Does not mutate cfg_in.
% Base eight fields are validated through the frozen no-SFA validator.

    if nargin < 1 || ~isstruct(cfg_in) || ~isscalar(cfg_in)
        error('FractionalMESN_v2_mechanistic_sfa:invalidConfig', ...
            'cfg_in must be a scalar struct.');
    end

    if isfield(cfg_in, 'c_E') || isfield(cfg_in, 'c_I')
        error('FractionalMESN_v2_mechanistic_sfa:invalidSfa', ...
            'Legacy c_E/c_I aliases are rejected in the v2 SFA API.');
    end

    required = {'n', 'alpha', 'dt', 'tau_x', 'W_in', 'W', ...
        'presynaptic_signs', 'activation', 'sfa'};
    missing = required(~isfield(cfg_in, required));
    if ~isempty(missing)
        error('FractionalMESN_v2_mechanistic_sfa:missingField', ...
            'Missing required configuration field: %s.', missing{1});
    end

    base_in = struct();
    base_in.n = cfg_in.n;
    base_in.alpha = cfg_in.alpha;
    base_in.dt = cfg_in.dt;
    base_in.tau_x = cfg_in.tau_x;
    base_in.W_in = cfg_in.W_in;
    base_in.W = cfg_in.W;
    base_in.presynaptic_signs = cfg_in.presynaptic_signs;
    base_in.activation = cfg_in.activation;

    try
        base_cfg = validate_fractional_mesn_v2_mechanistic_config(base_in);
    catch ME
        rethrow_as_sfa_config_error(ME);
    end

    sfa = validate_and_normalize_sfa(cfg_in.sfa);

    cfg = struct();
    cfg.n = base_cfg.n;
    cfg.alpha = base_cfg.alpha;
    cfg.dt = base_cfg.dt;
    cfg.tau_x = base_cfg.tau_x;
    cfg.W_in = base_cfg.W_in;
    cfg.W = base_cfg.W;
    cfg.presynaptic_signs = base_cfg.presynaptic_signs;
    cfg.activation = base_cfg.activation;
    cfg.sfa = sfa;
end

function rethrow_as_sfa_config_error(ME)
    prefix = 'FractionalMESN_v2_mechanistic:';
    if startsWith(ME.identifier, prefix)
        suffix = ME.identifier(numel(prefix) + 1:end);
        new_id = ['FractionalMESN_v2_mechanistic_sfa:', suffix];
        err = MException(new_id, '%s', ME.message);
        err = addCause(err, ME);
        throw(err);
    end
    rethrow(ME);
end

function sfa = validate_and_normalize_sfa(value)
    if ~isstruct(value) || ~isscalar(value)
        error('FractionalMESN_v2_mechanistic_sfa:invalidSfa', ...
            'sfa must be a scalar struct.');
    end

    if isfield(value, 'c_E') || isfield(value, 'c_I')
        error('FractionalMESN_v2_mechanistic_sfa:invalidSfa', ...
            'Legacy c_E/c_I aliases are rejected in the v2 SFA API.');
    end

    required = {'tau_a_E', 'c_a_E', 'tau_a_I', 'c_a_I'};
    missing = required(~isfield(value, required));
    if ~isempty(missing)
        error('FractionalMESN_v2_mechanistic_sfa:missingField', ...
            'Missing required sfa field: %s.', missing{1});
    end

    tau_a_E = validate_tau_vector(value.tau_a_E, ...
        'FractionalMESN_v2_mechanistic_sfa:invalidTauE', 'tau_a_E');
    c_a_E = validate_coupling_vector(value.c_a_E, numel(tau_a_E), ...
        'FractionalMESN_v2_mechanistic_sfa:invalidCouplingE', 'c_a_E');
    tau_a_I = validate_tau_vector(value.tau_a_I, ...
        'FractionalMESN_v2_mechanistic_sfa:invalidTauI', 'tau_a_I');
    c_a_I = validate_coupling_vector(value.c_a_I, numel(tau_a_I), ...
        'FractionalMESN_v2_mechanistic_sfa:invalidCouplingI', 'c_a_I');

    sfa = struct();
    sfa.tau_a_E = tau_a_E;
    sfa.c_a_E = c_a_E;
    sfa.tau_a_I = tau_a_I;
    sfa.c_a_I = c_a_I;
end

function tau = validate_tau_vector(value, err_id, name)
    if ~isnumeric(value) || ~isreal(value)
        error(err_id, '%s must be a finite real numeric vector.', name);
    end
    if isempty(value)
        tau = zeros(1, 0);
        return;
    end
    if ~isvector(value) || ~all(isfinite(value(:))) || any(value(:) <= 0)
        error(err_id, ...
            ['%s must be a finite real positive numeric vector ', ...
             '(empty allowed).'], name);
    end
    tau = reshape(double(value), 1, numel(value));
end

function c = validate_coupling_vector(value, n_channels, err_id, name)
    if ~isnumeric(value) || ~isreal(value)
        error(err_id, '%s must be a finite real numeric vector.', name);
    end
    if isempty(value)
        if n_channels ~= 0
            error(err_id, ...
                '%s length must exactly match the corresponding tau vector.', ...
                name);
        end
        c = zeros(1, 0);
        return;
    end
    if ~isvector(value) || ~all(isfinite(value(:))) || any(value(:) < 0) || ...
            numel(value) ~= n_channels
        error(err_id, ...
            ['%s must be a finite real nonnegative numeric vector ', ...
             'with length matching tau.'], name);
    end
    c = reshape(double(value), 1, numel(value));
end
