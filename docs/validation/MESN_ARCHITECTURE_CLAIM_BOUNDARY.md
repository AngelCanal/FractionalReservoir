# MESN architecture claim boundary

**Purpose:** Keep claims about the current MESN strictly within what the
codebase actually implements. Prevent conflating SFA, STD, synaptic DDE
delays, multi-timescale exponential banks, and a future genuinely fractional
MESN.

**Related sealed result:** `TEMPORAL_GATE_V1_NEGATIVE_RESULT.md`
(Phase 5C-B2 / 5D-A1).

---

## Current architecture (non-fractional MESN)

The reference publication MESN under `temporal_learning_gate_v1` is:

- three-timescale **excitatory** spike-frequency adaptation (SFA)
- common single-timescale **inhibitory** SFA
- short-term depression (STD) enabled
- inhibitory synaptic DDE delay enabled
- readout features: firing rates `r`
- raw input excluded from the MESN readout

This is a **non-fractional** multi-mechanism reservoir. It uses ordinary
(and delay) differential equations with exponential adaptation timescales.
It does **not** implement a fractional derivative, fractional integral, or
fractional-order operator.

Allowed wording examples:

- “multi-timescale excitatory SFA with common inhibitory SFA, STD, and
  inhibitory DDE delay”
- “non-fractional MESN”
- “measurable lag-10 information under a preregistered gate” (only with the
  sealed metrics and the negative validity outcome)

---

## What SFA is (and is not)

**SFA (spike-frequency adaptation)** here means exponential adaptation state
filters with finite timescale banks (`tau_a_E`, `tau_a_I`) and coupling
weights. Equal-weight three-timescale excitatory banks are still a sum of
exponentials.

SFA is **not**:

- a fractional derivative
- evidence of fractional dynamics
- interchangeable with “long memory” without a preregistered memory metric

---

## What STD is (and is not)

**STD (short-term depression)** is a synaptic efficacy resource mechanism.
It is part of the current non-fractional MESN stack when enabled.

STD is **not** a fractional operator and does not authorize fractional claims.

---

## What synaptic DDE delays are (and are not)

**Inhibitory DDE delay** means a finite synaptic delay in a delay differential
equation (scalar inhibitory lag in the reference profile).

A DDE delay is **not**:

- a fractional derivative
- proof of fractional dynamics
- interchangeable with distributed fractional memory kernels

---

## What a future genuinely fractional MESN would require

A future fractional MESN is a **new architecture version**. It is not a
relabeling of the current multi-timescale SFA/STD/DDE stack.

Any fractional implementation must provide, at minimum:

1. an explicit fractional operator (or convergent approximation thereof)
2. a new architecture / protocol version identity
3. **new** calibration
4. **new** validation
5. **untouched** evaluation seeds (no reuse of sealed v1 selection/test
   targets for post-hoc model shopping)
6. claim language that separates fractional dynamics from SFA/STD/DDE

Until that exists, fractional-dynamics claims remain unsupported. See also
`CLAIM_EVIDENCE.md` (fractional dynamics row).

---

## Claim discipline tied to the sealed v1 gate

From the sealed `temporal_learning_gate_v1` negative result:

- Do not say the architecture “passed.”
- Do not say the MESN “cannot learn” or “contains no temporal information.”
- Do not treat the result as evidence of fractional dynamics.
- Do not reopen `temporal_learning_gate_v1` or its test target for model
  selection.
- Do not replace frozen candidate 1 with candidates 5, 9, or 13 after
  observing the result.

Diagnosis of the memory shortfall proceeds on
`investigate/mesn-temporal-memory-v2` under new, explicitly versioned work —
not by mutating sealed v1 artifacts.
