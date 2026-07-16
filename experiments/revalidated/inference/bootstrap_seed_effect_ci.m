function out = bootstrap_seed_effect_ci(effect_oriented, n_replicates, alpha, stream, rng_namespace)
%BOOTSTRAP_SEED_EFFECT_CI  Seed-level percentile bootstrap intervals.
%
%   out = bootstrap_seed_effect_ci(effect_oriented, n_replicates, alpha, stream)
%   out = bootstrap_seed_effect_ci(..., rng_namespace)
%
% Resamples seed-effect rows with replacement. Does not mutate global RNG.
% Never persists RandStream handles; only serializable provenance.

    if nargin < 4 || isempty(stream)
        error('bootstrap_seed_effect_ci:MissingStream', ...
            'A local RandStream must be supplied.');
    end
    if ~isa(stream, 'RandStream')
        error('bootstrap_seed_effect_ci:InvalidStream', ...
            'stream must be a RandStream object.');
    end
    if nargin < 3 || isempty(alpha)
        alpha = 0.05;
    end
    if nargin < 2 || isempty(n_replicates)
        n_replicates = 20000;
    end
    if ~(isscalar(n_replicates) && isfinite(n_replicates) && ...
            n_replicates == round(n_replicates) && n_replicates > 0)
        error('bootstrap_seed_effect_ci:InvalidReplicates', ...
            'n_replicates must be a positive finite integer.');
    end
    if ~(isscalar(alpha) && isfinite(alpha) && alpha > 0 && alpha < 1)
        error('bootstrap_seed_effect_ci:InvalidAlpha', ...
            'alpha must satisfy 0 < alpha < 1.');
    end

    effect_oriented = effect_oriented(:);
    n = numel(effect_oriented);
    if n == 0
        error('bootstrap_seed_effect_ci:EmptyInput', 'effect_oriented must be non-empty.');
    end
    if ~all(isfinite(effect_oriented))
        error('bootstrap_seed_effect_ci:NonFinite', 'effect_oriented must be finite.');
    end

    boot_mean = zeros(n_replicates, 1);
    boot_median = zeros(n_replicates, 1);
    for r = 1:n_replicates
        idx = randi(stream, n, n, 1);
        sample = effect_oriented(idx);
        boot_mean(r) = mean(sample);
        boot_median(r) = median(sample);
    end

    ci_pct = 100 * (1 - alpha);
    lo_pct = (100 - ci_pct) / 2;
    hi_pct = 100 - lo_pct;

    out = struct();
    out.method = 'nonparametric_seed_bootstrap_percentile';
    out.n_replicates = n_replicates;
    out.alpha = alpha;
    out.ci_percent = ci_pct;
    out.mean_point = mean(effect_oriented);
    out.median_point = median(effect_oriented);
    out.mean_ci = prctile(boot_mean, [lo_pct, hi_pct]);
    out.median_ci = prctile(boot_median, [lo_pct, hi_pct]);
    out.mean_bootstrap_se = std(boot_mean, 0);
    out.median_bootstrap_se = std(boot_median, 0);
    out.rng_algorithm = stream.Type;
    out.rng_seed = stream.Seed;
    if nargin >= 5 && ~isempty(rng_namespace)
        out.rng_namespace_digest = canonical_sha256(rng_namespace);
    else
        out.rng_namespace_digest = '';
    end
end
