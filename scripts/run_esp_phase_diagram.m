%% run_esp_phase_diagram
% Empirical Echo State Property (ESP) phase diagram vs adaptation strength,
% with the analytical contraction boundary from J_eff_notes.md overlaid.
%
% Result 1 of the paper workplan. The reservoir is swept over a 2D grid of
%   x-axis : level_of_chaos      (spectral scaling of W)
%   y-axis : adapt_scale         (multiplier on the SFA strengths c_E, c_I)
% For each grid cell we:
%   (1) verify the ESP empirically with verify_echo_state_property, and
%   (2) evaluate the analytical gain g_max = max_j b_j phi'(x_eff_j) over a
%       driven trajectory together with ||W||_2, so the theoretical ESP
%       boundary ||W||_2 * g_max = 1 (Eq. ESP* in J_eff_notes.md) can be drawn.
%
% The prediction is that the empirical ESP region lies inside (is more
% permissive than) the conservative analytical boundary, and that increasing
% adaptation restores the ESP at higher levels of chaos.
%
% Output: results/esp_phase/esp_phase_<timestamp>.mat and a figure.

if exist('setup_paths', 'file') == 2
    setup_paths();
end

out_dir = fullfile(pwd, 'results', 'esp_phase');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

%% Grid definition
chaos_vals = linspace(0.8, 3.0, 12);   % x-axis: level_of_chaos
adapt_vals = linspace(0.0, 4.0, 12);   % y-axis: multiplier on c_E, c_I

% Baseline adaptation strengths (multiplied by adapt_scale on the grid)
base_c_E = 0.1/7;
base_c_I = 0.1/4;

%% Driving input and ESP options
dt = 0.1;
T = 3000;
washout = 800;
rng(123);
U = 0.2 * randn(T, 1);

esp_opts = struct('n_ic', 12, 'washout_steps', washout, 'eps_tol', 1e-3, ...
                  'ic_scale', 0.1, 'feature_mode', 'x', 'verbose', false);

%% Sweep (flattened for parfor)
n_c = numel(chaos_vals);
n_a = numel(adapt_vals);
n_cells = n_c * n_a;

esp_holds   = false(n_cells, 1);
final_spread = nan(n_cells, 1);
g_max       = nan(n_cells, 1);
W_norm2     = nan(n_cells, 1);
boundary    = nan(n_cells, 1);   % ||W||_2 * g_max ; ESP* predicts <1 => contracting

fprintf('ESP phase diagram: %d x %d = %d cells\n', n_c, n_a, n_cells);

parfor lin = 1:n_cells
    [ic, ia] = ind2sub([n_c, n_a], lin);

    overrides = struct();
    overrides.dt = dt;
    overrides.level_of_chaos = chaos_vals(ic);
    overrides.c_E = base_c_E * adapt_vals(ia);
    overrides.c_I = base_c_I * adapt_vals(ia);
    overrides.which_states = 'x';
    overrides.include_input = false;

    params = default_MESN_config(overrides);
    esn = SRNN_ESN(params);

    % (1) Empirical ESP
    esp = verify_echo_state_property(esn, U, esp_opts);
    esp_holds(lin) = esp.esp_holds;
    final_spread(lin) = esp.final_spread;

    % (2) Analytical gain and boundary from a driven trajectory
    esn.which_states = 'all';
    esn.resetState();
    [~, S_hist] = esn.runReservoir(U);
    gstat = local_gain_stats(params, S_hist, washout);

    g_max(lin) = gstat;
    W_norm2(lin) = norm(params.W, 2);
    boundary(lin) = W_norm2(lin) * g_max(lin);
end

% Reshape to grids (rows = chaos index, cols = adapt index)
ESP    = reshape(esp_holds, n_c, n_a);
SPREAD = reshape(final_spread, n_c, n_a);
GMAX   = reshape(g_max, n_c, n_a);
WN2    = reshape(W_norm2, n_c, n_a);
BND    = reshape(boundary, n_c, n_a);

save_path = fullfile(out_dir, sprintf('esp_phase_%s.mat', datestr(now, 'yyyymmdd_HHMMSS')));
save(save_path, 'chaos_vals', 'adapt_vals', 'ESP', 'SPREAD', 'GMAX', 'WN2', 'BND', ...
    'U', 'dt', 'washout', 'esp_opts', 'base_c_E', 'base_c_I');

%% Plot: empirical ESP region + analytical boundary contour
figure('Color', 'w');
imagesc(chaos_vals, adapt_vals, double(ESP')); hold on;
set(gca, 'YDir', 'normal');
colormap(gca, [0.85 0.4 0.4; 0.4 0.7 0.9]);   % FAIL (red) / HOLDS (blue)
cb = colorbar; cb.Ticks = [0.25 0.75]; cb.TickLabels = {'ESP fails', 'ESP holds'};

% Analytical boundary: ||W||_2 * g_max = 1
contour(chaos_vals, adapt_vals, BND', [1 1], 'k-', 'LineWidth', 2);

xlabel('level\_of\_chaos  (spectral scaling of W)');
ylabel('adaptation scale  (\times baseline c_E, c_I)');
title('ESP phase diagram (color) with analytical boundary ||W||_2 g_{max}=1 (black)');
grid on;

fprintf('Saved ESP phase diagram to %s\n', save_path);

% -------------------------------------------------------------------------
function g_stat = local_gain_stats(params, S_hist, washout)
% Effective gain statistic g_max = high percentile of b_j * phi'(x_eff_j)
% over the post-transient trajectory. This is the quantity in Eq. (ESP*).
    n = params.n;
    phi_prime = params.activation_function_derivative;

    T = size(S_hist, 1);
    t0 = min(washout + 1, T);
    g_peak = 0;
    for tt = t0:T
        S = S_hist(tt, :)';
        state = unpack_state(S, params);
        a_E = state.a_E;
        a_I = state.a_I;
        b_E = state.b_E;
        b_I = state.b_I;
        x = state.x;

        x_eff = compute_effective_q(state, params);

        b = ones(n, 1);
        if ~isempty(b_E); b(params.E_indices) = b_E; end
        if ~isempty(b_I); b(params.I_indices) = b_I; end

        g = b .* phi_prime(x_eff);
        g_peak = max(g_peak, max(g));
    end
    g_stat = g_peak;
end
