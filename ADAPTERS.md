# ADAPTERS.md — the adapter boundary (Run 4 · Phase C10)

**Status:** interface and enforcement COMPLETE and tested. VDA 5050 draft COMPLETE
against H1's capture. OCPI mapping COMPLETE in structure, **field names pending
R-1**. Mining and vertiport are contract-only stubs, deliberately.

24 tests pass (`python3 -m pytest adapters/ -q`).

---

## 1. The two laws

CLAUDE.md C10 requires both laws "encoded in interface types so violation is a
compile error." Python has no compile step, so the strongest honest equivalent is
used **and named as such**: both laws are enforced in `Adapter.__init_subclass__`,
which runs when the `class` statement executes. A violating adapter fails at
**import** — before any instance exists, before any translation runs. That is the
same practical guarantee (you cannot ship it) reached by a different mechanism.
This document says *import-time enforcement*, never "compile error", because the
distinction is real and pretending otherwise would be the first false claim in a
file whose whole job is to be checkable.

### LAW 1 — adapters translate, never decide

An adapter converts foreign words into kernel facts and kernel decisions into
foreign words. It never chooses a stall, a time, an order, or a priority.

Enforced three ways, all tested:

| Mechanism | What it catches |
|---|---|
| Decision-verb method names rejected | `assign_stall`, `choose_bay`, `optimize_route`, `book_slot`, … — the head word is matched, so prefixes fail too |
| `inbound()` may not return `ServiceIntent` | manufacturing a decision on the inbound path — scheduling by the back door |
| The Protocol has exactly two directions | no `state()`, no `tick()`, no site handle. **An adapter that cannot see site state cannot schedule against it** — withholding the inputs is the cheapest way to keep the law true |

### LAW 2 — power publication is schedule-shaped, never real-time

OTTO-Q publishes forward demand schedules to site controllers and vendor EMS. It
never commands a physical inverter (CLAUDE.md 2.5).

| Mechanism | What it catches |
|---|---|
| Only `ForwardPowerSchedule` is power-bearing | there is no setpoint type to reach for |
| Setpoint-shaped field names rejected | `setpoint_kw`, `target_kw`, `instantaneous_kw`, `duty_cycle`, `current_a`, … on any adapter-declared dataclass |
| `power_output_type` must be `ForwardPowerSchedule` | declaring any other power output |
| A zero-duration or empty schedule raises | *"a schedule with neither is a setpoint wearing a costume"* |

`PowerPeriod.limit_kw` is a **ceiling over an interval**, advisory to whoever owns
the hardware. There is deliberately no field meaning "draw exactly this now."

---

## 2. The interface

```
AssetFact          inbound   — something the foreign system asserts is TRUE.
                              A fact, never a request.
ServiceIntent      outbound  — a kernel decision awaiting translation. The adapter
                              receives it already decided.
ForwardPowerSchedule         — the only power-bearing outbound type.
```

The vocabulary is deliberately small. *An adapter that needs a richer vocabulary is
usually an adapter that is about to start deciding.*

---

## 3. OCPI mapping — `adapters/ocpi/`

> **ASSUMPTION — pending R-1.** Every OCPI *field name* below is assumed. H7 §3.1
> names `github.com/ocpi/ocpi` as the field source and marks it "adopt"; H8 confirms
> conformance is tested against 2.2.1 or 2.3.0. **Neither merged file contains the
> field lists.** The *structure*, the totality check and the round-trip property are
> independent of spelling: when R-1 lands, wrong names are a rename in
> `OCPI_CDR_FIELDS`, not a redesign.

### 3.1 The mapping is deliberately asymmetric

| Direction | Property | Why |
|---|---|---|
| CDR → SDR | **LOSSLESS** | the SDR was shaped as a superset in C3 |
| SDR → CDR | **LOSSY, by design** | OCPI standardised electrons; a wash has no kWh, no meter, no connector |

