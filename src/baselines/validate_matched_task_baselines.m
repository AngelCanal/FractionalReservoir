function [ok, report] = validate_matched_task_baselines(baselines, task, opts)
% VALIDATE_MATCHED_TASK_BASELINES  Central fail-closed required-baseline checks.
%
%   [ok, report] = validate_matched_task_baselines(baselines, task, opts)
%
% task: 'narma' | 'mackey_glass_onestep'
% Does not replace failed values. Finite R^2 may be negative.

    if nargin < 3 || isempty(opts)
        opts = struct();
    end
    require_dale = logical(local_get(opts, 'require_dale', true));
    require_comparisons = logical(local_get(opts, 'require_comparisons', true));
    require_candidate_table = logical(local_get(opts, 'require_candidate_table', false));
    lambda_grid = local_get(opts, 'lambda_grid', []);
    task_data_hash = local_get(opts, 'task_data_hash', '');
    split_hash = local_get(opts, 'split_hash', '');
    feature_mode = char(local_get(opts, 'feature_mode', ''));
    dale_keys = local_get(opts, 'dale_mesn_control_keys', struct( ...
        'feat_x', 'adapt-off__std-off__delay-ode_off__feat-x', ...
        'feat_r', 'adapt-off__std-off__delay-ode_off__feat-r'));

    report = struct();
    report.task = char(task);
    report.reasons = {};

    switch char(task)
        case 'narma'
            check_simple('training_target_mean');
            check_ridge_baseline('linear_input_history');
            check_conventional();
        case 'mackey_glass_onestep'
            check_simple('persistence');
            check_ridge_baseline('linear_autoregression');
            check_conventional();
        otherwise
            add_reason(sprintf('unknown_task:%s', char(task)));
    end

    if ~isempty(task_data_hash)
        if ~(isfield(baselines, 'task_data_hash') && ...
                strcmp(char(baselines.task_data_hash), char(task_data_hash)))
            add_reason('task_data_hash_mismatch');
        end
    end
    if ~isempty(split_hash)
        if ~(isfield(baselines, 'split_hash') && ...
                strcmp(char(baselines.split_hash), char(split_hash)))
            add_reason('split_hash_mismatch');
        end
    end

    if require_dale
        check_dale();
    end
    if require_comparisons
        check_comparisons_not_from_pending();
    end

    report.ok = isempty(report.reasons);
    ok = report.ok;

    function add_reason(msg)
        report.reasons{end+1} = msg; %#ok<AGROW>
    end

    function check_simple(name)
        if ~isfield(baselines, name)
            add_reason(sprintf('missing_%s', name));
            return;
        end
        b = baselines.(name);
        if ~isfield(b, 'status') || ~strcmp(char(b.status), 'computed')
            add_reason(sprintf('%s_status_not_computed', name));
        end
        nrmse = nested_nrmse(b);
        if ~isfinite(nrmse)
            add_reason(sprintf('%s_test_nrmse_nonfinite', name));
        end
        r2 = nested_r2(b);
        if ~(isempty(r2) || isfinite(r2))
            add_reason(sprintf('%s_test_r2_nonfinite', name));
        end
    end

    function check_ridge_baseline(name)
        if ~isfield(baselines, name)
            add_reason(sprintf('missing_%s', name));
            return;
        end
        b = baselines.(name);
        if ~isfield(b, 'status') || ~strcmp(char(b.status), 'computed')
            add_reason(sprintf('%s_status_not_computed', name));
            return;
        end
        nrmse = nested_nrmse(b);
        if ~isfinite(nrmse)
            add_reason(sprintf('%s_test_nrmse_nonfinite', name));
        end
        if ~isfield(b, 'selected_lambda') || ~isfinite(b.selected_lambda)
            add_reason(sprintf('%s_selected_lambda_invalid', name));
        elseif ~isempty(lambda_grid) && ~any(lambda_grid(:) == b.selected_lambda)
            add_reason(sprintf('%s_selected_lambda_not_in_grid', name));
        end
        if ~isfield(b, 'ridge_diagnostics') || ~isstruct(b.ridge_diagnostics) || ...
                isempty(fieldnames(b.ridge_diagnostics))
            add_reason(sprintf('%s_missing_ridge_diagnostics', name));
        end
    end

    function check_conventional()
        name = 'conventional_leaky_esn';
        if ~isfield(baselines, name)
            add_reason(sprintf('missing_%s', name));
            return;
        end
        b = baselines.(name);
        if ~isfield(b, 'status') || ~strcmp(char(b.status), 'computed')
            add_reason(sprintf('%s_status_not_computed', name));
            return;
        end
        nrmse = nested_nrmse(b);
        if ~isfinite(nrmse)
            add_reason(sprintf('%s_test_nrmse_nonfinite', name));
        end
        if ~isfield(b, 'selected_candidate_index') || ~isfinite(b.selected_candidate_index)
            add_reason(sprintf('%s_selected_candidate_invalid', name));
        end
        if ~isfield(b, 'selected_lambda') || ~isfinite(b.selected_lambda)
            add_reason(sprintf('%s_selected_lambda_invalid', name));
        elseif ~isempty(lambda_grid) && ~any(lambda_grid(:) == b.selected_lambda)
            add_reason(sprintf('%s_selected_lambda_not_in_grid', name));
        end
        if ~isfield(b, 'ridge_diagnostics') || ~isstruct(b.ridge_diagnostics) || ...
                isempty(fieldnames(b.ridge_diagnostics))
            add_reason(sprintf('%s_missing_ridge_diagnostics', name));
        end
        if require_candidate_table && ...
                (~isfield(b, 'candidate_selection_table') || isempty(b.candidate_selection_table))
            add_reason(sprintf('%s_missing_candidate_selection_table', name));
        end
    end

    function check_dale()
        if ~isfield(baselines, 'dale_mesn_control')
            add_reason('missing_dale_mesn_control');
            return;
        end
        d = baselines.dale_mesn_control;
        if ~isfield(d, 'status') || ~strcmp(char(d.status), 'pending_paired_aggregation')
            add_reason('dale_status_not_pending_paired_aggregation');
        end
        if ~isfield(d, 'dale_mesn_control_reference') || isempty(d.dale_mesn_control_reference)
            add_reason('dale_reference_key_missing');
            return;
        end
        if isfield(d, 'model_family') && strcmp(char(d.model_family), 'conventional_leaky_esn')
            add_reason('dale_labeled_as_conventional_esn');
        end
        if ~isempty(feature_mode)
            expect = dale_mesn_control_reference_key(feature_mode, dale_keys);
            if ~strcmp(char(d.dale_mesn_control_reference), expect)
                add_reason('dale_reference_key_mismatch');
            end
        end
        if isfield(d, 'comparison') && isstruct(d.comparison)
            if isfield(d.comparison, 'improvement_nrmse') && ...
                    isfinite(d.comparison.improvement_nrmse)
                add_reason('dale_pending_produced_superiority_claim');
            end
            if isfield(d.comparison, 'status') && ...
                    ~strcmp(char(d.comparison.status), 'pending_paired_aggregation')
                add_reason('dale_comparison_not_pending');
            end
        end
    end

    function check_comparisons_not_from_pending()
        names = fieldnames(baselines);
        for i = 1:numel(names)
            b = baselines.(names{i});
            if ~isstruct(b) || ~isfield(b, 'comparison')
                continue;
            end
            if strcmp(names{i}, 'dale_mesn_control')
                continue;
            end
            cmp = b.comparison;
            if isfield(cmp, 'status') && strcmp(char(cmp.status), 'pending_paired_aggregation')
                add_reason(sprintf('%s_comparison_pending', names{i}));
            end
        end
    end
end

function nrmse = nested_nrmse(b)
    nrmse = NaN;
    if isfield(b, 'metrics_test') && isfield(b.metrics_test, 'nrmse')
        nrmse = b.metrics_test.nrmse;
    elseif isfield(b, 'metrics') && isfield(b.metrics, 'test') && ...
            isfield(b.metrics.test, 'nrmse')
        nrmse = b.metrics.test.nrmse;
    end
end

function r2 = nested_r2(b)
    r2 = [];
    if isfield(b, 'metrics_test') && isfield(b.metrics_test, 'r2')
        r2 = b.metrics_test.r2;
    elseif isfield(b, 'metrics') && isfield(b.metrics, 'test') && ...
            isfield(b.metrics.test, 'r2')
        r2 = b.metrics.test.r2;
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
