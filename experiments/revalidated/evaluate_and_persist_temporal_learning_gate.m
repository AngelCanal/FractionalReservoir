function [gate_result, artifact_path, manifest_extra] = ...
        evaluate_and_persist_temporal_learning_gate(cfg, run_dir, save_results, gate_override)
% EVALUATE_AND_PERSIST_TEMPORAL_LEARNING_GATE  One-shot gate eval + optional save.
%
%   [gate_result, artifact_path, manifest_extra] = ...
%       evaluate_and_persist_temporal_learning_gate(cfg, run_dir, save_results)
%   [...] = evaluate_and_persist_temporal_learning_gate(cfg, run_dir, save_results, gate_override)
%
% Evaluates the gate exactly once for the final cfg. When save_results is true,
% atomically writes run_dir/validation/temporal_learning_gate.mat.
% gate_override (optional) injects a precomputed result (tests only).

    if nargin < 2
        run_dir = '';
    end
    if nargin < 3 || isempty(save_results)
        save_results = false;
    end
    if nargin < 4
        gate_override = [];
    end

    if ~isempty(gate_override)
        gate_result = gate_override;
    else
        gate_result = evaluate_temporal_learning_gate(cfg);
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
end
