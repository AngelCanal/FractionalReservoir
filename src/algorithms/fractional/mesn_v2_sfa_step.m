function [a_next, info] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_a)
%MESN_V2_SFA_STEP Exact integer-order SFA step under zero-order hold on r.
%
%   [a_next, info] = mesn_v2_sfa_step(a_previous, r_previous, dt, tau_a)
%
% Implements the exact exponential update for
%   tau_a * da/dt = r - a
% when r is held constant at r_previous during the step:
%   decay = exp(-dt ./ tau_a)
%   a_next = a_previous .* decay + r_previous(:) * (1 - decay)
%
% Does not clip, does not use Caputo or delay history, and does not
% mutate inputs.

    [a_matrix, n_population, n_channels] = validate_adaptation(a_previous);
    r_col = validate_rate(r_previous, n_population);
    dt = validate_dt(dt);
    tau_row = validate_tau(tau_a, n_channels);

    if n_channels == 0
        a_next = a_matrix;
    else
        decay = exp(-dt ./ tau_row);
        a_next = a_matrix .* decay + r_col * (1 - decay);
    end

    spec = mesn_v2_sfa_step_spec();
    info = struct();
    info.schema_version = spec.schema_version;
    info.content_hash = spec.content_hash;
    info.update_scheme = 'exact_exponential_zero_order_hold';
    info.rate_index = 'n_minus_1';
    info.n_population = n_population;
    info.n_channels = n_channels;
    info.clipped = false;
    info.integer_order = true;
    info.fractional_history_used = false;
    info.delay_history_used = false;
end

function [a_matrix, n_population, n_channels] = validate_adaptation(value)
    if ~isnumeric(value) || ~ismatrix(value) || ~isreal(value) || ...
            ~all(isfinite(value(:)))
        error('mesn_v2_sfa_step:invalidAdaptation', ...
            ['a_previous must be a finite real numeric two-dimensional ', ...
             'matrix of shape n_population-by-n_channels.']);
    end

    n_population = size(value, 1);
    n_channels = size(value, 2);
    a_matrix = double(value);
end

function r_col = validate_rate(value, n_population)
    if n_population == 0
        if ~isnumeric(value) || ~isreal(value)
            error('mesn_v2_sfa_step:invalidRate', ...
                ['r_previous must be a finite real numeric vector with ', ...
                 'exactly n_population elements.']);
        end
        if ~isempty(value)
            error('mesn_v2_sfa_step:invalidRate', ...
                'r_previous must be empty when n_population is zero.');
        end
        if ~is_canonical_empty_vector(value)
            error('mesn_v2_sfa_step:invalidRate', ...
                ['Empty r_previous must be [], zeros(0,1), or zeros(1,0) ', ...
                 'when n_population is zero.']);
        end
        r_col = zeros(0, 1);
        return;
    end

    if ~isnumeric(value) || ~isvector(value) || ~isreal(value) || ...
            ~all(isfinite(value(:))) || numel(value) ~= n_population
        error('mesn_v2_sfa_step:invalidRate', ...
            ['r_previous must be a finite real numeric vector with ', ...
             'exactly n_population elements.']);
    end

    r_col = reshape(double(value), n_population, 1);
end

function dt = validate_dt(value)
    if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
            ~isfinite(value) || value <= 0
        error('mesn_v2_sfa_step:invalidDt', ...
            'dt must be a finite real positive numeric scalar.');
    end
    dt = double(value);
end

function tau_row = validate_tau(value, n_channels)
    if n_channels == 0
        if ~isnumeric(value) || ~isreal(value)
            error('mesn_v2_sfa_step:invalidTau', ...
                ['tau_a must be a finite real positive numeric vector ', ...
                 'with exactly n_channels elements.']);
        end
        if ~isempty(value)
            error('mesn_v2_sfa_step:invalidTau', ...
                'tau_a must be empty when n_channels is zero.');
        end
        if ~is_canonical_empty_vector(value)
            error('mesn_v2_sfa_step:invalidTau', ...
                ['Empty tau_a must be [], zeros(0,1), or zeros(1,0) ', ...
                 'when n_channels is zero.']);
        end
        tau_row = zeros(1, 0);
        return;
    end

    if ~isnumeric(value) || ~isvector(value) || ~isreal(value) || ...
            ~all(isfinite(value(:))) || numel(value) ~= n_channels || ...
            any(value(:) <= 0)
        error('mesn_v2_sfa_step:invalidTau', ...
            ['tau_a must be a finite real positive numeric vector ', ...
             'with exactly n_channels elements.']);
    end

    tau_row = reshape(double(value), 1, n_channels);
end

function tf = is_canonical_empty_vector(value)
    sz = size(value);
    tf = isequal(sz, [0, 0]) || isequal(sz, [0, 1]) || isequal(sz, [1, 0]);
end
