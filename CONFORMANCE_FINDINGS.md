# CONFORMANCE_FINDINGS.md — is OTTO-Q a platform, or N products?

**Run 4 · Phase C11 · 2026-08-22.** Instrument: `conformance/`. 49 tests pass.
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
> It is called *provisional* for three specific reasons, each named below. Two are
> gaps in the instrument, not in the kernel. One — vertiport pad separation — is a
> real hole in the kernel's resource model.

| Pack | Status | Loads | Solves | Findings | Unexercised claims |
|---|---|---|---|---|---|
| robotaxi | reference | ✅ | ✅ 840 ops | none | **0 — fully evidenced** |
| yard-logistics | build | ✅ | ✅ 64 ops | none | **0 — fully evidenced** |
| mining | paper | ✅ | ✅ 96 ops | none | **3 of 6** |
| vertiport | paper | ✅ | ✅ 84 ops | **2** | 1 |

Zero power-cap violations, zero point overlaps, zero operations on incapable
points, across all four packs. The verifier is not vacuous: it has negative tests
for each of the three invariants, and rejects each when deliberately broken.

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

## 2. The one that looks harder than it is: **V4 — battery cooling**

A 20-minute cooldown before fast charge if SoC > 90% on landing. H3 rates this
among the three hardest vertiport constraints.

The kernel already has `min_gap_on_point` — the DCFC cooldown, 18 minutes in the
throughput model (CLAUDE.md 2.5). But that gap is a property of the **point**,
between successive sessions. V4's gap is a property of the **asset**, between its
own landing and its own charge, and is **conditional on SoC**.

Classified `DECLARATIVE`: the shape mirrors one the kernel already implements, and
an asset-side conditional gap looks like a new field plus a check, not a new
scheduling concept. **That classification is a claim, not a result** — it is
recorded as such so a later round can confirm or overturn it.

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

Mining reports zero findings, and that number is misleading on its own. **Three of
its six constraints name a mechanism the run never reached** (five before §3.1 was
closed), including the one H2 calls *"anathema to a solver-based kernel"*:

| Constraint | Claims | Exercised? |
|---|---|---|
| C1 clearance before bay entry | `movement_as_operation` | ✅ *(since §3.1 closed)* |
| C3 energy resupply window | `threshold_ladder` | ❌ |
| C4 trolley path dependency | `movement_as_operation` | ✅ *exercised, not stressed — see §3.1* |
| C5 multi-threshold maintenance | `threshold_ladder` | ❌ |
| **C6 operator override** | `work_side_refusal` | ❌ |
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
