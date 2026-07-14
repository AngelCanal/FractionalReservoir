function [params, meta] = build_ablation_params(cell_spec, base_seed, cfg, overrides)
% build_ablation_params  Paired MESN params for one ablation cell and base seed.
%
% Identical base_seed yields identical W0 / W_in across mechanism cells whenever
% dimensions permit (same n, n_inputs, dale, scaling target, input_mask_mode).
% Explicit tau_a_* from the cell profile are passed through so publication
% profiles never fall back to default_MESN_config logspace.

    if nargin < 4 || isempty(overrides)
        overrides = struct();
    end

    ov = cfg.base;
    ov.weight_rng_seed = base_seed;
    ov.input_rng_seed = base_seed + 1;
    ov.state_rng_seed = base_seed + 2;
    ov.n_a_E = cell_spec.n_a_E;
    ov.n_a_I = cell_spec.n_a_I;
    ov.n_b_E = cell_spec.n_b_E;
    ov.n_b_I = cell_spec.n_b_I;
    ov.lags = cell_spec.lags;
    ov.which_states = cell_spec.which_states;

    % Explicit profile vectors (required for publication fairness).
    if isfield(cell_spec, 'tau_a_E')
        ov.tau_a_E = cell_spec.tau_a_E;
    end
    if isfield(cell_spec, 'tau_a_I')
        ov.tau_a_I = cell_spec.tau_a_I;
    end
    if cell_spec.n_a_E > 0
        ov.c_a_E = cell_spec.c_a_E;
    end
    if cell_spec.n_a_I > 0
        ov.c_a_I = cell_spec.c_a_I;
    end

    if ~isfield(ov, 'input_mask_mode') || isempty(ov.input_mask_mode)
        ov.input_mask_mode = 'fixed_count';
    end
    if ~isfield(ov, 'adaptation_initialization_mode') || ...
            isempty(ov.adaptation_initialization_mode)
        ov.adaptation_initialization_mode = 'paired_weighted_match';
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

    % Propagate scientific metadata for summaries / manifests / fingerprints.
    if isfield(cell_spec, 'adaptation') || isfield(cell_spec, 'adaptation_profile_label')
        if isfield(cell_spec, 'adaptation_profile_label')
            params.adaptation_profile_label = cell_spec.adaptation_profile_label;
        else
            params.adaptation_profile_label = cell_spec.adaptation;
        end
    end
    if isfield(cell_spec, 'analysis_set')
        params.analysis_set = cell_spec.analysis_set;
    end
    if isfield(cell_spec, 'analysis_role')
        params.analysis_role = cell_spec.analysis_role;
    end
    if isfield(cell_spec, 'feature_analysis_role')
        params.feature_analysis_role = cell_spec.feature_analysis_role;
    end
    if isfield(cell_spec, 'raw_feature_dimension')
        params.raw_feature_dimension = cell_spec.raw_feature_dimension;
    end
    if isfield(cell_spec, 'projected_feature_dimension')
        params.projected_feature_dimension = cell_spec.projected_feature_dimension;
    end
    if isfield(cell_spec, 'dimension_matched')
        params.dimension_matched = cell_spec.dimension_matched;
    end

    meta.input_scaling = ov.input_scaling;
    meta.level_of_chaos = ov.level_of_chaos;
    meta.weight_rng_seed = ov.weight_rng_seed;
    meta.input_rng_seed = ov.input_rng_seed;
    meta.state_rng_seed = ov.state_rng_seed;
    meta.input_mask_mode = params.input_mask_mode;
    meta.adaptation_initialization_mode = params.adaptation_initialization_mode;
    if isfield(params, 'input_driven_indices')
        meta.input_driven_indices = params.input_driven_indices;
    end
    if isfield(params, 'input_nnz_per_channel')
        meta.input_nnz_per_channel = params.input_nnz_per_channel;
    end
    if isfield(params, 'adaptation_profile_label')
        meta.adaptation_profile_label = params.adaptation_profile_label;
    end
end
