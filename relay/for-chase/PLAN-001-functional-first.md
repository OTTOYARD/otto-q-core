# PLAN-001 — Functional first: the ladder to "everything all in 1"

FOR: CHASE · FROM: BUILD · 2026-08-27
Supersedes the CP-SAT-first sequencing. Written to your direction: *get it functional FIRST,
a-b then a-b-c then a-b-c-d, no real data until we've earned it, multi-OEM and multi-modal is the
point, not a later rung.*

---

## The decision you asked me to make: four tiers, one brain

There aren't two implementations. There are **four bodies of logic, three of which have already
drifted in substance** — and the drift is not stylistic:

| | copies | state |
|---|---|---|
| Recall ladder | 3 | The Python calls itself "a faithful reduction" of the SQL. It is missing three rungs, renumbers the rest so its rung 4 is a *different* rung, and replaces the per-operator SLA — our multi-tenant differentiator — with a hardcoded 30 minutes |
| Allocator | 4 | Four orderings, no two the same |
| Physics | 2 | Core models charge curves, an 18-min charger cooldown and a site power cap. The demo models **none** of them. The two can never agree on whether a plan is feasible |
| Service record | 2 | Neither is a superset of the other; no mapping exists |

And the structural fact underneath: **the Python kernel is architecturally barred from
production.** `tests/test_separation.py` bans every DB client across `policies`, `solvers`,
`recall`, `conformance`, and the edge functions are Deno/TypeScript — there is no Python runtime
in the deploy path at all. CP-SAT, the recall primitive and the conformance harness *cannot
influence a single production decision today.* The test that enforces purity is the same test
that guarantees disconnection.

Meanwhile the TypeScript side has the **right components wired to nothing**: the protocol adapters
and the trigger layer are correct, tested, and imported only by their own tests. The whole
protocol → fact → trigger → scheduler chain exists **only inside `chain.test.ts`**.

**So: not "pick a language." Put each where it already belongs and delete the duplication.**

| tier | language | role |
|---|---|---|
| **Ingestion** | TypeScript | Protocol adapters + triggers move out of the browser into the server-side ingest tier. Those edge functions are *already* TypeScript — this is a move, not a rewrite. Where a real message becomes a real service need |
| **Decision** | Python | CP-SAT, policies, recall, conformance. Runs as a service. **Proposes** |
| **Disposal** | SQL | The existing decide path. Still the only thing that writes a final assignment |
| **Viewer** | TypeScript | Renders. **No scheduling logic at all** |

Four allocators collapse to one. But I am **porting, not deleting**: the TS side has two ideas the
engine lacks — *abstention on unattested or stale facts*, and regret-based ordering that explicitly
rejects the endurance sort the older allocator still uses. Those move into the brain before
anything is retired.

---

## On "no real data yet, unless open source" — we already researched it and never wired it up

- **ArduPilot SITL** — the *actual autopilot firmware* flying a simulated airframe, emitting real
  MAVLink. **Copter** for your class-A/C drones, **QuadPlane** for the eVTOL, **Rover** for the
  UGVs. One open-source stack, three of your four modalities, real protocol traffic, headless in
  CI. (RES-002 has the setup facts: Copter-4.7.0, `pymavlink` 2.4.49, the exact message names.)
- **`mobilityhouse/ocpp`** (Python, MIT, full 2.0.1) for real charge points. (RES-001.)

`harness/README.md` admits the gap in one line: *"No live `sim_vehicle.py` (ArduPilot SITL) run,
and no live CSMS↔charge-point WebSocket session."* We validate our codecs against the real
**schemas** and have never had a real **stack** in the loop.

That is not fake data. It is real firmware and real protocol with simulated physics — exactly the
"very realistic feeds" bar, and when you later want real telemetry **the adapter does not change.**

---

## THE LADDER

Each rung adds **one** dimension of heterogeneity. Every gate is falsifiable: it says what proves
it passed *and* what would prove it failed. No rung depends on a number we cannot produce honestly.

