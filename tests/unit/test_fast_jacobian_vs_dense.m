function tests = test_fast_jacobian_vs_dense
tests = functiontests(localfunctions);
end

function testDelayedJacobianUnsupported(testCase)
    params = make_test_params(struct('lags', 0.03));
    S = zeros(state_layout(params).n_total, 1);
    testCase.verifyError(@() compute_Jacobian_fast(S, params), ...
        'MESN:DelayedJacobianUnsupported');
end

function testDenseVsFastAcrossMechanisms(testCase)
    rng(1729);
    mechanism_sets = {
        struct('n_a_E', 0, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0)
        struct('n_a_E', 2, 'n_a_I', 1, 'n_b_E', 0, 'n_b_I', 0)
        struct('n_a_E', 3, 'n_a_I', 2, 'n_b_E', 0, 'n_b_I', 0)
        struct('n_a_E', 0, 'n_a_I', 0, 'n_b_E', 1, 'n_b_I', 1)
        struct('n_a_E', 2, 'n_a_I', 1, 'n_b_E', 1, 'n_b_I', 1)
        };

    n_states = 5;  % 5 mechanisms x 5 states = 25 comparisons
    for m = 1:numel(mechanism_sets)
        overrides = mechanism_sets{m};
        overrides.n = 6;
        overrides.fraction_E = 0.5;
        overrides.lags = [];
        params = make_test_params(overrides);
        % Unequal per-timescale couplings when adaptation is present
        if params.n_a_E > 0
            params.c_a_E = linspace(0.05, 0.2, params.n_a_E);
            params.c_total_E = sum(params.c_a_E);
        end
        if params.n_a_I > 0
            params.c_a_I = linspace(0.02, 0.1, params.n_a_I);
            params.c_total_I = sum(params.c_a_I);
        end
        params = validate_MESN_params(params);
        layout = state_layout(params);

        for s = 1:n_states
            state = random_valid_state(params, layout);
            S = pack_state(state, params);

            J_dense = compute_Jacobian(S, params);
            J_fast = full(compute_Jacobian_fast(S, params));

            diff = J_dense - J_fast;
            fro_dense = norm(J_dense, 'fro');
            if fro_dense < eps
                rel_fro = norm(diff, 'fro');
            else
                rel_fro = norm(diff, 'fro') / fro_dense;
            end
            max_abs = max(abs(diff), [], 'all');

            testCase.verifyLessThan(rel_fro, 1e-12, ...
                sprintf('Mechanism %d state %d relative Frobenius error too large', m, s));
            testCase.verifyLessThan(max_abs, 1e-11, ...
                sprintf('Mechanism %d state %d max abs error too large', m, s));
        end
    end
end

function testFastDoesNotCallDenseBySource(testCase)
    % Structural separation: fast file must not invoke compute_Jacobian.
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    src = fileread(fullfile(repo_root, 'src', 'algorithms', 'Jacobian', 'compute_Jacobian_fast.m'));
    testCase.verifyFalse(contains(src, 'compute_Jacobian('), ...
        'compute_Jacobian_fast must not call compute_Jacobian');
end

function state = random_valid_state(params, layout)
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
