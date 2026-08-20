# TWIN_CORE.md — OTTO-Twin Core Hardening

**Run 3, Phase C7 deliverable.** 2026-08-19.
Artifacts: `db/migrations/0045_twin_determinism_and_playback.sql` (NOT yet applied — post-merge),
`scenarios/` (the nine canonical failure files), `metrics/demo_run_6727b04e.json` (the
end-to-end demonstration), and the nine freshly captured twin functions in `db/fn_current/`.

The twin was formalized, not rebuilt: everything below wraps or extends machinery that already
existed — the cert harness (`ottoq_cert_arm_start/step/finish`, the isolated benchmark depot
`22222222…`, `ottoq_score_run`, `ottoq_certify_run`), the content-hashed decision snapshots, the
132-type event catalog, and the itinerary-leg substrate.

---

## 1. Determinism certification (C7.1) — run, verdict, root cause, fix

**Method.** Two arms on the benchmark depot through the *existing* cert harness, identical in
every input: seed **424242**, policy `otto_q`, ab_group `c7de7e00-…424242`, 0 faults, identical
step cadence (1+7+6+6), shielded from the metronome/governor via `run_by='cert_harness'` (the
harness's own exemption). Canonical comparison: per-tick structural digest over the content-hashed
decision snapshots (vehicle id/state/SoC/stall + stall occupancy + session kW), aligned by
**sim-minute offset** so wall-clock anchoring cannot fake a diff.

**Verdict: FAIL — the twin is not deterministic under fixed seed today.**

| | Arm A `6727b04e` | Arm B `a1e3bdb3` |
|---|---|---|
| dispatches / commands issued / refused | 120 / 447 / 159 | 107 / 563 / 350 |
| throughput/hr (ottoq_ab_runs) | 8.1 | 7.1 |
| peak kW | 662.1 | 587.5 |
| aligned ticks identical | **0 of 20** | |
| first divergence | tick 2 (sim-min 60): 68/100 vehicle SoCs differ, 1 state, 0 stalls | |

Both runs are archived and stamped (`ottoq_run_archives` + the 0044 reproducibility key); their
`ottoq_ab_runs` scores are the first rows of the new era. **A same-seed pair currently shows a
~14% throughput spread — until 0045 is applied and re-certified, no CRN comparison is fully
paired, and every A/B claim must carry that caveat.**

**Root cause (exact).** Eleven RNG-salt sites in nine twin functions salt
`ottoq_sim_seeded_random`/`hashtextextended` with the **absolute sim clock**
(`… || p_sim_clock_now::text`), and every run anchors its sim clock to real `now()` at start
(`ottoq_cert_arm_start`, `twin.ottoq_sim_start_run`) — so two same-seed runs draw disjoint
streams by construction. The seeded-random discipline was right; the **salt domain** was wrong.
Offenders (all captured verbatim in `db/fn_current/`): `advance_deployed_telemetry` (the dominant
SoC-drain divergence), `advance_grid`, `advance_site_energy`, `advance_weather_and_solar`,
`bay_fault_handler`, `bess_step`, `dispatch_vehicle`, `emit_arrival_webhook` (×2),
`vehicle_exception_handler`.

**The fix (0045 §1–§2).** `twin.ottoq_sim_clock_salt(run, clock)` = whole seconds since the
run's own `sim_clock_start` — identical across same-seed runs by construction, falling back to
the old absolute text only when the run row is unknown. All 11 sites patched; every patched body
is byte-identical to its capture except the salt expression.

**The standing property test (0045 §3).** `ottoq_twin_run_digest(run)` +
`ottoq_twin_determinism_verdict(run_a, run_b)`. Re-certification procedure (run after 0045 is
applied): two arms exactly as above → `SELECT * FROM ottoq_twin_determinism_verdict(a, b)` →
expect `deterministic = true`; if false, `first_divergence_sim_min` points at the next offender.
One caveat stated up front: `ottoq_sample_calibrated` and the variability-card dealers are
downstream of the same seeds and are *expected* to become deterministic with the salt fix, but
only the re-cert can prove it — this test exists precisely so that claim is never hand-waved.

**Re-certification #2 (post-0047, 2026-08-19; arms `7821c9a8` / `a59a1f08` / `44252690`).**
Three findings, each caught by the cert doing its job:
1. **Harness leak (procedural):** `ottoq_cert_arm_start` labels runs `run_by='benchmark'`, but the
   metronome's exemption list is `('production_live','cert_harness')` — so cron ticks leak into
   cert arms at wall-clock-random points, misaligning the pair (arms C/D: 23 vs 24 ticks for
   identical 20-step procedures). **Every paired cert must set `run_by='cert_harness'` right
   after arm_start** (re-added to the procedure below); this also retroactively explains part of
   re-cert #1's residual divergence (arm A carried one stray tick).
2. **Twin bug (0048 §1):** with the exemption fixed, arm E died mid-tick on
   `idx_stalls_one_vehicle_per_stall`: both bay-admit blocks in
   `twin.ottoq_sim_advance_service_flow` flip the vehicle to its in-bay state BEFORE vacating its
   old stall; `trg_reassignment_guard` protects in-bay states, silently vetoes the release, and
   the following place-statement kills the whole tick. This is the mechanism behind the open
   B1 double-stall finding. Fix: handoff first, state write second (0048, post-merge).
3. **More absolute-clock salts (0048 §2):** the wash/detail/maintenance duration-card scopes
   (`ottoq_twin_deal`) key on `p_sim_clock_now::text` — the 0045/0047 defect class. Fixed the
   same way.
Re-certification #3 runs after 0048 is applied: arms with `run_by='cert_harness'` +
`next_tick_due_at` shield, expecting `deterministic = true`.

**Re-certification #15 (post-0060, 2026-08-20; arms `c5dbc377` / `943936c5`, started
18:02:31 and 18:05:32 — deliberately held off the 18:00Z mark, where the midnight-UTC
crossing would have landed exactly on a tick boundary and split the pair's day-keyed
draws).** 0060 verified applied (five post-md5s changed, no leftovers) and **proven
working**: the two arms' command streams are byte-paired in run-relative time for the
ENTIRE run, and the vehicle-state stream is paired for **312 of 313** transitions.
Verdict: **19/20 — the best round by a wide margin** (was 13/20), and the sole divergence
is the LAST tick, sim-min 600.

