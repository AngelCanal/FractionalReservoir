# MESN mathematical support matrix

Status of each model capability in the validation repair program. Updated as gates pass.

| Capability | Status |
|---|---|
| ODE forward model | implemented but not scientifically validated |
| Scalar inhibitory DDE forward model | supported and tested |
| Vector DDE | unsupported; guarded error |
| No STD | supported and tested |
| One STD resource per population | supported and tested |
| Multiple STD resources | unsupported; guarded error |
| Multi-timescale SFA | implemented but not scientifically validated |
| ODE Jacobian (dense) | implemented but not scientifically validated |
| ODE Jacobian (fast) | implemented but not scientifically validated |
| DDE Jacobian | unsupported; guarded error |
| ODE largest Lyapunov exponent | implemented but not scientifically validated |
| DDE Lyapunov analysis | unsupported; guarded error |
| Teacher-forced readout training | implemented but not scientifically validated |
| ODE autonomous generation | implemented but not scientifically validated |
| DDE autonomous generation | unsupported; guarded error |

## Terminology

The model is a **multi-timescale SFA/STD delayed reservoir (MESN)**. A finite bank of exponential adaptation filters is **not** a fractional derivative unless a separate mathematical approximation and error analysis is provided.

## Validation gates

See `docs/validation/BASELINE.md` and the implementation plan for gate definitions G0–G7.
