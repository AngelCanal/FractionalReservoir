function [controls, mat_path, run_dir] = package_validation_controls(options)
% package_validation_controls  Build Fig-1 validation_controls.mat from gates.
%
%   [controls, mat_path, run_dir] = package_validation_controls()
%   [controls, mat_path, run_dir] = package_validation_controls(options)
%
% Collects Dale sign counts, Jacobian FD errors (Gate G3), equal-length
% input-isolation flags (Gate G2), and known-system ODE LLE controls (Gate G4).
% Writes validation_controls.mat under results/revalidated/<run_id>/.
%
% Options:
%   .save_results (default true)
%   .n_dale_seeds (default 20)
%   .jac_n_states (default 3)
%   .master_seed  (default 1729)

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if exist('setup_paths', 'file') == 2
        setup_paths();
    end

    save_results = local_get(options, 'save_results', true);
    n_dale_seeds = local_get(options, 'n_dale_seeds', 20);
    jac_n_states = local_get(options, 'jac_n_states', 3);
    master_seed = local_get(options, 'master_seed', 1729);

    fprintf('Packaging validation controls (Dale / Jacobian FD / isolation / LLE)...\n');

    % --- Panel 1: Dale sign counts ---
    dale = collect_dale_sign_counts(n_dale_seeds, master_seed);

    % --- Panel 2: Jacobian finite-difference errors (G3) ---
    jac = verifyJacobianConsistency(struct( ...
        'seed', master_seed, ...
        'n_states', jac_n_states, ...
        'save_results', false));
    jacobian_fd_errors = [[jac.cases.rel_fro_dense_fd]'; [jac.cases.rel_fro_fast_fd]'].';
    jacobian_fd_max_abs = [[jac.cases.max_abs_dense_fd]'; [jac.cases.max_abs_fast_fd]'].';

    % --- Panel 3: Input isolation (G2) ---
    isolation = collect_input_isolation();

    % --- Panel 4: ODE LLE known-system controls (G4) ---
    lle_controls = collect_ode_lle_controls();

    controls = struct();
    controls.dale_sign_counts = dale.counts;           % [E_ok, I_ok] or histogram bars
    controls.dale_violations_E = dale.violations_E;
    controls.dale_violations_I = dale.violations_I;
    controls.dale_n_seeds = dale.n_seeds;
    controls.jacobian_fd_errors = jacobian_fd_errors;
    controls.jacobian_fd_max_abs = jacobian_fd_max_abs;
    controls.jacobian_all_pass = jac.all_pass;
    controls.jacobian_summary = struct( ...
        'max_rel_fro_dense_fd', jac.max_rel_fro_dense_fd, ...
        'max_abs_dense_fd', jac.max_abs_dense_fd, ...
        'max_rel_fro_fast_fd', jac.max_rel_fro_fast_fd, ...
        'max_abs_fast_fd', jac.max_abs_fast_fd, ...
        'n_cases', jac.n_cases);
    controls.input_isolation_pass = isolation.pass_flags;  % [ODE, DDE]
    controls.input_isolation = isolation;
    controls.lle_controls = lle_controls;
    controls.provenance = struct( ...
        'created_utc', char(datetime('now', 'TimeZone', 'UTC', ...
            'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z''')), ...
        'master_seed', master_seed, ...
        'matlab_version', version, ...
        'source', 'package_validation_controls.m', ...
        'gates', {{'G2', 'G3', 'G4', 'Dale'}});

    mat_path = '';
    run_dir = '';
    if save_results
        ctx_opts = struct('master_seed', master_seed);
        if isfield(options, 'run_id'); ctx_opts.run_id = options.run_id; end
        if isfield(options, 'revalidated_root_override')
            ctx_opts.revalidated_root_override = options.revalidated_root_override;
        end
        ctx = create_run_context('validation_controls', ctx_opts);
        run_dir = ctx.run_dir;
        mat_path = fullfile(run_dir, 'validation_controls.mat');
        % Save fields at top level so make_paper_figures load() finds them
        dale_sign_counts = controls.dale_sign_counts; %#ok<NASGU>
        jacobian_fd_errors = controls.jacobian_fd_errors; %#ok<NASGU>
        input_isolation_pass = controls.input_isolation_pass; %#ok<NASGU>
        lle_controls = controls.lle_controls; %#ok<NASGU>
        save(mat_path, 'dale_sign_counts', 'jacobian_fd_errors', ...
            'input_isolation_pass', 'lle_controls', 'controls');
        save_run_manifest(ctx, controls, struct( ...
            'mat_path', mat_path, ...
            'jacobian_all_pass', jac.all_pass, ...
            'isolation_all_pass', all(isolation.pass_flags), ...
            'lle_max_abs_err', max(abs(lle_controls.estimated - lle_controls.true_exponents))));
        fprintf('Wrote %s\n', mat_path);
    end
end