The residue is a single extra transition in arm B: vehicle `964bd583`,
`charge_complete_holding -> staged_for_departure`, correctly ordered ahead of
`acba173d`'s identical transition, which both arms make. A **membership** difference in a
cap-limited release, not an ordering one — both arms hold the vehicle in the same state at
the same stream position, and only B admits it.

ROOT CAUSE — **0057's guard has a blind spot, and this is the case that exposes it.** 0057
stopped the trigger clobbering callers that pass a stamp DIFFERENT from the stored one.
But inside a BEFORE UPDATE trigger, a caller passing the SAME value is indistinguishable
from one passing nothing — and that is exactly what happens when a vehicle changes state
**twice in one tick**: the second write carries the same sim clock the first one stored,
the guard reads "unset", and `NOW()` lands in `last_state_change`. The divergent write's
own event payload is the proof:

```
last_state_change: from 2026-08-21T04:05:32.269186+00   (the run's sim clock, tick 20)
                     to 2026-08-20T18:06:36.269616+00   (wall clock)
```

Two decide-path fairness cursors and `twin.ottoq_sim_advance_service_flow`'s release
cursor `ORDER BY` that column, so wall-clock ordering re-entered through the one door 0057
left open, and the cap-limited release admitted a different member set per arm. Fix:
**0061** (post-merge) — the guard's DEFAULT stamp becomes sim-domain whenever the
vehicle's depot has a running sim run, so the equal-value case re-stamps the identical sim
clock (a no-op) instead of a wall clock; production, having no running sim run, still
falls back to `NOW()` exactly as before. A sweep of all four trigger functions that write
`NEW.<col> := now()` found this is the only one writing a column anything orders by (the
rest write `updated_at`). Re-certification #16 runs after 0061 is applied, expecting
`deterministic = true`.

**Re-certification #14 (post-0059, 2026-08-20; arms `1a505390` / `eea3a256`, both armed
cleanly at first attempt — tethers cleared, tick_count=0 verified, starts 17:41:19 and
17:43:38 inside the same 17:30–18:00Z band so both 600-sim-min spans cross every hour
boundary and midnight UTC at the same tick index).** 0059 verified applied (post-md5
`ea24d2ab…`) and **proven working**: at the divergent tick BOTH arms walk the refusal
reactor in the new ascending-vehicle order (A: …ba70312c, c5a58859; B: …5dfd9db9,
ba70312c — each ascending). What differs is not the order but the CONTENT of the queue:
arm B carries one refused command arm A does not. Verdict: 13/20, first frame divergence
sim-min 420.

