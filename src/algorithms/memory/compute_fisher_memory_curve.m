function fisher = compute_fisher_memory_curve(esn_or_params, U, options)
% compute_fisher_memory_curve
% Approximate Fisher memory curve vs lag using a Jacobian-propagation
% linearization.
%
% This implements a practical discrete-time approximation:
%   S_{t+1} ≈ S_t + dt * f(S_t, u_t)
%   A_t ≈ I + dt * J_cont(S_t) , where J_cont = d f / dS (continuous-time Jacobian)
%   B_t ≈ dt * d f / du_t
% and sensitivity to an input impulse k steps back:
%   dS_t/du_{t-k} ≈ A_{t-1} ... A_{t-k} * B_{t-k}
%
% The curve is then:
%   FI(k) = mean_t || C * dS_t/du_{t-k} ||_2^2
% where C selects which state/features are considered (default: dendritic x only).
%
% Usage:
%   fisher = compute_fisher_memory_curve(params, U);
%   fisher = compute_fisher_memory_curve(esn, U, struct('K_max', 200));
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct
%   U             - (T x 1) driving input used for trajectory (recommended: white noise)
%   options       - struct (optional)
%       .K_max            (default 200)
%       .washout_steps    (default 500)
%       .sample_stride    (default 5)      % compute FI on every stride step
%       .use_states       (default 'x')    % 'x' or 'all' (selection matrix C)
%       .dt               (default params.dt or esn.dt)
%
% Output:
%   fisher - struct
%       .FI_curve     (K_max x 1)
%       .lags
%       .options
%       .notes

    if nargin < 3 || isempty(options)
        options = struct();
    end

    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
        params = exportParams(esn_or_params);
    else
        params = esn_or_params;
        esn = SRNN_ESN(params);
    end

    K_max = getFieldOrDefault(options, 'K_max', 200);
    washout_steps = getFieldOrDefault(options, 'washout_steps', 500);
    sample_stride = getFieldOrDefault(options, 'sample_stride', 5);
    use_states = getFieldOrDefault(options, 'use_states', 'x');
    dt = getFieldOrDefault(options, 'dt', params.dt);

    esn.which_states = 'all'; % we need full S_history anyway
    esn.resetState();
    [~, S_history] = esn.runReservoir(U);

    T = size(S_history, 1);
    if T <= washout_steps + K_max + 2
        error('compute_fisher_memory_curve:ShortTrajectory', ...
            'Need T > washout_steps + K_max + 2 (T=%d, washout=%d, K_max=%d)', ...
            T, washout_steps, K_max);
    end

    % Selection matrix C (features of interest)
    n_state = size(S_history, 2);
    C = speye(n_state);
    if strcmpi(use_states, 'x')
        len_a_E = params.n_E * params.n_a_E;
        len_a_I = params.n_I * params.n_a_I;
        len_b_E = params.n_E * params.n_b_E;
        len_b_I = params.n_I * params.n_b_I;
        x_start = len_a_E + len_a_I + len_b_E + len_b_I + 1;
        x_end = x_start + params.n - 1;
        idx = x_start:x_end;
        C = sparse(1:numel(idx), idx, 1, numel(idx), n_state);
    elseif ~strcmpi(use_states, 'all')
        error('compute_fisher_memory_curve:InvalidUseStates', ...
            'use_states must be ''x'' or ''all''');
    end

    % Input sensitivity B_t: only x-derivatives get u(t), scaled by 1/tau_d.
    % SRNN_reservoir uses u_ex = W_in * U'. For scalar U, du_ex/du = W_in(:,1).
    % df/d(u_ex) enters dx/dt additively: dx/dt ... + u_ex / tau_d.
    % So d f / d u = [zeros(a,b blocks); (W_in(:,1) / tau_d)].
    du = zeros(n_state, 1);
    du(end-params.n+1:end) = params.W_in(:, 1) / params.tau_d;
    B = dt * du;

    % Time indices used for averaging (post-washout)
    t0 = washout_steps + K_max + 1;
    t_idxs = t0:sample_stride:(T-1); % up to T-1 since we use A_{t-1}
    n_samples = numel(t_idxs);

    FI = zeros(K_max, 1);

    for s = 1:n_samples
        t = t_idxs(s);

        % We will propagate from (t-k) to t:
        % sens = A_{t-1} ... A_{t-k} * B
        sens = B;

        for k = 1:K_max
            % Continuous-time Jacobian at time (t-k)
            S_tk = S_history(t-k, :)';
            Jc = compute_Jacobian_fast(S_tk, params);
            A = speye(n_state) + dt * Jc; % Euler discretization of flow map

            sens = A * sens;

            % accumulate FI for this lag at time t (note: sens now corresponds to lag k)
            z = C * sens;
            FI(k) = FI(k) + sum(z.^2);
        end
    end

    FI = FI / max(n_samples, 1);

    fisher = struct();
    fisher.options = options;
    fisher.lags = (1:K_max).';
    fisher.FI_curve = FI;
    fisher.notes = sprintf(['Approximate FI using A≈I+dt*Jc and B≈dt*d f/du. ', ...
        'Use sample_stride=%d, n_samples=%d.'], sample_stride, n_samples);
end

function params = exportParams(esn)
    % Minimal export from SRNN_ESN object for Jacobian routines
    params = struct();
    params.n = esn.n;
    params.n_E = esn.n_E;
    params.n_I = esn.n_I;
    params.E_indices = esn.E_indices;
    params.I_indices = esn.I_indices;
    params.W = esn.W;
    params.W_in = esn.W_in;
    params.tau_d = esn.tau_d;
    params.n_a_E = esn.n_a_E;
    params.n_a_I = esn.n_a_I;
    params.tau_a_E = esn.tau_a_E;
    params.tau_a_I = esn.tau_a_I;
    params.n_b_E = esn.n_b_E;
    params.n_b_I = esn.n_b_I;
    params.tau_b_E_rec = esn.tau_b_E_rec;
    params.tau_b_E_rel = esn.tau_b_E_rel;
    params.tau_b_I_rec = esn.tau_b_I_rec;
    params.tau_b_I_rel = esn.tau_b_I_rel;
    params.c_E = esn.c_E;
    params.c_I = esn.c_I;
    params.activation_function = esn.activation_function;
    if isprop(esn, 'activation_function_derivative')
        params.activation_function_derivative = esn.activation_function_derivative;
    end
    params.dt = esn.dt;
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

