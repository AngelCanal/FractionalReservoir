function result = verifyJacobianConsistency(options)
% verifyJacobianConsistency  Validate analytical MESN ODE Jacobians.
%
%   result = verifyJacobianConsistency()
%   result = verifyJacobianConsistency(options)
%
% Cross-checks dense vs fast analytical Jacobians and both against a central
% finite-difference Jacobian of SRNN_reservoir, across mechanism combinations.
%
% Options (all optional):
%   .seed              RNG seed (default 1729)
%   .n_states          states per mechanism config (default 3)
%   .save_results      if true, write under results/revalidated/... (default false)
%   .rel_fro_tol       relative Frobenius tolerance (default 1e-5)
%   .max_abs_tol       maximum absolute error tolerance (default 1e-4)
%   .breakpoint_margin minimum |q - breakpoint| (default 1e-4)
%   .fd_options        options passed to finite_difference_jacobian

    if nargin < 1
        options = struct();
    end

    seed = get_opt(options, 'seed', 1729);
    n_states = get_opt(options, 'n_states', 3);
    save_results = get_opt(options, 'save_results', false);
    rel_fro_tol = get_opt(options, 'rel_fro_tol', 1e-5);
    max_abs_tol = get_opt(options, 'max_abs_tol', 1e-4);
    breakpoint_margin = get_opt(options, 'breakpoint_margin', 1e-4);
    fd_options = get_opt(options, 'fd_options', struct());

    mechanism_sets = { ...
        struct('n_a_E', 0, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0, 'label', 'no_SFA_no_STD'), ...
        struct('n_a_E', 1, 'n_a_I', 1, 'n_b_E', 0, 'n_b_I', 0, 'label', 'one_SFA_no_STD'), ...
        struct('n_a_E', 3, 'n_a_I', 2, 'n_b_E', 0, 'n_b_I', 0, 'label', 'multi_SFA_no_STD'), ...
        struct('n_a_E', 0, 'n_a_I', 0, 'n_b_E', 1, 'n_b_I', 1, 'label', 'no_SFA_STD'), ...
        struct('n_a_E', 2, 'n_a_I', 1, 'n_b_E', 1, 'n_b_I', 1, 'label', 'multi_SFA_STD') ...
        };

    rng(seed);
    cases = struct('label', {}, 'state_index', {}, ...
        'rel_fro_dense_fd', {}, 'max_abs_dense_fd', {}, ...
        'rel_fro_fast_fd', {}, 'max_abs_fast_fd', {}, ...
        'rel_fro_dense_fast', {}, 'max_abs_dense_fast', {}, ...
        'pass_dense_fd', {}, 'pass_fast_fd', {});

    case_idx = 0;
    for m = 1:numel(mechanism_sets)
        ov = mechanism_sets{m};
        label = ov.label;
        ov = rmfield(ov, 'label');
        ov.n = 6;
        ov.fraction_E = 0.5;
        ov.lags = [];
        ov.n_inputs = 1;
        ov.row_center_W = false;
        ov.weight_rng_seed = 1729 + m;
        ov.input_rng_seed = 1730 + m;
        [params, meta] = default_MESN_config(ov);
        params = validate_MESN_params(params);
        layout = state_layout(params);
        S_a = meta.cfg.S_a;
        S_c = meta.cfg.S_c;
        breakpoints = piecewise_sigmoid_breakpoints(S_a, S_c);

        t0 = 0.0;
        u_const = 0.1 * randn(params.n, 1);
        u_fun = @(t) u_const; %#ok<NASGU>
        rhs = @(S) SRNN_reservoir(t0, S, @(t) u_const, params);

        for s = 1:n_states
            S = sample_state_away_from_breakpoints(params, layout, ...
                breakpoints, breakpoint_margin);

            J_dense = compute_Jacobian(S, params);
            J_fast = full(compute_Jacobian_fast(S, params));
            J_fd = finite_difference_jacobian(rhs, S, fd_options);

            [rel_df, abs_df] = jacobian_errors(J_dense, J_fd);
            [rel_ff, abs_ff] = jacobian_errors(J_fast, J_fd);
            [rel_dfast, abs_dfast] = jacobian_errors(J_dense, J_fast);

            case_idx = case_idx + 1;
            cases(case_idx).label = label;
            cases(case_idx).state_index = s;
            cases(case_idx).rel_fro_dense_fd = rel_df;
            cases(case_idx).max_abs_dense_fd = abs_df;
            cases(case_idx).rel_fro_fast_fd = rel_ff;
            cases(case_idx).max_abs_fast_fd = abs_ff;
            cases(case_idx).rel_fro_dense_fast = rel_dfast;
            cases(case_idx).max_abs_dense_fast = abs_dfast;
            cases(case_idx).pass_dense_fd = (rel_df < rel_fro_tol) && (abs_df < max_abs_tol);
            cases(case_idx).pass_fast_fd = (rel_ff < rel_fro_tol) && (abs_ff < max_abs_tol);
        end
    end

    all_pass = all([cases.pass_dense_fd]) && all([cases.pass_fast_fd]);

    result = struct();
    result.cases = cases;
    result.all_pass = all_pass;
    result.rel_fro_tol = rel_fro_tol;
    result.max_abs_tol = max_abs_tol;
    result.seed = seed;
    result.n_states = n_states;
    result.n_cases = numel(cases);
    result.max_rel_fro_dense_fd = max([cases.rel_fro_dense_fd]);
    result.max_abs_dense_fd = max([cases.max_abs_dense_fd]);
    result.max_rel_fro_fast_fd = max([cases.rel_fro_fast_fd]);
    result.max_abs_fast_fd = max([cases.max_abs_fast_fd]);

    if save_results
        ctx = create_run_context('jacobian_finite_difference', ...
            struct('master_seed', seed));
        save(fullfile(ctx.run_dir, 'jacobian_fd_diagnostics.mat'), 'result');
        save_run_manifest(ctx, struct('seed', seed, 'n_states', n_states), ...
            struct('all_pass', all_pass, ...
            'max_rel_fro_dense_fd', result.max_rel_fro_dense_fd, ...
            'max_abs_dense_fd', result.max_abs_dense_fd));
        result.run_dir = ctx.run_dir;
    end