NEW INSTRUMENT — **command-stream alignment in run-relative time**. Aligning both arms'
`ottoq_vehicle_commands` streams on `rel_min = issued_at - sim_clock_start` (ordered by
content, not by id) puts the first real divergence at **sim-min 300 — four ticks before
the frame digest sees it**, because a refused command changes no vehicle state until the
reactor acts on it. At sim-min 300 arm A seated vehicle `ba70312c` in stall `45014fff`
while arm B seated `5dfd9db9` in that same stall. This instrument now precedes the frame
and decision diffs in the FAIL playbook: the frame digest reports where divergence
becomes *visible*, the command stream reports where it *happened*.

ROOT CAUSE — `twin.ottoq_sim_confirm_commands`, the confirm walk, carrying **both** known
nondeterminism classes at once: (a) the **0059 class** — its main cursor orders by
`c.issued_at` alone, the per-tick batch stamp, so within a tick it is heap order, and this
loop does not merely observe but OCCUPIES the stall it validates, making it the sharpest
capacity gate in the engine (whoever is confirmed first takes the stall; every later
command for it is refused `stall_unavailable`); and (b) the **0058 class** — its
preflight-supersede window breaks `issued_at` ties on `c.command_id`, which is
`gen_random_uuid()`, so a per-run-random value chose which command counted as current
intent and which were retired as `superseded`.

**A systematic sweep replaced the one-site-at-a-time habit** that had cost three rounds:
every `ORDER BY` in `public`/`twin`/`ottoq` was extracted and filtered for a sole key that
is a per-tick timestamp or a random-UUID tiebreak, then each hit classified by tick-path
membership (caller graph) and by whether it decides a scarce resource or a selection.
Twelve candidates: **five fixed** in 0060 (the three confirm-walk sites plus
`twin.ottoq_demand_rebook_after_eviction` and `ottoq.ottoq_rider_flag_indepot_sweep`,
which pick a visit by `created_at` — `now()`, one value per tick — and
`public.ottoq_active_charge_cap_kw` / `public.ottoq_l2_propose_bess`, which pick the
active site power cap and BESS setpoint by `issued_at` alone); **seven reviewed and
deliberately unchanged** and recorded in the 0060 header, including
`ottoq_enact_cuopt_batch`, which is quiesced by 0056 in every cert run and has no
in-database caller. Re-certification #15 runs after 0060 is applied, expecting
`deterministic = true`.

**Re-certification #13 (post-0058, 2026-08-20; arms `bb74e241` / `0b490fb0`; a first attempt
was aborted when the session's permission classifier blocked arm B's shield relabel past the
16:00Z boundary window — orphan arm `f7502d7e` discarded with its ab_group `…424255`; one
arm-B start was also discarded at tick_count=1 after a network timeout delayed the shield
past the minute top — the airtight check caught it).** 0058 verified applied (post-md5s
`06f17bf1…`/`149ad615…`, both byte-exact against locally built post-images) and **proven
working**: the eta_delay card sets are behaviorally identical per vehicle across the arms
(apparent diffs were multi-dispatch join artifacts; the one real single-card diff was
`will_delay=false` in both arms — inert) and zero charger-fault cards dealt a fault in
either arm. Verdict: 12/20, first divergence sim-min 390 (tick 13), all SoCs paired, four
gate-cluster vehicles holding different stalls/admission states. NEW INSTRUMENT — the
**full event-stream positional diff** (row_number over event_seq per run, sig =
event_type|entity) pins the first divergent event exactly: at stream position 1148 run B
emits two `stall.state_changed` reservations (stalls `67daf51e`, `891e775f`, reserved for
vehicle `0bfd4d59`) immediately BEFORE the refusal-reactor batch, run A immediately AFTER
it — same events, same run-relative reservation windows, opposite order. The reactor,
`ottoq.ottoq_react_to_refusals`, walks refused commands with a capacity-consuming
reserve-first walk, so its processing order decides WHO gets the free stalls and WHO
escalates `no_capacity` — and its cursor orders by `issued_at` ALONE, which is the
per-tick sim-clock batch stamp (measured: up to 72 commands share one value). Within a
tick that ORDER BY is heap order — **the 0050/0054 unordered-cursor class with an
insufficient key instead of a missing one; the 0054 sweep passed it because an ORDER BY
was present.** Schema-wide re-sweep of `ottoq` found no other offender
(`ottoq_stall_free_between` orders by distance+stall_code; `release_expired_bookings`'
unordered loop is commutative). Fix: **0059** (post-merge) — one line, run-stable
tiebreak `(issued_at, vehicle_id, command_type, payload->>'stall_id')`. Re-certification
#14 runs after 0059 is applied, expecting `deterministic = true`.

