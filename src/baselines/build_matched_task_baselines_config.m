function bb = build_matched_task_baselines_config(cfg)
% BUILD_MATCHED_TASK_BASELINES_CONFIG  Frozen Phase 4C-A one-step baselines.
%
%   bb = build_matched_task_baselines_config(cfg)
%
% Candidate grids and selection rules are preregistered. Do not reorder after
% observing results. Conventional ESN is distinct from Dale-only MESN control.

    n = cfg.base.n;
    bb = struct();
    bb.protocol_version = 'matched_task_baselines_v1';
    bb.enabled = true;
    bb.include_input_in_readout = false;
    bb.readout_solver = 'phase4a_economy_svd';
    bb.validation_metric = 'nrmse';
    bb.validation_tie_tolerance = 1e-12;
    bb.comparison_sign_convention = [ ...
        'improvement_nrmse = baseline_nrmse - model_nrmse; ', ...
        'improvement_nrmse > 0 means MESN better; ', ...
        'ratio_nrmse = model_nrmse / baseline_nrmse; ', ...
        'ratio_nrmse < 1 means MESN better'];

    ce = struct();
    ce.name = 'conventional_leaky_esn';
    ce.activation = 'tanh';
    ce.state_dimension = n;
    ce.initial_state = zeros(n, 1);
    ce.reservoir_bias = 0;
    ce.spectral_radius_candidates = [0.5, 0.9, 1.2];
    ce.leak_rate_candidates = [0.1, 0.3, 1.0];
    ce.input_scaling_candidates = [0.25, 0.5, 1.0];
    ce.reservoir_seed_offset = 2000;
    ce.reuse_mesn_input_support = true;
    ce.reuse_mesn_input_direction = true;
    ce.no_raw_input_readout = true;
    ce.recurrent_dale_constrained = false;
    ce.has_sfa = false;
    ce.has_std = false;
    ce.has_delay = false;
    ce.candidate_enumeration_order = [ ...
        'spectral_radius listed order; then leak_rate; then input_scaling'];
    ce.across_candidate_tie_rule = [ ...
        'lowest finite validation NRMSE; ties within 1e-12 take earliest ', ...
        'enumerated candidate'];
    bb.conventional_leaky_esn = ce;

    bb.narma = struct( ...
        'required', {{'training_target_mean', 'linear_input_history', ...
            'conventional_leaky_esn', 'dale_mesn_control'}}, ...
        'linear_history_length_source', 'narma_order', ...
        'dale_mesn_control_role', 'paired_cell_reference_resolved_in_aggregation');

    bb.mackey_glass_onestep = struct( ...
        'required', {{'persistence', 'linear_autoregression', ...
            'conventional_leaky_esn', 'dale_mesn_control'}}, ...
        'ar_lags_source', 'options.ar_lags', ...
        'dale_mesn_control_role', 'paired_cell_reference_resolved_in_aggregation', ...
        'autonomous_rollout', 'deferred_to_phase_4c_b');

    bb.dale_mesn_control_keys = struct( ...
        'feat_x', 'adapt-off__std-off__delay-ode_off__feat-x', ...
        'feat_r', 'adapt-off__std-off__delay-ode_off__feat-r');
end
