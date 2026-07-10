function nmc = compute_nonlinear_memory_capacity(esn_or_params, options)
% compute_nonlinear_memory_capacity
% Nonlinear memory capacity with correct lag alignment and chance correction.
%
% Single term P_d(u(t-k)): valid t > k.
% Cross term P_p(u(t-k1))*P_q(u(t-k2)): common t > max(k1,k2), both operands
% indexed from that same t. Target length is asserted equal to feature rows.
%
% Uses independent train/validation/test sequences and the same chance-
% correction structure as compute_memory_capacity.
%
% Usage:
%   nmc = compute_nonlinear_memory_capacity(params);
%   nmc = compute_nonlinear_memory_capacity(esn, struct('degrees',[1 2 3]));
%   nmc = compute_nonlinear_memory_capacity(inject, opts); % unit-test inject

    if nargin < 2 || isempty(options)
        options = struct();
    end

    lags = getFieldOrDefault(options, 'lags', []);
    if isempty(lags)
        K_max = getFieldOrDefault(options, 'K_max', 100);
        lags = (1:K_max)';
    else
        lags = lags(:);
    end
    if isempty(lags) || any(lags ~= floor(lags)) || any(lags < 1)
        error('compute_nonlinear_memory_capacity:InvalidLags', ...
            'lags must be positive integers.');
    end
    max_lag = max(lags);

    washout = getFieldOrDefault(options, 'washout', 200);
    min_rows = getFieldOrDefault(options, 'minimum_scored_rows', 50);
    input_scale = getFieldOrDefault(options, 'input_scale', 1.0);
    feature_mode = getFieldOrDefault(options, 'feature_mode', 'x');
    degrees = getFieldOrDefault(options, 'degrees', [2 3]);
    degrees = degrees(:).';
    include_cross = getFieldOrDefault(options, 'include_cross_terms', false);
    cross_max_pairs = getFieldOrDefault(options, 'cross_max_pairs', 200);
    cross_degrees = getFieldOrDefault(options, 'cross_degrees', [1 1]);
    if numel(cross_degrees) ~= 2
        error('compute_nonlinear_memory_capacity:InvalidCrossDegrees', ...
            'cross_degrees must be a 1x2 vector [p q].');
    end

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
        error('compute_nonlinear_memory_capacity:ShortSequence', ...
            'Each sequence must exceed washout+max(lag)+minimum_scored_rows (%d).', ...
            need_len);
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

    % Build explicit task list
    tasks = struct('type', {}, 'degree', {}, 'lag', {}, 'lag1', {}, 'lag2', {}, ...
        'degree1', {}, 'degree2', {}, 'label', {});
    for di = 1:numel(degrees)
        d = degrees(di);
        for li = 1:numel(lags)
            k = lags(li);
            tasks(end+1) = make_legendre_task(d, k); %#ok<AGROW>
        end
    end

    cross_pairs = zeros(0, 2);
    if include_cross
        pairs = [];
        for k1 = 1:numel(lags)
            for k2 = (k1+1):numel(lags)
                pairs = [pairs; lags(k1), lags(k2)]; %#ok<AGROW>
                if size(pairs, 1) >= cross_max_pairs
                    break;
                end
            end
            if size(pairs, 1) >= cross_max_pairs
                break;
            end
        end
        cross_pairs = pairs;
        p = cross_degrees(1);
        q = cross_degrees(2);
        for pi = 1:size(cross_pairs, 1)
            tasks(end+1) = make_cross_task(p, q, cross_pairs(pi, 1), cross_pairs(pi, 2)); %#ok<AGROW>
        end
    end

    n_tasks = numel(tasks);
    rho2 = zeros(n_tasks, 1);
    chance_rho2 = zeros(n_tasks, 1);
    capacity = zeros(n_tasks, 1);
    lambda_per_task = zeros(n_tasks, 1);
    n_scored = zeros(n_tasks, 1);

    n_chance = 100;
    chance_shifts = max_lag + (1:n_chance);

    for ti = 1:n_tasks
        task = tasks(ti);
        [Xtr, ytr] = build_xy(X_train, u_train, task);
        [Xva, yva] = build_xy(X_val, u_val, task);
        [Xte, yte] = build_xy(X_test, u_test, task);

        assert_rows_match(Xtr, ytr, task.label);
        assert_rows_match(Xva, yva, task.label);
        assert_rows_match(Xte, yte, task.label);

        n_scored(ti) = size(Xte, 1);
        if size(Xtr, 1) < min_rows || size(Xva, 1) < min_rows || size(Xte, 1) < min_rows
            error('compute_nonlinear_memory_capacity:TooFewRows', ...
                'Task %s has fewer than minimum_scored_rows=%d.', task.label, min_rows);
        end

        if isempty(lambda_grid)
            sel = select_ridge_lambda(Xtr, ytr, Xva, yva);
        else
            sel = select_ridge_lambda(Xtr, ytr, Xva, yva, lambda_grid);
        end
        model = sel.selected_model;
        lambda_per_task(ti) = sel.selected_lambda;

        yhat = apply_ridge_readout(model, Xte);
        rho2(ti) = squared_corr(yhat, yte);

        ch = zeros(n_chance, 1);
        for ci = 1:n_chance
            ch(ci) = squared_corr(yhat, circshift(yte, chance_shifts(ci)));
        end
        chance_rho2(ti) = mean(ch);
        capacity(ti) = max(0, rho2(ti) - chance_rho2(ti));
    end

    % Pack Legendre grid for convenience
    n_deg = numel(degrees);
    n_lag = numel(lags);
    NMC_leg = nan(n_deg, n_lag);
    for ti = 1:n_tasks
        if strcmp(tasks(ti).type, 'legendre')
            di = find(degrees == tasks(ti).degree, 1);
            li = find(lags == tasks(ti).lag, 1);
            NMC_leg(di, li) = capacity(ti);
        end
    end

    nmc = struct();
    nmc.options = options;
    nmc.degrees = degrees;
    nmc.lags = lags;
    nmc.tasks = tasks;
    nmc.rho2 = rho2;
    nmc.chance_rho2 = chance_rho2;
    nmc.capacity = capacity;
    nmc.NMC_legendre = NMC_leg;
    nmc.lambda_per_task = lambda_per_task;
    nmc.n_scored = n_scored;
    nmc.seeds = struct('train', seed_train, 'val', seed_val, 'test', seed_test);
    nmc.chance_shifts = chance_shifts(:);
    nmc.total_capacity = sum(capacity);

    if include_cross
        cross_idx = strcmp({tasks.type}, 'cross');
        nmc.cross_pairs = cross_pairs;
        nmc.cross_degrees = cross_degrees;
        nmc.NMC_cross = capacity(cross_idx);
        nmc.cross_tasks = tasks(cross_idx);
    end