**Re-certification #12 (post-0057, 2026-08-20; arms `54ff816e` / `7015af46`, arm A restarted
once for metronome contamination — armed at second :56 of the minute; the ~3s top-of-minute
hazard window again).** 0057 verified applied (post md5 `b171ab31…`, changed=true). Verdict:
**14/20 ticks identical — the best round yet** (was 3/20), first divergence pushed from
sim-min 120 to **450** (tick 15). The stamp fix **holds**: `task_start` processing order is
byte-paired through tick 14, and the tick-15 decisions stream is byte-paired through position
16. The residue is exactly **two vehicles**: run B carries three extra decisions for vehicle
`464c07e3` (a stall_assignment noop, a `promote_ready`, an `amend_plan`) and lacks A's
`amend_plan` for `5b8524d6`. The variability-card ledger closes the case itself: 464c07e3's
`eta_delay` card reads `will_delay=false` in arm A and `will_delay=true / 'accident' / 60 min
/ applied=true` in arm B — same seed, same vehicle, same trip, **different card**, because
`ottoq_twin_deal_eta_card` salts its three CRN draws with `p_dispatch_id`, and
`ottoq_vehicle_dispatches.dispatch_id` is `gen_random_uuid()` — **the 0052 per-run-random-UUID
salt class, hiding inside the card dealers.** The applied 60-minute delay held B's arrival;
the shifted stall capacity then flipped vehicle `6e5c4806`'s deferrable-return booking
(deployed in A, en_route in B) purely downstream. `ottoq_twin_deal_fault_card` has the
identical defect (session scope; `ocpp_sessions.id` is `uuid_generate_v4()`); a function-wide
sweep over `crn_draw`/`sample_calibrated`/`seeded_random` callers found **no third offender**.
The playbook's 0057-guard check also ran clean: twin state writes pass distinct sim-clock
stamps (paired +30-min deltas in the event payloads, anchored to each run's own start). Fix:
**0058** (post-merge) — 0055's role split applied to both dealers: the UUID stays the ledger
key (scope_instance, bucket_key, dedupe untouched); the draw scope moves to vehicle [+ stall]
+ whole sim-minutes of the dispatch/session start since the run's own `sim_clock_start`
(sim-clock domain both sides, so the delta is an exact tick multiple in every arm); no-run and
no-row callers keep the old UUID scope verbatim. Re-certification #13 runs after 0058 is
applied, expecting `deterministic = true`.

**Re-certification #11 (post-0056, 2026-08-20; arms `112fea03` / `5a209c14`, arm B restarted
once for metronome contamination).** 0056 verified applied and **proven working**: the
quiesce policy rows exist for both arms, the fire path logged **40 `policy_disabled` gate
refusals** (ledger-honest, countable), there were **zero real cuOpt HTTP calls**, and the
deferral holds were inert. Verdict: 3/20, first divergence sim-min 120 — one tick further
again, states and SoCs fully paired at the divergence tick. The residue: the decide path's
~104 `task_start` decisions per tick have a **fully scrambled processing order** across the
pair. Those cursors order by `(last_state_change, id)` — and the offender is the vehicles
trigger `public.log_vehicle_state_change` (`trg_vehicle_state_change`), which
**unconditionally overwrites `NEW.last_state_change` with `NOW()`** on every state change,
clobbering the sim-clock stamp that every twin write site deliberately passes (40+ sites
swept: `p_sim_clock` / `v_clock` / `p_sim_clock_now`). `last_state_change` was therefore a
REAL-clock column inside twin runs, and vehicle fairness order tracked wall-clock execution
physics instead of the seed — **the `last_state_change` real-clock ordering finding parked
since re-cert #4, now measured directly.** Fix: **0057** (post-merge) — one guard in the
trigger: default to `NOW()` only when the UPDATE did not itself set the column (production
callers byte-for-byte unchanged); preserve a caller-provided stamp. Re-certification #12
runs after 0057 is applied, expecting `deterministic = true`.

