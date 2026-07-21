function cfg = validate_fractional_mesn_v2_mechanistic_config(cfg_in)
%VALIDATE_FRACTIONAL_MESN_V2_MECHANISTIC_CONFIG Validate no-delay mechanistic engine config.
%
%   cfg = validate_fractional_mesn_v2_mechanistic_config(cfg_in)
%
% Returns a new normalized scalar struct. Does not mutate cfg_in.

    if nargin < 1 || ~isstruct(cfg_in) || ~isscalar(cfg_in)
        error('FractionalMESN_v2_mechanistic:invalidConfig', ...
            'cfg_in must be a scalar struct.');
    end

    required = {'n', 'alpha', 'dt', 'tau_x', 'W_in', 'W', ...
        'presynaptic_signs', 'activation'};
    missing = required(~isfield(cfg_in, required));
    if ~isempty(missing)
        error('FractionalMESN_v2_mechanistic:missingField', ...
            'Missing required configuration field: %s.', missing{1});
    end

    n = validate_n(cfg_in.n);
    alpha = validate_alpha(cfg_in.alpha);
    dt = validate_positive_scalar(cfg_in.dt, ...
        'FractionalMESN_v2_mechanistic:invalidDt', 'dt');
    tau_x = validate_positive_scalar(cfg_in.tau_x, ...
        'FractionalMESN_v2_mechanistic:invalidTauX', 'tau_x');
    W_in = validate_input_matrix(cfg_in.W_in, n);
    W = validate_w_matrix(cfg_in.W, n);
    signs = validate_and_normalize_signs(cfg_in.presynaptic_signs, n);
    validate_dale_under_mechanistic_prefix(W, signs);
    activation = validate_and_normalize_activation(cfg_in.activation);

    cfg = struct();
    cfg.n = n;
    cfg.alpha = alpha;
    cfg.dt = dt;
    cfg.tau_x = tau_x;
    cfg.W_in = W_in;
    cfg.W = W;
    cfg.presynaptic_signs = signs;
    cfg.activation = activation;
end

function n = validate_n(value)
    if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
            ~isfinite(value) || value < 1 || value ~= floor(value)
        error('FractionalMESN_v2_mechanistic:invalidN', ...
            'n must be a finite positive integer scalar.');
    end
    n = double(value);
end

function alpha = validate_alpha(value)
    if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ~isfinite(value)
        error('FractionalMESN_v2_mechanistic:invalidAlpha', ...
            'alpha must be a finite real scalar.');
    end
    if ~(value > 0 && value <= 1)
        error('FractionalMESN_v2_mechanistic:invalidAlpha', ...
            'alpha must satisfy 0 < alpha <= 1.');
    end
    alpha = double(value);
end

function x = validate_positive_scalar(value, id, name)
    if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
            ~isfinite(value) || ~(value > 0)
        error(id, '%s must be a finite positive real scalar.', name);
    end
    x = double(value);
end

function W_in = validate_input_matrix(value, n)
    if ~isnumeric(value) || ~ismatrix(value) || ~isreal(value) || ...
            ~all(isfinite(value(:))) || size(value, 1) ~= n
        error('FractionalMESN_v2_mechanistic:invalidWin', ...
            'W_in must be a finite real 2-D numeric matrix with n rows.');
    end
    W_in = double(value);
end

function W = validate_w_matrix(value, n)
    if ~isnumeric(value) || ~ismatrix(value) || ~isreal(value) || ...
            ~all(isfinite(value(:))) || ~isequal(size(value), [n, n])
        error('FractionalMESN_v2_mechanistic:invalidW', ...
            'W must be a finite real n-by-n numeric matrix.');
    end
    W = double(value);
end

function signs = validate_and_normalize_signs(value, n)
    if ~isnumeric(value) || ~isvector(value) || ~isreal(value) || ...
            ~all(isfinite(value(:))) || numel(value) ~= n
        error('FractionalMESN_v2_mechanistic:invalidPresynapticSigns', ...
            'presynaptic_signs must be a finite real numeric vector with n elements.');
    end
    if ~all(value == 1 | value == -1)
        error('FractionalMESN_v2_mechanistic:invalidPresynapticSigns', ...
            'Each presynaptic sign must be exactly +1 or -1.');
    end
    signs = reshape(double(value), 1, n);
end

function validate_dale_under_mechanistic_prefix(W, signs)
    try
        validate_mesn_v2_dale_matrix(W, signs);
    catch ME
        if startsWith(ME.identifier, 'mesn_v2_dale_validator:')
            if contains(ME.identifier, 'invalidSigns')
                error('FractionalMESN_v2_mechanistic:invalidPresynapticSigns', ...
                    '%s', ME.message);
            end
            error('FractionalMESN_v2_mechanistic:invalidW', '%s', ME.message);
        end
        rethrow(ME);
    end
end

function activation = validate_and_normalize_activation(value)
    if ~isstruct(value) || ~isscalar(value)
        error('FractionalMESN_v2_mechanistic:invalidActivation', ...
            'activation must be a scalar struct.');
    end

    if ~isfield(value, 'mode')
        error('FractionalMESN_v2_mechanistic:invalidActivation', ...
            'activation.mode is required.');
    end

    mode = normalize_mode(value.mode);

    if strcmp(mode, 'identity')
        S_a = normalize_identity_parameter(value, 'S_a');
        S_c = normalize_identity_parameter(value, 'S_c');
    else
        if ~isfield(value, 'S_a') || ~isfield(value, 'S_c')
            error('FractionalMESN_v2_mechanistic:invalidActivation', ...
                'piecewise_sigmoid requires explicit S_a and S_c.');
        end
        S_a = validate_piecewise_sa(value.S_a);
        S_c = validate_piecewise_sc(value.S_c);
    end

    activation = struct();
    activation.mode = mode;
    activation.S_a = S_a;
    activation.S_c = S_c;

    % Behavioral authority: frozen rate-map module must accept normalized cfg.
    try
        mesn_v2_rate_map(0, activation);
    catch ME
        if startsWith(ME.identifier, 'mesn_v2_rate_map:')
            error('FractionalMESN_v2_mechanistic:invalidActivation', ...
                '%s', ME.message);
        end
        rethrow(ME);
    end
end

function mode = normalize_mode(value)
    if isstring(value) && isscalar(value)
        mode = char(value);
    elseif ischar(value) && isrow(value)
        mode = value;
    else
        error('FractionalMESN_v2_mechanistic:invalidActivation', ...
            'activation.mode must be a scalar string or char row.');
    end

    allowed = {'piecewise_sigmoid', 'identity'};
    if ~any(strcmp(mode, allowed))
        error('FractionalMESN_v2_mechanistic:invalidActivation', ...
            'Unsupported activation mode: %s.', mode);
    end
end

function x = normalize_identity_parameter(value, name)
    if ~isfield(value, name) || isempty(value.(name))
        x = [];
        return;
    end
    error('FractionalMESN_v2_mechanistic:invalidActivation', ...
        '%s must be empty for identity mode.', name);
end

function S_a = validate_piecewise_sa(value)
    if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
            ~isfinite(value) || value < 0 || value > 1
        error('FractionalMESN_v2_mechanistic:invalidActivation', ...
            'S_a must be a finite real scalar with 0 <= S_a <= 1.');
    end
    S_a = double(value);
end

function S_c = validate_piecewise_sc(value)
    if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
            ~isfinite(value)
        error('FractionalMESN_v2_mechanistic:invalidActivation', ...
            'S_c must be a finite real scalar.');
    end
    S_c = double(value);
end