C10's done-when is "round-trips a synthetic session losslessly." The lossless
direction is the one asserted. Claiming losslessness the other way would be false
for every non-energy operation — i.e. for most of the catalog.

### 3.2 Field-by-field

| OCPI CDR | `ottoq_service_detail_records` | Note |
|---|---|---|
| `id` | `sdr_id` | |
| `start_date_time` / `end_date_time` | `started_at` / `ended_at` | |
| `session_id` | `ocpp_session_id` | |
| `total_energy` | `energy_kwh` | |
| `total_cost` | `total_cost_usd` | |
| `currency` | `currency` | |
| `total_time` | `duration_min` | **UNIT HAZARD** — ours is minutes; OCPI assumed hours. R-1 asks. Conversion lives in one place. |
| `cdr_token` | `fleet_operator_id` | via `ottoq_service_tokens` |
| `tariff_id` | `tariff_id` | |
| `signed_data` | `signature` | ours is a keyed registry, OCPI's is one blob |
| `last_updated` | `issued_at` | |
| `cdr_location` | `depot_id` + `stall_id` | |

### 3.3 What OCPI cannot carry — the moat, enumerated

`operation_code` · `pack_id` · `asset_class_code` · `peak_kw` · `cost_components` ·
`billable_amount_usd` · `source_kind` · itinerary provenance · the signing registry ·
`data_source` · `sim_run_id`.

**The test asserts the loss is total:** from an OCPI CDR alone you cannot distinguish
a wash from a charge that delivered no energy. That indistinguishability *is* the gap
CLAUDE.md 2.6 and H1's gap table independently describe. H1 marks the owner of
"Model Service Session w/ Economics" as **None** and notes: *"This is the moat."*

---

## 4. VDA 5050 draft — `adapters/vda5050/`

Source: H1's verbatim `/order` and `/state` capture. **Every consumed and emitted
field is named** in `CONSUMED_STATE_FIELDS` and `EMITTED_ORDER_FIELDS`, or marked
`PROVISIONAL` — C10's done-when for this adapter.

### 4.1 Where OTTO-Q sits

Beside a VDA 5050 master controller, never instead of it. H1: the standard is
"comprehensive, operational and command-capable" for dispatch and traffic, and
"explicitly excludes service-side functions: energy strategy, battery health
economics, service events, and cross-fleet settlement." **That exclusion is the seam.**

### 4.2 The handoff sequence

| # | Step | Owner |
|---|---|---|
| 1 | `/order` (work) → robot | master |
| 2 | `/state` → master | robot |
| 3 | `/state` forwarded or tapped → OTTO-Q | **integration — see R-2 Q3** |
| 4 | `RecallDecision.decide(...)` | **KERNEL** (`recall/`) |
| 5 | `ServiceIntent` → master | kernel |
| 6 | `ServiceIntent` → `/order` (service) | **this adapter — translation only** |
| 7 | `/order` (service) sequenced → robot | master |
| 8 | `/state`, `actionState: COMPLETED` | robot |
| 9 | `/state` → `AssetFact(ready)` | **this adapter — translation only** |
| 10 | ready-for-work → master | kernel |

Steps 6 and 9 are the only ones the adapter performs. **The master decides where the
robot drives; OTTO-Q decides when it stops working and what it needs; the adapter
decides nothing.**

### 4.3 Two things marked provisional, and why

**The version discrepancy.** H1's prose says VDA 5050 **3.0.0 (March 2026)**; every
JSON example in the same file carries `"version": "1.3.2"`. Both cannot be right. The
adapter reads the wire version, echoes it, and **never parses it for behaviour**. → R-2 Q1.

**The `actionType` vocabulary.** H1 captures the action *structure* precisely but does
not enumerate the predefined action set. The adapter emits OTTO-Q-namespaced custom
actions (`ottoq.startCharging`) on the reasoning that **an unrecognised custom action
should fail loudly, whereas a guessed standard name could silently collide with a real
one and trigger the wrong behaviour on real hardware.** R-2 Q4 asks what a robot
actually does with an unknown action — which confirms or refutes that reasoning.

