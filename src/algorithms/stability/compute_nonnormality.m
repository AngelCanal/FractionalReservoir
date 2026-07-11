function nn = compute_nonnormality(A, options)
% compute_nonnormality
% Non-normality and transient-growth diagnostics for a continuous-time generator.
%
% The input A must be a continuous-time linear generator such as the
% quasi-static fast Jacobian J_eff, not the raw recurrent matrix W.
% Spectral abscissa and Kreiss claims are interpreted in continuous time:
%   dx/dt = A x
%
% Usage:
%   nn = compute_nonnormality(A);
%   nn = compute_nonnormality(A, struct('do_transient', true));
%
% Inputs:
%   A       - (n x n) continuous-time generator (e.g. J_eff)
%   options - struct (optional)
%       .do_transient   (default true)  compute max_t ||expm(tA)|| envelope
%       .t_grid         (default linspace(0,20,200)) time grid for transient
%       .eta_grid       (default logspace(-2,1,24)) positive real parts Re(z)
%       .omega_grid     (default symmetric imag grid; see code)
%       .n_eta          (default 24) used if eta_grid omitted
%       .n_omega        (default 121) used if omega_grid omitted
%
% Output:
%   nn - struct with fields:
%       .departure_F            Henrici departure (Frobenius)
%       .departure_F_norm       normalized Henrici departure
%       .numerical_abscissa     max eig of (A+A')/2
%       .spectral_abscissa      max real part of eig(A)
%       .norm2                  ||A||_2
%       .spectral_radius        max |eig(A)|
%       .kreiss_lb              continuous Kreiss lower bound (NaN if unstable)
%       .status                 'ok' | 'unstable_not_applicable' | 'grid_boundary_contact' | ...
%       .eta_grid, .omega_grid  grids used for the resolvent scan
%       .kreiss_at_boundary     true if the maximizing sample touches a grid edge
%       .max_transient_growth, .t_at_max_growth
%       .is_stable              spectral_abscissa < 0
%
% Continuous-time Kreiss constant (lower bound on a documented grid):
%   K(A) ~= sup_{Re(z)>0} Re(z) * ||(z I - A)^{-1}||_2
% evaluated with smallest singular values (no explicit inv).
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
    nn.matrix_role = 'continuous_time_generator';

    if any(~isfinite(A(:)))
        nn = nan_result(nn);
        nn.status = 'nonfinite_input';
        return;
    end

    A = full(A);
    ev = eig(A);
    nn.spectral_abscissa = max(real(ev));
    nn.spectral_radius = max(abs(ev));
    nn.norm2 = norm(A, 2);
    nn.is_stable = nn.spectral_abscissa < 0;

    % Normalized Henrici departure:
    %   sqrt(max(0, ||A||_F^2 - sum |lambda|^2)) / ||A||_F
    fro = norm(A, 'fro');
    fro2 = fro^2;
    dep2 = max(0, fro2 - sum(abs(ev).^2));
    nn.departure_F = sqrt(dep2);
    if fro == 0
        nn.departure_F_norm = 0;
    else
        nn.departure_F_norm = nn.departure_F / fro;
    end

    S = (A + A') / 2;
    nn.numerical_abscissa = max(real(eig(S)));

    % Documented positive-real / symmetric imaginary grids for Re(z) > 0
    if isfield(options, 'eta_grid') && ~isempty(options.eta_grid)
        etas = options.eta_grid(:).';
    else
        etas = logspace(-2, 1, n_eta);
    end
    if isfield(options, 'omega_grid') && ~isempty(options.omega_grid)
        omegas = options.omega_grid(:).';
    else
        im_span = max([1.5 * nn.spectral_radius, 1, 2 * max(etas)]);
        omegas = linspace(-im_span, im_span, n_omega);
    end
    nn.eta_grid = etas;
    nn.omega_grid = omegas;
    nn.eta_bounds = [min(etas), max(etas)];
    nn.omega_bounds = [min(omegas), max(omegas)];

    if ~nn.is_stable
        nn.kreiss_lb = nan;
        nn.kreiss_at_boundary = false;
        nn.status = 'unstable_not_applicable';
        nn = attach_transient(nn, A, do_transient, t_grid);
        return;
    end

    In = eye(n);
    expand_rounds = 0;
    max_expand = 4;
    while true
        [kreiss, best_eta, best_omega] = scan_kreiss(A, In, etas, omegas, n);
        touch_eta_lo = isfinite(best_eta) && abs(best_eta - min(etas)) <= 10*eps(min(etas));
        touch_eta_hi = isfinite(best_eta) && abs(best_eta - max(etas)) <= 10*eps(max(etas));
        touch_omega = isfinite(best_omega) && ...
            (abs(best_omega - min(omegas)) <= 10*eps(abs(min(omegas))+1) || ...
             abs(best_omega - max(omegas)) <= 10*eps(abs(max(omegas))+1));

        need_expand = false;
        if touch_eta_lo && expand_rounds < max_expand
            etas = unique([logspace(log10(min(etas))-1, log10(min(etas)), 8), etas]);
            need_expand = true;
        end
        if touch_eta_hi && expand_rounds < max_expand
            eta_max_old = max(etas);
            etas_new = logspace(log10(eta_max_old), log10(eta_max_old)+1, 10);
            [kreiss_new, ~, ~] = scan_kreiss(A, In, etas_new, omegas, n);
            % If the outer-eta asymptote has plateaued, accept without further expansion
            if abs(kreiss_new - kreiss) <= 1e-3 * max(1, kreiss)
                touch_eta_hi = false;
            else
                etas = unique([etas, etas_new]);
                need_expand = true;
            end
        end
        if touch_omega && expand_rounds < max_expand
            span = max(abs(omegas));
            omegas = linspace(-2*span, 2*span, max(numel(omegas), 2*numel(omegas)-1));
            need_expand = true;
        end

        if ~need_expand
            break;
        end
        expand_rounds = expand_rounds + 1;
    end

    nn.eta_grid = etas;
    nn.omega_grid = omegas;
    nn.eta_bounds = [min(etas), max(etas)];
    nn.omega_bounds = [min(omegas), max(omegas)];
    nn.kreiss_lb = kreiss;
    nn.kreiss_maximizer = [best_eta, best_omega];
    nn.kreiss_grid_expansions = expand_rounds;

    touch_eta = isfinite(best_eta) && ...
        (abs(best_eta - min(etas)) <= 10*eps(min(etas)) || ...
         abs(best_eta - max(etas)) <= 10*eps(max(etas)));
    touch_omega = isfinite(best_omega) && ...
        (abs(best_omega - min(omegas)) <= 10*eps(abs(min(omegas))+1) || ...
         abs(best_omega - max(omegas)) <= 10*eps(abs(max(omegas))+1));
    % Outer-eta contact after plateau check is asymptotic for many normal generators
    asymptotic_ok = touch_eta && abs(best_eta - max(etas)) <= 10*eps(max(etas)) && ...
        ~touch_omega && abs(best_eta - min(etas)) > 10*eps(min(etas));
    nn.kreiss_at_boundary = (touch_eta || touch_omega) && ~asymptotic_ok;
    if nn.kreiss_at_boundary
        nn.status = 'grid_boundary_contact';
        warning('compute_nonnormality:GridBoundaryContact', ...
            ['Kreiss maximizer touches the documented grid boundary ', ...
             '(eta=%.3g, omega=%.3g). Expand eta_grid/omega_grid before ', ...
             'interpreting kreiss_lb.'], best_eta, best_omega);
    else
        nn.status = 'ok';
    end

    nn = attach_transient(nn, A, do_transient, t_grid);
end

function [kreiss, best_eta, best_omega] = scan_kreiss(A, In, etas, omegas, n)
    kreiss = 0;
    best_eta = nan;
    best_omega = nan;
    for e = etas
        for w = omegas
            z = e + 1i * w;
            R = z * In - A;
            if n <= 32
                sm = min(svd(R));
            else
                sm = svds(R, 1, 'smallest');
                if isempty(sm) || ~(sm > 0) || ~isfinite(sm)
                    sm = min(svd(R));
                end
            end
            if sm > 0 && isfinite(sm)
                val = e * (1 / sm);
                if val > kreiss
                    kreiss = val;
                    best_eta = e;
                    best_omega = w;
                end
            end
        end
    end
end

function nn = nan_result(nn)
    nn.departure_F = nan;
    nn.departure_F_norm = nan;
    nn.numerical_abscissa = nan;
    nn.spectral_abscissa = nan;
    nn.norm2 = nan;
    nn.spectral_radius = nan;
    nn.kreiss_lb = nan;
    nn.max_transient_growth = nan;
    nn.t_at_max_growth = nan;
    nn.is_stable = false;
    nn.kreiss_at_boundary = false;
    nn.eta_grid = [];
    nn.omega_grid = [];
    nn.eta_bounds = [nan, nan];
    nn.omega_bounds = [nan, nan];
end

function nn = attach_transient(nn, A, do_transient, t_grid)
    if do_transient
        gmax = 1;
        targ = 0;
        for tt = t_grid
            g = norm(expm(A * tt), 2);
            if g > gmax
                gmax = g;
                targ = tt;
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