**Re-certification #10 (post-0055, 2026-08-20; arms `36adbeae` / `515526fe`, arms A and B
each restarted once for metronome contamination — the airtight tick_count=0 check caught
both; the metronome fires at the top of each minute, so arms started near :00 are the ones
it catches).** 0055 verified applied (post md5 `979dbe6a…`; 0 draws still salted with
v_visit, 21 on v_salt). Verdict: 2/20, first divergence sim-min 90 — and the diff is a
**milestone**: for the first time every STATE and every SoC is paired at the divergence
tick; the entire residue is the stall-reservation pairing shifted by one down an ordered
stall list. The decisions audit trail shows the two runs' very FIRST tick-3 decisions
differ — and the mechanism is **architectural, not another salt**: the cuOpt proposer fired
**33 times in each arm** (`cuopt_invocation_log`) and armed **50 vs 47**
right-of-first-refusal deferrals (`ottoq_cuopt_deferrals`). The deferral holds a vehicle out
of the local greedy path "while a solve is in flight" — and in-flight-ness is real pg_net
HTTP timing, real debounce windows (`cuopt_debounce_s`, REAL domain by design), and real
TTL clocks. Two same-seed runs therefore held DIFFERENT vehicles, and every downstream
stall pairing shifted behind them. **The twin's own state machine is now fully
deterministic; what remains is the deliberately real-async proposer.** Fix: **0056**
(post-merge) — per-run policy `cuopt_propose_enabled` (default 1: production and demo
behavior byte-identical): `ottoq_cuopt_refresh` refuses when 0 and logs the refusal as gate
`policy_disabled` (the ledger rule: countable in both directions), `ottoq_cuopt_defer_hold`
never holds when 0, and `ottoq_cert_arm_start` sets 0 for its own run. Nothing is removed —
propose/dispose and the NVIDIA pipeline are untouched everywhere else. Re-certification #11
runs after 0056 is applied, expecting `deterministic = true`.

**Re-certification #9 (post-0054, 2026-08-20; arms `b982b594` / `1c552be5`, arm B restarted
twice for metronome contamination — tick_count 2 then 1 — before a clean tick_count=0 start;
the airtight procedure caught both).** 0054 applied (first attempt aborted safely — inserted
`--` line comments swallowed ` LOOP` on single-line cursors; corrected to `/* */` block
comments and re-applied); post-apply sweep shows ONLY the documented fence-audit skip
remaining — **every per-tick cursor on the path is now provably ordered.** Verdict: 1/20,
first divergence sim-min 60 — the SAME tick-2 signature as #8 (10 vehicles swap
`charge_complete_holding` ↔ `staged_for_departure`, every SoC paired). With cursors
eliminated, the offender is one level down: the wash-triage verdict is a **pure function of
each vehicle's service manifest**, and `twin.ottoq_sim_generate_service_manifest` salts every
one of its 21 seeded draws (fault, urgency, inspection, tidy, wash, PM, calibration, …) plus
its 3 duration-card deals with `v_visit = vehicle || ':' || to_char(v_clock,
'YYYYMMDDHH24MISS')` — the ABSOLUTE sim clock, the 0045 salt class, hiding inside the visit
key; the function's own 0020 note documents the salt/key fusion as deliberate. Same-seed runs
dealt different manifests by construction, so the triage staged different subsets. Fix:
**0055** (post-merge) — the roles are split: `v_visit` stays the ledger key everywhere
(visit_key, rider-flag binding, carryover, meta), the 24 draw/deal sites move to a
run-relative `v_salt` (whole minutes since `sim_clock_start`, `GREATEST(0,…)` so the tick-1
arrival batch — whose clock is the reset's wall clock, fractionally before `sim_clock_start`
— lands in bucket 0 in every run); no-run callers keep the old absolute salt verbatim. All 6
anchors pre-verified (counts 1/1/21/1/1/1 exact) under the 0054 mechanism extended with
per-patch expected counts. Re-certification #10 runs after 0055 is applied, expecting
`deterministic = true`.

