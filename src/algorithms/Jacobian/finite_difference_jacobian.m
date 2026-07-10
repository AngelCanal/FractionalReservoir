function J_fd = finite_difference_jacobian(rhs, S, options)
% FINITE_DIFFERENCE_JACOBIAN  Central finite-difference Jacobian of an RHS.
%
%   J_fd = finite_difference_jacobian(rhs, S)
%   J_fd = finite_difference_jacobian(rhs, S, options)
%
% rhs must be a function handle @(S) -> dS/dt of the same length as S.
% Default per-coordinate step: h_j = sqrt(eps) * (1 + abs(S_j)).
% Override with options.h (scalar) or options.h_vec (length(S) vector).

    if nargin < 3
        options = struct();
    end

    S = S(:);
    N = numel(S);
    if N < 1
        error('MESN:InvalidStateLength', 'S must be nonempty.');
    end
    if any(~isfinite(S))
        error('MESN:InvalidStateShape', 'S must be finite.');
    end
    if ~isa(rhs, 'function_handle')
        error('finite_difference_jacobian:InvalidRHS', ...
            'rhs must be a function handle.');
    end

    if isfield(options, 'h_vec') && ~isempty(options.h_vec)
        h = options.h_vec(:);
        if numel(h) ~= N
            error('finite_difference_jacobian:InvalidStep', ...
                'options.h_vec must have length numel(S).');
        end
    elseif isfield(options, 'h') && ~isempty(options.h)
        h = options.h * ones(N, 1);
    else
        h = sqrt(eps) * (1 + abs(S));
    end

    if any(~isfinite(h)) || any(h <= 0)
        error('finite_difference_jacobian:InvalidStep', ...
            'Finite-difference steps must be finite and positive.');
    end

    J_fd = zeros(N, N);
    for j = 1:N
        Sp = S;
        Sm = S;
        Sp(j) = Sp(j) + h(j);
        Sm(j) = Sm(j) - h(j);
        J_fd(:, j) = (rhs(Sp) - rhs(Sm)) / (2 * h(j));
    end
end
