function [Wres, info] = build_conventional_leaky_esn_Wres(n, spectral_radius, seed)
% BUILD_CONVENTIONAL_LEAKY_ESN_WRES  Unconstrained dense tanh-ESN recurrent matrix.
%
%   [Wres, info] = build_conventional_leaky_esn_Wres(n, spectral_radius, seed)
%
% Dense Gaussian (no Dale constraints). Scaled so max|eig(Wres)| equals the
% requested spectral radius.

    if ~(isscalar(n) && n == floor(n) && n >= 1)
        error('build_conventional_leaky_esn_Wres:InvalidN', 'n must be a positive integer.');
    end
    if ~(isscalar(spectral_radius) && isfinite(spectral_radius) && spectral_radius > 0)
        error('build_conventional_leaky_esn_Wres:InvalidRho', ...
            'spectral_radius must be a positive finite scalar.');
    end

    stream = RandStream('mt19937ar', 'Seed', seed);
    W = randn(stream, n, n) / sqrt(n);
    ev = eig(W);
    rho0 = max(abs(ev));
    if ~(isfinite(rho0) && rho0 > 0)
        error('build_conventional_leaky_esn_Wres:ZeroRadius', ...
            'Drawn recurrent matrix has non-positive spectral radius.');
    end
    Wres = W * (spectral_radius / rho0);
    ach = max(abs(eig(Wres)));

    info = struct();
    info.requested_spectral_radius = spectral_radius;
    info.achieved_spectral_radius = ach;
    info.seed = seed;
    info.recurrent_dale_constrained = false;
    info.distribution = 'iid_gaussian_scaled_1_over_sqrt_n';
end
