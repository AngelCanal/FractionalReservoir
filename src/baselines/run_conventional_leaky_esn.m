function [H, info] = run_conventional_leaky_esn(U, Wres, Win, alpha, options)
% RUN_CONVENTIONAL_LEAKY_ESN  Discrete leaky tanh ESN state trajectory.
%
%   [H, info] = run_conventional_leaky_esn(U, Wres, Win, alpha)
%   [H, info] = run_conventional_leaky_esn(U, Wres, Win, alpha, options)
%
% Update:
%   h(t) = (1-alpha)*h(t-1) + alpha*tanh(Wres*h(t-1) + Win*u(t))
%
% Features are reservoir states only (no raw input appended). Initial state is
% zero unless options.initial_state is provided.

    if nargin < 5 || isempty(options)
        options = struct();
    end
    if ~(isscalar(alpha) && isfinite(alpha) && alpha >= 0 && alpha <= 1)
        error('run_conventional_leaky_esn:InvalidAlpha', ...
            'leak rate alpha must be in [0, 1].');
    end

    U = U(:, :);
    T = size(U, 1);
    n = size(Wres, 1);
    if size(Wres, 2) ~= n
        error('run_conventional_leaky_esn:BadWres', 'Wres must be square.');
    end
    if size(Win, 1) ~= n || size(Win, 2) ~= size(U, 2)
        error('run_conventional_leaky_esn:BadWin', ...
            'Win size must be [n, n_inputs] matching U.');
    end

    if isfield(options, 'initial_state') && ~isempty(options.initial_state)
        h = options.initial_state(:);
        if numel(h) ~= n
            error('run_conventional_leaky_esn:BadIC', 'initial_state length must be n.');
        end
    else
        h = zeros(n, 1);
    end
    bias = 0;
    if isfield(options, 'reservoir_bias') && ~isempty(options.reservoir_bias)
        bias = options.reservoir_bias;
    end

    H = zeros(T, n);
    for t = 1:T
        pre = Wres * h + Win * U(t, :)' + bias;
        h = (1 - alpha) * h + alpha * tanh(pre);
        H(t, :) = h.';
    end

    info = struct();
    info.feature_dimension = n;
    info.include_input = false;
    info.activation = 'tanh';
    info.leak_rate = alpha;
    info.finite_state_trajectory = all(isfinite(H(:)));
    info.equation = 'h(t)=(1-a)h(t-1)+a*tanh(Wres*h(t-1)+Win*u(t))';
end
