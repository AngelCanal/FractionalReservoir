function bench = stimulus_counting_benchmark(esn_or_params, options)
% stimulus_counting_benchmark
% Pulse counting task: reservoir is driven by brief pulses at irregular
% intervals; readout learns to output cumulative count (optionally normalized).
%
% Usage:
%   bench = stimulus_counting_benchmark(params);
%
% Inputs:
%   esn_or_params - SRNN_ESN object OR params struct
%   options - struct (optional)
%       .T            (default 6000)
%       .pulse_width  (default 3)    samples
%       .min_isi      (default 20)   samples
%       .max_isi      (default 120)  samples
%       .amplitude    (default 1.0)
%       .normalize_target (default true)
%       .washout      (default 200)
%       .train_ratio  (default 0.6)
%       .lambda       (default 1e-6)
%       .seed         (default 1)
%       .feature_mode (default 'x')
%
% Output:
%   bench - struct with signals and metrics

    if nargin < 2 || isempty(options)
        options = struct();
    end

    T = getFieldOrDefault(options, 'T', 6000);
    pulse_width = getFieldOrDefault(options, 'pulse_width', 3);
    min_isi = getFieldOrDefault(options, 'min_isi', 20);
    max_isi = getFieldOrDefault(options, 'max_isi', 120);
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
    pulse_times = [];
    t = 1;
    while t <= T - pulse_width
        isi = randi([min_isi, max_isi], 1, 1);
        t = t + isi;
        if t <= T - pulse_width
            u(t:(t+pulse_width-1)) = amplitude;
            pulse_times(end+1) = t; %#ok<AGROW>
        end
    end

    % Target: cumulative count
    y = zeros(T, 1);
    count = 0;
    for i = 1:T
        if u(i) > 0 && (i == 1 || u(i-1) == 0)
            count = count + 1;
        end
        y(i) = count;
    end
    if normalize_target && count > 0
        y = y / count;
    end

    n_train = floor(T * train_ratio);
    u_train = u(1:n_train);
    y_train = y(1:n_train);
    u_test  = u((n_train+1):end);
    y_test  = y((n_train+1):end);

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
    bench.pulse_times = pulse_times(:);
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

