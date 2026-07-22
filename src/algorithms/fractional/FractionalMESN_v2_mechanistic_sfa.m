classdef FractionalMESN_v2_mechanistic_sfa
    %FRACTIONALMESN_V2_MECHANISTIC_SFA SFA-enabled no-delay Fractional MESN v2.
    %
    % Value class storing validated configuration only. simulate is
    % stateless with respect to the object. Caputo acts only on x; SFA is
    % integer-order via mesn_v2_sfa_step. No STD, delay, readout, or RNG.

    properties (SetAccess = private)
        Config
    end

    methods
        function obj = FractionalMESN_v2_mechanistic_sfa(cfg)
            if nargin < 1
                error('FractionalMESN_v2_mechanistic_sfa:missingConfig', ...
                    'Configuration is required.');
            end
            obj.Config = validate_fractional_mesn_v2_mechanistic_sfa_config(cfg);
        end

        function [X, Q, R, A_E, A_I, info] = simulate(obj, U, x0, a0)
            cfg = obj.Config;
            U = FractionalMESN_v2_mechanistic_sfa.validate_input_sequence( ...
                U, size(cfg.W_in, 2));
            x0_row = FractionalMESN_v2_mechanistic_sfa.normalize_x0( ...
                x0, cfg.n);

            E_idx = find(cfg.presynaptic_signs == 1);
            I_idx = find(cfg.presynaptic_signs == -1);
            n_E = numel(E_idx);
            n_I = numel(I_idx);
            n_a_E = numel(cfg.sfa.tau_a_E);
            n_a_I = numel(cfg.sfa.tau_a_I);

            a0_norm = FractionalMESN_v2_mechanistic_sfa.normalize_a0( ...
                a0, n_E, n_I, n_a_E, n_a_I);

            N = size(U, 1);
            X = zeros(N + 1, cfg.n);
            Q = zeros(N + 1, cfg.n);
            R = zeros(N + 1, cfg.n);
            A_E = zeros(N + 1, n_E, n_a_E);
            A_I = zeros(N + 1, n_I, n_a_I);

            X(1, :) = x0_row;
            A_E(1, :, :) = reshape(a0_norm.a_E, [1, n_E, n_a_E]);
            A_I(1, :, :) = reshape(a0_norm.a_I, [1, n_I, n_a_I]);

            adaptation_0 = FractionalMESN_v2_mechanistic_sfa.adaptation_row( ...
                a0_norm.a_E, a0_norm.a_I, cfg, E_idx, I_idx);
            Q(1, :) = X(1, :) - adaptation_0;
            R(1, :) = mesn_v2_rate_map(Q(1, :), cfg.activation);

            for k = 1:N
                r_previous = R(k, :);
                u_previous = U(k, :);
                a_E_previous = reshape(A_E(k, :, :), [n_E, n_a_E]);
                a_I_previous = reshape(A_I(k, :, :), [n_I, n_a_I]);

                input_previous = (cfg.W_in * u_previous.').';
                recurrent_previous = (cfg.W * r_previous.').';
                drive_previous = input_previous + recurrent_previous;

                [x_next, step_info] = caputo_l1_semiimplicit_step( ...
                    X(1:k, :), drive_previous, cfg.dt, cfg.alpha, cfg.tau_x);
                FractionalMESN_v2_mechanistic_sfa.validate_step_info( ...
                    step_info, cfg.alpha, k);

                [a_E_next, sfa_E_info] = mesn_v2_sfa_step( ...
                    a_E_previous, r_previous(E_idx), cfg.dt, cfg.sfa.tau_a_E);
                [a_I_next, sfa_I_info] = mesn_v2_sfa_step( ...
                    a_I_previous, r_previous(I_idx), cfg.dt, cfg.sfa.tau_a_I);
                FractionalMESN_v2_mechanistic_sfa.validate_sfa_info( ...
                    sfa_E_info, n_E, n_a_E, k);
                FractionalMESN_v2_mechanistic_sfa.validate_sfa_info( ...
                    sfa_I_info, n_I, n_a_I, k);

                X(k + 1, :) = x_next;
                A_E(k + 1, :, :) = reshape(a_E_next, [1, n_E, n_a_E]);
                A_I(k + 1, :, :) = reshape(a_I_next, [1, n_I, n_a_I]);

                adaptation_k = FractionalMESN_v2_mechanistic_sfa.adaptation_row( ...
                    a_E_next, a_I_next, cfg, E_idx, I_idx);
                Q(k + 1, :) = X(k + 1, :) - adaptation_k;
                R(k + 1, :) = mesn_v2_rate_map(Q(k + 1, :), cfg.activation);
            end

            info = FractionalMESN_v2_mechanistic_sfa.build_info( ...
                cfg, N, n_E, n_I, n_a_E, n_a_I);
        end
    end

    methods (Static, Access = private)
        function U = validate_input_sequence(U, n_input)
            if ~isnumeric(U) || ~ismatrix(U) || ~isreal(U) || ...
                    ~all(isfinite(U(:)))
                error('FractionalMESN_v2_mechanistic_sfa:invalidU', ...
                    'U must be a finite real numeric matrix.');
            end
            if size(U, 2) ~= n_input
                error('FractionalMESN_v2_mechanistic_sfa:invalidU', ...
                    'U must have exactly size(W_in,2) columns.');
            end
            U = double(U);
        end

        function x0_row = normalize_x0(x0, n)
            if ~isnumeric(x0) || ~isreal(x0) || ~all(isfinite(x0(:)))
                error('FractionalMESN_v2_mechanistic_sfa:invalidX0', ...
                    'x0 must be finite, real, and numeric.');
            end
            if isscalar(x0)
                x0_row = repmat(double(x0), 1, n);
                return;
            end
            if isvector(x0) && numel(x0) == n
                x0_row = reshape(double(x0), 1, n);
                return;
            end
            error('FractionalMESN_v2_mechanistic_sfa:invalidX0', ...
                'x0 must be a scalar or a vector with n elements.');
        end

        function a0_out = normalize_a0(a0, n_E, n_I, n_a_E, n_a_I)
            if ~isstruct(a0) || ~isscalar(a0)
                error('FractionalMESN_v2_mechanistic_sfa:invalidA0', ...
                    'a0 must be a scalar struct with fields a_E and a_I.');
            end
            if ~isfield(a0, 'a_E') || ~isfield(a0, 'a_I')
                error('FractionalMESN_v2_mechanistic_sfa:invalidA0', ...
                    'a0 must contain fields a_E and a_I.');
            end
            a0_out = struct();
            a0_out.a_E = FractionalMESN_v2_mechanistic_sfa.normalize_a_matrix( ...
                a0.a_E, n_E, n_a_E, 'a_E');
            a0_out.a_I = FractionalMESN_v2_mechanistic_sfa.normalize_a_matrix( ...
                a0.a_I, n_I, n_a_I, 'a_I');
        end

        function A = normalize_a_matrix(value, n_pop, n_chan, name)
            if ~isnumeric(value) || ~isreal(value)
                error('FractionalMESN_v2_mechanistic_sfa:invalidA0', ...
                    '%s must be a finite real numeric matrix.', name);
            end
            if isequal(size(value), [n_pop, n_chan])
                if ~all(isfinite(value(:)))
                    error('FractionalMESN_v2_mechanistic_sfa:invalidA0', ...
                        '%s must be finite.', name);
                end
                A = double(value);
                return;
            end
            if isempty(value) && (n_pop == 0 || n_chan == 0)
                A = zeros(n_pop, n_chan);
                return;
            end
            error('FractionalMESN_v2_mechanistic_sfa:invalidA0', ...
                '%s must have exact shape %d-by-%d.', name, n_pop, n_chan);
        end

        function adaptation = adaptation_row(a_E, a_I, cfg, E_idx, I_idx)
            adaptation = zeros(1, cfg.n);
            if ~isempty(E_idx)
                adaptation(E_idx) = (a_E * cfg.sfa.c_a_E(:)).';
            end
            if ~isempty(I_idx)
                adaptation(I_idx) = (a_I * cfg.sfa.c_a_I(:)).';
            end
        end

        function validate_step_info(step_info, alpha, step_index)
            if ~isstruct(step_info) || ~isfield(step_info, 'schema_version') || ...
                    ~strcmp(step_info.schema_version, ...
                    'fractional_mesn_v2_caputo_l1_core_v1')
                error('FractionalMESN_v2_mechanistic_sfa:coreContractViolation', ...
                    'Core step returned an unexpected schema at step %d.', ...
                    step_index);
            end
            if ~isfield(step_info, 'drive_index') || ...
                    ~strcmp(step_info.drive_index, 'n_minus_1')
                error('FractionalMESN_v2_mechanistic_sfa:coreContractViolation', ...
                    'Core step returned an unexpected drive index at step %d.', ...
                    step_index);
            end
            if ~isfield(step_info, 'alpha_one_branch_used') || ...
                    ~isequal(logical(step_info.alpha_one_branch_used), alpha == 1)
                error('FractionalMESN_v2_mechanistic_sfa:coreContractViolation', ...
                    ['Core step returned an unexpected alpha==1 branch flag ', ...
                     'at step %d.'], step_index);
            end
        end

        function validate_sfa_info(sfa_info, n_pop, n_chan, step_index)
            if ~isstruct(sfa_info) || ~isfield(sfa_info, 'schema_version') || ...
                    ~strcmp(sfa_info.schema_version, 'mesn_v2_sfa_step_v1')
                error('FractionalMESN_v2_mechanistic_sfa:sfaContractViolation', ...
                    'SFA step returned an unexpected schema at step %d.', ...
                    step_index);
            end
            if ~isfield(sfa_info, 'n_population') || sfa_info.n_population ~= n_pop
                error('FractionalMESN_v2_mechanistic_sfa:sfaContractViolation', ...
                    'SFA step returned unexpected n_population at step %d.', ...
                    step_index);
            end
            if ~isfield(sfa_info, 'n_channels') || sfa_info.n_channels ~= n_chan
                error('FractionalMESN_v2_mechanistic_sfa:sfaContractViolation', ...
                    'SFA step returned unexpected n_channels at step %d.', ...
                    step_index);
            end
            if ~isfield(sfa_info, 'clipped') || sfa_info.clipped
                error('FractionalMESN_v2_mechanistic_sfa:sfaContractViolation', ...
                    'SFA step reported clipping at step %d.', step_index);
            end
        end

        function info = build_info(cfg, N, n_E, n_I, n_a_E, n_a_I)
            spec = fractional_mesn_v2_mechanistic_sfa_engine_spec();
            info = struct();
            info.engine_schema_version = spec.schema_version;
            info.engine_content_hash = spec.content_hash;
            info.foundation_engine_schema_version = ...
                spec.foundation_engine_schema_version;
            info.foundation_engine_content_hash = ...
                spec.foundation_engine_content_hash;
            info.core_schema_version = spec.core_schema_version;
            info.core_content_hash = spec.core_content_hash;
            info.rate_map_schema_version = spec.rate_map_schema_version;
            info.rate_map_content_hash = spec.rate_map_content_hash;
            info.dale_validator_schema_version = ...
                spec.dale_validator_schema_version;
            info.dale_validator_content_hash = ...
                spec.dale_validator_content_hash;
            info.sfa_step_schema_version = spec.sfa_step_schema_version;
            info.sfa_step_content_hash = spec.sfa_step_content_hash;
            info.alpha = cfg.alpha;
            info.alpha_one_branch_used = (cfg.alpha == 1);
            info.n_steps = N;
            info.n_E = n_E;
            info.n_I = n_I;
            info.n_a_E = n_a_E;
            info.n_a_I = n_a_I;
            info.drive_index = 'n_minus_1';
            info.rate_index = 'n_minus_1';
            info.input_index = 'n_minus_1';
            info.sfa_rate_index = 'n_minus_1';
            info.full_fractional_history_used = true;
            info.fractional_history_truncated = false;
            info.sfa_integer_order = true;
            info.sfa_clipped = false;
            info.activation_mode = cfg.activation.mode;
            info.dale_signs_valid = true;
            info.included_mechanisms = spec.included_mechanisms;
            info.excluded_mechanisms = spec.excluded_mechanisms;
        end
    end
end
