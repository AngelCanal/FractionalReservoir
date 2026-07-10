# MESN validation tests

Deterministic MATLAB function-based tests for the MESN validation repair program.

## Interactive MATLAB

From the repository root:

```matlab
addpath(genpath(pwd));
results = run_all_tests;
assertSuccess(results);
```

## Batch (CI or shell)

From the repository root:

```matlab
matlab -batch "addpath(genpath(pwd)); r=run_all_tests; assertSuccess(r)"
```

## Layout

| Directory | Purpose |
|---|---|
| `tests/unit/` | Pure helpers, validation, algebra, fitting |
| `tests/integration/` | Solver calls and class-level workflows |
| `tests/scientific/` | Known-system controls and claim-level gates |
| `tests/helpers/` | Shared test fixtures (not auto-discovered as tests) |

## Defaults

- RNG seed: `1729` (via `make_test_params`)
- ODE solver tolerances in tests: `RelTol=1e-8`, `AbsTol=1e-10`
- DDE solver tolerances in tests: `RelTol=1e-7`, `AbsTol=1e-9`
