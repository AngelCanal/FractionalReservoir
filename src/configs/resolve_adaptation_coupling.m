function params = resolve_adaptation_coupling(params)
% resolve_adaptation_coupling  Canonical per-timescale adaptation coupling.
%
% Populates c_a_E/c_a_I and c_total_E/c_total_I. Legacy scalar c_E/c_I are
% expanded with MESN:LegacyAdaptationCoupling when c_a_* is absent.

    params = resolve_population_coupling(params, 'E', 0.1/7);
    params = resolve_population_coupling(params, 'I', 0.1/4);
end

function params = resolve_population_coupling(params, pop, default_total)
    n_field = sprintf('n_a_%s', pop);
    c_a_field = sprintf('c_a_%s', pop);
    c_legacy_field = sprintf('c_%s', pop);
    total_field = sprintf('c_total_%s', pop);

    n_a = params.(n_field);
    has_new = isfield(params, c_a_field);
    has_legacy = isfield(params, c_legacy_field);

    if has_new && has_legacy
        error('MESN:AmbiguousAdaptationCoupling', ...
            'Provide either %s or %s, not both.', c_a_field, c_legacy_field);
    end

    if n_a == 0
        params.(c_a_field) = zeros(1, 0);
        params.(total_field) = 0;
        if isfield(params, c_legacy_field)
            params = rmfield(params, c_legacy_field);
        end
        return;
    end

    if has_new
        c_a = params.(c_a_field);
    elseif has_legacy
        warning('MESN:LegacyAdaptationCoupling', ...
            'Scalar %s is deprecated; use %s instead.', c_legacy_field, c_a_field);
        c_a = params.(c_legacy_field) * ones(1, n_a);
        params = rmfield(params, c_legacy_field);
    else
        c_a = ones(1, n_a) * (default_total / n_a);
    end

    params.(c_a_field) = c_a;
    params.(total_field) = sum(c_a);
end
