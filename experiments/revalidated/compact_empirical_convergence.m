function s = compact_empirical_convergence(esp)
% compact_empirical_convergence  Canonical convergence fields for cell results.

    s = struct();
    s.classification = local_field(esp, 'classification', '');
    s.classification_reason = local_field(esp, 'classification_reason', '');
    s.pair_slopes = local_field(esp, 'pair_slopes', []);
    s.median_pair_slope = local_field(esp, 'median_pair_slope', NaN);
    s.mean_pair_slope = local_field(esp, 'mean_pair_slope', NaN);
    s.slope_per_time_units = local_field(esp, 'slope_per_time_units', 'per_second');
    s.pair_slopes_per_sample_compat = local_field(esp, 'pair_slopes_per_sample_compat', []);
    s.final_max_spread = local_field(esp, 'final_max_spread', NaN);
    s.final_median_spread = local_field(esp, 'final_median_spread', NaN);
    s.convergence_ratio = local_field(esp, 'convergence_ratio', NaN);
    s.n_usable_tail_points = local_field(esp, 'n_usable_tail_points', NaN);
    s.fraction_at_floor = local_field(esp, 'fraction_at_floor', NaN);
    s.fit_interval_seconds = local_field(esp, 'fit_interval_seconds', [NaN, NaN]);
    s.fit_quality_r2 = local_field(esp, 'fit_quality_r2', NaN);
    s.dde_empirical_only = logical(local_field(esp, 'dde_empirical_only', false));
    s.history_space_sampled = logical(local_field(esp, 'history_space_sampled', false));
    s.dde_constant_history_limitation = logical(local_field(esp, ...
        'dde_constant_history_limitation', false));
    if isfield(esp, 'dde_limitation_note')
        s.dde_limitation_note = esp.dde_limitation_note;
    end
    if isfield(esp, 'initial_state_summaries')
        s.initial_state_summaries = esp.initial_state_summaries;
    end
end

function v = local_field(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
