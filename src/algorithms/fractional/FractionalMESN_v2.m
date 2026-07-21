classdef FractionalMESN_v2
    %FRACTIONALMESN_V2 Minimal isolated Fractional MESN v2 engine.

    properties (SetAccess = private)
        Config
    end

    methods
        function obj = FractionalMESN_v2(cfg)
            if nargin < 1
                error('FractionalMESN_v2:missingConfig', ...
                    'Configuration is required.');
            end
            obj.Config = validate_fractional_mesn_v2_config(cfg);
        end

        function [X, info] = simulate(obj, U, x0)
            cfg = obj.Config;
            U = FractionalMESN_v2.validate_input_sequence(U, size(cfg.W_in, 2));
            x0_row = FractionalMESN_v2.normalize_x0(x0, cfg.n);

            N = size(U, 1);
            X = zeros(N + 1, cfg.n);
            X(1, :) = x0_row;

            for k = 1:N
                x_previous = X(k, :);
                u_previous = U(k, :);
                input_previous = (cfg.W_in * u_previous.').';

                if strcmp(cfg.recurrence_mode, 'input_only')
                    recurrent_previous = zeros(1, cfg.n);
                else
                    recurrent_previous = (cfg.W * x_previous.').';
                end

                drive_previous = input_previous + recurrent_previous;
                [x_next, step_info] = caputo_l1_semiimplicit_step( ...
                    X(1:k, :), drive_previous, cfg.dt, cfg.alpha, cfg.tau_x);
                FractionalMESN_v2.validate_step_info(step_info, cfg.alpha, k);
                X(k + 1, :) = x_next;
            end

            info = FractionalMESN_v2.build_info(cfg, N);
        end
    end

    methods (Static, Access = private)
        function U = validate_input_sequence(U, n_input)
            if ~isnumeric(U) || ~ismatrix(U) || ~isreal(U) || ~all(isfinite(U(:)))
                error('FractionalMESN_v2:invalidU', ...
                    'U must be a finite real numeric matrix.');
            end
            if size(U, 2) ~= n_input
                error('FractionalMESN_v2:invalidU', ...
                    'U must have exactly size(W_in,2) columns.');
            end
            U = double(U);
        end

        function x0_row = normalize_x0(x0, n)
            if ~isnumeric(x0) || ~isreal(x0) || ~all(isfinite(x0(:)))
                error('FractionalMESN_v2:invalidX0', ...
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
            error('FractionalMESN_v2:invalidX0', ...
                'x0 must be a scalar or a vector with n elements.');
        end

        function validate_step_info(step_info, alpha, step_index)
            if ~isstruct(step_info) || ~isfield(step_info, 'schema_version') || ...
                    ~strcmp(step_info.schema_version, ...
                    'fractional_mesn_v2_caputo_l1_core_v1')
                error('FractionalMESN_v2:coreContractViolation', ...
                    'Core step returned an unexpected schema at step %d.', step_index);
            end
            if ~isfield(step_info, 'drive_index') || ...
                    ~strcmp(step_info.drive_index, 'n_minus_1')
                error('FractionalMESN_v2:coreContractViolation', ...
                    'Core step returned an unexpected drive index at step %d.', step_index);
            end
            if ~isfield(step_info, 'alpha_one_branch_used') || ...
                    ~isequal(logical(step_info.alpha_one_branch_used), alpha == 1)
                error('FractionalMESN_v2:coreContractViolation', ...
                    'Core step returned an unexpected alpha==1 branch flag at step %d.', ...
                    step_index);
            end
        end

        function info = build_info(cfg, N)
            spec = fractional_mesn_v2_engine_spec();
            info = struct();
            info.engine_schema_version = spec.schema_version;
            info.engine_content_hash = spec.content_hash;
            info.core_schema_version = spec.core_schema_version;
            info.core_content_hash = spec.core_content_hash;
            info.alpha = cfg.alpha;
            info.alpha_one_branch_used = (cfg.alpha == 1);
            info.n_steps = N;
            info.recurrence_mode = cfg.recurrence_mode;
            info.full_history_used = true;
            info.truncated = false;
            info.input_index = 'n_minus_1';
            info.recurrence_index = 'n_minus_1';
        end
    end
end
