function weights = caputo_l1_weights(alpha, n_terms)
%CAPUTO_L1_WEIGHTS L1 Caputo convolution weights on a uniform grid.
%
%   weights = caputo_l1_weights(alpha, n_terms)
%
% For 0 < alpha < 1 and k = 0,...,n_terms-1:
%
%   w_k(alpha) = (k+1)^(1-alpha) - k^(1-alpha)
%
% with w_0 = 1 exactly.
%
% For alpha == 1 (exact comparison), returns the limiting sequence
% [1; zeros(n_terms-1,1)] via a dedicated branch (never by evaluating
% k^(1-alpha)).
%
% Near alpha -> 1^-, uses the stable equivalent for k >= 1:
%
%   p = 1 - alpha
%   w_k = exp(p*log(k)) * expm1(p*log1p(1/k))
%
% Returns a double column vector. No persistent or global caches.

    validate_alpha(alpha);
    validate_n_terms(n_terms);

    n_terms = double(n_terms);
    if n_terms == 0
        weights = zeros(0, 1);
        return;
    end

    weights = zeros(n_terms, 1);
    weights(1) = 1;  % w_0

    if alpha == 1
        % Dedicated limiting branch: [1; 0; 0; ...]
        return;
    end

    p = 1 - alpha;
    for k = 1:(n_terms - 1)
        % Stable form of (k+1)^p - k^p
        weights(k + 1) = exp(p * log(k)) * expm1(p * log1p(1 / k));
    end

    if any(~isfinite(weights)) || any(weights <= 0)
        error('caputo_l1_weights:NonPositiveWeight', ...
            'L1 weights must be finite and positive.');
    end
end

function validate_alpha(alpha)
    if ~isnumeric(alpha) || ~isscalar(alpha) || ~isreal(alpha) || ~isfinite(alpha)
        error('caputo_l1_weights:InvalidAlpha', ...
            'alpha must be a finite real scalar.');
    end
    if ~(alpha > 0 && alpha <= 1)
        error('caputo_l1_weights:AlphaOutOfRange', ...
            'alpha must satisfy 0 < alpha <= 1.');
    end
end

function validate_n_terms(n_terms)
    if ~isnumeric(n_terms) || ~isscalar(n_terms) || ~isreal(n_terms) || ~isfinite(n_terms)
        error('caputo_l1_weights:InvalidNTerms', ...
            'n_terms must be a finite real scalar.');
    end
    if n_terms < 0 || n_terms ~= floor(n_terms)
        error('caputo_l1_weights:InvalidNTerms', ...
            'n_terms must be a finite nonnegative integer.');
    end
end
