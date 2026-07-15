function [gate_result, artifact_path, manifest_extra] = ...
        evaluate_and_persist_temporal_learning_gate(cfg, run_dir, save_results, persist_opts)
% EVALUATE_AND_PERSIST_TEMPORAL_LEARNING_GATE  One-shot gate eval + optional save.
%
%   [gate_result, artifact_path, manifest_extra] = ...
%       evaluate_and_persist_temporal_learning_gate(cfg, run_dir, save_results)
%   [...] = evaluate_and_persist_temporal_learning_gate(cfg, run_dir, save_results, persist_opts)
%
% Evaluates the gate exactly once for the final cfg. When save_results is true,
% atomically writes run_dir/validation/temporal_learning_gate.mat.
%
% persist_opts (optional):
%   gate_override               - precomputed result (tests only)
%   allow_injected_test_fixture - must be true to accept gate_override
%
% Normally executed results are validated before persistence. Scientific failure
% (passed=false) is still persisted when the artifact is internally consistent.

    if nargin < 2
        run_dir = '';
    end
    if nargin < 3 || isempty(save_results)
        save_results = false;
    end
    if nargin < 4 || isempty(persist_opts)
        persist_opts = struct();
    end

    gate_override = local_get(persist_opts, 'gate_override', []);
    allow_injected = logical(local_get(persist_opts, 'allow_injected_test_fixture', false));

    if ~isempty(gate_override)
        if ~allow_injected
            error('evaluate_and_persist_temporal_learning_gate:OverrideForbidden', ...
                ['temporal_learning_gate_override requires ', ...
                 'allow_injected_test_fixture=true (test-only).']);
        end
        gate_result = gate_override;
        gate_result.evaluation_provenance = struct( ...
            'mode', 'injected_test_fixture', ...
            'test_override_used', true, ...
            'test_target_mutated', false);
    else
        gate_result = evaluate_temporal_learning_gate(cfg);
        [artifact_ok, val_report] = validate_temporal_learning_gate_result(gate_result, cfg);
        if ~artifact_ok
            error('evaluate_and_persist_temporal_learning_gate:ArtifactInvalid', ...
                'Gate result failed independent validation: %s', ...
                strjoin(val_report.reasons, ','));
        end
    end

    artifact_path = '';

    if logical(save_results) && ~isempty(run_dir)
        val_dir = fullfile(char(run_dir), 'validation');
        if ~isfolder(val_dir)
            mkdir(val_dir);
        end
        artifact_path = fullfile(val_dir, 'temporal_learning_gate.mat');
        atomic_save_results(artifact_path, struct('temporal_learning_gate', gate_result));
    end

    manifest_extra = struct();
    manifest_extra.temporal_learning_gate_protocol_version = char(gate_result.protocol_version);
    manifest_extra.temporal_learning_gate_protocol_fingerprint = ...
        char(gate_result.protocol_fingerprint);
    manifest_extra.temporal_learning_gate_status = char(gate_result.status);
    manifest_extra.temporal_learning_gate_passed = logical(gate_result.passed);
    if isfield(gate_result, 'failure_reasons')
        manifest_extra.temporal_learning_gate_failure_reasons = gate_result.failure_reasons;
    else
        manifest_extra.temporal_learning_gate_failure_reasons = {};
    end
    if isfield(gate_result, 'evaluation_provenance')
        manifest_extra.temporal_learning_gate_evaluation_mode = ...
            char(gate_result.evaluation_provenance.mode);
    end
end

function v = local_get(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
