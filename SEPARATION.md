# SEPARATION.md — the solver / simulator boundary

The founder's rule, which this document and `tests/test_separation.py` enforce:

> OTTO-Q is the foundational solver. It must not have simulation data wired in that makes it
> automatically know the answer to any particular world. The simulator — OTTO-Twin or any
> third-party world — is a **source of inputs, delivered as declared data**; the kernel must
> work identically pointed at a real depot it has never seen.

## The audit (2026-08-24), and what it found

**Simulation bleed into the solver: none found.** Mechanically verified, now CI-enforced:

- No kernel module (`policies/ solvers/ sites/ wear/ onboarding/ conformance/ recall/
  adapters/ metrics/`) imports a database client, the twin, or any network client. The
  kernel's entire world arrives as **function arguments** — scenario dicts, SiteProfiles,
  FleetSpecs, ExposureRecords.
- No kernel module contains the production project ref or the benchmark depot id. Knowing
  either is the beginning of knowing the answer.
- Every file read a kernel module performs is on an **explicit allowlist with a stated
  reason**, in exactly two categories: loading *declared world data* (scenarios, profiles,
  packs) or *byte-verifying* a committed artifact against a fresh computation. A new read
  fails CI and forces its author to justify it — that review moment is the point.
- The strictest slice — the modules that house `decide()` or price or derive
  (`assignment_policy`, the policy harness, `tariff`, `degradation`, `sizer`, the recall
  primitive) — read **no files at all**.

**One real leak was found, and it is not simulation — it is sector vocabulary.**
`solvers/cpsat/model.py` hardcodes point kinds (`"dcfc"`, `"l2"`, `"wash_bay"`,
`"service_bay"`) and two literal durations (wash = 12 min, inspect = 20 min). That is
*scenario data baked into the kernel*: a world whose service points are called something
else — an eVTOL pad, a swap dock, a mining refuel bay — cannot be expressed without editing
solver code, which violates the kernel test ("could a mining pack and a vertiport pack both
use it unchanged?"). This is being fixed by generalization, not exemption; it is also the
enabling step for multimodal.

## What runs on what — the answer to "twin data or your own scaffolding?"

Three layers, deliberately distinct:

| layer | world it runs against | what it is for |
|---|---|---|
| **Python kernel tests** (140+) | **our own scaffolding**: committed `scenario_*.json` files with fleets generated from a seed, site profiles, pack files | proving solver/pricing/sizing logic, deterministically, with zero twin involvement |
| **Determinism certification** (SQL, `ottoq_cert_arm_*`) | the **twin's** benchmark depot, sim-generated worlds | proving the *production decide path* is deterministic — the twin exercising the engine, which is its job |
| **Twin calibration** (ACN-Data, NYC TLC, NOAA quantile grids) | shapes twin **worlds** only | making simulated worlds realistic; **never consulted by the solver** |

The direction of information flow is one-way in both test layers: worlds flow *into* the
solver as data; nothing from a solved world flows back into solver code. Committed run
artifacts (`*_seed424242.json`) are reproducibility *outputs* under version control — a
CI test asserts kernel code never reads one back in, because an artifact fed back into a
decision is a memorized answer.

## The standing constraint this extends

This is the same rule already governing the intelligence layer (the founder's original
formulation): *no simulation data built onto the orchestration/intelligence, because it
will not apply to real-world depots.* The wear model's coefficients are literature with
provenance tags, not sim fits; the tariff engine's rates are utility schedules; the
sizer's physics are arithmetic. Where a number has no defensible source the module
refuses or labels — it never learns one from the twin.