**Re-certification #8 (post-0053, 2026-08-20; arms `c1389c7b` / `5d986813`, both verified
tick_count=0 at start, boundary-safe start minutes).** 0053 verified applied (md5 match); the
config residue is gone. Verdict: **1 of 20 ticks identical, first divergence sim-min 60** —
apparently a regression, actually the strongest signal yet: with the world truly identical at
start and no stale charge plans staggering completions, many vehicles now finish charging
simultaneously, and the tick-2 frame diff shows **9 vehicles swapping between
`charge_complete_holding` and `staged_for_departure` with every SoC paired** — a
capacity-limited promotion picking WHO advances in **heap order**. Proximate offender:
`twin.ottoq_sim_wash_triage` (its cursor over `charge_complete_holding` has no ORDER BY). The
full-catalog sweep 0050 never ran outside the five advance functions then found **21 unordered
per-tick cursor sites across 16 functions**, including the decide path itself
(`ottoq_decide_tick`'s gate router and BESS cursor) and its planning helpers
(opportunistic charges, reservation re-optimizer, vacated-space release, pre-arrival
contracts, unplaced-vehicle placer, comms advance, net-load forecast, and seven more twin
functions). 2.5 names determinism under fixed seed a kernel requirement, so the decide-path
sites are kernel-bug fixes: previously ARBITRARY orders made stable, semantics unchanged.
Fix: **0054** (post-merge) — a new self-verifying mechanism sized to a 74KB function: per
site, assert the pinned pre-image md5 and exactly-once anchor occurrence, single-site replace
server-side, EXECUTE; atomic, transcription-free. All 21 anchors pre-verified read-only
against production (every pin matches, every anchor unique).
`public.ottoq_check_fence_containment` deliberately skipped (read-only geometry audit).
Re-certification #9 runs after 0054 is applied, expecting `deterministic = true`.

**Re-certification #7 (post-0052, 2026-08-19; arms `483954ce` / `4b626bb7`, both verified
tick_count=0 at start, both start-minutes on the same side of every hour/date boundary).**
0052 verified applied (both md5s match the file-applied scratch). The single-recall swap is
gone — the holdout fix holds. Verdict: **8 of 20 ticks identical, first divergence sim-min
210** — once more the overnight-window tick. This one is **NOT an RNG bug: it is cross-run
state leakage in the cert harness's world reset.** The proof is written in the vehicle config
payloads (`ottoq_events.new_state`): arm A's `config->'charge_plan'->>'planned_at'` values
carry the fractional-second sim-clock signature of the *previous* cert's arm B (`…:06.133086`
= run `1a576926`), and arm B's carry arm A's (`…:05.932765` = run `483954ce`).
`ottoq.ottoq_book_appointment` writes `config->'charge_plan'` on every booking (the charge
doctrine); `public.ottoq_benchmark_reset` strips 13 config keys but not that one (nor
`deploy_gate`, nor the `arm_fault_*` keys the emergency release writes), so **every arm
starts with the previous run's plans** — invisible to the structural digest (which reads
state/SoC/stall only) until the overnight charge-planning path reads the stale plans and the
two arms plan differently. Fix: **0053** (post-merge) — the reset's strip list gains
`charge_plan`, `deploy_gate`, and the three `arm_fault_*` keys; the function's own guard
restricts it to benchmark depots. `config->'last_balance_charge_at'` is also run-written
(balance-charge completions) but was identical across this pair — recorded as the next
residue channel to check first if re-cert #8 still diverges. Re-certification #8 runs after
0053 is applied, expecting `deterministic = true`.

**Re-certification #6 (post-0051, 2026-08-19; arms `eb5a5d37` / `1a576926`, both verified
tick_count=0 at start).** 0051 verified applied (both md5s match the file-applied scratch).
The gate-assignment permutation is GONE — the assigner fix holds. Verdict: **8 of 20 ticks
identical, first divergence sim-min 270** — exactly the tick the sim clock crosses 22:00
America/Chicago and the overnight recall window opens. The tick-9 frame diff is a **single
swap**: a different deployed vehicle was recalled in each run (one `arrived_at_gate` in A,
the other in B), everything else paired. The recall cursor itself is run-stable
(`ORDER BY current_soc, id` — verified); the offender is its **eligibility filter**:
`public.ottoq_is_overnight_holdout` hashes `p_run::text` — the per-run-random sim_run_id
(the 0047 salt class) — so two same-seed runs hold out different vehicles by construction,
at both call sites (`ottoq_plan_dispatch_tick` 'recall' and `ottoq_evaluate_return_need`
rung 6). A sweep found the same class in `public.ottoq_comms_emit_telemetry` (run uuid +
absolute clock on the dropout/latency draw; comms staleness feeds the rung-8 recall, so
decision-path-reachable). `ottoq_book_appointment`'s stall picks were audited in the same
pass and are already run-stable (every pick ends `…, s.id`). Fix: **0052** (post-merge) —
holdout keyed on the run's random_seed (unknown-run callers byte-identical), comms seed on
run seed + `ottoq_sim_clock_salt`; captures md5-verified, diff-proven to two changed sites.
Re-certification #7 runs after 0052 is applied, expecting `deterministic = true`.
*Standing harness caveat, made explicit:* `sim_clock_start` is real `now()` at arm, so
hour-of-day and calendar-date expressions (deploy fraction by hour, night waves, wash-day
rotation, the holdout date term) agree across a cert pair only because arms start minutes
apart. **Cert arms must not straddle an hour boundary, midnight UTC, or 05:00
America/Chicago**; pinning `sim_clock_start` to a canonical anchor in the cert harness is
the recorded follow-up that would retire this caveat class entirely.

