classdef SRNN_ESN < handle
    % SRNN_ESN: Echo State Network wrapper for the SRNN reservoir
    %
    % This class implements a complete Reservoir Computing / Echo State Network
    % paradigm using the SRNN reservoir (SRNN_reservoir.m or SRNN_reservoir_DDE.m)
    % as the dynamic core and adding a trainable linear readout layer.
    %
    % Reservoir dynamics (see SRNN_reservoir.m):
    %   r_i = phi(x_eff_i),  s_j = b_j * r_j  (presynaptic STD)
    %   dx/dt = (-x + W*s + u) / tau_d, plus SFA/STD on a and b
    %
    % Key features:
    %   - Wraps the fractional SRNN reservoir dynamics
    %   - Implements ridge regression for readout training
    %   - Handles time series data with proper temporal splitting and washout
    %   - Configurable feature extraction from reservoir states
    %   - Optional inclusion of raw input as readout features
    %
    % Example usage:
    %   esn = SRNN_ESN(params);
    %   metrics = esn.trainReadout(U_train, Y_train, train_options);
    %   Y_pred = esn.predict(U_test);
    
    properties
        % Reservoir architecture parameters
        n              % Total number of neurons
        n_E            % Number of excitatory neurons
        n_I            % Number of inhibitory neurons
        E_indices      % Indices of excitatory neurons
        I_indices      % Indices of inhibitory neurons
        
        % Adaptation and STD parameters
        n_a_E          % Number of adaptation timescales for E neurons
        n_a_I          % Number of adaptation timescales for I neurons
        n_b_E          % STD flag for E neurons (0 or 1)
        n_b_I          % STD flag for I neurons (0 or 1)
        
        % Network connectivity and dynamics
        W              % Recurrent weight matrix (n x n)
        W_in           % Input weight matrix (n x n_inputs)
        tau_d          % Dendritic time constant
        tau_a_E        % Adaptation time constants for E neurons
        tau_a_I        % Adaptation time constants for I neurons
        tau_b_E_rec    % STD recovery time constant for E neurons
        tau_b_E_rel    % STD release time constant for E neurons
        tau_b_I_rec    % STD recovery time constant for I neurons
        tau_b_I_rel    % STD release time constant for I neurons
        c_E            % Adaptation scaling for E neurons
        c_I            % Adaptation scaling for I neurons
        activation_function  % Nonlinearity (function handle)
        activation_function_derivative % Derivative of nonlinearity (function handle)
        
        % Reservoir state
        S              % Current state vector [a_E(:); a_I(:); b_E(:); b_I(:); x(:)]
        S0             % Initial state (for reset)
        
        % Readout layer
        W_out          % Readout weight matrix
        b_out          % Readout bias vector
        
        % Configuration
        which_states   % Which states to use as features ('x', 'r', 'all')
        include_input  % Whether to include raw input in features
        lambda         % Ridge regression regularization parameter
        dt             % Time step for ODE integration (seconds)
        
        % Synaptic delay (DDE mode)
        lags           % Synaptic delay values (empty = no delay, uses ODE)
        W_components   % Cell array: {W_instant, W_delayed} for DDE mode
        
        % Metadata
        n_inputs       % Number of input dimensions
        n_outputs      % Number of output dimensions
        is_trained     % Flag indicating if readout has been trained

        % Canonical validated parameters and reproducible state seed
        params         % Full validated parameter struct
        state_rng_seed % Local RNG seed for resetState (default 42)
    end
    
    methods
        function obj = SRNN_ESN(params)
            % SRNN_ESN: Constructor for the ESN class
            %
            % Input:
            %   params - struct with fields:
            %     Required:
            %       n - total number of neurons
            %       n_E - number of excitatory neurons
            %       n_I - number of inhibitory neurons
            %       W - recurrent weight matrix (n x n)
            %       W_in - input weight matrix (n x n_inputs)
            %       tau_d - dendritic time constant
            %       activation_function - nonlinearity (function handle)
            %     Optional:
            %       n_a_E, n_a_I - adaptation timescales (default: 0)
            %       tau_a_E, tau_a_I - adaptation time constants
            %       n_b_E, n_b_I - STD flags (default: 0)
            %       tau_b_E_rec, tau_b_E_rel, tau_b_I_rec, tau_b_I_rel
            %       c_E, c_I - adaptation scaling (default: 1.0)
            %       which_states - 'x' (default), 'r', or 'all'
            %       include_input - true/false (default: false)
            %       lambda - regularization (default: 1e-6)
            %       dt - time step for ODE integration in seconds (default: 1.0)
            
            % Required parameters
            params = validate_MESN_params(params);
            obj.params = params;
            obj.state_rng_seed = getFieldOrDefault(params, 'state_rng_seed', 42);

            obj.n = params.n;
            obj.n_E = params.n_E;
            obj.n_I = params.n_I;
            obj.W = params.W;
            obj.W_in = params.W_in;
            obj.tau_d = params.tau_d;
            obj.activation_function = params.activation_function;
            obj.activation_function_derivative = params.activation_function_derivative;
            
            % Compute indices
            obj.E_indices = 1:obj.n_E;
            obj.I_indices = (obj.n_E + 1):(obj.n_E + obj.n_I);
            
            % Input dimension
            obj.n_inputs = size(obj.W_in, 2);
            
            % Optional adaptation parameters
            obj.n_a_E = getFieldOrDefault(params, 'n_a_E', 0);
            obj.n_a_I = getFieldOrDefault(params, 'n_a_I', 0);
            obj.tau_a_E = getFieldOrDefault(params, 'tau_a_E', []);
            obj.tau_a_I = getFieldOrDefault(params, 'tau_a_I', []);
            
            % Optional STD parameters
            obj.n_b_E = getFieldOrDefault(params, 'n_b_E', 0);
            obj.n_b_I = getFieldOrDefault(params, 'n_b_I', 0);
            obj.tau_b_E_rec = getFieldOrDefault(params, 'tau_b_E_rec', inf);
            obj.tau_b_E_rel = getFieldOrDefault(params, 'tau_b_E_rel', inf);
            obj.tau_b_I_rec = getFieldOrDefault(params, 'tau_b_I_rec', inf);
            obj.tau_b_I_rel = getFieldOrDefault(params, 'tau_b_I_rel', inf);
            
            % Adaptation scaling
            obj.c_E = getFieldOrDefault(params, 'c_E', 1.0);
            obj.c_I = getFieldOrDefault(params, 'c_I', 1.0);
            
            % Configuration
            obj.which_states = getFieldOrDefault(params, 'which_states', 'x');
            obj.include_input = getFieldOrDefault(params, 'include_input', false);
            obj.lambda = getFieldOrDefault(params, 'lambda', 1e-6);
            obj.dt = getFieldOrDefault(params, 'dt', 1.0);
            
            % Synaptic delay configuration (DDE mode)
            % E connections are instant, I connections are delayed
            obj.lags = getFieldOrDefault(params, 'lags', []);
            if ~isempty(obj.lags) && isscalar(obj.lags) && obj.lags > 0
                % Build W_components: {W_instant, W_delayed}
                % W_instant: only E columns (I columns zeroed)
                W_inst = zeros(obj.n);
                W_inst(:, obj.E_indices) = obj.W(:, obj.E_indices);
                % W_delayed: only I columns (E columns zeroed)
                W_delayed = zeros(obj.n);
                W_delayed(:, obj.I_indices) = obj.W(:, obj.I_indices);
                obj.W_components = {W_inst, W_delayed};
            else
                obj.lags = [];
                obj.W_components = {};
            end
            
            % Initialize state
            obj.resetState();
            
            % Readout not yet trained
            obj.is_trained = false;
            obj.W_out = [];
            obj.b_out = [];
            obj.n_outputs = 0;
        end
        
        function metrics = trainReadout(obj, U, Y, options)
            % trainReadout: Train the linear readout layer using ridge regression
            %
            % Inputs:
            %   U - Input time series (n_timesteps x n_inputs)
            %   Y - Target time series (n_timesteps x n_outputs)
            %   options - struct with fields:
            %     train_ratio - fraction for training (default: 0.6)
            %     val_ratio - fraction for validation (default: 0.2)
            %     washout_steps - number of initial steps to ignore (default: 100)
            %     lambda - ridge regularization parameter (default: obj.lambda)
            %
            % Output:
            %   metrics - struct with train_mse, val_mse, train_nrmse, val_nrmse
            
            % Parse options
            if nargin < 4
                options = struct();
            end
            train_ratio = getFieldOrDefault(options, 'train_ratio', 0.6);
            val_ratio = getFieldOrDefault(options, 'val_ratio', 0.2);
            washout_steps = getFieldOrDefault(options, 'washout_steps', 100);
            lambda = getFieldOrDefault(options, 'lambda', obj.lambda);
            
            % Update lambda
            obj.lambda = lambda;
            
            % Get dimensions
            n_timesteps = size(U, 1);
            obj.n_outputs = size(Y, 2);
            
            % Compute split indices (temporal order preserved)
            n_train = floor(n_timesteps * train_ratio);
            n_val = floor(n_timesteps * val_ratio);
            
            % Split data temporally
            U_train = U(1:n_train, :);
            Y_train = Y(1:n_train, :);
            U_val = U(n_train+1:n_train+n_val, :);
            Y_val = Y(n_train+1:n_train+n_val, :);
            
            fprintf('Training readout layer...\n');
            fprintf('  Total samples: %d\n', n_timesteps);
            fprintf('  Training samples: %d (after washout: %d)\n', n_train, n_train - washout_steps);
            fprintf('  Validation samples: %d\n', n_val);
            fprintf('  Washout steps: %d\n', washout_steps);
            fprintf('  Lambda (regularization): %.2e\n', lambda);
            
            % Reset reservoir and run over training data
            obj.resetState();
            opts = struct('reset_before', true, 'update_internal_state', false);
            [X_train, ~] = obj.runReservoir(U_train, opts);
            
            % Apply washout: remove first washout_steps samples
            if washout_steps >= n_train
                error('Washout steps (%d) must be less than training samples (%d)', ...
                      washout_steps, n_train);
            end
            X_train = X_train(washout_steps+1:end, :);
            Y_train_use = Y_train(washout_steps+1:end, :);
            
            % Train readout using ridge regression
            % W_out = (X'*X + lambda*I) \ (X'*Y)
            n_features = size(X_train, 2);
            W_ridge = X_train' * X_train + lambda * eye(n_features);
            obj.W_out = W_ridge \ (X_train' * Y_train_use);
            
            % Compute bias as mean of residuals
            Y_train_pred = X_train * obj.W_out;
            obj.b_out = mean(Y_train_use - Y_train_pred, 1)';
            
            % Evaluate on training set (after washout)
            Y_train_pred = Y_train_pred + obj.b_out';
            train_metrics = compute_metrics(Y_train_pred, Y_train_use);
            
            % Evaluate on validation set
            obj.resetState();
            [X_val, ~] = obj.runReservoir(U_val, opts);
            Y_val_pred = X_val * obj.W_out + obj.b_out';
            val_metrics = compute_metrics(Y_val_pred, Y_val);
            
            % Mark as trained
            obj.is_trained = true;
            
            % Compile metrics
            metrics = struct();
            metrics.train_mse = train_metrics.mse;
            metrics.train_nrmse = train_metrics.nrmse;
            metrics.val_mse = val_metrics.mse;
            metrics.val_nrmse = val_metrics.nrmse;
            
            fprintf('  Training MSE: %.6f, NRMSE: %.4f\n', metrics.train_mse, metrics.train_nrmse);
            fprintf('  Validation MSE: %.6f, NRMSE: %.4f\n', metrics.val_mse, metrics.val_nrmse);
        end
        
        function [Y_pred, X_features] = predict(obj, U)
            % predict: Generate predictions using the trained readout
            %
            % Input:
            %   U - Input time series (n_timesteps x n_inputs)
            %
            % Output:
            %   Y_pred - Predicted outputs (n_timesteps x n_outputs)
            %   X_features - Extracted features (optional, for analysis)
            
            if ~obj.is_trained
                warning('SRNN_ESN:NotTrained', ...
                      'Readout layer has not been trained. Call trainReadout() first.');
            end
            
            % Run reservoir over input sequence
            pred_opts = struct('reset_before', true, 'update_internal_state', false);
            [X_features, ~] = obj.runReservoir(U, pred_opts);
            
            % Apply readout
            Y_pred = X_features * obj.W_out + obj.b_out';
        end
        
        function [Y_gen, X_features] = generateAutonomous(obj, initial_data, n_steps, options)
            % generateAutonomous: ODE closed-loop generation with state-consistent feedback
            %
            % Inputs:
            %   initial_data - Teacher-forcing prefix (n_washout x n_inputs) or struct.input
            %   n_steps      - Number of autonomous steps (>= 1)
            %   options      - horizon (must be 1), washout_steps, return_features,
            %                  ode_reltol, ode_abstol
            %
            % Outputs:
            %   Y_gen        - Generated outputs (n_steps x n_outputs)
            %   X_features   - Reservoir features during generation (optional)

            if ~obj.is_trained
                error('SRNN_ESN:NotTrained', ...
                    'Readout layer has not been trained. Call trainReadout() first.');
            end
            if ~isempty(obj.lags)
                error('SRNN_ESN:DDEAutonomousUnsupported', ...
                    'Autonomous generation is unsupported in DDE mode.');
            end
            if n_steps < 1
                error('SRNN_ESN:InvalidAutonomousSteps', ...
                    'n_steps must be >= 1.');
            end
            if obj.n_inputs ~= obj.n_outputs
                error('SRNN_ESN:AutonomousDimensionMismatch', ...
                    'Autonomous closed-loop requires n_inputs == n_outputs (got %d and %d).', ...
                    obj.n_inputs, obj.n_outputs);
            end

            if nargin < 4 || isempty(options)
                options = struct();
            end
            horizon = getFieldOrDefault(options, 'horizon', 1);
            if horizon ~= 1
                error('SRNN_ESN:UnsupportedAutonomousHorizon', ...
                    'Only horizon=1 autonomous rollout is supported.');
            end

            if isstruct(initial_data) && isfield(initial_data, 'input')
                initial_data = initial_data.input;
            end
            if isempty(initial_data) || ndims(initial_data) ~= 2 || any(~isfinite(initial_data(:)))
                error('SRNN_ESN:InvalidInput', ...
                    'initial_data must be a finite 2-D array.');
            end
            if size(initial_data, 2) ~= obj.n_inputs
                error('SRNN_ESN:InvalidInput', ...
                    'initial_data must have %d input columns.', obj.n_inputs);
            end

            washout_steps = getFieldOrDefault(options, 'washout_steps', size(initial_data, 1));
            return_features = getFieldOrDefault(options, 'return_features', false);
            ode_reltol = getFieldOrDefault(options, 'ode_reltol', 1e-6);
            ode_abstol = getFieldOrDefault(options, 'ode_abstol', 1e-8);

            washout_steps = min(washout_steps, size(initial_data, 1));
            U_washout = initial_data(1:washout_steps, :);

            wash_opts = struct('reset_before', true, 'update_internal_state', true, ...
                'ode_reltol', ode_reltol, 'ode_abstol', ode_abstol);
            [X_washout, ~] = obj.runReservoir(U_washout, wash_opts);

            current_feedback = X_washout(end, :) * obj.W_out + obj.b_out';

            Y_gen = zeros(n_steps, obj.n_outputs);
            if return_features
                X_features = zeros(n_steps, size(obj.W_out, 1));
            else
                X_features = [];
            end

            step_opts = struct('reset_before', false, 'update_internal_state', true, ...
                'ode_reltol', ode_reltol, 'ode_abstol', ode_abstol);

            for t = 1:n_steps
                [X_t, ~] = obj.runReservoir(current_feedback, step_opts);
                Y_t = X_t * obj.W_out + obj.b_out';
                Y_gen(t, :) = Y_t;
                if return_features
                    X_features(t, :) = X_t;
                end
                current_feedback = Y_t;
            end
        end
        
        function params_out = exportParams(obj)
            params_out = obj.params;
        end

        function resetState(obj)
            stream = RandStream('mt19937ar', 'Seed', obj.state_rng_seed);

            state = struct();
            state.a_E = 0.1 * rand(stream, obj.n_E, obj.n_a_E);
            state.a_I = 0.1 * rand(stream, obj.n_I, obj.n_a_I);

            if obj.n_b_E > 0
                state.b_E = ones(obj.n_E * obj.n_b_E, 1);
            else
                state.b_E = zeros(0, 1);
            end
            if obj.n_b_I > 0
                state.b_I = ones(obj.n_I * obj.n_b_I, 1);
            else
                state.b_I = zeros(0, 1);
            end
            state.x = 0.1 * rand(stream, obj.n, 1);

            obj.S0 = pack_state(state, obj.params);
            obj.S = obj.S0;
        end
        
        function S = getState(obj)
            % getState: Get current reservoir state
            S = obj.S;
        end
        
        function setState(obj, S)
            layout = state_layout(obj.params);
            if numel(S) ~= layout.n_total
                error('MESN:InvalidStateLength', ...
                    'State length %d does not match expected %d.', numel(S), layout.n_total);
            end
            if any(~isfinite(S))
                error('MESN:InvalidStateShape', 'State vector contains non-finite values.');
            end
            obj.S = S(:);
        end
        
        function setHyperparams(obj, hyperparams)
            % setHyperparams: Update hyperparameters
            %
            % Input:
            %   hyperparams - struct with fields to update:
            %     lambda - regularization parameter
            %     which_states - feature extraction mode
            %     include_input - whether to include raw input
            %     dt - time step for ODE integration
            
            if isfield(hyperparams, 'lambda')
                obj.lambda = hyperparams.lambda;
            end
            if isfield(hyperparams, 'which_states')
                obj.which_states = hyperparams.which_states;
            end
            if isfield(hyperparams, 'include_input')
                obj.include_input = hyperparams.include_input;
            end
            if isfield(hyperparams, 'dt')
                obj.dt = hyperparams.dt;
            end
        end
        
    end
    
    methods (Access = public)
        
        function [X_features, S_history, info] = runReservoir(obj, U, options)
            % runReservoir  Simulate reservoir dynamics over input sequence U.
            if nargin < 3 || isempty(options)
                options = struct();
            end
            reset_before = getFieldOrDefault(options, 'reset_before', true);
            update_internal_state = getFieldOrDefault(options, 'update_internal_state', false);
            ode_reltol = getFieldOrDefault(options, 'ode_reltol', 1e-6);
            ode_abstol = getFieldOrDefault(options, 'ode_abstol', 1e-8);
            dde_reltol = getFieldOrDefault(options, 'dde_reltol', 1e-6);
            dde_abstol = getFieldOrDefault(options, 'dde_abstol', 1e-8);

            if isempty(U) || ndims(U) ~= 2 || any(~isfinite(U(:)))
                error('SRNN_ESN:InvalidInput', 'U must be a finite nonempty 2-D array.');
            end
            if size(U, 2) ~= obj.n_inputs
                error('SRNN_ESN:InvalidInput', ...
                    'U must have %d input columns.', obj.n_inputs);
            end

            n_timesteps = size(U, 1);
            S_start = obj.S;
            if reset_before
                S_start = obj.S0;
            elseif ~isempty(obj.lags)
                error('SRNN_ESN:DDEContinuationUnsupported', ...
                    'DDE continuation between separate runReservoir calls is unsupported.');
            end

            if n_timesteps == 1
                t_span = [0, obj.dt];
                t_grid = t_span;
            else
                t_span = 0:obj.dt:(n_timesteps - 1) * obj.dt;
                t_grid = t_span;
            end

            neural_drive = obj.W_in * U';
            if n_timesteps == 1
                % Constant input over [0, dt] requires two interpolant knots.
                neural_drive = repmat(neural_drive, 1, numel(t_grid));
            end
            u_fun = make_input_interpolant(t_grid, neural_drive);
            params = obj.params;

            if isempty(obj.lags)
                odefun = @(t, S) SRNN_reservoir(t, S, u_fun, params);
                options_ode = odeset('RelTol', ode_reltol, 'AbsTol', ode_abstol);
                [~, S_history] = ode23s(odefun, t_span, S_start, options_ode);
                mode = 'ODE';
                reltol_used = ode_reltol;
                abstol_used = ode_abstol;
            else
                params.lags = obj.lags;
                params.W_components = obj.W_components;
                options_dde = ddeset('RelTol', dde_reltol, 'AbsTol', dde_abstol);
                sol = dde23(@(t, y, Z) SRNN_reservoir_DDE(t, y, Z, u_fun, params), ...
                    obj.lags, S_start, [t_span(1), t_span(end)], options_dde);
                S_history = deval(sol, t_grid)';
                mode = 'DDE';
                reltol_used = dde_reltol;
                abstol_used = dde_abstol;
            end

            S_end = S_history(end, :)';
            if update_internal_state
                obj.S = S_end;
            end

            if n_timesteps == 1
                S_history = S_history(end, :);
            end

            X_features = obj.extractFeatures(S_history, U);

            info = struct();
            info.mode = mode;
            info.reltol = reltol_used;
            info.abstol = abstol_used;
            info.S_start = S_start;
            info.S_end = S_end;
            info.t = t_grid;
            info.reset_before = reset_before;
            info.update_internal_state = update_internal_state;
        end
        
        function X = extractFeatures(obj, S_history, U)
            % extractFeatures: Extract configured state variables as features
            %
            % Input:
            %   S_history - State trajectory (n_timesteps x n_state_vars)
            %   U - Original input time series (n_timesteps x n_inputs)
            %
            % Output:
            %   X - Feature matrix (n_timesteps x n_features)
            
            n_timesteps = size(S_history, 1);
            
            layout = state_layout(obj.params);
            x_history = S_history(:, layout.idx_x);

            switch obj.which_states
                case 'x'
                    % Use dendritic states only (default)
                    X = x_history;
                    
                case 'r'
                    % Compute firing rates r = phi(x_eff) from state history
                    X = zeros(n_timesteps, obj.n);
                    for t = 1:n_timesteps
                        S_t = S_history(t, :)';
                        [r_t, ~] = obj.computeRates(S_t);
                        X(t, :) = r_t';
                    end
                    
                case 'all'
                    % Use all state variables
                    X = S_history;
                    
                otherwise
                    error('SRNN_ESN:InvalidConfig', ...
                          'which_states must be ''x'', ''r'', or ''all''');
            end
            
            % Optionally include raw input
            if obj.include_input
                X = [X, U];
            end
        end
        
        function [r, x_eff] = computeRates(obj, S)
            state = unpack_state(S, obj.params);
            c_E = obj.params.c_E;
            c_I = obj.params.c_I;

            x_eff = state.x;
            if obj.n_a_E > 0
                x_eff(obj.E_indices) = x_eff(obj.E_indices) - c_E * sum(state.a_E, 2);
            end
            if obj.n_a_I > 0
                x_eff(obj.I_indices) = x_eff(obj.I_indices) - c_I * sum(state.a_I, 2);
            end

            r = obj.activation_function(x_eff);
        end
        
    end
end

function value = getFieldOrDefault(s, field, default_value)
    % Helper function to get field from struct or return default
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

