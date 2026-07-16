function out = paired_sign_flip_test(effect_oriented, options)
%PAIRED_SIGN_FLIP_TEST  Two-sided paired sign-flip test on mean statistic.
%
%   out = paired_sign_flip_test(effect_oriented)
%   out = paired_sign_flip_test(effect_oriented, options)
%
% Statistic: abs(mean(effect_oriented)). Exact enumeration for n<=16;
% Monte Carlo with plus-one correction otherwise. Local RandStream required
% for Monte Carlo paths only.

    if nargin < 2
        options = struct();
    end

    effect_oriented = effect_oriented(:);
    n = numel(effect_oriented);
    if n == 0
        error('paired_sign_flip_test:EmptyInput', 'effect_oriented must be non-empty.');
    end
    if ~all(isfinite(effect_oriented))
        error('paired_sign_flip_test:NonFinite', 'effect_oriented must be finite.');
    end

    tol = local_get(options, 'comparison_tolerance', 1e-12);
    exact_max_n = local_get(options, 'exact_max_n', 16);
    mc_replicates = local_get(options, 'mc_replicates', 100000);

    if ~(isscalar(exact_max_n) && isfinite(exact_max_n) && ...
            exact_max_n == round(exact_max_n) && exact_max_n >= 0)
        error('paired_sign_flip_test:InvalidExactMaxN', ...
            'exact_max_n must be a nonnegative integer.');
    end
    if ~(isscalar(mc_replicates) && isfinite(mc_replicates) && ...
            mc_replicates == round(mc_replicates) && mc_replicates > 0)
        error('paired_sign_flip_test:InvalidMcReplicates', ...
            'mc_replicates must be a positive integer.');
    end
    if ~(isscalar(tol) && isfinite(tol) && tol >= 0)
        error('paired_sign_flip_test:InvalidTolerance', ...
            'comparison_tolerance must be finite and nonnegative.');
    end

    out = struct();
    out.observed_statistic = abs(mean(effect_oriented));
    out.alternative = 'two_sided';
    out.n = n;

    if all(effect_oriented == 0)
        out.p_value = 1;
        out.method = 'all_zero';
        out.permutations_evaluated = 0;
        out.status = 'all_zero';
        return;
    end

    if n <= exact_max_n
        count_ge = 0;
        n_perm = 2^n;
        for mask = 0:(n_perm - 1)
            signs = bitget(mask, 1:n);
            signs = 2 * signs - 1;  % map {0,1} -> {-1,+1}
            perm_stat = abs(mean(signs(:) .* effect_oriented));
            if perm_stat >= out.observed_statistic - tol
                count_ge = count_ge + 1;
            end
        end
        out.p_value = count_ge / n_perm;
        out.method = 'exact';
        out.permutations_evaluated = n_perm;
        out.monte_carlo_se = NaN;
        out.status = 'defined';
        return;
    end

    stream = local_get(options, 'stream', []);
    if isempty(stream) || ~isa(stream, 'RandStream')
        error('paired_sign_flip_test:MissingStream', ...
            'Monte Carlo sign-flip requires a local RandStream.');
    end

    chunk_size = 10000;
    count_ge = 0;
    remaining = mc_replicates;
    while remaining > 0
        batch = min(chunk_size, remaining);
        for r = 1:batch
            signs = (-1) .^ randi(stream, 2, n, 1);
            perm_stat = abs(mean(signs .* effect_oriented));
            if perm_stat >= out.observed_statistic - tol
                count_ge = count_ge + 1;
            end
        end
        remaining = remaining - batch;
    end

    out.p_value = (1 + count_ge) / (mc_replicates + 1);
    out.method = 'monte_carlo';
    out.permutations_evaluated = mc_replicates;
    out.monte_carlo_se = sqrt(out.p_value * (1 - out.p_value) / (mc_replicates + 1));
    out.rng_algorithm = stream.Type;
    out.rng_seed = stream.Seed;
    out.status = 'defined';
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
