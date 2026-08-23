# CONFORMANCE_FINDINGS.md — is OTTO-Q a platform, or N products?

**Run 4 · Phase C11 · 2026-08-22.** Instrument: `conformance/`. 56 tests pass.
*Revised the same day: §3.1 below recorded a gap in the instrument; that gap has
since been closed and the table re-measured. The original finding is kept rather
than deleted — it is the reason the numbers moved.*
CLAUDE.md instructs that this document be written *"willing to conclude either
way."* What follows is written to that instruction.

---

## The verdict

> **Platform — provisionally, and with one identified exception that is a genuine
> solver change rather than a missing field.**
>
> Four packs across four unrelated sectors load against a closed spec and schedule
> to zero invariant violations with **zero kernel modification**. That is the
> thesis's central claim and it survived the test.
>
> It is called *provisional* for the reasons named below. **Exactly one genuine
> solver change was found across all four packs** — vertiport pad separation (§1), a
> pairwise spatial exclusion the resource model cannot express. Everything else that
> looked like a kernel hole turned out to be either a gap in this instrument or a
> wiring gap between two kernel parts that both already exist (§1b). All of those
> have been closed and re-measured; the numbers in the table above are post-correction.

| Pack | Status | Loads | Solves | Findings | Unexercised claims |
|---|---|---|---|---|---|
| robotaxi | reference | ✅ | ✅ 840 ops | none | **0 — fully evidenced** |
| yard-logistics | build | ✅ | ✅ 64 ops | none | **0 — fully evidenced** |
| mining | paper | ✅ | ✅ 96 ops | none | **3 of 6** |
| vertiport | paper | ✅ | ✅ 84 ops | **2** | 1 |

Zero power-cap violations, zero point overlaps, zero operations on incapable
points, across all four packs. The verifier is not vacuous: it has negative tests
for each of the three invariants, and rejects each when deliberately broken.

> **CORRECTION (2026-08-23) — the power-cap half of that sentence is vacuous and is
> withdrawn.** No pack can reach the 3,000 kW cap even with every point drawing its rated
> power simultaneously: mining tops out at 600 kW, vertiport 1,400, yard-logistics 1,524,
> robotaxi 1,652. "Zero power-cap violations" was guaranteed by arithmetic before the
> scheduler ran, so it is not evidence that the kernel holds the site constraint. The
> *verifier* remains sound — `test_verifier_catches_power_cap_breach` constructs a deliberate
> breach and asserts rejection — but the packs passing it prove nothing. The point-overlap
> and incapable-point results are unaffected: those constraints do bind and are contested.
> See `docs/BENCHMARK_CREDIBILITY.md`.

---

## 1. The one genuine solver change: **V5 — pad separation**

FAA EB 105A requires a minimum 1.5× aircraft-diameter separation between *active*
vertipads. That is a **pairwise spatial exclusion**: two named points may not be
simultaneously active.

Every resource mechanism the kernel has is either

- **per-point** — `exclusive_occupancy` (the `ottoq_stall_bookings` EXCLUDE
  constraint), or
- **site-wide** — `site_power_cap`.

**Nothing expresses a constraint between two specific points.** No declarative
field fixes this; a pack can declare the pairing, but the scheduler has no notion
of "if A is busy, B must be idle" to enforce it. This is classified
`SOLVER_CHANGE` in the pack file itself, and the classification was written
*before* the harness ran.

**Honest scope of the damage.** This is not a vertiport-only concern. Pairwise
exclusion is the shape of any spatial-interference constraint — adjacent bays that
share a door swing, two lifts that cannot both extend, a crane envelope over two
stalls. The kernel has not needed it yet because robotaxi and yard depots are
modelled as independent points. **It is a real limit of the resource model, and
the first one this project has found that a declarative mechanism cannot close.**

Per CLAUDE.md 2.2 this is a platform-thesis finding, and it is escalated here
rather than absorbed. It does not falsify the thesis — one solver extension across
four sectors is a good ratio — but it is the honest cost of entry to vertiport.

## 1b. Mining C6 answered — and the finding is a WIRING gap, not a modelling one

*This section was rewritten after further investigation. Its first version claimed
the kernel could not express the limit of an operator override. That was wrong, and
the corrected version is below. The error is left described rather than deleted,
because it is the same mistake this document warns packs against: reasoning from
one mechanism's shape to the kernel's whole capability.*

H2 calls `C6_Operator_Override_Overrules_System` *"anathema to a solver-based
kernel"*. The claim has now been exercised against the real C9 primitive
(`conformance/test_operator_override.py`, 5 tests).

