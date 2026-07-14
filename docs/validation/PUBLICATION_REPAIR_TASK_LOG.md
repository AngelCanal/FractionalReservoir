# MESN publication repair — task log

## Phase 1 checklist (before edits)

- [x] Confirm clean worktree at `bf78733`
- [x] Add `cfg.protocol_tier` (`smoke` | `pilot` | `publication`)
- [x] Add deterministic `cfg.protocol_fingerprint` (exclude timestamps/paths/host/runtime/fingerprint; canonicalize function handles)
- [x] Dedicated `run_mechanism_ablation_smoke.m`; reduced full-run path forces smoke + non-publication
- [x] Replace `g7_complete` with readiness fields; `publication_ready` is AND of all requirements
- [x] Add `validate_publication_run.m`
- [x] Regression tests: smoke≠publication-ready; fingerprint sensitivity/stability; missing seed/condition; duplicates; NaN primary; 30 smoke seeds fail readiness
- [x] Run Phase 1 tests; commit; do not start Phase 2

## Phase 1 after edits

| Field | Value |
|---|---|
| Status | complete |
| Starting SHA | `bf7873337d3e8df5a04f7bb32858910d380b1252` |
| Files changed | see git commit |
| Phase 1 tests | `tests/unit/test_protocol_fingerprint.m` — 14/14 pass |
| Full suite | 236/236 pass (elapsed ~1238 s) |
| Scientific behavior changed | no model equations or scientific parameters; protocol identity / gates only |
| Remaining blockers | Phase 2+ (ESP reset, matched contrasts, fair SFA, learning gate, etc.) |

## Phase 2

Not started.
