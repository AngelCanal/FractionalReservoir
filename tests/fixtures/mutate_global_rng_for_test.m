function mutate_global_rng_for_test()
%MUTATE_GLOBAL_RNG_FOR_TEST  Test-only helper that mutates the global RNG.
%
%   mutate_global_rng_for_test()
%
% Intentionally touches the global stream so calibration end-of-run audits
% can be regression-tested. Not exposed as a production option.

    rand();
end
