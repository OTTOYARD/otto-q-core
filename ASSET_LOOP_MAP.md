# The asset loop, measured — recall → staging assignment → stage completion → dispatch

**Measured 2026-09-13, ~16:00–18:00 UTC (11:00 AM – 1:00 PM CT), against the live
`otto-q-core` engine (`gxdrcyphqjzjsuhxuqtg`) and this repo. Read-only.**

Chase asked for the loop to be closed: an asset calls back, OTTO-Q answers with a queuing
assignment, stages complete, the asset is dispatched — with the proposal layer mediating
what the asset **needs** against what is **allowed** and what is **optimal**.

Six independent lenses mapped it. Every count here was re-measured rather than quoted,
because CLAUDE.md's own figures have moved by orders of magnitude three times.

---

## THE ONE-SENTENCE ANSWER

**The loop is not open — it is closed and talking to itself.** OTTO-Q already composes a
real staging assignment and already exposes a real inbound door for an asset to ask for
one. No asset has ever walked through the door, and no assignment has ever left the
building. The expensive part is built; the wire is not.

---

## 1. WHAT ALREADY EXISTS (do not rebuild any of this)

**The assignment is already composed, and it is good.** `ottoq_vehicle_commands` holds
**794,745** rows over six verbs (`stage` 303,749 · `begin_charge` 294,629 ·
`proceed_to_stall` 188,706 · `enter_wash` 6,904 · `enter_service` 748 · `dispatch` 9).
**100,140** of those payloads already carry `stall_id`, `stall_type`, `eta_at`, `ttl_s`,
`urgency`, `correlation_id`, `appointment:true`, and a `plan` object with an itemised timed
itinerary — `legs[]` with `svc`/`seq`/`starts_at`/`ends_at`/`est_min`/`parallel`/
`requires_bay`, plus `total_min` and `projected_ready_at`.

That is **four of the five things** a returning asset needs to be told: where to go, what
class of point, what it will receive, and when it will be ready.

**The inbound door exists and is deployed.** `POST /functions/v1/ottoq-ingest` with
`stream:"arrival"` (v9, `verify_jwt=true`) takes a vehicle reference, `eta_min` and
`arrival_soc`; calls `public.ottoq_ingest_vehicle_signal` → `ottoq.ottoq_decide_return_on_signal`
→ the recall ladder → `ottoq.ottoq_book_appointment`; and **returns an appointment**:
`{command_type:"proceed_to_stall", stall_id, stall_type, charger_class, projected_ready_at,
plan_total_min, ttl_s, secured}`. It is even designed both-directionally —
`v_intent := p_eta_min IS NOT NULL` marks a vehicle-initiated announcement and forces
`deferrable=false`.

**Settlement is genuinely structural.** `public.ottoq_close_atom_leg` flips a leg to `done`
and an AFTER UPDATE trigger emits a ServiceDetailRecord for every catalog type marked
`emits_sdr`. `ottoq_check_sdr_coverage(NULL)` returns **0 uncovered**, all twelve emitting
leg types at 100%.

---

## 2. WHERE THE LOOP IS BROKEN — five findings, in severity order

### 2.1 The handshake is forged (blocker)
Every one of the 794,745 commands was dispositioned by OTTO-Q or the twin —
`otto_q_preflight` 721,741 · `run_finalizer` 25,704 · `otto_q_preflight_refusal` 21,318 ·
`otto_q_preflight_supersede` 19,431 · `twin_auto_tech` 5,548. **Never once by an external
actor.** The ack function's own default actor `oem_fleet` and the bridge's `robovac_bridge`
appear **zero** times. The uplink ack is written by OTTO-Q **in the same transaction as the
downlink**. That is not fire-and-forget; it is a forged handshake, and it means no number
anywhere in this system distinguishes "the asset was told" from "we decided".

### 2.2 The pull API cannot see the engine's own work (blocker)
`ottoq_fleet_pending_commands` filters `sim_run_id IS NULL`, and only **5 of 794,745**
commands have ever had a NULL `sim_run_id`. The production endpoint an arriving asset would
poll is **structurally blind to 99.9994% of what the engine issues**.