**Re-certification #5 (post-0050, 2026-08-19; arms `8e8da5c5` / `0d920ed3`, both verified
tick_count=0 at start).** 0050 verified applied (all five md5s match the file-applied scratch).
The five patched advance functions are now deterministic — no crashes, 20v20 aligned, and the
in-bay service flow no longer permutes. Verdict: **9 of 20 ticks identical, first divergence
sim-min 300**, and the tick-10 frame diff is again a pure **vehicle↔stall matching permutation**,
now isolated to the **gate-admission assigner**: same states, same SoCs, same stall set in use,
different pairing. Root cause, two residual instances of already-fixed classes in
`twin.ottoq_sim_auto_charge_assign_tick`: (1) its stall-shuffle seed hashes the **absolute sim
clock** (`p_sim_clock_now::text` — the 0045 salt-domain class), so the seeded stall pick differs
across same-seed runs; (2) its vehicle cursor is `ORDER BY current_soc` with **no tiebreak** —
integer-SoC ties (measured: the 48/48 and 65/65 pairs at tick 10 are exactly the swapped
vehicles) fall back to heap order (the 0050 class). A sweep found the same absolute-clock salt
in `twin.ottoq_sim_auto_dispatch_tick`'s dispatch-ranking seed. Fix: **0051** (post-merge) —
both seeds re-salted via `ottoq_sim_clock_salt`, plus the run-stable `id` tiebreak; captures
md5-verified byte-exact against production, diff-proven to exactly three changed lines.
Re-certification #6 runs after 0051 is applied, expecting `deterministic = true`.

