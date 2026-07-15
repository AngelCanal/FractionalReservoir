function [ok, report] = validate_seed_matched_baseline_bundle(bundle, cfg, base_seed, cell_W_in)
% VALIDATE_SEED_MATCHED_BASELINE_BUNDLE  Identity + fail-closed reuse checks.
%
%   [ok, report] = validate_seed_matched_baseline_bundle(bundle, cfg, base_seed, cell_W_in)
%
% Rejects wrong seed/fingerprint/W_in/task/split identity and non-production
% provenance modes for publication reuse.

    report = struct();
    report.reasons = {};
    report.ok = false;

    if ~isstruct(bundle)
        report.reasons = {'bundle_not_struct'};
        ok = false;
        return;
    end

    required = { ...
        'schema_version', 'protocol_version', 'protocol_tier', 'protocol_fingerprint', ...
        'base_seed', 'narma_task_seed', 'mackey_glass_task_seed', 'reservoir_size', ...
        'W_in_hash', 'narma_task_data_hash', 'narma_split_hash', ...
        'mackey_glass_task_data_hash', 'mackey_glass_split_hash', ...
        'baseline_result_status', 'evaluation_provenance', 'bundle_id', ...
        'narma', 'mackey_glass_onestep'};
    for i = 1:numel(required)
        if ~isfield(bundle, required{i})
            report.reasons{end+1} = sprintf('missing_field_%s', required{i}); %#ok<AGROW>
        end
    end
    if ~isempty(report.reasons)
        ok = false;
        return;
    end

    if ~strcmp(char(bundle.schema_version), 'seed_matched_baseline_bundle_v1')
        report.reasons{end+1} = 'schema_version_mismatch';
    end
    if bundle.base_seed ~= base_seed
        report.reasons{end+1} = 'base_seed_mismatch';
    end
    if ~strcmp(char(bundle.protocol_fingerprint), char(cfg.protocol_fingerprint))
        report.reasons{end+1} = 'protocol_fingerprint_mismatch';
    end
    if isfield(cfg, 'protocol_tier') && ...
            ~strcmp(char(bundle.protocol_tier), char(cfg.protocol_tier))
        report.reasons{end+1} = 'protocol_tier_mismatch';
    end

    cell_hash = hash_numeric_array(cell_W_in);
    if ~strcmp(char(bundle.W_in_hash), cell_hash)
        report.reasons{end+1} = 'W_in_hash_mismatch';
    end
    if size(cell_W_in, 1) ~= bundle.reservoir_size
        report.reasons{end+1} = 'reservoir_size_mismatch';
    end

    if ~isfield(bundle, 'evaluation_provenance') || ...
            ~isfield(bundle.evaluation_provenance, 'mode')
        report.reasons{end+1} = 'missing_evaluation_provenance';
    else
        mode = char(bundle.evaluation_provenance.mode);
        forbidden = {'injected', 'injected_test_fixture', 'fixture', 'override', ...
            'mutated', 'precomputed_unvalidated', 'executed_cell_local'};
        if any(strcmp(mode, forbidden))
            report.reasons{end+1} = sprintf('provenance_rejected_for_sharing:%s', mode);
        elseif ~strcmp(mode, 'executed_shared_seed_bundle')
            report.reasons{end+1} = sprintf('provenance_not_shared_seed_bundle:%s', mode);
        end
    end

    if ~strcmp(char(bundle.baseline_result_status), 'ok')
        report.reasons{end+1} = 'bundle_baseline_result_status_failed';
        if isfield(bundle, 'failure_reasons')
            report.reasons = [report.reasons, bundle.failure_reasons(:)']; %#ok<AGROW>
        end
    end

    expect_narma_seed = base_seed + 20;
    expect_mg_seed = base_seed + 30;
    if bundle.narma_task_seed ~= expect_narma_seed
        report.reasons{end+1} = 'narma_task_seed_mismatch';
    end
    if bundle.mackey_glass_task_seed ~= expect_mg_seed
        report.reasons{end+1} = 'mackey_glass_task_seed_mismatch';
    end

    lambda_grid = resolve_baseline_lambda_grid(struct(), cfg);
    if isfield(bundle, 'narma') && isfield(bundle.narma, 'baselines')
        [n_ok, n_rep] = validate_matched_task_baselines(bundle.narma.baselines, 'narma', ...
            struct('lambda_grid', lambda_grid, ...
                'task_data_hash', bundle.narma_task_data_hash, ...
                'split_hash', bundle.narma_split_hash, ...
                'require_dale', false, ...
                'require_comparisons', false, ...
                'require_candidate_table', true));
        if ~n_ok
            report.reasons = [report.reasons, prepend('narma', n_rep.reasons)]; %#ok<AGROW>
        end
    end
    if isfield(bundle, 'mackey_glass_onestep') && ...
            isfield(bundle.mackey_glass_onestep, 'baselines')
        [m_ok, m_rep] = validate_matched_task_baselines( ...
            bundle.mackey_glass_onestep.baselines, 'mackey_glass_onestep', ...
            struct('lambda_grid', lambda_grid, ...
                'task_data_hash', bundle.mackey_glass_task_data_hash, ...
                'split_hash', bundle.mackey_glass_split_hash, ...
                'require_dale', false, ...
                'require_comparisons', false, ...
                'require_candidate_table', true));
        if ~m_ok
            report.reasons = [report.reasons, prepend('mackey_glass', m_rep.reasons)]; %#ok<AGROW>
        end
    end

    % Recompute deterministic bundle id from identity fields (no timestamps).
    identity = local_identity(bundle);
    recomputed = canonical_sha256(identity);
    if ~strcmp(char(bundle.bundle_id), recomputed)
        report.reasons{end+1} = 'bundle_id_mismatch';
    end

    report.ok = isempty(report.reasons);
    ok = report.ok;
end

function identity = local_identity(bundle)
    identity = struct();
    identity.schema_version = bundle.schema_version;
    identity.protocol_version = bundle.protocol_version;
    identity.protocol_tier = bundle.protocol_tier;
    identity.protocol_fingerprint = bundle.protocol_fingerprint;
    identity.base_seed = bundle.base_seed;
    identity.narma_task_seed = bundle.narma_task_seed;
    identity.mackey_glass_task_seed = bundle.mackey_glass_task_seed;
    identity.reservoir_size = bundle.reservoir_size;
    identity.dt = bundle.dt;
    identity.candidate_grids = bundle.candidate_grids;
    identity.ridge_lambda_grid = bundle.ridge_lambda_grid;
    identity.W_in_hash = bundle.W_in_hash;
    identity.narma_task_data_hash = bundle.narma_task_data_hash;
    identity.narma_split_hash = bundle.narma_split_hash;
    identity.mackey_glass_task_data_hash = bundle.mackey_glass_task_data_hash;
    identity.mackey_glass_split_hash = bundle.mackey_glass_split_hash;
end

function out = prepend(prefix, reasons)
    out = reasons(:);
    for i = 1:numel(out)
        out{i} = sprintf('%s:%s', prefix, out{i});
    end
end
