function mc = compute_memory_capacity(esn_or_params, options)
% compute_memory_capacity
% Held-out linear memory capacity (Jaeger-style) with chance correction.
%
% For lag k > 0, features at time t predict u(t-k). Train, validation, and
% test use independent i.i.d. Uniform[-1,1] sequences with independent
% reservoir resets. Ridge lambda is selected on validation via
% select_ridge_lambda / fit_ridge_readout. Chance bias uses 100 deterministic
% circular target shifts larger than max(lag).
%
% Corrected capacity: max(0, rho2 - chance_rho2). Total is the sum over the
% preregistered lags (not comparable across different max lags).
%
% Usage:
%   mc = compute_memory_capacity(params);
%   mc = compute_memory_capacity(esn, struct('lags', 1:50, 'washout', 100));
%   mc = compute_memory_capacity(inject, opts);  % inject.X_*/u_* for unit tests
%
% Options:
%   .lags                 (default 1:200) positive integer lags
%   .washout              (default 200)
%   .T_train/.T_val/.T_test  (defaults 3000/1000/1000) or .T with ratios
%   .minimum_scored_rows  (default 50)
%   .input_scale          (default 1.0)  u ~ U[-scale, scale]
%   .seed_train/val/test  (defaults 123/124/125)
%   .lambda_grid          (default select_ridge_lambda default)
%   .feature_mode         (default 'x')
%
% Output fields include rho2, chance_rho2, MC_spectrum (corrected), MC_total,
% lambda_per_lag, n_scored, seeds, lags, options.

    if nargin < 2 || isempty(options)
        options = struct();
    end

    lags = getFieldOrDefault(options, 'lags', []);
    if isempty(lags)
        K_max = getFieldOrDefault(options, 'K_max', 200);
        lags = (1:K_max)';
    else
        lags = lags(:);
    end
    if isempty(lags) || any(lags ~= floor(lags)) || any(lags < 1)
        error('compute_memory_capacity:InvalidLags', ...
            'lags must be positive integers.');
    end
    max_lag = max(lags);

    washout = getFieldOrDefault(options, 'washout', 200);
    min_rows = getFieldOrDefault(options, 'minimum_scored_rows', 50);
    input_scale = getFieldOrDefault(options, 'input_scale', 1.0);
    feature_mode = getFieldOrDefault(options, 'feature_mode', 'x');
    seed_train = getFieldOrDefault(options, 'seed_train', ...
        getFieldOrDefault(options, 'seed', 123));
    seed_val = getFieldOrDefault(options, 'seed_val', seed_train + 1);
    seed_test = getFieldOrDefault(options, 'seed_test', seed_train + 2);
    lambda_grid = getFieldOrDefault(options, 'lambda_grid', []);

    T_train = getFieldOrDefault(options, 'T_train', []);
    T_val = getFieldOrDefault(options, 'T_val', []);
    T_test = getFieldOrDefault(options, 'T_test', []);
    if isempty(T_train) || isempty(T_val) || isempty(T_test)
        T = getFieldOrDefault(options, 'T', 5000);
        train_ratio = getFieldOrDefault(options, 'train_ratio', 0.6);
        val_ratio = getFieldOrDefault(options, 'val_ratio', 0.2);
        T_train = floor(T * train_ratio);
        T_val = floor(T * val_ratio);
        T_test = T - T_train - T_val;
    end

    need_len = washout + max_lag + min_rows;
    if T_train < need_len || T_val < need_len || T_test < need_len
        error('compute_memory_capacity:ShortSequence', ...
            ['Each of T_train/T_val/T_test must exceed washout+max(lag)+', ...
             'minimum_scored_rows (%d); got %d/%d/%d.'], ...
            need_len, T_train, T_val, T_test);
    end

    inject = isstruct(esn_or_params) && isfield(esn_or_params, 'X_train');
    if inject
        X_train = esn_or_params.X_train;
        X_val = esn_or_params.X_val;
        X_test = esn_or_params.X_test;
        u_train = esn_or_params.u_train(:);
        u_val = esn_or_params.u_val(:);
        u_test = esn_or_params.u_test(:);
    else
        if isa(esn_or_params, 'SRNN_ESN')
            esn = esn_or_params;
        else
            esn = SRNN_ESN(esn_or_params);
        end
        esn.which_states = feature_mode;
        esn.include_input = false;

        [X_train, u_train] = drive_sequence(esn, T_train, washout, input_scale, seed_train);
        [X_val, u_val] = drive_sequence(esn, T_val, washout, input_scale, seed_val);
        [X_test, u_test] = drive_sequence(esn, T_test, washout, input_scale, seed_test);
    end

    n_lag = numel(lags);
    rho2 = zeros(n_lag, 1);
    chance_rho2 = zeros(n_lag, 1);
    MC = zeros(n_lag, 1);
    lambda_per_lag = zeros(n_lag, 1);
    n_scored = zeros(n_lag, 1);

    n_chance = getFieldOrDefault(options, 'n_chance', 100);
    if ~(isscalar(n_chance) && n_chance == floor(n_chance) && n_chance >= 1)
        error('compute_memory_capacity:InvalidNChance', ...
            'n_chance must be a positive integer.');
    end
    % Deterministic circular shifts strictly larger than max_lag
    chance_shifts = max_lag + (1:n_chance);

    for li = 1:n_lag
        k = lags(li);
        [Xtr, ytr] = align_lag(X_train, u_train, k);
        [Xva, yva] = align_lag(X_val, u_val, k);
        [Xte, yte] = align_lag(X_test, u_test, k);

        n_scored(li) = size(Xte, 1);
        if size(Xtr, 1) < min_rows || size(Xva, 1) < min_rows || size(Xte, 1) < min_rows
            error('compute_memory_capacity:TooFewRows', ...
                'Lag %d has fewer than minimum_scored_rows=%d after alignment.', ...
                k, min_rows);
        end

        if isempty(lambda_grid)
            sel = select_ridge_lambda(Xtr, ytr, Xva, yva);
        else
            sel = select_ridge_lambda(Xtr, ytr, Xva, yva, lambda_grid);
        end
        model = sel.selected_model;
        lambda_per_lag(li) = sel.selected_lambda;

        yhat = apply_ridge_readout(model, Xte);
        rho2(li) = squared_corr(yhat, yte);

        ch = zeros(n_chance, 1);
        for ci = 1:n_chance
            y_shift = circshift(yte, chance_shifts(ci));
            ch(ci) = squared_corr(yhat, y_shift);
        end
        chance_rho2(li) = mean(ch);
        MC(li) = max(0, rho2(li) - chance_rho2(li));
    end

    mc = struct();
    mc.options = options;
    mc.lags = lags;
    mc.rho2 = rho2;
    mc.chance_rho2 = chance_rho2;
    mc.MC_spectrum = MC;
    mc.MC_total = sum(MC);
    mc.lambda_per_lag = lambda_per_lag;
    mc.n_scored = n_scored;
    mc.seeds = struct('train', seed_train, 'val', seed_val, 'test', seed_test);
    mc.chance_shifts = chance_shifts(:);
end

function [X, u] = drive_sequence(esn, T, washout, input_scale, seed)
    rng(seed);
    u_full = (2 * rand(T, 1) - 1) * input_scale;
    esn.resetState();
    X_full = esn.runReservoir(u_full);
    X = X_full((washout+1):end, :);
    u = u_full((washout+1):end, 1);
end

function [X_aln, y] = align_lag(X, u, k)
% Features at t predict u(t-k): use rows t = (k+1):end, targets u(t-k).
    y = u(1:(end-k));
    X_aln = X((k+1):end, :);
    if size(X_aln, 1) ~= numel(y)
        error('compute_memory_capacity:AlignMismatch', ...
            'Aligned feature/target lengths differ (%d vs %d).', ...
            size(X_aln, 1), numel(y));
    end
end

function r2 = squared_corr(yhat, y)
    yhat = yhat(:);
    y = y(:);
    if std(yhat) < eps || std(y) < eps
        r2 = 0;
        return;
    end
    c = corr(yhat, y, 'Rows', 'complete');
    if ~isfinite(c)
        r2 = 0;
    else
        r2 = c^2;
    end
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end
