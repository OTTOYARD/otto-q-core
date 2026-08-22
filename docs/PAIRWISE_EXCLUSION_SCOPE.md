# Scope: pairwise point exclusion (C11 finding V5)

**Design note, not an implementation.** `CONFORMANCE_FINDINGS.md` §4 item 4 says to
scope this before committing, *"since it touches the resource model that the
determinism work in Run 3 has just been stabilised around."* This is that scoping.
Nothing here is applied.

---

## 1. The requirement

FAA EB 105A: minimum 1.5× aircraft-diameter separation between **active** vertipads.
Formally: **for certain point pairs (A, B), A and B may not be occupied
simultaneously.**

The kernel today has exactly two resource shapes:

| Shape | Mechanism | Scope |
|---|---|---|
| one asset per point | `exclusive_occupancy` — `ottoq_stall_bookings` EXCLUDE constraint | **one** point |
| a shared ceiling | `site_power_cap` — `ottoq_claim_tick_kw` | **all** points |

Pairwise exclusion is neither. It is a constraint over an *arbitrary subset* of
points, and there is no mechanism for it.

**It is not vertiport-only.** The same shape covers adjacent bays sharing a door
swing, two lifts that cannot both extend, a crane envelope over two stalls, a wash
bay whose runoff blocks the neighbouring pad. Any depot with real geometry will
eventually need it.

## 2. Why this is genuinely a solver change

The site power cap looks superficially similar — a constraint over many points — and
it is worth being precise about why it does not generalise.

`site_power_cap` is a **sum against a scalar**: every claimant contributes, the
scheduler tests one number, and admitting a claim is a local decision. Pairwise
exclusion is a **graph property**: whether B may start depends on which *specific*
other points are active, so the feasible set depends on the assignment so far. That
is the difference between a capacity check and a colouring problem, and it is why no
declarative field closes it — a pack can *declare* the pairs, but the decide path has
no notion of "consult the pairs before admitting."

## 3. Three options, with the trade-off stated

### Option A — an exclusion-group resource (recommended for a first cut)

Model each conflicting set as a named resource of capacity 1 that every member point
consumes while occupied. `pad_pair_1_2` has capacity 1; both pads consume it.

- **Reuses machinery that already exists** — this is exactly the `path_resources`
  shape C11 added to the conformance harness, and structurally the same as the
  cumulative-resource pattern in 2.5.
- **Cheapest to make deterministic**, which matters: the resource is named, so the
  decide path's cursor over it gets a total order for free, the way 0067's tiebreak
  did for stalls. *After this week, "can it be made deterministic" is a first-class
  selection criterion, not an afterthought.*
- **Limitation, stated:** it expresses *mutual* exclusion cleanly and asymmetric or
  distance-graded rules badly. "A blocks B but B does not block A" needs Option B.

### Option B — an explicit conflict graph

A `point_conflicts(point_a, point_b, reason)` table consulted at admission.

- Expresses asymmetry and any topology.
- **Cost:** a new lookup on the hot admission path, and a new ordering seam — every
  cursor over conflicts is a fresh opportunity for the exact non-determinism class
  that took Run 3 twenty-one certification rounds to close.

### Option C — geometry, computed

Derive conflicts from coordinates and a separation rule.

**Originally rejected here on kernel-purity grounds — that rejection was too
quick, and §6 corrects it.** The objection was that this puts *geometry* in the
kernel, and "1.5× rotor diameter" is aviation. The second half stands; the first
does not, because **the kernel already stores the geometry** (§6).

The correct split is finer than "geometry is sector logic":

| Layer | Holds | Verdict |
|---|---|---|
| kernel | stall coordinates — `stalls.relative_x/relative_y`, `ottoq_site_structures` footprints | **already there, and sector-neutral** — a position is not an aviation concept |
| **pack** | the separation *rule* — "1.5× rotor diameter", or a mine's trolley clearance, or a door-swing radius | **this is the sector-specific part** |

So C becomes viable *if the rule lives in the pack and only the coordinates live in
the kernel* — which is exactly the kernel/pack split CLAUDE.md 2.2 prescribes, and
it produces the conflict SET that Option A then consumes as its resource groups.

**Recommendation: A as the enforcement mechanism, with the conflict set derived
pack-side (C) rather than hand-declared.** B only if an asymmetric case appears. A
and C are complements, not alternatives — C decides *which* points conflict, A
enforces it.

## 4. What must be true before any of this is written

1. **A pinned-clock baseline exists** (0065) — so the change can be differenced
   rather than argued. It does.
2. **The certification is green before touching it** — re-cert #20 is 20/20. Any
   pairwise work starts from that state and re-certifies after.
3. **Written prediction first.** After 0068, the rule is that a behaviour change
   states its expected effect *before* the run, and is rewritten rather than
   defended if the numbers disagree.
4. **One variable.** 0067 bundled two changes and cost a round to untangle.

## 5. What this is worth

Vertiport is a **paper** pack (CLAUDE.md 2.2) — no revenue depends on it today. The
honest framing is that this is **the price of entry to a sector we have not yet
entered**, discovered before committing engineering to it rather than after.

Against that: the same mechanism is what any geometrically-real depot needs. The
question this section originally left open — *does a real site have a conflicting
pair today?* — is now answered in §6. It does not. **Waiting is therefore the
recommendation, on evidence rather than on instinct.**

---

## 6. The urgency question, answered empirically (2026-08-22)

§5 said the deciding question was whether a real site has a conflicting pair today.
Measured across every depot in `otto-q-core`:

| | |
|---|---|
| stalls with coordinates | **319 of 319** — geometry is complete, not aspirational |
| depots covered | 3 |
| closest stall pair | **8.95 units** |
| median pair distance | 189.23 units |
| pairs closer than 1 unit | **0** |
| coincident pairs | **0** |

**No existing site has a stall pair close enough to plausibly interfere.** The
closest two stalls anywhere are ~9 units apart against a median of ~189. V5 is
therefore **not urgent**, and this is now a measurement rather than an assumption.

Two consequences worth carrying forward:

1. **The scoping recommendation stands, with evidence.** Do not build pairwise
   exclusion yet. Revisit when a site is modelled whose points actually interfere —
   and the check above is cheap to re-run as a gate on that.
2. **The kernel already has the input Option C needs.** `stalls.relative_x/relative_y`
   is populated for every stall, and `ottoq_site_structures` carries 54 footprints
   with `width_ft`, `length_ft`, `rotation_deg` and lat/lng. Deriving a conflict set
   is a query, not a data-collection project. That is what moved C from "rejected"
   to "recommended as the derivation half" in §3.

**Method note:** the first version of §3 rejected Option C by reasoning about what
the kernel *ought* to contain, without checking what it *does* contain. That is the
same error this phase has now made twice — §1b and §2 of `CONFORMANCE_FINDINGS.md`
were both corrections of exactly that shape. Checking first is cheaper every time.
