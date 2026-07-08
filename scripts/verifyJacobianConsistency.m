%% verifyJacobianConsistency
% Validate the analytical Jacobians of the MESN reservoir that underpin the
% Lyapunov-spectrum and Echo-State-Property analyses.
%
% Three cross-checks are performed at several realistic states drawn from a
% driven reservoir trajectory:
%
%   (1) compute_Jacobian (dense loop assembly) vs compute_Jacobian_fast
%       (sparse/vectorised assembly). These must agree to machine precision.
%
%   (2) compute_Jacobian (analytical) vs a central finite-difference Jacobian
%       of SRNN_reservoir. These must agree to O(h^2) finite-difference error.
%
%   (3) compute_J_eff (effective dx/dt Jacobian w.r.t. x, with a and b frozen)
%       vs the corresponding dx/dt-by-x block of the full analytical Jacobian.
%       These must agree to machine precision because J_eff is, by definition,
%       that diagonal block:
%           J_eff = (1/tau_d) * (-I + W * diag(b .* phi'(x_eff)))
%
% Outputs a PASS/FAIL summary and (optionally) saves the diagnostics.

clear; clc;

if exist('setup_paths', 'file') == 2
    setup_paths();
end

%% Configuration
[params, ~] = default_MESN_config(struct());

% Total number of system equations (used by several downstream tools).
len_a_E = params.n_E * params.n_a_E;
len_a_I = params.n_I * params.n_a_I;
len_b_E = params.n_E * params.n_b_E;
len_b_I = params.n_I * params.n_b_I;
N_sys_eqs = len_a_E + len_a_I + len_b_E + len_b_I + params.n;
params.N_sys_eqs = N_sys_eqs;

%% Generate realistic states from a short driven run
dt = params.dt;
T = 1500;
T_washout = 500;
rng(7);
U = 0.2 * randn(T, 1);

esn = SRNN_ESN(params);
esn.which_states = 'all';   % keep full state to sample from
esn.resetState();
[~, S_hist] = esn.runReservoir(U);

% Sample a handful of post-transient states
sample_idx = round(linspace(T_washout + 1, T, 6));
n_samples = numel(sample_idx);

% Finite-difference settings: use a fixed time and a constant external input
% so the SRNN_reservoir right-hand side depends only on the state S.
t0 = 0.0;
t_ex = [0, dt];
u_const = 0.2 * randn(params.n, 1);   % arbitrary but fixed drive
u_ex = [u_const, u_const];
rhs = @(S) SRNN_reservoir(t0, S, t_ex, u_ex, params);

h = 1e-6;   % central-difference step

%% Preallocate diagnostics
diag_results = struct( ...
    'idx', num2cell(sample_idx), ...
    'err_fast_vs_full', [], ...
    'rel_fast_vs_full', [], ...
    'err_fd_vs_full', [], ...
    'rel_fd_vs_full', [], ...
    'err_Jeff_vs_block', [], ...
    'rel_Jeff_vs_block', []);

% Index range of the dx/dt-by-x block within the full Jacobian.
row_x = (N_sys_eqs - params.n + 1):N_sys_eqs;
col_x = row_x;

fprintf('Verifying Jacobian consistency at %d states (N_sys_eqs = %d)\n', ...
    n_samples, N_sys_eqs);

for s = 1:n_samples
    S = S_hist(sample_idx(s), :)';

    % --- Analytical Jacobians ---
    J_full = compute_Jacobian(S, params);
    J_fast = full(compute_Jacobian_fast(S, params));

    % --- Finite-difference Jacobian of SRNN_reservoir ---
    J_fd = zeros(N_sys_eqs, N_sys_eqs);
    for k = 1:N_sys_eqs
        Sp = S; Sp(k) = Sp(k) + h;
        Sm = S; Sm(k) = Sm(k) - h;
        J_fd(:, k) = (rhs(Sp) - rhs(Sm)) / (2 * h);
    end

    % --- Effective Jacobian vs full dx/dx block ---
    J_eff = full(compute_J_eff(S, params));
    J_block = J_full(row_x, col_x);

    % --- Errors (max absolute + relative Frobenius) ---
    e_ff = max(abs(J_fast(:) - J_full(:)));
    r_ff = norm(J_fast - J_full, 'fro') / max(norm(J_full, 'fro'), eps);

    e_fd = max(abs(J_fd(:) - J_full(:)));
    r_fd = norm(J_fd - J_full, 'fro') / max(norm(J_full, 'fro'), eps);

    e_je = max(abs(J_eff(:) - J_block(:)));
    r_je = norm(J_eff - J_block, 'fro') / max(norm(J_block, 'fro'), eps);

    diag_results(s).err_fast_vs_full = e_ff;
    diag_results(s).rel_fast_vs_full = r_ff;
    diag_results(s).err_fd_vs_full = e_fd;
    diag_results(s).rel_fd_vs_full = r_fd;
    diag_results(s).err_Jeff_vs_block = e_je;
    diag_results(s).rel_Jeff_vs_block = r_je;

    fprintf(['  state %d (t-index %4d): |fast-full|=%.2e  |fd-full|=%.2e  ' ...
             '|Jeff-block|=%.2e\n'], s, sample_idx(s), e_ff, e_fd, e_je);
end

%% Aggregate and PASS/FAIL
max_ff = max([diag_results.err_fast_vs_full]);
max_fd = max([diag_results.err_fd_vs_full]);
max_je = max([diag_results.err_Jeff_vs_block]);

tol_exact = 1e-9;   % assembly should match to ~machine precision
tol_fd    = 1e-4;   % central FD limited by O(h^2) and phi' curvature

pass_ff = max_ff <= tol_exact;
pass_fd = max_fd <= tol_fd;
pass_je = max_je <= tol_exact;

fprintf('\n================ Jacobian consistency summary ================\n');
fprintf('  fast vs full  : max abs err = %.3e   [tol %.1e]  -> %s\n', ...
    max_ff, tol_exact, ternary(pass_ff, 'PASS', 'FAIL'));
fprintf('  FD  vs full   : max abs err = %.3e   [tol %.1e]  -> %s\n', ...
    max_fd, tol_fd, ternary(pass_fd, 'PASS', 'FAIL'));
fprintf('  J_eff vs block: max abs err = %.3e   [tol %.1e]  -> %s\n', ...
    max_je, tol_exact, ternary(pass_je, 'PASS', 'FAIL'));
fprintf('==============================================================\n');

all_pass = pass_ff && pass_fd && pass_je;
if ~all_pass
    warning('verifyJacobianConsistency:Mismatch', ...
        'One or more Jacobian consistency checks exceeded tolerance.');
else
    fprintf('All Jacobian consistency checks PASSED.\n');
end

%% Optional: persist diagnostics for provenance
try
    out_dir = fullfile(pwd, 'results', 'jacobian_checks');
    if ~exist(out_dir, 'dir'); mkdir(out_dir); end
    save_path = fullfile(out_dir, sprintf('jacobian_consistency_%s.mat', ...
        datestr(now, 'yyyymmdd_HHMMSS')));
    save(save_path, 'diag_results', 'params', 'tol_exact', 'tol_fd', 'all_pass');
    fprintf('Saved diagnostics to %s\n', save_path);
catch ME
    warning('verifyJacobianConsistency:SaveFailed', '%s', ME.message);
end

% -------------------------------------------------------------------------
function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
