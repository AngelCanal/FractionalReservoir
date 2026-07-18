# Seed role ledger

**Status:** frozen (Phase 5D-A2)  
**Authority:** `experiments/development/temporal_memory_development_config.m`  
**Companion:** `docs/validation/TEMPORAL_MEMORY_DEVELOPMENT_PREREGISTRATION.md`

This ledger records seed **roles**, observation status, retirement, and
reservation. It exists to prevent silent reuse across v1 gate evidence,
development diagnosis, and future v2 confirmatory work.

---

## 1. Role taxonomy

| Role | Meaning | Executable now? |
|---|---|---|
| `v1_observed` | Already seen under sealed `temporal_learning_gate_v1` / calibration | only if also listed as development-permitted |
| `development_executable` | Permitted for `temporal_memory_diagnostic_v1` | yes (development only) |
| `retired_from_future_publication` | Must not enter future confirmatory paper seed sets | no (for future paper) |
| `current_publication` | Current publication matrix seeds | **no** in development |
| `reserved_future_v2` | Untouched seeds for future v2 gate / paper | **no** in development |

---

## 2. V1 already observed

### Model seeds

```text
[1729, 2718, 31415, 10007, 10009]
```

### Task seeds

```text
[9001, 9002, 9003]
```

### Shuffle seeds

```text
[9101, 9102, 9103]
```

### Calibration seeds

```text
[1729, 2718]
```

Notes:

- V1 test input seed **9003** is permanently forbidden for development execution.
- V1 test targets must never be used for model selection.

---

## 3. Retired from future confirmatory publication

```text
[10007, 10009]
```

Retire these from any future confirmatory paper seed set because the
architecture-repair decision will be informed by their v1 gate outcomes.

They remain recorded as v1-observed. They are **not** development-executable
model seeds under this protocol (development executes only
`[1729, 2718, 31415]`).

---

## 4. Development-executable seeds

### Model seeds

```text
[1729, 2718, 31415]
```

Already observed; may now be used **only** for development diagnosis.

### Task seeds

| Split | Seed |
|---|---|
| train | 12001 |
| validation | 12002 |
| test | 12003 |

### Shuffle seeds

| Split | Seed |
|---|---|
| train | 12101 |
| validation | 12102 |
| test | 12103 |

Disjointness requirements (all must hold):

- development task ≠ development model
- development shuffle ≠ development model
- development shuffle ≠ development task
- development seeds ≠ v1 task / shuffle seeds
- development seeds ≠ current publication seeds (execution)
- development seeds ≠ all reserved future-v2 seeds
- development seeds ≠ calibration-only reuse beyond the explicit development
  model-seed permission above

---

## 5. Reserved future v2 seeds (do not execute in development)

### Future v2 gate model seeds

```text
[11003, 11027, 11047, 11057, 11069]
```

### Future v2 gate task seeds

| Split | Seed |
|---|---|
| train | 13001 |
| validation | 13003 |
| test | 13007 |

### Future v2 gate shuffle seeds

| Split | Seed |
|---|---|
| train | 13101 |
| validation | 13103 |
| test | 13107 |

### Future v2 calibration seeds

```text
[14009, 14011]
```

### Future v2 full publication seeds (exactly 30 unique)

```text
[10037, 10039, 10061, 10067, 10069, 10079, 10091, 10093,
 10099, 10103, 10111, 10133, 10139, 10141, 10151, 10159,
 10163, 10169, 10177, 10181, 10193, 10211, 10223, 10243,
 10247, 10253, 10259, 10267, 10271, 10273]
```

Relative to the current publication set, `10007` and `10009` are removed and
`10271` and `10273` are added, preserving cardinality 30.

---

## 6. Current publication seeds (not for development execution)

```text
[10007, 10009, 10037, 10039, 10061, 10067, 10069, 10079, 10091, 10093,
 10099, 10103, 10111, 10133, 10139, 10141, 10151, 10159, 10163, 10169,
 10177, 10181, 10193, 10211, 10223, 10243, 10247, 10253, 10259, 10267]
```

Listed for isolation checks. This ledger does **not** mutate
`mechanism_ablation_config.m`.

---

## 7. Enforcement

`validate_temporal_memory_development_config` rejects:

- executed use of seed **9003**
- executed use of any reserved future-v2 seed
- overlap between development task and model seeds
- missing retirement of `10007` / `10009`
- any attempt to mark this development protocol publication-ready