### 2.3 Nobody has ever used the front door (blocker)
**100%** of the **140,146** recall decisions are OTTO-Q deciding *for* the asset, all
`data_source='twin'`. The twin bypasses the ingest path entirely —
`twin.ottoq_sim_advance_deployed_telemetry` calls `ottoq_evaluate_return_need` and
`ottoq_book_appointment` directly. Zero of 127,797 dispatches carry the `signal_source` key
the inbound path stamps. Zero `vehicle.command_ack` events exist. The one OEM API key
("Waymo Production") has `last_used_at IS NULL`. `recall_issued` and `recall_refused` are
declared in the canonical event catalog, asserted in code, and **have never been emitted**.
`early_recall_log` — cited in CLAUDE.md 2.7 as proof the Recall Decision already exists — is
**empty**.

### 2.4 There is no queue (major, and it is the thing Chase named)
There is **no queue object anywhere**: no wait-list table, no position column, no ordered
view, no `row_number()` over the waiting population. Position is the transient row order of
two cursors inside `ottoq_decide_tick`, recomputed from scratch every tick and never
promised. **Zero of 794,745 command payloads and zero of 104,803 comms messages contain a
queue position, rank, or ordinal.** The staging pool is real (232 staging stalls: 113
Nashville / 115 Benchmark / 4 grid). Two locks exist that cannot see each other:
`ottoq_book_stall` never consults `stalls.reserved_by`, and `ottoq_reserve_stall` never
consults `ottoq_stall_bookings`.

And `SLA.002.max_queue_depth` — the only queue-depth rule in the engine — is declared and
wired, has **never been invoked**, and **its body would raise 22P02 if it ever were**.

### 2.5 Dispatch is not gated by the readiness verdict (blocker)
`ottoq_brain_deploy_rank` is consumed in an `ORDER BY` and **never in a `WHERE`** — so a
vehicle with no enacted readiness decision, or one the L1 shield actively held, can still be
dispatched. Two divergent deploy floors exist: the shield reads the versioned per-operator
SLA floor; the twin planner that actually dispatches **hardcodes `current_soc >= 80`**.
Dispatch is performed by a 2-minute cron, not by the work side and not by the decide path.

`dispatch_due_at` — required-ready-time — exists on **60,901 of 122,208** needs and is read
only as a *not-before hold* and an after-the-fact KPI. **Nothing schedules backwards from
it.** For a kernel whose fourth question is "when must I be ready", that is the gap.

---

## 3. THE PROPOSAL LAYER: three seats, and they are not where the decisions are

Catalog-wide, exactly **three** functions call `ottoq_l2_external_proposal`:
`ottoq_decide_tick:130` (`redeployment`), `ottoq_decide_tick:965` (`service_sequencing`),
and `ottoq_honour_reservation_proposal:49` (`stall_assignment`). No edge function and no
Python bridge calls the selector — **the seat list is closed.**

| loop stage | proposer seat? | proposals ever |
|---|---|---|
| inbound recall | **none at all** | — |
| staging assignment | yes (`stall_assignment`) | 12,805 |
| stage completion | **none at all** | — |
| dispatch | seat exists (`redeployment`) | **0 — lifetime** |

Even within staging, only one of four admission paths owns the seat: **§(3b) gate intake
enacts a physical staging assignment with no proposer and no shield probe** (3,930 enacted
decisions in 7 days), §(4) has only a local proposer, and **§(4b) — the router for the
site's scarcest spaces — hardcodes its "proposal" as a `jsonb_build_object` at line 846.**

The L1 shield gates **4 of the 30 probe points the rules declare**, and the 26 unprobed ones
include every point corresponding to a stage with no proposer.

---

## 4. THE INTELLIGENCE VERDICT — one honest sentence each

> **Nemotron** is the only intelligence source that has ever changed what this engine did:
> **262 decision rows**, every one enacted, writing run policy dials
> (`deploy_peak_fraction`, `energy_demand_factor_peak`) via `ottoq_policy_set(p_by:'ottoq_prime')`
> — **a path the L1 safety shield does not gate**, because a policy-dial write is not a
> stall assignment the shield inspects, and it keeps no per-call ledger of its own.

