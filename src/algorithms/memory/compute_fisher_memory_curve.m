function fisher = compute_fisher_memory_curve(esn_or_params, U, options)
% compute_fisher_memory_curve
% QUARANTINED. The historical routine is neither a validated Fisher information
% metric nor a delay-aware sensitivity analysis.
%
% Default behaviour: error MESN:FisherMemoryNotValidated.
% Legacy (invalid) computation only with options.allow_legacy_invalid = true.
% Legacy outputs are prefixed legacy_ and set scientifically_valid = false.
%
% See docs/validation/FISHER_MEMORY_STATUS.md.

    if nargin < 3 || isempty(options)
        options = struct();
    end

    allow_legacy = isfield(options, 'allow_legacy_invalid') && ...
        logical(options.allow_legacy_invalid);

    if ~allow_legacy
        error('MESN:FisherMemoryNotValidated', ...
            ['compute_fisher_memory_curve is quarantined: the existing ', ...
             'calculation is neither a validated Fisher information nor a ', ...
             'delay-aware sensitivity. Set options.allow_legacy_invalid=true ', ...
             'only to reproduce the legacy/invalid curve. See ', ...
             'docs/validation/FISHER_MEMORY_STATUS.md.']);
    end

    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
        params = exportParams(esn_or_params);
    else
        params = esn_or_params;
        esn = SRNN_ESN(params);
    end

    if isfield(params, 'lags') && ~isempty(params.lags)
        error('MESN:DelayedSensitivityUnsupported', ...
            ['Fisher/sensitivity memory is not defined for delayed MESN; ', ...
            'refusing to substitute an ODE Jacobian analysis.']);
    end

    K_max = getFieldOrDefault(options, 'K_max', 200);
    washout_steps = getFieldOrDefault(options, 'washout_steps', 500);
    sample_stride = getFieldOrDefault(options, 'sample_stride', 5);
    use_states = getFieldOrDefault(options, 'use_states', 'x');
    dt = getFieldOrDefault(options, 'dt', params.dt);

    esn.which_states = 'all';
    esn.resetState();
    [~, S_history] = esn.runReservoir(U);

    T = size(S_history, 1);
    if T <= washout_steps + K_max + 2
        error('compute_fisher_memory_curve:ShortTrajectory', ...
            'Need T > washout_steps + K_max + 2 (T=%d, washout=%d, K_max=%d)', ...
            T, washout_steps, K_max);
    end

    n_state = size(S_history, 2);
    C = speye(n_state);
    if strcmpi(use_states, 'x')
        layout = state_layout(params);
        idx = layout.idx_x;
        C = sparse(1:numel(idx), idx, 1, numel(idx), n_state);
    elseif ~strcmpi(use_states, 'all')
        error('compute_fisher_memory_curve:InvalidUseStates', ...
            'use_states must be ''x'' or ''all''');
    end

    du = zeros(n_state, 1);
    du(end-params.n+1:end) = params.W_in(:, 1) / params.tau_d;
    B = dt * du;

    t0 = washout_steps + K_max + 1;
    t_idxs = t0:sample_stride:(T-1);
    n_samples = numel(t_idxs);

    FI = zeros(K_max, 1);

    for s = 1:n_samples
        t = t_idxs(s);
        sens = B;
        for k = 1:K_max
            S_tk = S_history(t-k, :)';
            Jc = compute_Jacobian_fast(S_tk, params);
            A = speye(n_state) + dt * Jc;
            sens = A * sens;
            z = C * sens;
            FI(k) = FI(k) + sum(z.^2);
        end
    end

    FI = FI / max(n_samples, 1);

    known_defects = { ...
        'wrong historical Jacobian', ...
        'Euler transition approximation', ...
        'product-order ambiguity', ...
        'lag-offset ambiguity', ...
        'no noise/statistical model', ...
        'no DDE support'};

    fisher = struct();
    fisher.options = options;
    fisher.scientifically_valid = false;
    fisher.legacy_invalid = true;
    fisher.known_defects = known_defects;
    fisher.legacy_lags = (1:K_max)';
    fisher.legacy_FI_curve = FI;
    % Do not expose unprefixed FI_curve as if it were validated Fisher info.
    fisher.notes = sprintf([ ...
        'LEGACY/INVALID. Approximate sensitivity energy using A≈I+dt*Jc and ', ...
        'B≈dt*df/du (sample_stride=%d, n_samples=%d). Not Fisher information.'], ...
        sample_stride, n_samples);
end

function params = exportParams(esn)
    params = esn.exportParams();
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end
