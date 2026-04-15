function bench = frequency_discrimination_benchmark(esn_or_params, options)
% frequency_discrimination_benchmark
% Frequency tracking task: input is a sine wave whose frequency changes at
% random intervals; readout predicts the current frequency.
%
% Usage:
%   bench = frequency_discrimination_benchmark(params);
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct
%   options - struct (optional)
%       .T            (default 8000)
%       .dt           (default 0.1)   used for generating sine phase
%       .freq_set     (default [0.02 0.05 0.1 0.2 0.4]) cycles/sec
%       .min_seg      (default 200)   samples
%       .max_seg      (default 800)   samples
%       .amplitude    (default 1.0)
%       .normalize_target (default true)
%       .washout      (default 200)
%       .train_ratio  (default 0.6)
%       .lambda       (default 1e-6)
%       .seed         (default 1)
%       .feature_mode (default 'x')
%
% Output:
%   bench - struct with signals, metrics, and predictions

    if nargin < 2 || isempty(options)
        options = struct();
    end

    T = getFieldOrDefault(options, 'T', 8000);
    dt = getFieldOrDefault(options, 'dt', 0.1);
    freq_set = getFieldOrDefault(options, 'freq_set', [0.02 0.05 0.1 0.2 0.4]);
    min_seg = getFieldOrDefault(options, 'min_seg', 200);
    max_seg = getFieldOrDefault(options, 'max_seg', 800);
    amplitude = getFieldOrDefault(options, 'amplitude', 1.0);
    normalize_target = getFieldOrDefault(options, 'normalize_target', true);
    washout = getFieldOrDefault(options, 'washout', 200);
    train_ratio = getFieldOrDefault(options, 'train_ratio', 0.6);
    lambda = getFieldOrDefault(options, 'lambda', 1e-6);
    seed = getFieldOrDefault(options, 'seed', 1);
    feature_mode = getFieldOrDefault(options, 'feature_mode', 'x');

    if isa(esn_or_params, 'SRNN_ESN')
        esn = esn_or_params;
    else
        esn = SRNN_ESN(esn_or_params);
    end

    esn.which_states = feature_mode;
    esn.include_input = false;
    esn.lambda = lambda;

    rng(seed);

    u = zeros(T, 1);
    y = zeros(T, 1);

    t = (0:(T-1))' * dt;
    idx = 1;
    phase0 = 0;
    seg_info = [];

    while idx <= T
        seg_len = randi([min_seg, max_seg], 1, 1);
        seg_end = min(T, idx + seg_len - 1);
        f = freq_set(randi(numel(freq_set), 1, 1));

        tt = t(idx:seg_end);
        % continuous phase to avoid discontinuity at segment boundaries
        u(idx:seg_end) = amplitude * sin(2*pi*f*(tt - tt(1)) + phase0);
        y(idx:seg_end) = f;

        % update phase offset for next segment
        phase0 = 2*pi*f*(tt(end) - tt(1) + dt) + phase0;

        seg_info = [seg_info; idx, seg_end, f]; %#ok<AGROW>
        idx = seg_end + 1;
    end

    if normalize_target
        y_min = min(freq_set);
        y_max = max(freq_set);
        if y_max > y_min
            y = (y - y_min) / (y_max - y_min);
        end
    end

    n_train = floor(T * train_ratio);
    u_train = u(1:n_train);
    y_train = y(1:n_train);
    u_test = u((n_train+1):end);
    y_test = y((n_train+1):end);

    esn.resetState();
    [Xtr, ~] = esn.runReservoir(u_train);
    Xtr = Xtr((washout+1):end, :);
    ytr = y_train((washout+1):end);

    n_feat = size(Xtr, 2);
    W_ridge = (Xtr' * Xtr) + lambda * eye(n_feat);
    Wout = W_ridge \ (Xtr' * ytr);
    bout = mean(ytr - Xtr * Wout, 1);

    y_pred_train = Xtr * Wout + bout;
    metrics_train = compute_metrics(y_pred_train, ytr);

    esn.resetState();
    [Xte, ~] = esn.runReservoir(u_test);
    Xte = Xte((washout+1):end, :);
    yte = y_test((washout+1):end);
    y_pred_test = Xte * Wout + bout;
    metrics_test = compute_metrics(y_pred_test, yte);

    bench = struct();
    bench.options = options;
    bench.u = u;
    bench.y = y;
    bench.seg_info = seg_info;
    bench.metrics_train = metrics_train;
    bench.metrics_test = metrics_test;
    bench.y_pred_test = y_pred_test;
    bench.y_test = yte;
    bench.Wout = Wout;
    bench.bout = bout;
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

