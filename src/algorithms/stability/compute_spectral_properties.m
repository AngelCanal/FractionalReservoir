function spec = compute_spectral_properties(W, params, options)
% compute_spectral_properties
% Compute eigen-spectrum and summary spectral measures for a matrix W.
%
% Usage:
%   spec = compute_spectral_properties(W);
%   spec = compute_spectral_properties(W, params);
%   spec = compute_spectral_properties(W, params, struct('do_plot', true));
%
% Inputs:
%   W       - (n x n) matrix
%   params  - (optional) struct with fields .n_E, .n_I, .E_indices, .I_indices
%             used only for optional E/I sub-spectrum diagnostics.
%   options - (optional) struct:
%       .do_plot (default false)
%       .plot_title (default '')
%
% Output:
%   spec - struct with fields:
%       .eigvals
%       .spectral_radius          = max(|lambda|)
%       .spectral_abscissa        = max(Re(lambda))
%       .spectral_gap_abscissa    = max(Re(lambda)) - second_max(Re(lambda))
%       .has_nan_inf
%       .n
%     and if params provided:
%       .eigvals_EE, .eigvals_II  (sub-block eigenvalues)

    if nargin < 2
        params = struct();
    end
    if nargin < 3 || isempty(options)
        options = struct();
    end

    do_plot = getFieldOrDefault(options, 'do_plot', false);
    plot_title = getFieldOrDefault(options, 'plot_title', '');

    spec = struct();
    spec.n = size(W, 1);
    spec.has_nan_inf = any(~isfinite(W), 'all');

    if spec.has_nan_inf
        spec.eigvals = complex(nan(spec.n, 1), nan(spec.n, 1));
        spec.spectral_radius = nan;
        spec.spectral_abscissa = nan;
        spec.spectral_gap_abscissa = nan;
        return;
    end

    eigvals = eig(W);
    spec.eigvals = eigvals;
    spec.spectral_radius = max(abs(eigvals));
    re = real(eigvals);
    spec.spectral_abscissa = max(re);
    if numel(re) >= 2
        re_sorted = sort(re, 'descend');
        spec.spectral_gap_abscissa = re_sorted(1) - re_sorted(2);
    else
        spec.spectral_gap_abscissa = nan;
    end

    % Optional E/I block diagnostics (useful for Dale structured W)
    if isfield(params, 'E_indices') && isfield(params, 'I_indices')
        E = params.E_indices(:);
        I = params.I_indices(:);
        if ~isempty(E) && ~isempty(I) && max([E; I]) <= spec.n
            W_EE = W(E, E);
            W_II = W(I, I);
            spec.eigvals_EE = eig(W_EE);
            spec.eigvals_II = eig(W_II);
        end
    end

    if do_plot
        figure('Color', 'w');
        plot(real(eigvals), imag(eigvals), 'k.', 'MarkerSize', 10);
        xlabel('Re(\lambda)');
        ylabel('Im(\lambda)');
        axis equal;
        grid on;
        if isempty(plot_title)
            title(sprintf('Eigenvalues | rho=%.3f, abscissa=%.3f', ...
                spec.spectral_radius, spec.spectral_abscissa));
        else
            title(plot_title);
        end
    end
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

