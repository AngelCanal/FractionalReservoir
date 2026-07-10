function esp = verify_echo_state_property(esn_or_params, U, options)
% verify_echo_state_property
% Empirically verify the Echo State Property (ESP) by checking convergence
% of trajectories from multiple initial conditions under the same input.
%
% Usage:
%   esp = verify_echo_state_property(esn, U);
%   esp = verify_echo_state_property(params, U);
%   esp = verify_echo_state_property(esn, U, struct('n_ic', 20, ...));
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct for SRNN_ESN(params)
%   U             - (T x n_inputs) input sequence
%   options       - struct (optional)
%       .n_ic            (default 20)
%       .washout_steps   (default 200)
%       .eps_tol         (default 1e-3)
%       .ic_scale        (default 0.1)   % magnitude of random IC perturbations
%       .feature_mode    (default 'x')   % 'x' or 'r' or 'all'
%       .use_reference   (default 'first') % 'first' or 'mean'
%       .verbose         (default true)
%
% Output:
%   esp - struct:
%       .esp_holds
%       .convergence_curve   (T x 1) spread vs time (after washout)
%       .final_spread
%       .t_idx               indices used for curve (washout+1 : T)
%       .n_ic
%       .options

    if nargin < 3 || isempty(options)
        options = struct();
    end

    n_ic = getFieldOrDefault(options, 'n_ic', 20);
    washout_steps = getFieldOrDefault(options, 'washout_steps', 200);
    eps_tol = getFieldOrDefault(options, 'eps_tol', 1e-3);
    ic_scale = getFieldOrDefault(options, 'ic_scale', 0.1);
    feature_mode = getFieldOrDefault(options, 'feature_mode', 'x');
    use_reference = getFieldOrDefault(options, 'use_reference', 'first');
    verbose = getFieldOrDefault(options, 'verbose', true);

    if washout_steps < 0
        error('verify_echo_state_property:InvalidWashout', 'washout_steps must be >= 0');
    end
    if size(U, 1) <= washout_steps + 1
        error('verify_echo_state_property:ShortInput', ...
            'U is too short for washout_steps=%d (need > washout_steps+1)', washout_steps);
    end

    % Build ESN
    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
    else
        esn = SRNN_ESN(esn_or_params);
    end

    % Force a consistent feature extraction mode during ESP test
    esn.which_states = feature_mode;

    % Base initial state template
    esn.resetState();
    S_base = esn.getState();
    S0 = S_base;

    % Identify b segments to re-initialize to 1 (if STD enabled)
    layout = state_layout(esn.params);
    idx_b_E = layout.idx_b_E;
    idx_b_I = layout.idx_b_I;

    T = size(U, 1);
    X_all = [];

    if verbose
        fprintf('ESP check: running %d initial conditions...\n', n_ic);
    end

    for k = 1:n_ic
        % Randomize IC around the base state; keep depression variables in [0,1] via reinit to 1.
        rng(1000 + k);
        S_k = S0 + ic_scale * randn(size(S0));
        if ~isempty(idx_b_E)
            S_k(idx_b_E) = 1;
        end
        if ~isempty(idx_b_I)
            S_k(idx_b_I) = 1;
        end

        esn.setState(S_k);
        [X_feat, ~] = esn.runReservoir(U);

        if isempty(X_all)
            X_all = zeros(T, size(X_feat, 2), n_ic);
        end
        X_all(:, :, k) = X_feat;
    end

    t_idx = (washout_steps + 1) : T;
    Xw = X_all(t_idx, :, :);

    % Compute a spread curve: distance to a reference trajectory
    % (O(n_ic) not O(n_ic^2), stable and sufficient for ESP verification).
    switch lower(use_reference)
        case 'first'
            X_ref = Xw(:, :, 1);
        case 'mean'
            X_ref = mean(Xw, 3);
        otherwise
            error('verify_echo_state_property:InvalidReference', ...
                'use_reference must be ''first'' or ''mean''');
    end

    n_t = size(Xw, 1);
    spread = zeros(n_t, 1);
    for ti = 1:n_t
        Xi = squeeze(Xw(ti, :, :));   % n_feat x n_ic
        if size(Xi, 2) ~= n_ic
            Xi = Xi.';
        end
        switch lower(use_reference)
            case 'first'
                ref = Xi(:, 1);
                dnorm = sqrt(sum((Xi - ref).^2, 1));
            case 'mean'
                ref = mean(X_ref, 2);
                dnorm = sqrt(sum((Xi - ref).^2, 1));
            otherwise
                error('verify_echo_state_property:InvalidReference', ...
                    'use_reference must be ''first'' or ''mean''');
        end
        spread(ti) = max(dnorm);
    end

    esp = struct();
    esp.n_ic = n_ic;
    esp.options = options;
    esp.t_idx = t_idx(:);
    esp.convergence_curve = spread;
    esp.final_spread = spread(end);

    tail_len = min(50, numel(spread));
    tail = spread(end-tail_len+1:end);
    esp.esp_holds = all(isfinite(tail)) && max(tail) <= eps_tol;

    if verbose
        fprintf('ESP check: final spread = %.3e (tol=%.3e) => %s\n', ...
            esp.final_spread, eps_tol, ternary(esp.esp_holds, 'HOLDS', 'FAILS'));
    end
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

function out = ternary(cond, a, b)
    if cond
        out = a;
    else
        out = b;
    end
end

