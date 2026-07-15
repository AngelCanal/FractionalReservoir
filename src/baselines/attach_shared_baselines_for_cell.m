function baselines = attach_shared_baselines_for_cell(bundle_task, model_nrmse, feature_mode, bb, bundle_id)
% ATTACH_SHARED_BASELINES_FOR_CELL  Compact shared baselines + cell comparisons.
%
%   baselines = attach_shared_baselines_for_cell(bundle_task, model_nrmse, ...
%       feature_mode, bb, bundle_id)
%
% Recomputes model-vs-baseline comparisons from this cell's MESN NRMSE.
% Dale-only reference is feature-specific and remains pending aggregation.
% Full candidate tables stay only in the seed bundle artifact.

    if nargin < 4 || isempty(bb)
        bb = build_matched_task_baselines_config(struct('base', struct('n', 1)));
    end
    src = bundle_task.baselines;
    baselines = struct();
    baselines.protocol_version = local_field(src, 'protocol_version', bb.protocol_version);
    baselines.resolved_lambda_grid = local_field(src, 'resolved_lambda_grid', []);
    baselines.model_test_nrmse = model_nrmse;
    baselines.bundle_id = bundle_id;
    baselines.evaluation_provenance = struct( ...
        'mode', 'executed_shared_seed_bundle', ...
        'bundle_id', bundle_id);
    if isfield(bundle_task, 'task')
        baselines.task_data_hash = bundle_task.task.task_data_hash;
        baselines.split_hash = bundle_task.task.split_hash;
    end

    names = fieldnames(src);
    for i = 1:numel(names)
        nm = names{i};
        if any(strcmp(nm, {'protocol_version', 'resolved_lambda_grid', ...
                'model_test_nrmse', 'dale_mesn_control'}))
            continue;
        end
        b = src.(nm);
        if ~isstruct(b)
            baselines.(nm) = b;
            continue;
        end
        baselines.(nm) = compact_baseline_for_cell(b, model_nrmse);
    end

    % Feature-specific Dale reference (never from conventional ESN).
    dale_key = dale_mesn_control_reference_key(feature_mode, bb.dale_mesn_control_keys);
    dale = struct();
    dale.name = 'dale_mesn_control';
    dale.status = 'pending_paired_aggregation';
    dale.role = 'paired_cell_reference';
    dale.protocol_version = 'matched_task_baselines_v1';
    dale.model_family = 'dale_mesn_control';
    dale.feature_dimension = NaN;
    dale.include_input = false;
    dale.train_rows = NaN;
    dale.validation_rows = NaN;
    dale.test_rows = NaN;
    dale.metrics = struct();
    dale.selected_lambda = NaN;
    dale.ridge_diagnostics = struct();
    dale.lambda_selection_table = [];
    dale.hyperparameters = struct();
    dale.provenance = struct( ...
        'dale_mesn_control_reference', dale_key, ...
        'note', 'Metric resolved from paired cell table in aggregation phase.', ...
        'not_conventional_esn', true);
    dale.dale_mesn_control_reference = dale_key;
    dale.comparison = struct( ...
        'status', 'pending_paired_aggregation', ...
        'dale_mesn_control_reference', dale_key);
    baselines.dale_mesn_control = dale;

    % Backward-compatible aliases when present upstream
    if isfield(baselines, 'training_target_mean')
        baselines.target_mean = baselines.training_target_mean;
    end
    if isfield(baselines, 'linear_input_history')
        baselines.linear_input_ar = baselines.linear_input_history;
    end
    if isfield(baselines, 'linear_autoregression')
        baselines.linear_ar = baselines.linear_autoregression;
    end
end

function b = compact_baseline_for_cell(b, model_nrmse)
    drop = {'candidate_selection_table', 'lambda_selection_table'};
    for i = 1:numel(drop)
        if isfield(b, drop{i})
            b = rmfield(b, drop{i});
        end
    end
    if isfield(b, 'ridge_diagnostics') && isstruct(b.ridge_diagnostics)
        rd = b.ridge_diagnostics;
        for f = {'coefficients', 'feature_mean', 'feature_scale'}
            if isfield(rd, f{1})
                rd = rmfield(rd, f{1});
            end
        end
        b.ridge_diagnostics = rd;
    end
    nrmse = local_nrmse(b);
    if isfield(b, 'name') && strcmp(char(b.name), 'dale_mesn_control')
        return;
    end
    b.comparison = baseline_model_comparison(model_nrmse, nrmse);
end

function nrmse = local_nrmse(b)
    if isfield(b, 'metrics_test') && isfield(b.metrics_test, 'nrmse')
        nrmse = b.metrics_test.nrmse;
    elseif isfield(b, 'metrics') && isfield(b.metrics, 'test') && ...
            isfield(b.metrics.test, 'nrmse')
        nrmse = b.metrics.test.nrmse;
    else
        nrmse = NaN;
    end
end

function v = local_field(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