### Rung 0 — stop the lies. **In flight today.**
Three provenance defects, all verified against production, two fixed in this PR.
**Gate:** the certification can be deliberately broken and observed going red. *(See "what shipped
today" below.)*

### Rung 1 — one asset, one node, every hop real. **DONE 2026-08-27** (est. ~1 week)
ArduPilot SITL copter → real MAVLink → adapter → fact → trigger → service need. **Gate met.**
`OTTO-Defense#26`.

ArduCopter 4.7.0 built from source, armed under its own pre-arm checks, climbed to 30 m and held
until the battery ran out. The 28 committed samples carry percentages **ArduPilot's own battery
monitor computed** — 67% to 0%, crossing the recall threshold on the way. The test compares the
raw wire integer against whether the recall fired: 15 samples that must stay quiet, 13 that must
all fire, and nothing computes both sides.

**The kill gate passed, and it earned its keep.** Killing the aircraft mid-flight took four rounds
to get right, and all four failures were the same defect: **a guard that could not fire.** The
MAVLink library everyone uses hangs forever on a dead link (32 MB of error text in three seconds,
and the call never returns) — an ingest process would freeze on a vanished aircraft with no record
and no alarm. An orphaned simulator on the port meant a test that "killed the aircraft" was killing
the wrong one. My own kill step announced success without checking. My own liveness test counted
corrupt bytes as proof of life. Same shape as the K3 bug in rung 0, three more times.

*Not yet:* booking → completion → signed record. That crosses into the engine and needs the ingest
tier this plan describes. It is rung 1's second half and it is next.

### Rung 2 — a second modality through the same doors. **~1 week**
Add SITL Rover (UGV). Same adapter, same ledger, same engine.
**Gate:** the UGV completes rung 1 unchanged, **and we publish the complete list of kernel changes
it forced.** From the schema I expect at least three — service-point kinds are a fixed Postgres
enum, job types are a fixed 22-value list, all robotaxi. *A non-empty list is not a failure to
hide; it is the answer to "platform or N products," and it gets written down either way.*

### Rung 3 — a second OEM. **~1 week**
Two vehicles, same modality, different capability declarations and different operator terms.
**Gate:** the two are separable by one filter in the record, and the per-operator SLA actually
changes a decision. If both OEMs get identical treatment, multi-tenancy is decorative.

### Rung 4 — the heterogeneous node. **~2 weeks**
Your picture: class-A drones + class-C drones + eVTOL + two OEMs of UGV, one node, sharing power.
**Gate:** a power-constrained moment where the engine must choose between modalities, and the
audit log gives a reason code for who waited.

### Rung 5 — energy for real. **~2 weeks**
Genset fuel + solar + battery on the shared node — grounded in the AMMPS/GREENS work already done.
**Gate:** run the node until the genset runs dry. Service must degrade, not silently continue.

### Rung 6 — rearm as a first-class operation. **~1 week**
**Gate:** a rearm and a charge compete for the same asset's time and the ordering is explained.

### Rung 7 — a second node. **~2 weeks**
**Gate:** the recall decision sends an asset to the *further* node because the nearer one is
saturated, and says so.

### Rung 8 — the evaluator view. **~2 weeks**
Real-time visual + audit log, reading a real run.
**Gate:** a skeptic reads a number off the screen and off the command line for the same run ID and
they match. Pull the network cable: it degrades to the committed offline run and **says so on
screen** rather than blanking.

**Optimization — CP-SAT proposing on real inputs — comes after rung 4, not before.** Per your
instruction. One warning: the claim that "the wiring already exists" is **false**. The disposer
consults outside proposals for redeployment and service sequencing only; the stall assignment —
the actual scheduling problem — goes through a different path whose only outside-proposal door
hardcodes `source='cuopt'` and has no caller. That seam has to be built.

---

## Green lights that are lying to us

This is the direct answer to *"not optimize on fake and made up testing with flawed logic."*

| signal | why it is worthless |
|---|---|
| **CI passing** | All four steps are pure Python over packages another test *structurally forbids* from touching the engine. **The database could be entirely broken and CI would be green.** |
| **KPI certification K3** | `CASE WHEN count(*) = 0 THEN 'PASS(empty)' ELSE 'PASS'` — no FAIL branch existed. Fixed today, and **it went red on the first run: 153 of 155 archived runs carry no reproducibility key.** |
| **"145 archived reproducible runs"** | Now 155, and 153 of them cannot be reproduced — the config hash was never written. The archive function returns a field named `reproducible_from` that omits it |
| **SDR coverage check** | Empty is good, so it passes on an idle system |
| **"CP-SAT wins on the KPIs"** | The scorer imports its physics from the same module CP-SAT solves against, and two of four guarded numbers are terms CP-SAT explicitly minimises. **It is graded on its own homework.** |
| **"Four packs conform, zero kernel modification"** | The conformance harness solves with its *own* simple scheduler, not the production engine. It proves the packs are **expressible**, not that the engine can run them. Rung 2 is the real test |
| **Any policy comparison number** | The A/B table has zero rows and all 145 archived runs are the same policy. Nothing comparative is reproducible today |

---

## Two corrections I owe you

1. **"Browser-only is the ITAR containment boundary"** — I said that, and it is not true.
   `SECURITY.md` §1 states the threat model plainly: OTTO-Defense is *"a sales artifact shown to
   Army innovation cells and investors."* It is a **demo posture we invented**. The phrase appears
   in nine places and is a diligence liability; it should be struck.

2. **cuOpt: I mis-stated the numbers in your favour and against us.** I said "0 NVIDIA calls, 2
   enacted lifetime." The honest sentence, and the only one anyone should use:
   *in the retained window, 255 invocations, 249 abstaining because the gate found no eligible
   vehicle, 0 calls to NVIDIA with a logged status, 0 proposals; in the preserved August 1–3
   evidence, 51 NVIDIA receipts, 21 proposals, 2 enacted decisions.* Never "zero lifetime NVIDIA
   calls" — that is false, and it is the same misquantification in the other direction.

   **cuOpt is dropped from the control loop** on your instruction and the evidence supports it: it
   needs a GPU and an outbound call to NVIDIA, which a defense enclave will not have. We keep the
   deferral mechanism itself, because CP-SAT inherits it.

---

## What shipped today (rung 0)

**`db/checks/0044_kpi_certification.sql` — K3 could not fail.** Its verdict tested `count(*)`, the
total number of archives, so empty gave `PASS(empty)` and any rows gave `PASS`. There was no FAIL
branch, and the `unstamped` column it computes was never consulted. K2 immediately above is written
correctly, which is how it survived review. Empty is now its own verdict, so a certification can no
longer go green on a system where nothing happened.

**`db/migrations/0073_provenance_says_what_it_is.sql` — two provenance fields stop lying.**
Written, pinned and dry-run against production; **not applied** — your merge authorizes that, per
the repo's convention. (Same for 0074 below. Both parse-checked against the live database without
executing; every anchor verified as occurring exactly once.)