function dale = collect_dale_sign_counts(n_seeds, master_seed)
    violations_E = zeros(n_seeds, 1);
    violations_I = zeros(n_seeds, 1);
    for s = 1:n_seeds
        seed = master_seed + s - 1;
        [~, meta] = default_MESN_config(struct( ...
            'n', 12, ...
            'fraction_E', 0.5, ...
            'dale', true, ...
            'row_center_W', false, ...
            'weight_rng_seed', seed, ...
            'input_rng_seed', seed + 1000, ...
            'lags', []));
        violations_E(s) = meta.sign_violations_E;
        violations_I(s) = meta.sign_violations_I;
    end
    dale = struct();
    dale.n_seeds = n_seeds;
    dale.violations_E = violations_E;
    dale.violations_I = violations_I;
    % Bar chart: [n_seeds_with_zero_E_violations, n_seeds_with_zero_I_violations]
    dale.counts = [sum(violations_E == 0); sum(violations_I == 0)];
    dale.labels = {'E cols nonneg'; 'I cols nonpos'};
end

function isolation = collect_input_isolation()
    isolation = struct();
    isolation.pass_flags = false(1, 2);
    isolation.labels = {'ODE', 'DDE'};

    % ODE: equal-length inputs differing at one sample
    params = make_test_params(struct('lags', []));
    esn = SRNN_ESN(params);
    n = 25;
    U1 = randn(RandStream('mt19937ar', 'Seed', 1729), n, size(params.W_in, 2));
    U2 = U1;
    U2(10, :) = U2(10, :) + 1;
    opts = struct('reset_before', true, 'update_internal_state', false, ...
        'ode_reltol', 1e-8, 'ode_abstol', 1e-10);
    [X1, ~] = esn.runReservoir(U1, opts);
    [X2, ~] = esn.runReservoir(U2, opts);
    isolation.ode_max_diff = max(abs(X1 - X2), [], 'all');
    isolation.pass_flags(1) = isolation.ode_max_diff > 1e-6;

    % DDE
    params_d = make_test_params(struct('lags', 0.05));
    esn_d = SRNN_ESN(params_d);
    U1d = randn(RandStream('mt19937ar', 'Seed', 1730), n, 1);
    U2d = U1d;
    U2d(15) = U2d(15) + 2;
    opts_d = struct('reset_before', true, 'update_internal_state', false, ...
        'dde_reltol', 1e-7, 'dde_abstol', 1e-9);
    [Y1, ~] = esn_d.runReservoir(U1d, opts_d);
    [Y2, ~] = esn_d.runReservoir(U2d, opts_d);
    isolation.dde_max_diff = max(abs(Y1 - Y2), [], 'all');
    isolation.pass_flags(2) = isolation.dde_max_diff > 1e-6;
end

function lle = collect_ode_lle_controls()
    % Known linear systems: negative and positive scalar exponents + 2-D diagonal
    true_exponents = [-0.5; 0.4; -0.3; -1.1];
    estimated = zeros(size(true_exponents));

    % Scalar stable
    lam = -0.5;
    r = benettin_lle_ode(struct( ...
        'odefun', @(t, x) lam * x, ...
        'x0', 1.0, ...
        'T_interval', [0, 40], ...
        'lya_dt', 0.5, ...
        'seed', 1, ...
        'ode_options', odeset('RelTol', 1e-9, 'AbsTol', 1e-11)));
    estimated(1) = r.LLE;

    % Scalar unstable
    lam = 0.4;
    r = benettin_lle_ode(struct( ...
        'odefun', @(t, x) lam * x, ...
        'x0', 1.0, ...
        'T_interval', [0, 25], ...
        'lya_dt', 0.5, ...
        'seed', 2, ...
        'ode_options', odeset('RelTol', 1e-9, 'AbsTol', 1e-11)));
    estimated(2) = r.LLE;

    % 2-D diagonal via QR spectrum (largest two)
    lam2 = [-0.3; -1.1];
    A = diag(lam2);
    qr = lyapunov_spectrum_qr_ode(struct( ...
        'odefun', @(t, x) A * x, ...
        'jacobian_fun', @(t, x) A, ...
        'x0', [1; 0.5], ...
        'T_interval', [0, 40], ...
        'lya_dt', 0.5, ...
        'ode_solver', @ode45, ...
        'ode_options', odeset('RelTol', 1e-9, 'AbsTol', 1e-11), ...
        'compute_benettin', true, ...
        'seed', 3));
    estimated(3) = qr.LE_spectrum(1);
    estimated(4) = qr.LE_spectrum(2);

    lle = struct();
    lle.true_exponents = true_exponents;
    lle.estimated = estimated;
    lle.labels = {'scalar_stable'; 'scalar_unstable'; 'diag_LE1'; 'diag_LE2'};
    lle.abs_err = abs(estimated - true_exponents);
    lle.tol = 5e-3;
    lle.all_pass = all(lle.abs_err < lle.tol);
end

function v = local_get(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