`blockingType: HARD` is *not* provisional: H1 gives the enum and states HARD "prevents
other actions." A service action occupies the asset exclusively — a robot cannot charge
and haul — so HARD is the only correct value.

Order and action ids are **deterministic** from the intent, never random. Random ids
would break the master's de-duplication *and* put a nondeterminism in the adapter —
the exact defect class migrations 0052/0055/0058 spent three rounds removing.

---

## 5. Paper packs — `adapters/mining/`, `adapters/vertiport/`

Contract only: they load, declare their constraints, and **raise on use**. Following
the C5 `WaymoStagingPolicy` precedent. Implementing them would prejudge C11's verdict.

Neither drafts a wire format, because neither research file has one: H2's open
questions record that MineStar/DISPATCH endpoints, schemas and auth are unknown; H3
records that Eve UATM third-party API access is unconfirmed. **A guessed field list
would read as knowledge.**

Each declares its hardest constraints and an honest read, **written before C11 runs so
the verdict cannot be retrofitted**:

| Constraint | Read |
|---|---|
| mining C4 trolley path dependency | probably declarative (transit point, exclusive occupancy) — unconfirmed |
| mining C5 multi-threshold maintenance | **likely already supported** — `RecallDecision` is a first-hit-wins rung ladder over multi-signal state. Easier than H2 expects |
| **mining C6 operator override** | **the one to watch.** H2 calls it "anathema to a solver-based kernel." We may already have it: 2.7 makes work-side refusal a first-class event triggering re-solve, and C9 implements `refuse()`. If an override is a refusal with a different actor, the kernel bends. **If it must also invalidate a constraint the solver treated as hard, it does not — and that is a platform-thesis finding to escalate per 2.2, not to quietly absorb.** |
| vertiport battery cooling | likely declarative — 2.5 already has DCFC cooldown as a minimum gap on the *service point*; this is the same on the *asset*. Whether the kernel expresses asset-side gaps is a real C11 question, not a rename |
| vertiport tug-as-resource | probably supported — 2.3 already requires inter-point moves that consume path resources |
| **vertiport charger compatibility** | **flagged** — a non-numeric handshake dependency where duration is not determined by power alone. Least like our `(asset_class, operation)` capability model |

**Two independent sectors describe the same hole.** H1's gap table marks
`Arbitrate Multi-Party Bay Access` owner **None**; H3's open questions ask "how do
vertiport operators plan to handle inter-operator arbitration for pad scheduling?"
That convergence is the strongest evidence in the research set that the kernel is
aimed at something real.

---

## 6. C10 done-when

| Criterion | Status |
|---|---|
| OCPI mapping round-trips a synthetic session losslessly | **PASS** — CDR → SDR → CDR asserted equal; fixture asserted to exercise every mapped field |
| VDA 5050 draft names every consumed/emitted field or marks it provisional | **PASS** — `CONSUMED_STATE_FIELDS`, `EMITTED_ORDER_FIELDS` |
| No adapter contains a scheduling decision | **PASS** — enforced at import, 13 law tests |
| `ADAPTERS.md` + the adapter interface | **PASS** — this file, `adapters/base.py` |
| Mining and vertiport stubs with interface contracts only | **PASS** |

## 7. Open requests

- **R-1** — OCPI 2.2.1 field lists for Session, CDR, Tariff, Token, ChargingProfile,
  with units and complete enum sets. Plus: does OCPI define *any* object for a
  completed non-energy service event? **Our 2.6 moat claim depends on the answer
  being no, and we should not repeat it in a spec we intend to publish until it is
  confirmed.**
- **R-2** — which VDA 5050 version H1 actually captured; the `actionType` vocabulary;
  what a robot does with an unknown action; whether a master controller exposes
  `/state` to a third party.