**H2's prediction is wrong in the direction it feared.** The kernel supports the
override cleanly: `run_recall_cycle` consults `work_side_accepts`, and a refusal
cancels the recall, emits `recall_refused`, and triggers re-solve — exactly the
first-class-event contract CLAUDE.md 2.7 specifies. A human override is a refusal
with a human actor, and the kernel already bends.

**And the kernel models override AUTHORITY precisely — in Layer 1, already.**
`ottoq_rules` (52 rows, 29 distinct codes, 686,057 logged evaluations) carries
`severity`, `enforcement`, `override_allowed` and `override_min_role` per rule:

| | count | examples |
|---|---|---|
| non-overridable, `block`, **safety_critical** | 10 | `HW.001.connector_compatibility`, `HW.003.sensor_liveness`, `EN.001.grid_capacity_ceiling` |
| non-overridable, `block`, critical | 26 | `HW.004.stall_single_vehicle`, `SLA.001.min_soc_at_deployment` |
| **overridable, behind a named role** | 5 | `EN.004.demand_response_compliance` → `command_center_operator`; `SLA.006.maintenance_window` → `depot_supervisor` |

There is even `SM.005.audit_note_required_on_overrides`. So the kernel can already
express *"a supervisor may override a maintenance window but nobody may override a
sensor-liveness block"* — which is precisely what a mine operator needs.

**The actual finding, and it is narrower and more tractable than first stated:**

> **The recall refusal path does not consult any of it.** `work_side_accepts` is a
> bare `Callable[[RecallOutcome], bool]` — **no actor, no role, no rule reference**.
> So the refusal has nothing to check the Layer 1 authority model against, and
> `run_recall_cycle` never reads `outcome.deferrable` either.

Measured consequence: an asset with a safety-critical fault yields
`recall=True, urgency=critical, deferrable=False`, and a refusal cancels it anyway.
The same holds for `critical_reserve` — a vehicle about to strand below reserve can
be kept working by a refusal.

**Classification: an INTEGRATION defect in the reference implementation, not a
solver change and not a pack conformance failure.** Both halves exist — Layer 1
knows who may override what, and the recall primitive knows the outcome is
non-deferrable — and they are simply not connected. Two tests pin it: one asserts
`run_recall_cycle` references no authority concept, another that its callback
signature carries no actor. **Both fail loudly the moment someone wires it up**, so
this finding cannot quietly rot.

Not everything here is a defect, and the tests say so: refusing a *routine* recall
is correct and intended, and is asserted as such.

---

## 2. The one that looked like a second hole and was not: **V4 — battery cooling**

A 20-minute cooldown before fast charge if SoC > 90% on landing. H3 rates this among
the three hardest vertiport constraints, and it was originally recorded here as a
finding with **no kernel mechanism**, on the reasoning that `min_gap_on_point` is a
property of the **point** while V4's gap belongs to the **asset** and is
**conditional on SoC**.

**That reasoning was right about `min_gap_on_point` and wrong about the kernel.**
Layer 1 (`ottoq_rules`) is exactly a conditional, parameterizable, logged
precondition engine, and `HW.002.charger_state_precondition` is already the same
shape in production. *"Block `fast_charge` for 20 minutes after landing when SoC >
90"* is a **row**, not a code change.

**The omission was in this harness's mechanism registry, not in the engine.**
`layer1_rule` has been added to the closed registry with its evidence, and V4
reclassified to it. Recorded rather than quietly fixed, because a registry that
grows silently is how a falsification test becomes a rubber stamp — and because the
mistake is instructive: reasoning from *one* mechanism's shape to the kernel's whole
capability is the same error this document warns packs against.

---

## 3. Where the instrument is weaker than the verdict

Stated plainly, because a verdict is only as good as what produced it.

### 3.1 `movement_as_operation` — the gap, and its closure

**Original finding (kept for the record):** the harness scheduled service
operations but not the inter-point moves between them, so the mechanism CLAUDE.md
2.3 calls one of the two places throughput lives was *asserted by every pack and
tested by nothing.*

**Closed.** The harness now schedules a move whenever an asset changes points, and
`path_resources` were added to the pack spec: a named finite resource a move
occupies for its duration (a trolley line of capacity 1, a tug fleet of capacity
2). A **fourth invariant** — no path-resource over-subscription — is verified on the
same concurrency sweep as the power cap.

**This was not a kernel change.** `path_resources` is a pack-level declaration
mapped to `movement_as_operation`, which 2.3 says the engine already has. The
instrument caught up to the kernel; the kernel was not extended to suit a pack.

**What it changed.** `movement_as_operation` is now exercised by all four packs.
robotaxi and yard-logistics went from one unverified claim each to **fully
evidenced — every mechanism they claim was actually reached.** Mining fell from
five unverified claims to three.