> **cuOpt** has 20,424 ledger rows of which only **16 ever carried an HTTP status from
> NVIDIA**; those 16 produced 136 proposals and **27 enactments**; the last real call to
> `optimize.api.nvidia.com` was **2026-08-30 04:36:02 UTC — 14 days and 2,107,009 decisions
> ago** — and everything since is 10,329 `policy_disabled` abstentions, because
> `0152_cert_quiesce` disables it on every cert run and 1,057 of 1,090 retained runs are
> `cert_harness`.

> **CP-SAT** is the best-built and least consequential: 20 checks pass byte-identically on
> OR-Tools **9.15.6755** with all four of CLAUDE.md 2.5's determinism pins asserted, it fired
> four times against the live engine on 2026-09-13 and submitted **90 proposals through the
> real door — and zero were enacted, or even quoted by a decision row.**

> **CORRECTION 2026-09-14 (`db/checks/0211`) — the last clause is no longer true.** On run
> `33f87a41-3f0e-41c6-8da8-608376d56d6a` (busy_day / 424242 / Nashville flagship) the proposer
> loop fired twelve times and the deterministic kernel **ENACTED three CP-SAT proposals**, at
> ticks 2, 8 and 18, each with `enacted_action` equal to `proposed_action` and a full L1
> `rule_results` array attached. Of 83 proposals in that run, **29 (35%) were CP-SAT's own
> abstentions**, 23 met a `noop_no_candidate` from the disposer after CP-SAT had named a
> specific stall (the open lead, G49), 17 lost to the local path on a different stall — which
> is the right-of-first-refusal working — and 3 were taken. "Least consequential" still holds
> on volume; "never enacted" does not.

> **The Anthropic advisory proposer has never been asked anything by the live engine**:
> zero proposals, zero fires, zero cost incurred. The key went live 2026-09-13 evening; the
> path is written and guarded and has still never run.

**All three NVIDIA-backed paths (cuOpt, orchestrator-agent Nemotron, nemotron-copilot) are
simultaneously dark, and the shutdown was deliberate rather than a fault.**

---

## 5. BUILD ORDER

Split by blast radius. Anything touching `ottoq_decide_tick` is the tick path — a total
function that must never abort a tick — and forces a recertification round.

**Ring 1 — safe, outside the certified path, unblocks the most:**
1. **Make the pull API able to see the engine's work.** `sim_run_id IS NULL` is the single
   filter standing between a real fleet and 794,745 composed assignments.
2. **Stop forging the ack.** Split downlink from uplink so "delivered" and "accepted" are
   distinct, externally-written facts. This is G8's lease/ack/retry/TTL — `ttl_s` is already
   written into every appointment payload and read by nothing.
3. **Give the queue a durable object** with a position that can be promised, and make the
   reservation book and the booking calendar read each other.
4. **Fix `SLA.002.max_queue_depth`** — it would throw 22P02 today. A rule that cannot run is
   worse than no rule, because it reads as coverage.

**Ring 2 — gated, forces recert:**
5. Gate dispatch on the readiness verdict (`deploy_rank` into the `WHERE`), and collapse the
   two divergent deploy floors onto the versioned SLA one.
6. Schedule backwards from `dispatch_due_at` instead of only holding against it.
7. Put a proposer seat on inbound recall and on stage completion; feed the starved
   `redeployment` seat.

**Ring 3 — intelligence, mostly unblocked by the DB secret:**
8. Exercise the Anthropic advisory path once and measure it.
9. Decide cuOpt's fate against the ledger: 14 days dark and deliberately quiesced.
10. Find out why 90 CP-SAT proposals were not even *quoted* — that is a consumption defect,
    not a solver defect.
11. Give Nemotron a per-call ledger, and decide whether a policy-dial write should be
    shield-gated. Today it is the one path where an AI changes the engine unchecked.

---

*Source: workflow `wf_cf7fecc9-792`, six lenses (inbound, outbound, staging,
completion_dispatch, proposal_layer, intelligence_inventory), stopped before the seventh
(depot/energy/vehicle SOPs) at Chase's instruction to cut agent usage. Gap verification was
in flight and did not complete, so the gaps above are **measured but not yet adversarially
refuted** — treat each as a strong lead, and confirm the capability truly does not exist
before building it.*
