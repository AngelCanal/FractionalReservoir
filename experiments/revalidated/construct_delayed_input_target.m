function [y, scored_idx, U_scored] = construct_delayed_input_target(U, target_lag_steps, washout_steps, n_samples)
% CONSTRUCT_DELAYED_INPUT_TARGET  Build y(t)=u(t-k) with washout and lag prefix.
%
%   [y, scored_idx, U_scored] = construct_delayed_input_target(U, k, washout, n)
%
% Requires numel(U) == washout + k + n. Scored samples start after washout and
% lag so that y(t)=U(t-k) never references another split.

    if nargin < 4
        error('construct_delayed_input_target:MissingArgs', 'Four arguments required.');
    end
    k = target_lag_steps;
    if ~(isfinite(k) && k > 0 && k == floor(k))
        error('construct_delayed_input_target:InvalidLag', ...
            'target_lag_steps must be a positive integer.');
    end
    L_expected = washout_steps + k + n_samples;
    if numel(U) ~= L_expected
        error('construct_delayed_input_target:LengthMismatch', ...
            'Expected length %d, got %d.', L_expected, numel(U));
    end
    U = U(:);
    scored_idx = (washout_steps + k + 1):L_expected;
    scored_idx = scored_idx(:);
    y = U(scored_idx - k);
    U_scored = U(scored_idx);
end