**Re-certification #4 (post-0049, 2026-08-19; arms `a4ce46d4` / `523f770e`, both verified
tick_count=0 at start — the airtight-start procedure below).** 0049 verified applied; **no tick
crashed** — the 0048/0049 state-machine fixes hold end-to-end. Verdict: **11 of 20 ticks
identical, first divergence sim-min 360, and at that tick every one of the 100 vehicle SoCs was
paired** — all seeded randomness is now deterministic. The residual diff is a pure
**stall-assignment permutation**: the same stalls paired to a vehicle queue shifted by one.
Root cause: **eleven per-tick processing cursors across five twin functions iterate with no
ORDER BY** — physical heap order, which drifts between runs, decided who claimed a shared
resource first. Fix: **0050** (post-merge) — run-stable ORDER BY (vehicle.id / stall.id; never
per-run-random or real-clock keys) on all eleven; diff-proven additive-only.
*Harness lessons now standing procedure:* (a) relabel `run_by='cert_harness'` immediately after
arm_start **and verify `tick_count = 0` before the first step** — a metronome tick can land in
even a 2-second window (it contaminated the first arm-B attempt, `94982168`, discarded); (b) a
CTE combining arm_start with the relabel does NOT work (the outer UPDATE cannot see rows the
CTE's function inserted in the same statement).

**Re-certification #3 (post-0048, 2026-08-19; arm `5822181f`, correct `cert_harness` labeling).**
0048 verified applied (md5 match). The 0048 reorder works — and the cert then surfaced the next
gate mismatch, one layer deeper: a tick died on the **vehicle-side arm interlock** even though
the admit path had asked `twin.ottoq_arm_refuse_move` first. The mirror and the backstop evaluate
the tether in **two different clock domains, exactly one tick apart**: refuse_move used the
caller's in-flight tick clock (persisted clock + 30 min), the interlock trigger uses the run's
persisted `sim_clock_current` (advanced only at tick end). A demate expiring exactly on the tick
boundary (vehicle `02f1a60b`, until = the new tick's own timestamp) was therefore "movable" to
the mirror and "held" by the backstop. Fix: **0049** (post-merge) — refuse_move sources its
clock from the guard's exact expression, making mirror and backstop provably consistent for
every caller; the boundary case defers one tick. Re-certification #4 runs after 0049 is applied.

**Re-certification #1 (post-0045, 2026-08-19; arms `2ab6ab11` / `e12faa29`, seed 424242).**
The cert worked exactly as designed: **10 of 20 aligned ticks identical (was 0 of 20)**, and at
the first divergence (sim-min 330) **all 100 vehicle SoCs were paired** — the 0045 salt fix
holds across every patched stream. The residual divergence is a *single vehicle* (charging in
arm A, still at the gate in arm B): charge-session **rate noise** shifted one session's
completion tick, which shifted a stall hand-off. Root cause: two salt sites the 0045 census
missed — `twin.ottoq_sim_advance_charge_sessions` (×2) and `twin.ottoq_sim_start_charge_session`
(×2) salt their noise with the per-run-random **session UUID** and the **absolute clock**.
Fix: **0047** (committed, NOT yet applied — post-merge), same salt-domain treatment via
`ottoq_sim_clock_salt` on (vehicle, run-relative offsets). Re-certification #2 runs after 0047
is applied, expecting `deterministic = true`.

**Bonus finding from the same runs:** `ottoq_certify_run` on arm A: `certified = false` —
2 of 21 frames show a stall held by two vehicles (`over_stall_ticks=2`). The frame-level B1
invariant is violated under the batch cuOpt enactment era; needs its own root-cause (candidate:
frame capture mid-enactment vs. the EXCLUDE calendar, which cannot itself double-book).

## 2. What 0045 changes when applied (post-merge)

| § | Change | Risk |
|---|---|---|
| 1–2 | salt-domain fix, 9 functions | behavior of *individual draws* changes once (new stream); distributions unchanged; nothing reads the old salts |
| 3 | digest + verdict fns | additive, read-only |
| 4 | 5 canonical event types registered | additive catalog rows |
| 5 | `ottoq_twin_playback_timeline` view | additive, read-only |
| 6 | **decision surfaced for merge review:** `ottoq_ab_runs` reclassified engine → evidence (purge stops deleting A/B scores; the C4 mystery of the empty table) | A/B rows now outlive runs, as `ottoq_run_archives` already does |

## 3. Canonical event vocabulary (C7.2) — the audit

Catalog holds 132 types. Mapping to the canonical thirteen:

| Canonical | Exists today as | 0045 action |
|---|---|---|
| arrival | `twin.vehicle_arrived` (+ `ottoq.arrival_forecast`, `fleet.arrival_delayed`) | none (mapped) |
| op_start / op_end | `twin.service_started`, `charge.session_started/completed`, `task.state_changed` | none (mapped) |
| fault | `charge.session_faulted`, `charge.fault_injected`, `twin.bay_fault_reroute` | none (mapped) |
| point_blocked / point_cleared | `stall.state_changed` (+ bay_fault equipment_config lifecycle) | none (mapped) |
| power_loss / power_restored | `twin.grid_brownout`, `twin.grid_voltage_sag`, `twin.grid_frequency_excursion` | none (mapped) |
| **move_start / move_end** | — | **registered (0045)**; emitters follow with the playback adoption |
| **recall_issued / recall_refused** | — (`early_recall_log` holds the concept) | **registered (0045)**; C9 emits |
| **touch_event** | — (KPI-4 currently enumerates human actor types) | **registered (0045)**; supersedes the enumeration once emitters adopt |

## 4. Failure-scenario library (C7.3)

`scenarios/` — the canonical nine, each a committed data file with an honest `status`:
**executable today** (blocked_point, overstay, immobile_asset, mid_session_charger_fault — each
names its live injector: bay-fault policy knobs, eta_delay variability, breakdown-rate profile,
cert-arm `fault_chargers` / `inject_fault`), **partial** (zone_power_loss — site-wide cap
injectors exist, per-zone does not), and **provisional** with the unlocking work named
(human_path_crossing → twin path-resource model; swap_dock_jam → yard-logistics pack;
tug_unavailable → vertiport paper pack; work_side_recall_refusal → C9).

## 5. Playback timeline (C7.4)

`ottoq_twin_playback_timeline` (0045 §5): `(entity_id, event_type, t_start, t_end, from_pose,
to_pose)` per itinerary leg, poses from stall geometry, `playback_schema_version = 'v1'`,
security-invoker view, pure SQL. Zero Isaac imports in the path — this is the seam the in-house
3D layer renders from and through which Track B can return (CLAUDE.md 2.8). Verified rendering
rows on the scratch instance.

## 6. Discipline check (C7.5)

Nothing added carries a new run-scoped column (views and the salt helper are stateless; the five
event types are catalog rows). `data_source` co-existence untouched. The one retention change
(§6, ab_runs) is a *surfaced decision*, not a silent drift — merging 0045 is deciding it.

## 7. The demonstration run, end-to-end into the C6 CLI (the deliverable's spine)

Run **`6727b04e-b890-45e3-87c1-ac4c558e2a81`** (benchmark depot, `normal_day`, seed 424242,
policy `otto_q`, 690 sim-minutes — over the 139-minute credibility floor): driven by the cert
harness → scored into `ottoq_ab_runs` → archived (`ottoq_archive_run`) → stamped with the 0044
reproducibility key → **`ottoq_kpi_five(run)` returns all five canonical KPIs** (committed
verbatim in `metrics/demo_run_6727b04e.json`, with the safety-cert result and the determinism
verdict alongside). Headline: peak_site_kw 662.1 · turns/point/day 1.84–1.92 ·
touch_events_per_turn 0.059 · p95_time_to_service 0 min · asset-hours 773.4+27.6.
Every number above traces to that run ID.