**And it produced a real result, not just a green tick.** Vertiport's
`Tug-As-Resource` (capacity 2) is genuinely **stressed**: moves actually contend
for tugs, the capacity check has to say no, and the schedule survives. That is a
constraint H3 rates among the hardest for vertiports, now evidenced rather than
assumed.

**One honest weakness, reported by the instrument itself.** Mining's trolley line
is *exercised but never stressed* — 36 moves, zero overlapping pairs, so the
capacity check was reached but never had to reject anything. A pass under those
conditions means very little, and `ConformanceResult.path_stressed` now says so in
the output rather than letting it read as a strong result. The path checker is
separately proven to fire: a negative test feeds it two concurrent trams against
capacity 1 and asserts the rejection.

**A limitation worth naming for whoever picks up mining C4.** Path consumption is
declared **per operation**, not per `(asset_class, operation)`. Mining's trolley
line binds only *trolley-assisted* trucks, but a pack can only say "the `tram`
operation consumes the trolley line" — which would bind diesel trucks too. The
declarative workaround is to split the operation (`tram` vs `tram_trolley`); that
was not done here because it should be measured, not assumed to work. **This is the
most likely place mining C4's conformance argument breaks, and it is not yet
tested.**

### 3.2 Mining passes on five unexamined claims

Mining reports zero findings, and that number is misleading on its own. **Two of its six
constraints name a mechanism the harness run never reached** (five before §3.1 was
closed, three before C6 was exercised separately in §1b):

| Constraint | Claims | Exercised? |
|---|---|---|
| C1 clearance before bay entry | `movement_as_operation` | ✅ *(since §3.1 closed)* |
| C3 energy resupply window | `threshold_ladder` | ❌ |
| C4 trolley path dependency | `movement_as_operation` | ✅ *exercised, not stressed — see §3.1* |
| C5 multi-threshold maintenance | `threshold_ladder` | ❌ |
| **C6 operator override** | `work_side_refusal` | ✅ **answered — see §1b** |
| C2 exclusive bay use | `exclusive_occupancy` | ✅ |

**C6 is the open question of this phase.** CLAUDE.md 2.7 makes work-side refusal a
first-class event triggering re-solve, and C9 implements `refuse()`. *If* a human
override is a refusal with a human actor, the kernel already bends and H2's
prediction is wrong. *If* the override must additionally invalidate a constraint
the solver treated as hard — keep hauling a truck the rules say must be serviced —
then `work_side_refusal` does not cover it and mining acquires a `SOLVER_CHANGE`
finding of its own.

**The harness cannot currently tell these apart, and the verdict above should be
read knowing that.**

### 3.3 The harness tests expressibility, not throughput

A pack passing here has shown its world is expressible in kernel mechanisms and
admits a feasible schedule. It has **not** shown the production decide path
produces good throughput on it — that is C6/C8's question, measured separately and
on a live twin. The harness's scheduler is deliberately simple (earliest-fit under
kernel mechanisms only), because if a pack cannot be scheduled even by an
unambitious algorithm, the obstacle is the *model*, which is what is under test.
Conflating the two would let a pack pass on the strength of the engine's tuning
rather than the kernel's generality.

---

## 4. What would settle it

In priority order, each a concrete next experiment rather than a direction:

1. ~~**Schedule movements in the harness.**~~ **DONE** — see §3.1. Two packs went to
   fully evidenced; vertiport's tug constraint is now genuinely stressed. Residual:
   stress mining's trolley line, and test the per-class path split.
2. **Model an operator override and run it against `refuse()`.** Settles mining C6
   — the single finding most likely to change this verdict.
3. **Attempt a declarative asset-side conditional gap.** Confirms or overturns
   V4's `DECLARATIVE` classification.
4. **Design pairwise point exclusion.** The one acknowledged solver change. Worth
   scoping before it is committed to, since it touches the resource model that the
   determinism work in Run 3 has just been stabilised around.

---

## 5. The result that was not designed for, and is the strongest signal here

Two unrelated sectors independently describe **the same missing capability**.

H1's gap table (intralogistics) lists `Arbitrate Multi-Party Bay Access` — fair,
contractual, signed arbitration of a physical service bay between operators —
owner: **None**. H3's open questions (vertiport) ask: *"How do vertiport operators
plan to handle inter-operator arbitration for pad scheduling?"*

Neither research file was written with the other in view. Both arrive at a hole
that no standard and no product fills, and it is precisely the hole the kernel's
multi-tenant terms (`ottoq_fleet_operator_slas`), signed event stream, and
propose/dispose audit trail are shaped to fill.

**That convergence is not evidence that the kernel is technically general — §1 is
the honest accounting there. It is evidence that the generality is aimed at
something real.** Those are different claims and this document keeps them apart.
