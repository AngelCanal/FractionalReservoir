function cfg = validate_fractional_mesn_v2_config(cfg_in)
%VALIDATE_FRACTIONAL_MESN_V2_CONFIG Validate isolated Fractional MESN v2 config.
%
%   cfg = validate_fractional_mesn_v2_config(cfg_in)

    if nargin < 1 || ~isstruct(cfg_in) || ~isscalar(cfg_in)
        error('FractionalMESN_v2:invalidConfig', ...
            'cfg_in must be a scalar struct.');
    end

    required = {'n', 'alpha', 'dt', 'tau_x', 'W_in', 'W', 'recurrence_mode'};
    missing = required(~isfield(cfg_in, required));
    if ~isempty(missing)
        error('FractionalMESN_v2:missingField', ...
            'Missing required configuration field: %s.', missing{1});
    end

    n = validate_n(cfg_in.n);
    alpha = validate_alpha(cfg_in.alpha);
    dt = validate_positive_scalar(cfg_in.dt, ...
        'FractionalMESN_v2:invalidDt', 'dt');
    tau_x = validate_positive_scalar(cfg_in.tau_x, ...
        'FractionalMESN_v2:invalidTauX', 'tau_x');
    W_in = validate_input_matrix(cfg_in.W_in, n);
    recurrence_mode = validate_recurrence_mode(cfg_in.recurrence_mode);
    W = validate_recurrence_matrix(cfg_in.W, n, recurrence_mode);

    cfg = struct();
    cfg.n = n;
    cfg.alpha = alpha;
    cfg.dt = dt;
    cfg.tau_x = tau_x;
    cfg.W_in = W_in;
    cfg.W = W;
    cfg.recurrence_mode = recurrence_mode;
end

function n = validate_n(value)
    if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
            ~isfinite(value) || value < 1 || value ~= floor(value)
        error('FractionalMESN_v2:invalidN', ...
            'n must be a finite positive integer scalar.');
    end
    n = double(value);
end

function alpha = validate_alpha(value)
    if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ~isfinite(value)
        error('FractionalMESN_v2:invalidAlpha', ...
            'alpha must be a finite real scalar.');
    end
    if ~(value > 0 && value <= 1)
        error('FractionalMESN_v2:invalidAlpha', ...
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
        error('FractionalMESN_v2:invalidWin', ...
            'W_in must be a finite real 2-D numeric matrix with n rows.');
    end
    W_in = double(value);
end

function recurrence_mode = validate_recurrence_mode(value)
    if isstring(value) && isscalar(value)
        recurrence_mode = char(value);
    elseif ischar(value)
        recurrence_mode = value;
    else
        error('FractionalMESN_v2:invalidRecurrenceMode', ...
            'recurrence_mode must be ''input_only'' or ''linear''.');
    end

    recurrence_mode = char(string(recurrence_mode));
    if ~any(strcmp(recurrence_mode, {'input_only', 'linear'}))
        error('FractionalMESN_v2:invalidRecurrenceMode', ...
            'recurrence_mode must be ''input_only'' or ''linear''.');
    end
end

function W = validate_recurrence_matrix(value, n, recurrence_mode)
    switch recurrence_mode
        case 'input_only'
            if isempty(value)
                W = zeros(n, n);
                return;
            end
            if ~isnumeric(value) || ~ismatrix(value) || ~isreal(value) || ...
                    ~all(isfinite(value(:))) || ~isequal(size(value), [n, n])
                error('FractionalMESN_v2:invalidW', ...
                    ['For input_only, W must be empty or a finite real ', ...
                     'zero n-by-n matrix.']);
            end
            if any(value(:) ~= 0)
                error('FractionalMESN_v2:invalidW', ...
                    'For input_only, W must be empty or exactly zero.');
            end
            W = zeros(n, n);
        case 'linear'
            if ~isnumeric(value) || ~ismatrix(value) || ~isreal(value) || ...
                    ~all(isfinite(value(:))) || ~isequal(size(value), [n, n])
                error('FractionalMESN_v2:invalidW', ...
                    'For linear recurrence, W must be a finite real n-by-n matrix.');
            end
            W = double(value);
        otherwise
            error('FractionalMESN_v2:invalidRecurrenceMode', ...
                'recurrence_mode must be ''input_only'' or ''linear''.');
    end
end