- The SDR's `data_source` was `CASE WHEN p_sim_run_id IS NULL THEN 'production' ELSE 'twin' END`.
  But the engine cannot tick without a run, so **every record live operation will ever write is
  stamped `twin`** — including at the depot already switched to a real feed. Measured on
  production: `data_source` production 51 / twin 746, and `sim_run_id` null 51 / set 746. **The two
  distributions are identical** — the field carries no independent information at all, which is
  what makes it dangerous: it looks like evidence. Now reads `depots.feed_mode`.
- The twin computes SoC from a burn model and labels it `'oem_telemetry'` — 216 of 221 vehicles
  carry that label. The CHECK constraint already permits `'estimated'`. The schema had the honest
  word all along; nobody used it.

**`db/migrations/0074_the_archive_carries_its_key.sql` — the archives start carrying their
reproducibility key.** Found by the K3 fix above: the moment the check could fail, it did —
`archives 155, unstamped 153, FAIL`. Two runs were stamped by hand on the day the key shipped and
nothing has been stamped since, including ten runs archived afterwards.

- The helper that stamps the key is **defined once and called from nowhere.** The reproducibility
  key was made opt-in and nothing opted in. Meanwhile the archive function returns a field named
  `reproducible_from` carrying four fields and not the fifth — the config hash, the only one that
  pins the *configuration* rather than the scenario label.
- It could never have worked as a later step, which is the useful part: the helper recovers the
  hash by reading the run row, and runs are purged after archiving — 10 run rows survive against
  155 archives. The hash has to be taken at archive time while the config is still in hand. That
  is where it now goes.
- The helper also **fabricated a hash when it couldn't find one** — `md5('')`, a constant. Called
  on a purged run it would have stamped 153 unrelated runs with the same value and turned K3
  green. Same shape as the bug that led me here: first a check that could not fail, then a key
  that could not disagree. The fallback is gone; a missing config now yields no hash at all.

The 153 existing rows **cannot** be repaired — their configs were purged. Inventing hashes for
them is the exact fabrication this work exists to remove, so K3 stays red until they age out and
every new archive carries its key. **The red is the honest state of the evidence, not a
regression**, and it is the first number in this repo that got worse by being measured correctly.

Neither is backfilled. Those rows were produced under simulated physics and the label is correct
for them; rewriting history to improve a metric is the opposite of what this is for.

---

## What I need from you

Only one thing is genuinely blocked: **nothing.** Rung 1's first half is done and pushed; its
second half (booking → completion → signed record) needs no decision from you either.

One thing worth your attention, not because it blocks anything but because it is the clearest
pattern in the work so far: **six times now, in two repos, a check has turned out to be incapable
of failing** — K3, the SDR coverage check, the run-archive key, and three inside the kill harness
built specifically to catch that class of bug. It is the standing first question on every review
from here: *what would make this go red?* If the answer is "nothing", it is not a check.

Two things worth knowing when you have a view, neither blocking:

- **Where the demo points.** `SECURITY.md`'s own threat table has a row saying *no shared database
  with commercial infrastructure.* Pointing the defense viewer at the commercial project
  contradicts that row. It needs a decision eventually, not now.
- **Off-network for the field.** You said later-stage, and I agree. The ladder does not paint us
  into a corner either way: the engine is server-side, and the viewer keeps its offline bundle.
