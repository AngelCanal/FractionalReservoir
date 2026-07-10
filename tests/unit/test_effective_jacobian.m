function tests = test_effective_jacobian
tests = functiontests(localfunctions);
end

function testMatchesFullJacobianXxBlockAllMechanisms(testCase)
    rng(1729);
    mechanism_sets = {
        struct('n_a_E', 0, 'n_a_I', 0, 'n_b_E', 0, 'n_b_I', 0)
        struct('n_a_E', 2, 'n_a_I', 1, 'n_b_E', 0, 'n_b_I', 0)
        struct('n_a_E', 3, 'n_a_I', 2, 'n_b_E', 0, 'n_b_I', 0)
        struct('n_a_E', 0, 'n_a_I', 0, 'n_b_E', 1, 'n_b_I', 1)
        struct('n_a_E', 2, 'n_a_I', 1, 'n_b_E', 1, 'n_b_I', 1)
        };

    for m = 1:numel(mechanism_sets)
        ov = mechanism_sets{m};
        ov.n = 6;
        ov.fraction_E = 0.5;
        ov.lags = [];
        params = make_test_params(ov);
        layout = state_layout(params);

        for s = 1:3
            state = random_valid_state(params);
            S = pack_state(state, params);
            J_eff = compute_J_eff(S, params);
            J_full = compute_Jacobian(S, params);
            J_block = J_full(layout.idx_x, layout.idx_x);

            denom = norm(J_block, 'fro');
            if denom < eps
                rel = norm(J_eff - J_block, 'fro');
            else
                rel = norm(J_eff - J_block, 'fro') / denom;
            end
            testCase.verifyLessThan(rel, 1e-12, ...
                sprintf('Mechanism %d state %d relative error', m, s));
        end
    end
end

function testDelayedInputErrors(testCase)
    params = make_test_params(struct('lags', 0.05));
    S = zeros(state_layout(params).n_total, 1);
    testCase.verifyError(@() compute_J_eff(S, params), ...
        'MESN:DelayedJacobianUnsupported');
end

function testNotesTitleReflectsRestrictedScope(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    notes = fileread(fullfile(repo_root, 'src', 'algorithms', 'Jacobian', 'J_eff_notes.md'));
    testCase.verifyTrue(contains(notes, ...
        'Quasi-static fast-subsystem Jacobian for the non-delayed ODE'));
    testCase.verifyTrue(contains(notes, 'conditional, not universal'));
    testCase.verifyTrue(contains(notes, 'DDE ESP proof'));
    testCase.verifyTrue(contains(notes, 'DelayedJacobianUnsupported'));
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