end

function task = make_legendre_task(d, k)
    task = struct( ...
        'type', 'legendre', ...
        'degree', d, ...
        'lag', k, ...
        'lag1', k, ...
        'lag2', k, ...
        'degree1', d, ...
        'degree2', [], ...
        'label', sprintf('P_%d(u(t-%d))', d, k));
end

function task = make_cross_task(p, q, k1, k2)
    task = struct( ...
        'type', 'cross', ...
        'degree', [], ...
        'lag', max(k1, k2), ...
        'lag1', k1, ...
        'lag2', k2, ...
        'degree1', p, ...
        'degree2', q, ...
        'label', sprintf('P_%d(u(t-%d))*P_%d(u(t-%d))', p, k1, q, k2));
end

function [X_aln, y] = build_xy(X, u, task)
    u = u(:);
    T = size(X, 1);
    if numel(u) ~= T
        error('compute_nonlinear_memory_capacity:SizeMismatch', ...
            'u and X must share length for task %s.', task.label);
    end

    if strcmp(task.type, 'legendre')
        k = task.lag;
        t = (k+1):T;
        y = legendreP(task.degree, u(t - k));
        X_aln = X(t, :);
    elseif strcmp(task.type, 'cross')
        k1 = task.lag1;
        k2 = task.lag2;
        kmax = max(k1, k2);
        t = (kmax+1):T;
        y = legendreP(task.degree1, u(t - k1)) .* legendreP(task.degree2, u(t - k2));
        X_aln = X(t, :);
    else
        error('compute_nonlinear_memory_capacity:UnknownTask', 'Unknown task type.');
    end
end

function assert_rows_match(X, y, label)
    if size(X, 1) ~= size(y, 1)
        error('compute_nonlinear_memory_capacity:DimMismatch', ...
            'Feature/target row counts differ for task %s (%d vs %d).', ...
            label, size(X, 1), size(y, 1));
    end
end

function [X, u] = drive_sequence(esn, T, washout, input_scale, seed)
    rng(seed);
    u_full = (2 * rand(T, 1) - 1) * input_scale;
    esn.resetState();
    X_full = esn.runReservoir(u_full);
    X = X_full((washout+1):end, :);
    u = u_full((washout+1):end, 1);
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

function P = legendreP(d, x)
    switch d
        case 0
            P = ones(size(x));
        case 1
            P = x;
        case 2
            P = 0.5 * (3*x.^2 - 1);
        case 3
            P = 0.5 * (5*x.^3 - 3*x);
        case 4
            P = (1/8) * (35*x.^4 - 30*x.^2 + 3);
        otherwise
            Pn_1 = x;
            Pn_2 = ones(size(x));
            for n = 1:(d-1)
                Pn = ((2*n+1).*x.*Pn_1 - n.*Pn_2) ./ (n+1);
                Pn_2 = Pn_1;
                Pn_1 = Pn;
            end
            P = Pn_1;
    end
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end
