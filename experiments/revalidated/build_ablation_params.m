function [params, meta] = build_ablation_params(cell_spec, base_seed, cfg, overrides)
% build_ablation_params  Paired MESN params for one ablation cell and base seed.
%
% Identical base_seed yields identical W0 / W_in across mechanism cells whenever
% dimensions permit (same n, n_inputs, dale, scaling target).

    if nargin < 4 || isempty(overrides)
        overrides = struct();
    end

    ov = cfg.base;
    ov.weight_rng_seed = base_seed;
    ov.input_rng_seed = base_seed + 1;
    ov.n_a_E = cell_spec.n_a_E;
    ov.n_a_I = cell_spec.n_a_I;
    ov.n_b_E = cell_spec.n_b_E;
    ov.n_b_I = cell_spec.n_b_I;
    ov.lags = cell_spec.lags;
    ov.which_states = cell_spec.which_states;
    if cell_spec.n_a_E > 0
        ov.c_a_E = cell_spec.c_a_E;
    end
    if cell_spec.n_a_I > 0
        ov.c_a_I = cell_spec.c_a_I;
    end

    % Operating-point fields (T102) may override shared scales.
    if isfield(cfg, 'frozen_operating_point') && ~isempty(cfg.frozen_operating_point)
        ov.input_scaling = cfg.frozen_operating_point.input_scaling;
        ov.level_of_chaos = cfg.frozen_operating_point.level_of_chaos;
    end

    override_fields = fieldnames(overrides);
    for i = 1:numel(override_fields)
        ov.(override_fields{i}) = overrides.(override_fields{i});
    end

    [params, meta] = default_MESN_config(ov);
    meta.input_scaling = ov.input_scaling;
    meta.level_of_chaos = ov.level_of_chaos;
    meta.weight_rng_seed = ov.weight_rng_seed;
    meta.input_rng_seed = ov.input_rng_seed;
end
