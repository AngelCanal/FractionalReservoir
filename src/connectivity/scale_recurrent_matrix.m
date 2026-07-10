function [W, meta] = scale_recurrent_matrix(W0, target, method)
% scale_recurrent_matrix  Scale a recurrent matrix to a target spectral measure.
%
%   [W, meta] = scale_recurrent_matrix(W0, target, method)
%
%   method 'radius'   : target / max(abs(eig(W0)))
%   method 'abscissa' : target / max(real(eig(W0))) for strictly positive abscissa

    if nargin < 3 || isempty(method)
        method = 'abscissa';
    end

    if ~isfinite(target) || target <= 0
        error('MESN:InvalidScaleTarget', ...
            'recurrent_scale_target must be finite and positive.');
    end

    W_eigs = eig(W0);
    norm2 = norm(W0, 2);

    switch lower(method)
        case 'abscissa'
            denom = max(real(W_eigs));
            if denom <= 100 * eps(max(norm2, eps))
                error('MESN:InvalidAbscissaScale', ...
                    'Abscissa scaling requires a strictly positive max(real(eig(W0))).');
            end
        case 'radius'
            denom = max(abs(W_eigs));
            if denom <= 100 * eps(max(norm2, eps))
                error('MESN:InvalidRadiusScale', ...
                    'Radius scaling requires a nonzero spectral radius.');
            end
        otherwise
            error('MESN:InvalidScaleMethod', ...
                'Unknown scale method: %s (use ''abscissa'' or ''radius'')', method);
    end

    factor = target / denom;
    W = factor * W0;

    scaled_eigs = eig(W);
    meta = struct();
    meta.method = lower(method);
    meta.target = target;
    meta.factor = factor;
    meta.unscaled_radius = max(abs(W_eigs));
    meta.scaled_radius = max(abs(scaled_eigs));
    meta.unscaled_abscissa = max(real(W_eigs));
    meta.scaled_abscissa = max(real(scaled_eigs));
    meta.norm2 = norm(W, 2);
    meta.recurrent_scale_target = target;
    meta.level_of_chaos = target;
    assert(meta.recurrent_scale_target == meta.level_of_chaos);
end
