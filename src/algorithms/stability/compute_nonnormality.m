function nn = compute_nonnormality(A, options)
% compute_nonnormality
% Non-normality and transient-growth diagnostics for a (real) square matrix.
%
% Non-normal matrices (A A' ~= A' A) can exhibit large transient amplification
% even when every eigenvalue is stable. This is the "how quickly does it blow
% up" question raised in the project notes, and it is quantified here through
% four complementary measures used in the paper (Result 2 supporting analysis).
%
% Usage:
%   nn = compute_nonnormality(A);
%   nn = compute_nonnormality(A, struct('do_transient', true));
%
% Inputs:
%   A       - (n x n) matrix (e.g. W, or the effective Jacobian J_eff)
%   options - struct (optional)
%       .do_transient   (default true)  compute max_t ||expm(tA)|| envelope
%       .t_grid         (default linspace(0,20,200)) time grid for transient
%       .n_eta          (default 24)   resolvent grid points in Re(z)>0
%       .n_omega        (default 121)  resolvent grid points along Im(z)
%
% Output:
%   nn - struct with fields:
%       .departure_F            Henrici departure from normality (Frobenius)
%       .departure_F_norm       departure_F / ||A||_F  (0 = normal)
%       .numerical_abscissa     max eig of (A+A')/2  (initial growth rate of ||e^{tA}||)
%       .spectral_abscissa      max real part of eig(A)
%       .norm2                  largest singular value ||A||_2
%       .spectral_radius        max |eig(A)|
%       .kreiss_lb              continuous Kreiss constant lower bound (see notes)
%       .max_transient_growth   sup_t ||expm(tA)||_2  (>=1; large => strong transient)
%       .t_at_max_growth        time achieving the transient peak
%       .is_stable              spectral_abscissa < 0
%
% References: Trefethen & Embree, "Spectra and Pseudospectra" (2005).

    if nargin < 2 || isempty(options)
        options = struct();
    end
    do_transient = getFieldOrDefault(options, 'do_transient', true);
    t_grid = getFieldOrDefault(options, 't_grid', linspace(0, 20, 200));
    n_eta = getFieldOrDefault(options, 'n_eta', 24);
    n_omega = getFieldOrDefault(options, 'n_omega', 121);

    nn = struct();
    n = size(A, 1);
    nn.n = n;

    if any(~isfinite(A(:)))
        nn.departure_F = nan; nn.departure_F_norm = nan;
        nn.numerical_abscissa = nan; nn.spectral_abscissa = nan;
        nn.norm2 = nan; nn.spectral_radius = nan; nn.kreiss_lb = nan;
        nn.max_transient_growth = nan; nn.t_at_max_growth = nan;
        nn.is_stable = false;
        return;
    end

    ev = eig(full(A));
    nn.spectral_abscissa = max(real(ev));
    nn.spectral_radius = max(abs(ev));
    nn.norm2 = norm(full(A), 2);
    nn.is_stable = nn.spectral_abscissa < 0;

    % Henrici departure from normality (Frobenius):
    %   d_F(A)^2 = ||A||_F^2 - sum_i |lambda_i|^2  >= 0
    fro2 = norm(A, 'fro')^2;
    dep2 = max(fro2 - sum(abs(ev).^2), 0);
    nn.departure_F = sqrt(dep2);
    nn.departure_F_norm = nn.departure_F / max(sqrt(fro2), eps);

    % Numerical abscissa: largest eigenvalue of the symmetric part.
    % Equals d/dt ||e^{tA}|| at t=0; positive => guaranteed initial growth.
    S = (full(A) + full(A)') / 2;
    nn.numerical_abscissa = max(real(eig(S)));

    % Continuous-time Kreiss constant lower bound:
    %   K(A) = sup_{Re(z) > 0} Re(z) * ||(zI - A)^{-1}||_2
    % Scanned on a grid shifted just past the spectral abscissa so that the
    % supremum region Re(z) > alpha is sampled. For a stable matrix the
    % Kreiss matrix theorem bounds sup_t ||e^{tA}|| between K and e*n*K.
    alpha = nn.spectral_abscissa;
    eta_min = max(1e-3, 0.01 * max(abs(alpha), 1));
    eta_max = max(2.0, 3 * max(abs(alpha), 1));
    etas = linspace(eta_min, eta_max, n_eta);
    im_span = max(1.5 * nn.spectral_radius, 1);
    omegas = linspace(-im_span, im_span, n_omega);
    In = eye(n);
    kreiss = 0;
    for e = etas
        re = alpha + e;              % ensure we are to the right of the spectrum
        for w = omegas
            z = re + 1i * w;
            R = (z * In - full(A));
            % ||R^{-1}||_2 = 1 / sigma_min(R)
            sm = min(svd(R));
            if sm > 0
                val = e * (1 / sm);  % weight by distance past the abscissa
                if val > kreiss
                    kreiss = val;
                end
            end
        end
    end
    nn.kreiss_lb = kreiss;

    % Direct transient-growth envelope sup_t ||expm(tA)||_2.
    if do_transient
        gmax = 1; targ = 0;
        for tt = t_grid
            g = norm(expm(full(A) * tt), 2);
            if g > gmax
                gmax = g; targ = tt;
            end
        end
        nn.max_transient_growth = gmax;
        nn.t_at_max_growth = targ;
    else
        nn.max_transient_growth = nan;
        nn.t_at_max_growth = nan;
    end
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end
