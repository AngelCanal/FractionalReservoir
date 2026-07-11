function mi = mutual_info_SISO(data_in, data_out, options)
% mutual_info_SISO  Histogram plug-in mutual information (SISO) with null control.
%
% Estimator
%   Plug-in MI from a 2-D histogram:
%     I(X;Y) = sum_{i,j} p_{ij} log2( p_{ij} / (p_i p_j) )
%   with the convention 0*log(...) = 0 (empty cells contribute nothing).
%
% Bin rule
%   Equal-width bins via linspace over the training-segment range of each
%   variable. Bin edges are fitted once on the training segment and reused
%   unchanged on the evaluation segment (no re-fitting on eval data).
%
% Bias control
%   A deterministic permutation null shuffles the evaluation input relative
%   to the output (fixed local RNG stream). Corrected MI is
%     max(0, raw - null_mean).
%
% Occupancy
%   Returns occupied-bin counts. Warns when expected joint-cell occupancy
%   n_eval / (n_bins_in * n_bins_out) is below min_expected_occupancy.
%
% Usage:
%   mi = mutual_info_SISO(x, y);
%   mi = mutual_info_SISO(x, y, struct('n_bins_in', 16, 'n_bins_out', 16));
%
% Inputs are row or column vectors (single channel). Channels-x-time matrices
% with one row are also accepted.
%
% Output struct fields include:
%   .raw, .null_mean, .null_std, .corrected
%   .edges_in, .edges_out
%   .occupied_bins_in, .occupied_bins_out, .occupied_joint
%   .n_train, .n_eval, .expected_cell_occupancy
%   .low_occupancy_warning
%   .estimator, .bin_rule, .status
%
% status is 'ok' when independent/perfect controls are meaningful for the
% chosen binning; callers that fail scientific controls should set
% status='unsupported' rather than retuning the correction.

    if nargin < 3 || isempty(options)
        options = struct();
    end

    x = flatten_channel(data_in, 'data_in');
    y = flatten_channel(data_out, 'data_out');
    if numel(x) ~= numel(y)
        error('mutual_info_SISO:LengthMismatch', ...
            'data_in and data_out must have the same number of samples');
    end
    n = numel(x);
    if n < 4
        error('mutual_info_SISO:TooFewSamples', 'Need at least 4 samples');
    end

    n_bins_in = get_opt(options, 'n_bins_in', 16);
    n_bins_out = get_opt(options, 'n_bins_out', 16);
    n_null = get_opt(options, 'n_null', 20);
    seed = get_opt(options, 'seed', 1);
    min_occ = get_opt(options, 'min_expected_occupancy', 5);
    train_fraction = get_opt(options, 'train_fraction', 0.5);

    if isfield(options, 'x_train') && isfield(options, 'y_train')
        x_train = flatten_channel(options.x_train, 'x_train');
        y_train = flatten_channel(options.y_train, 'y_train');
        x_eval = x;
        y_eval = y;
    else
        n_train = max(2, floor(train_fraction * n));
        n_train = min(n_train, n - 2);
        x_train = x(1:n_train);
        y_train = y(1:n_train);
        x_eval = x((n_train + 1):end);
        y_eval = y((n_train + 1):end);
    end

    edges_in = equal_width_edges(x_train, n_bins_in);
    edges_out = equal_width_edges(y_train, n_bins_out);

    raw = plugin_mi(x_eval, y_eval, edges_in, edges_out);

    stream = RandStream('mt19937ar', 'Seed', seed);
    null_vals = zeros(n_null, 1);
    for k = 1:n_null
        perm = randperm(stream, numel(x_eval));
        null_vals(k) = plugin_mi(x_eval(perm), y_eval, edges_in, edges_out);
    end
    null_mean = mean(null_vals);
    null_std = std(null_vals);

    [occ_in, occ_out, occ_joint] = occupancy_counts(x_eval, y_eval, edges_in, edges_out);
    n_eval = numel(x_eval);
    expected_occ = n_eval / (n_bins_in * n_bins_out);
    low_occ = expected_occ < min_occ;
    if low_occ
        warning('mutual_info_SISO:LowOccupancy', ...
            ['Expected joint-cell occupancy %.2f is below min_expected_occupancy=%g. ', ...
             'MI estimates may be unreliable.'], expected_occ, min_occ);
    end

    mi = struct();
    mi.estimator = 'histogram_plugin';
    mi.bin_rule = 'equal_width_linspace_train_edges';
    mi.raw = raw;
    mi.null_mean = null_mean;
    mi.null_std = null_std;
    mi.null_values = null_vals;
    mi.corrected = max(0, raw - null_mean);
    mi.edges_in = edges_in;
    mi.edges_out = edges_out;
    mi.n_bins_in = n_bins_in;
    mi.n_bins_out = n_bins_out;
    mi.occupied_bins_in = occ_in;
    mi.occupied_bins_out = occ_out;
    mi.occupied_joint = occ_joint;
    mi.n_train = numel(x_train);
    mi.n_eval = n_eval;
    mi.expected_cell_occupancy = expected_occ;
    mi.low_occupancy_warning = low_occ;
    mi.seed = seed;
    mi.n_null = n_null;
    mi.status = 'ok';
end

function x = flatten_channel(data, name)
    if ~isnumeric(data) || isempty(data)
        error('mutual_info_SISO:InvalidData', '%s must be numeric', name);
    end
    if isvector(data)
        x = data(:);
        return;
    end
    if size(data, 1) == 1
        x = data(:);
        return;
    end
    if size(data, 2) == 1
        x = data(:);
        return;
    end
    error('mutual_info_SISO:NotSISO', ...
        '%s must be a single channel (vector or 1 x T)', name);
end

function edges = equal_width_edges(v, n_bins)
    vmin = min(v);
    vmax = max(v);
    if ~(isfinite(vmin) && isfinite(vmax))
        error('mutual_info_SISO:NonFinite', 'Training data must be finite');
    end
    if vmax <= vmin
        pad = max(1, abs(vmin)) * 1e-6;
        edges = linspace(vmin - pad, vmax + pad, n_bins + 1);
    else
        edges = linspace(vmin, vmax, n_bins + 1);
    end
end

function I = plugin_mi(x, y, edges_x, edges_y)
    n = numel(x);
    if n == 0
        I = 0;
        return;
    end
    P_joint = histcounts2(x(:), y(:), edges_x, edges_y);
    P_joint = P_joint / n;
    P_x = sum(P_joint, 2);
    P_y = sum(P_joint, 1);
    I = 0;
    for i = 1:numel(P_x)
        for j = 1:numel(P_y)
            pij = P_joint(i, j);
            if pij <= 0
                continue;
            end
            px = P_x(i);
            py = P_y(j);
            if px <= 0 || py <= 0
                continue;
            end
            I = I + pij * log2(pij / (px * py));
        end
    end
    if ~isfinite(I)
        I = 0;
    end
end

function [occ_x, occ_y, occ_j] = occupancy_counts(x, y, edges_x, edges_y)
    cx = histcounts(x(:), edges_x);
    cy = histcounts(y(:), edges_y);
    cj = histcounts2(x(:), y(:), edges_x, edges_y);
    occ_x = nnz(cx > 0);
    occ_y = nnz(cy > 0);
    occ_j = nnz(cj > 0);
end

function value = get_opt(s, field, default_value)
    if isfield(s, field) && ~isempty(s.(field))
        value = s.(field);
    else
        value = default_value;
    end
end
