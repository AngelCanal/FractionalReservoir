function u_fun = make_input_interpolant(t_grid, neural_drive)
% make_input_interpolant  Fresh linear input interpolant for one simulation.
%
% u_fun = make_input_interpolant(t_grid, neural_drive)
%   t_grid: strictly increasing vector length T
%   neural_drive: n x T projected drive
%   u_fun(t): n x 1 column vector

    t_grid = t_grid(:);
    if numel(t_grid) < 2
        error('MESN:InvalidInputGrid', 't_grid must contain at least two time points.');
    end
    if any(~isfinite(t_grid)) || any(diff(t_grid) <= 0)
        error('MESN:InvalidInputGrid', 't_grid must be finite and strictly increasing.');
    end

    if size(neural_drive, 2) ~= numel(t_grid)
        error('MESN:InvalidInputGrid', ...
            'neural_drive must be n x T with T = numel(t_grid).');
    end
    if any(~isfinite(neural_drive(:)))
        error('MESN:InvalidInputGrid', 'neural_drive must be finite.');
    end

    n = size(neural_drive, 1);
    F = griddedInterpolant(t_grid, neural_drive', 'linear', 'none');

    u_fun = @eval_input;
    function u = eval_input(t)
        u = F(t);
        u = u(:);
        if numel(u) ~= n || any(~isfinite(u))
            error('MESN:InputTimeOutOfRange', ...
                'Input query at t=%g is out of range or non-finite.', t);
        end
    end
end