end

function v = get_opt(options, name, default)
    if isfield(options, name) && ~isempty(options.(name))
        v = options.(name);
    else
        v = default;
    end
end

function [rel_fro, max_abs] = jacobian_errors(J_a, J_b)
    diff = J_a - J_b;
    max_abs = max(abs(diff), [], 'all');
    denom = norm(J_a, 'fro');
    if denom < eps
        rel_fro = norm(diff, 'fro');
    else
        rel_fro = norm(diff, 'fro') / denom;
    end
end

function bps = piecewise_sigmoid_breakpoints(S_a, S_c)
    a = S_a / 2;
    c = S_c;
    if a == 0.5
        bps = [c - 0.5, c + 0.5];
    else
        bps = [c + a - 1, c - a, c + a, c + 1 - a];
    end
end

function S = sample_state_away_from_breakpoints(params, layout, breakpoints, margin)
    max_tries = 200;
    for attempt = 1:max_tries
        state = random_valid_state(params);
        S = pack_state(state, params);
        q = compute_effective_q(state, params);
        if min_distance_to_breakpoints(q, breakpoints) >= margin
            return;
        end
    end
    error('verifyJacobianConsistency:BreakpointResampleFailed', ...
        'Could not sample a state at least %.1e from activation breakpoints.', margin);
end

function d = min_distance_to_breakpoints(q, breakpoints)
    q = q(:);
    breakpoints = breakpoints(:).';
    d = min(min(abs(q - breakpoints), [], 2));
end

function state = random_valid_state(params)
    state = struct();
    if params.n_a_E > 0
        state.a_E = 0.1 + 0.5 * rand(params.n_E, params.n_a_E);
    else
        state.a_E = zeros(params.n_E, 0);
    end
    if params.n_a_I > 0
        state.a_I = 0.1 + 0.5 * rand(params.n_I, params.n_a_I);
    else
        state.a_I = zeros(params.n_I, 0);
    end
    if params.n_b_E > 0
        state.b_E = 0.3 + 0.5 * rand(params.n_E, 1);
    else
        state.b_E = zeros(0, 1);
    end
    if params.n_b_I > 0
        state.b_I = 0.3 + 0.5 * rand(params.n_I, 1);
    else
        state.b_I = zeros(0, 1);
    end
    state.x = randn(params.n, 1);
end
