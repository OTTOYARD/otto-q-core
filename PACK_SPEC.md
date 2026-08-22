# PACK_SPEC.md — what a sector pack is, formally (Run 4 · Phase C11)

A **pack** is declarative data. CLAUDE.md 2.2: *"could a mining pack and a vertiport
pack both use it unchanged? Yes → kernel. No → pack."* C11 makes that testable:

> **A pack is valid iff its declarative files load and solve on the kernel with
> ZERO kernel modification.**

This file defines "load". The harness (`conformance/`) defines "solve".

---

## 1. The falsification rule

Every pack declares its constraints. The harness maps each declared constraint to a
**kernel mechanism**. A constraint with no mechanism is a **finding**, and each
finding is classified exactly one of:

| Class | Meaning |
|---|---|
| `DECLARATIVE` | a new pack-level field or table would express it — the kernel already has the machinery |
| `SOLVER_CHANGE` | the kernel's decide path itself must change — this is the platform-thesis threat |
| `OUT_OF_SCOPE` | it is a work-side concern; CLAUDE.md 2.2 forbids OTTO-Q owning it |

**The mechanism registry is closed and is defined from what the engine actually has**
(`conformance/spec.py: KERNEL_MECHANISMS`). A pack author cannot add one — that is
what makes the instrument a falsification test rather than a rubber stamp. If a pack
needs a mechanism that is not in the registry, the honest outcomes are to extend the
kernel (and say so) or to conclude the thesis is wrong for that sector.

---

## 2. Required structure

```json
{
  "pack_id":        "robotaxi",
  "status":         "reference | build | paper",
  "source":         "provenance — a live table, or a merged research file",
  "asset_classes":  [ { "code", "display_name", "energy_kind" } ],
  "operations":     [ { "operation_code", "display_name", "category",
                        "parallel_with_charge", "is_movement",
                        "energy_bearing", "emits_sdr" } ],
  "service_points": [ { "point_type", "capabilities": [[asset_class, operation]],
                        "exclusive": bool, "min_gap_min": number|null } ],
  "constraints":    [ { "code", "description", "mechanism" } ]
}
```

### Field rules

- **`pack_id`** unique; matches `ottoq_operation_catalog.pack_id` where the pack is live.
- **`status`** — `reference` (robotaxi, the worked example), `build` (yard-logistics),
  `paper` (mining, vertiport — conformance only, stub adapters accepted per C10.4).
- **`source`** is mandatory and must name where the data came from. A pack whose
  source is "invented" is not a pack; it is a guess with a schema.
- **`operations[].emits_sdr`** — CLAUDE.md 2.6 requires every completed operation to
  terminate in an SDR. Movement operations are the only permitted exception, and the
  validator enforces exactly that: `emits_sdr == false` ⟹ `is_movement == true`.
- **`service_points[].capabilities`** is the `(asset_class, operation)` pair model
  from 2.3. An operation may only be scheduled onto a point that declares the pair.
- **`constraints[].mechanism`** must be a member of the registry **or** the literal
  `null`, which is a pack author's declaration of *"I do not believe the kernel can
  express this."* `null` is not a failure to fill in a field — it is the finding, and
  the harness reports it as such.

---

## 3. The three invariants the harness verifies

Verbatim from CLAUDE.md C11.1:

1. **No power-cap violation.** Concurrent energy-bearing operations must not exceed
   the site power cap at any instant.
2. **No point overlap.** No service point runs two operations at once unless the
   point declares `exclusive: false` and both operations declare
   `parallel_with_charge` compatibility.
3. **No operation on an incapable point.** Every scheduled `(asset_class, operation)`
   must appear in that point's declared capabilities.

These are checked on a constructed scenario, not asserted.

---

## 4. What a pack may NOT contain

- **No work-side concepts.** No ride dispatch, pick assignment, haul-cycle
  optimisation, or mission planning (CLAUDE.md 2.6, "No work-side features"). The
  Recall Decision is the only touchpoint. A pack declaring a work-side constraint is
  reported `OUT_OF_SCOPE` rather than accommodated.
- **No executable code.** Packs are data. Sector-specific *code* lives only in
  adapters (2.2), where C10's two laws bind it.
- **No kernel patches.** A pack that requires one has falsified the thesis for its
  sector, and `CONFORMANCE_FINDINGS.md` must say so plainly.
