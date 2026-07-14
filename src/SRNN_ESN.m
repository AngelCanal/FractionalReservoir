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
        c_a_E          % Per-timescale adaptation coupling for E neurons
        c_a_I          % Per-timescale adaptation coupling for I neurons
        activation_function  % Nonlinearity (function handle)
        activation_function_derivative % Derivative of nonlinearity (function handle)
        
        % Reservoir state
        S              % Current state vector [a_E(:); a_I(:); b_E(:); b_I(:); x(:)]
        S0             % Initial state (for reset)
        
        % Readout layer
        W_out          % Readout weight matrix (deprecated mirror of readout_model)
        b_out          % Readout bias vector (deprecated mirror)
        readout_model  % Fitted standardized ridge model from fit_ridge_readout
        
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
        ode_solver     % Default ODE integrator (function handle); [] => ode23s
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
            %       c_a_E, c_a_I - per-timescale adaptation coupling vectors
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
            obj.c_a_E = params.c_a_E;
            obj.c_a_I = params.c_a_I;
            
            % Configuration
            obj.which_states = getFieldOrDefault(params, 'which_states', 'x');
            obj.include_input = getFieldOrDefault(params, 'include_input', false);
            obj.lambda = getFieldOrDefault(params, 'lambda', 1e-6);
            obj.dt = getFieldOrDefault(params, 'dt', 1.0);
            if isfield(params, 'ode_solver') && ~isempty(params.ode_solver)
                obj.ode_solver = params.ode_solver;
            else
                obj.ode_solver = @ode23s;
            end
            
            % Synaptic delay configuration (DDE mode)
            % E connections are instant, I connections are delayed
            obj.lags = getFieldOrDefault(params, 'lags', []);
            if ~isempty(obj.lags) && isscalar(obj.lags) && obj.lags > 0
                W_inst = zeros(obj.n);
                W_inst(:, obj.E_indices) = obj.W(:, obj.E_indices);
                W_delayed = zeros(obj.n);
                W_delayed(:, obj.I_indices) = obj.W(:, obj.I_indices);
                obj.W_components = {W_inst, W_delayed};

                assert(isequal(W_inst + W_delayed, obj.W));
                assert(all(W_inst(:, obj.I_indices) == 0, 'all'));
                assert(all(W_delayed(:, obj.E_indices) == 0, 'all'));
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
            obj.readout_model = [];
            obj.n_outputs = 0;
        end
        
        function metrics = trainReadout(obj, U, Y, options)
            % trainReadout: Train readout on one continuous driven trajectory.
            %
            % Simulates inputs 1:val_end once (no reset at train/val boundary).
            % Selects lambda on train/val, then refits on train+val.
            % Never simulates test input or reads test targets.
            
            if nargin < 4
                options = struct();
            end
            if ~isfield(options, 'train_ratio') || ~isfield(options, 'val_ratio') || ...
                    ~isfield(options, 'washout_steps')
                error('SRNN_ESN:MissingTrainOptions', ...
                    'options must include train_ratio, val_ratio, and washout_steps.');
            end
            train_ratio = options.train_ratio;
            val_ratio = options.val_ratio;
            washout_steps = options.washout_steps;
            if isfield(options, 'lambda_grid')
                lambda_grid = options.lambda_grid;
            else
                lambda_grid = [];
            end

            if any(~isfinite(U(:))) || any(~isfinite(Y(:)))
                error('SRNN_ESN:NonFiniteTrainData', 'U and Y must be finite.');
            end
            if size(U, 1) ~= size(Y, 1)
                error('SRNN_ESN:RowMismatch', 'U and Y must have the same number of rows.');
            end

            n_timesteps = size(U, 1);
            n_train = floor(n_timesteps * train_ratio);
            n_val = floor(n_timesteps * val_ratio);
            n_test = n_timesteps - n_train - n_val;
            if n_test < 1
                error('SRNN_ESN:EmptyTestBlock', ...
                    'Test block must have at least one sample.');
            end
            if washout_steps >= n_train
                error('SRNN_ESN:InvalidWashout', ...
                    'washout_steps (%d) must be less than n_train (%d).', ...
                    washout_steps, n_train);
            end

            train_idx = 1:n_train;
            val_idx = (n_train + 1):(n_train + n_val);
            test_idx = (n_train + n_val + 1):n_timesteps;
            val_end = n_train + n_val;

            % Fit into locals first so failures leave the previous model intact.
            prev_model = obj.readout_model;
            prev_W = obj.W_out;
            prev_b = obj.b_out;
            prev_lambda = obj.lambda;
            prev_trained = obj.is_trained;
            prev_n_outputs = obj.n_outputs;

            try
                run_opts = struct('reset_before', true, 'update_internal_state', false, ...
                    'ode_reltol', getFieldOrDefault(options, 'ode_reltol', 1e-8), ...
                    'ode_abstol', getFieldOrDefault(options, 'ode_abstol', 1e-10), ...
                    'dde_reltol', getFieldOrDefault(options, 'dde_reltol', 1e-7), ...
                    'dde_abstol', getFieldOrDefault(options, 'dde_abstol', 1e-9));
                if isfield(options, 'ode_solver')
                    run_opts.ode_solver = options.ode_solver;
                elseif ~isempty(obj.ode_solver)
                    run_opts.ode_solver = obj.ode_solver;
                end
                [X_driven, ~] = obj.runReservoir(U(1:val_end, :), run_opts);

                X_train = X_driven(washout_steps+1:n_train, :);
                Y_train = Y(washout_steps+1:n_train, :);
                X_val = X_driven(val_idx, :);
                Y_val = Y(val_idx, :);

                selection = select_ridge_lambda(X_train, Y_train, X_val, Y_val, lambda_grid);
                selected_lambda = selection.selected_lambda;

                X_tv = X_driven(washout_steps+1:val_end, :);
                Y_tv = Y(washout_steps+1:val_end, :);
                final_model = fit_ridge_readout(X_tv, Y_tv, selected_lambda);

                Y_train_pred = apply_ridge_readout(final_model, X_train);
                Y_val_pred = apply_ridge_readout(final_model, X_val);
                train_metrics = compute_metrics(Y_train_pred, Y_train);
                val_metrics = compute_metrics(Y_val_pred, Y_val);

                % Assign only after successful fit
                obj.readout_model = final_model;
                obj.lambda = selected_lambda;
                obj.n_outputs = size(Y, 2);
                % Deprecated mirrors in original (unstandardized) feature coordinates
                obj.W_out = final_model.coefficients ./ final_model.sigma(:);
                obj.b_out = final_model.intercept(:) - obj.W_out' * final_model.mu(:);
                obj.is_trained = true;

                metrics = struct();
                metrics.train_mse = train_metrics.mse;
                metrics.train_nrmse = train_metrics.nrmse;
                metrics.val_mse = val_metrics.mse;
                metrics.val_nrmse = val_metrics.nrmse;
                metrics.selected_lambda = selected_lambda;
                metrics.lambda_table = selection.table;
                metrics.train_idx = train_idx;
                metrics.val_idx = val_idx;
                metrics.test_idx = test_idx;
                metrics.washout_steps = washout_steps;
            catch ME
                obj.readout_model = prev_model;
                obj.W_out = prev_W;
                obj.b_out = prev_b;
                obj.lambda = prev_lambda;
                obj.is_trained = prev_trained;
                obj.n_outputs = prev_n_outputs;
                rethrow(ME);
            end
        end
        
        function [Y_pred, X_features, info] = predict(obj, U, options)
            % predict: Independent prediction with optional known context.
            %
            % [Y_pred, X, info] = predict(obj, U)
            % [Y_pred, X, info] = predict(obj, U, options)
            %
            % Default options.reset_before = true.
            % Optional options.context_U supplies preceding input rows that are
            % simulated then discarded before reporting predictions.

            if nargin < 3 || isempty(options)
                options = struct();
            end
            reset_before = getFieldOrDefault(options, 'reset_before', true);
            update_internal_state = getFieldOrDefault(options, 'update_internal_state', false);
            context_U = getFieldOrDefault(options, 'context_U', zeros(0, obj.n_inputs));

            if ~obj.is_trained || isempty(obj.readout_model)
                error('SRNN_ESN:NotTrained', ...
                    'Readout layer has not been trained. Call trainReadout() first.');
            end
            if ~isempty(obj.lags) && update_internal_state
                error('SRNN_ESN:DDEContinuationUnsupported', ...
                    'update_internal_state is not supported in DDE mode.');
            end
            if ~isempty(context_U) && size(context_U, 2) ~= obj.n_inputs
                error('SRNN_ESN:InvalidContext', ...
                    'context_U must have n_inputs columns.');
            end

            n_context = size(context_U, 1);
            U_run = [context_U; U];
            run_opts = struct( ...
                'reset_before', reset_before, ...
                'update_internal_state', update_internal_state, ...
                'ode_reltol', getFieldOrDefault(options, 'ode_reltol', 1e-6), ...
                'ode_abstol', getFieldOrDefault(options, 'ode_abstol', 1e-8), ...
                'dde_reltol', getFieldOrDefault(options, 'dde_reltol', 1e-6), ...
                'dde_abstol', getFieldOrDefault(options, 'dde_abstol', 1e-8));
            [X_all, ~, run_info] = obj.runReservoir(U_run, run_opts);
            X_features = X_all(n_context+1:end, :);
            Y_pred = apply_ridge_readout(obj.readout_model, X_features);

            info = struct();
            info.reset_before = reset_before;
            info.update_internal_state = update_internal_state;
            info.n_context = n_context;
            info.mode = run_info.mode;
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

            current_feedback = apply_ridge_readout(obj.readout_model, X_washout(end, :));

            Y_gen = zeros(n_steps, obj.n_outputs);
            if return_features
                X_features = zeros(n_steps, obj.readout_model.n_features);
            else
                X_features = [];
            end

            step_opts = struct('reset_before', false, 'update_internal_state', true, ...
                'ode_reltol', ode_reltol, 'ode_abstol', ode_abstol);

            for t = 1:n_steps
                [X_t, ~] = obj.runReservoir(current_feedback, step_opts);
                Y_t = apply_ridge_readout(obj.readout_model, X_t);
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
            %
            % Initial-condition precedence (unambiguous; conflicts error):
            %   1. options.history_fn (DDE only) — fresh solve from that history.
            %   2. options.initial_state — ODE IC, or DDE constant history if no
            %      history_fn. Requires reset_before=false.
            %   3. Else if reset_before=true — use obj.S0 (constant history in DDE).
            %   4. Else — ODE continuation from obj.S (DDE continuation unsupported).
            %
            % Object state obj.S is updated only when update_internal_state=true.
            if nargin < 3 || isempty(options)
                options = struct();
            end
            reset_before = getFieldOrDefault(options, 'reset_before', true);
            update_internal_state = getFieldOrDefault(options, 'update_internal_state', false);
            ode_reltol = getFieldOrDefault(options, 'ode_reltol', 1e-6);
            ode_abstol = getFieldOrDefault(options, 'ode_abstol', 1e-8);
            dde_reltol = getFieldOrDefault(options, 'dde_reltol', 1e-6);
            dde_abstol = getFieldOrDefault(options, 'dde_abstol', 1e-8);
            has_initial = isfield(options, 'initial_state') && ~isempty(options.initial_state);
            has_history = isfield(options, 'history_fn') && ~isempty(options.history_fn);
            if isfield(options, 'ode_solver') && ~isempty(options.ode_solver)
                ode_solver = options.ode_solver;
            elseif ~isempty(obj.ode_solver)
                ode_solver = obj.ode_solver;
            else
                ode_solver = @ode23s;
            end
            if ischar(ode_solver) || (isstring(ode_solver) && isscalar(ode_solver))
                ode_solver = str2func(char(ode_solver));
            end
            if ~isa(ode_solver, 'function_handle')
                error('SRNN_ESN:InvalidODESolver', ...
                    'options.ode_solver must be a function handle or name.');
            end

            if isempty(U) || ndims(U) ~= 2 || any(~isfinite(U(:)))
                error('SRNN_ESN:InvalidInput', 'U must be a finite nonempty 2-D array.');
            end
            if size(U, 2) ~= obj.n_inputs
                error('SRNN_ESN:InvalidInput', ...
                    'U must have %d input columns.', obj.n_inputs);
            end

            if has_history && isempty(obj.lags)
                error('SRNN_ESN:HistoryRequiresDDE', ...
                    'options.history_fn is valid only in DDE mode (nonempty lags).');
            end
            if has_history && has_initial
                error('SRNN_ESN:ConflictingInitialHistory', ...
                    ['Supply either options.initial_state (ODE IC / DDE constant ', ...
                     'history) or options.history_fn (DDE), not both.']);
            end
            if has_initial && reset_before
                error('SRNN_ESN:ConflictingInitialState', ...
                    ['Cannot combine options.initial_state with reset_before=true. ', ...
                     'Set reset_before=false when providing an explicit initial state.']);
            end
            if has_history && reset_before
                error('SRNN_ESN:ConflictingHistoryReset', ...
                    ['Cannot combine options.history_fn with reset_before=true. ', ...
                     'Set reset_before=false when providing an explicit history.']);
            end
            if ~isempty(obj.lags) && update_internal_state && ~(has_initial || has_history || reset_before)
                error('SRNN_ESN:DDEContinuationUnsupported', ...
                    'DDE continuation between separate runReservoir calls is unsupported.');
            end

            n_timesteps = size(U, 1);
            history_fn = [];
            if has_history
                history_fn = options.history_fn;
                if ~isa(history_fn, 'function_handle')
                    error('SRNN_ESN:InvalidHistoryFn', ...
                        'options.history_fn must be a function handle t |-> packed state.');
                end
                S_start = validate_packed_state_vector(obj, history_fn(0));
            elseif has_initial
                S_start = validate_packed_state_vector(obj, options.initial_state);
            elseif reset_before
                S_start = obj.S0;
            elseif ~isempty(obj.lags)
                error('SRNN_ESN:DDEContinuationUnsupported', ...
                    'DDE continuation between separate runReservoir calls is unsupported.');
            else
                S_start = obj.S;
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
                [~, S_history] = ode_solver(odefun, t_span, S_start, options_ode);
                mode = 'ODE';
                reltol_used = ode_reltol;
                abstol_used = ode_abstol;
                history_mode = 'ode_initial_state';
            else
                params.lags = obj.lags;
                params.W_components = obj.W_components;
                options_dde = ddeset('RelTol', dde_reltol, 'AbsTol', dde_abstol);
                if isempty(history_fn)
                    dde_history = S_start;  % constant history
                    history_mode = 'dde_constant_history';
                else
                    lag_max = max(obj.lags(:));
                    dde_history = @(t) validate_history_sample(obj, history_fn, t, lag_max);
                    history_mode = 'dde_explicit_history_fn';
                end
                sol = dde23(@(t, y, Z) SRNN_reservoir_DDE(t, y, Z, u_fun, params), ...
                    obj.lags, dde_history, [t_span(1), t_span(end)], options_dde);
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
            info.S_start = S_start(:);
            info.S_end = S_end;
            info.t = t_grid;
            info.reset_before = reset_before;
            info.update_internal_state = update_internal_state;
            info.used_explicit_initial_state = has_initial;
            info.used_explicit_history_fn = has_history;
            info.history_mode = history_mode;
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
            x_eff = compute_effective_q(state, obj.params);
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

function S = validate_packed_state_vector(obj, S_in)
    layout = state_layout(obj.params);
    S = S_in(:);
    if numel(S) ~= layout.n_total
        error('MESN:InvalidStateLength', ...
            'State length %d does not match expected %d.', numel(S), layout.n_total);
    end
    if any(~isfinite(S))
        error('MESN:InvalidStateShape', 'State vector contains non-finite values.');
    end
    resource_idx = [layout.idx_b_E(:); layout.idx_b_I(:)];
    if ~isempty(resource_idx)
        b = S(resource_idx);
        if any(b < -1e-7) || any(b > 1 + 1e-7)
            error('MESN:InvalidResourceState', ...
                'STD resource components of initial_state/history must lie in [0,1].');
        end
        S(resource_idx) = min(max(b, 0), 1);
    end
end

function S = validate_history_sample(obj, history_fn, t, lag_max)
    if t < -lag_max - 10*eps(lag_max) || t > 10*eps(lag_max)
        % dde23 may query slightly outside; still require a packed finite vector
    end
    S = validate_packed_state_vector(obj, history_fn(t));
end

