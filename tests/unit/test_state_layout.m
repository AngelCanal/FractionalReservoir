function tests = test_state_layout
tests = functiontests(localfunctions);
end

function testExactMapsTwoEOneI(testCase)
    params = struct();
    params.n = 3;
    params.n_E = 2;
    params.n_I = 1;
    params.n_a_E = 3;
    params.n_a_I = 2;
    params.n_b_E = 1;
    params.n_b_I = 1;
    params.E_indices = 1:2;
    params.I_indices = 3;

    layout = state_layout(params);

    testCase.verifyEqual(layout.len_a_E, 6);
    testCase.verifyEqual(layout.len_a_I, 2);
    testCase.verifyEqual(layout.len_b_E, 2);
    testCase.verifyEqual(layout.len_b_I, 1);
    testCase.verifyEqual(layout.len_x, 3);
    testCase.verifyEqual(layout.n_total, 14);

    testCase.verifyEqual(layout.map_a_E, [1 3 5; 2 4 6]);
    testCase.verifyEqual(layout.map_a_I, [7 8]);
    testCase.verifyEqual(layout.map_b_E, [9; 10]);
    testCase.verifyEqual(layout.map_b_I, 11);
    testCase.verifyEqual(layout.idx_x, 12:14);
end

function testZeroWidthGroups(testCase)
    params = base_params();
    params.n_a_E = 0;
    params.n_a_I = 0;
    params.n_b_E = 0;
    params.n_b_I = 0;

    layout = state_layout(params);
    testCase.verifyEqual(size(layout.map_a_E), [params.n_E, 0]);
    testCase.verifyEqual(size(layout.map_a_I), [params.n_I, 0]);
    testCase.verifyEqual(size(layout.map_b_E), [params.n_E, 0]);
    testCase.verifyEqual(size(layout.map_b_I), [params.n_I, 0]);
    testCase.verifyEqual(layout.n_total, params.n);
end

function testIdentityMapRelation(testCase)
    params = base_params();
    params.n_E = 2;
    params.n_I = 1;
    params.n_a_E = 3;
    layout = state_layout(params);

    for k = 1:params.n_a_E
        for i = 1:params.n_E
            testCase.verifyEqual(layout.map_a_E(i, k), layout.idx_a_E(i + (k - 1) * params.n_E));
        end
    end
end

function testAllMechanismCombinations(testCase)
    combos = { ...
        [0 0 0 0], ...
        [2 1 0 0], ...
        [0 0 1 1], ...
        [2 1 1 1] ...
    };

    for c = 1:numel(combos)
        params = base_params();
        params.n_a_E = combos{c}(1);
        params.n_a_I = combos{c}(2);
        params.n_b_E = combos{c}(3);
        params.n_b_I = combos{c}(4);
        layout = state_layout(params);

        all_idx = [layout.idx_a_E(:); layout.idx_a_I(:); layout.idx_b_E(:); layout.idx_b_I(:); layout.idx_x(:)];
        testCase.verifyEqual(numel(unique(all_idx)), layout.n_total);
        testCase.verifyEqual(sort(all_idx), (1:layout.n_total)');
    end
end

function params = base_params()
    params.n = 3;
    params.n_E = 2;
    params.n_I = 1;
    params.n_a_E = 1;
    params.n_a_I = 1;
    params.n_b_E = 1;
    params.n_b_I = 1;
    params.E_indices = 1:2;
    params.I_indices = 3;
end
