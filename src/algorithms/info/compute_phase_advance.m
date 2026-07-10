function pa = compute_phase_advance(X, u, options)
% compute_phase_advance  DEPRECATED wrapper around compute_response_lag.
%
% Prefer compute_response_lag. The historical name "phase advance" and the
% claim that negative lag means features lead the input are incorrect under the
% fixed convention R(k)=corr(feature(t),input(t+k)):
%   k < 0 -> feature lags (past input); k > 0 -> apparent future association.
%
% Issues warning MESN:DeprecatedPhaseAdvance on every call.

    if nargin < 3
        options = struct();
    end

    warning('MESN:DeprecatedPhaseAdvance', ...
        ['compute_phase_advance is deprecated. Use compute_response_lag. ', ...
         'Under R(k)=corr(feature(t),input(t+k)), k<0 means the feature lags ', ...
         '(past input); k>0 is apparent future association, not a validated lead.']);

    rl = compute_response_lag(X, u, options);

    % Compatibility fields for legacy callers (same numeric values as response lag).
    pa = rl;
    pa.xcorr_mean = mean(abs(rl.correlation_by_lag), 1);
    pa.peak_lag_per_unit = rl.peak_lag_samples;
    pa.mean_peak_lag = rl.mean_peak_lag_samples;
    % Historical name: fraction with k*<0. Under the corrected convention this
    % is memory-like lag, not "leading/predictive".
    pa.frac_leading = rl.frac_negative_lag;
end
