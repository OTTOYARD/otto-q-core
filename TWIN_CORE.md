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

**The time-of-day confound, and what it does and does not invalidate (recorded 2026-08-21).**
`public.ottoq_cert_arm_start` (md5 `7dbb6135…`) hardcodes the run's sim clock to `v_now`:
`sim_clock_start = sim_clock_current = v_now`, `sim_clock_end = v_now + 24h`. So a cert pair
does not sample "the scenario" — it samples the 10-sim-hour slice of `normal_day` that begins
at whatever wall-clock time the round was armed. Measured across two consecutive rounds on the
SAME code path: re-cert #17 armed 22:40Z carried 1,075 / 1,098 vehicle commands per arm; #18
armed 00:32Z carried 1,562 / 1,598 — ~45% more work from the arrival curve alone.

What this invalidates: **the cross-round `ticks_identical` trend**. Quoting "12/20 → 14/20 →
9/20" as progress was wrong, and it was quoted that way in earlier records here; those numbers
are per-round diagnostics, not a score, and the sentence in the #16 record already said so
before the confound was understood.

What this does **not** invalidate: **every within-round A-vs-B comparison, and therefore every
bug found.** The two arms of a pair are armed ~2 minutes apart inside the same 30-minute band
(the BAND RULE), so they sample the same slice under the same load. Each determinism verdict is
a valid same-input comparison; no fix in 0045–0064 rests on a cross-round claim.

The fix, when the founder greenlights it: `twin.ottoq_sim_start_run` (md5 `a8454174…`) **already
accepts `p_sim_clock_start timestamptz DEFAULT NULL`** — the capability exists one layer down.
Only `ottoq_cert_arm_start` fails to pass one. Pinning it is a cert-harness-only change with zero
effect on production scheduling semantics.

**THE ONE-ROW ASYMMETRY IN RE-CERT #20, RUN DOWN (2026-08-22, read-only).** Recorded because
it changes how the passing certification should be *stated*, not just as a loose end.

Re-cert #20 scored 20/20 with `deterministic = TRUE`, yet the two arms differed by one command
(refusals 310 vs 311, never-reacted 68 vs 69). A full outer join of both arms' command streams,
keyed `(vehicle_id, command_type, rank ordered by issued_at then payload)`, isolates **exactly
one differing row in the entire run**:

| | arm A | arm B |
|---|---|---|
| vehicle | `8e00a933` | `8e00a933` |
| command | `stage` → staging stall `fa4f4d72` | `stage` → staging stall `fa4f4d72` |
| issued | sim `2026-08-23 04:00:00` | sim `2026-08-23 04:00:00` |
| **outcome** | **executed** | **refused `target_occupied`** |

**My earlier guess was wrong and is corrected here.** I recorded this as "most likely a trailing
boundary command after the final tick." It is not: 04:00 is **tick 12** of a run starting 22:00,
squarely mid-run. The guess was never checked before being written down.

**It is inert, and that is measured, not assumed.** A per-tick frame diff over
`ottoq_decision_snapshots.frame->'vehicles'`, joined on vehicle id across all 20 ticks, returns
**zero divergent vehicles** — no vehicle differs in state or stall at any tick in either arm.
This vehicle's other two commands are byte-identical in both arms (`proceed_to_stall` → `1cc14b7f`
at 06:30, → `94358f10` at 07:00, both executed). So the vehicle went to the same places at the
same times in both arms; the disputed `stage` changed nothing observable.

**WHAT IT ACTUALLY MEANS, STATED PRECISELY.** One instant of staging-stall occupancy — whether
`fa4f4d72` was free at sim 04:00 — still differs between two same-seed arms. The digest does not
score it, because the digest scores the frame (vehicle state) and this divergence never reaches
the frame. So the certification claim must be stated as what was actually measured:

> Same seed + scenario + policy produce an identical vehicle-state frame at every one of 20
> ticks, and an identical scored event stream. **One command outcome out of ~523 differed
> without affecting world state.**

That is still a pass, and a strong one. It is not the same sentence as "every byte of the run is
identical," and the record should not let those two be confused.

**NOT CHASED FURTHER, deliberately.** There is a residual ordering seam upstream of staging-stall
occupancy that is not yet total. It is benign in this scenario but there is no guarantee it stays
benign in another — a divergence that does not propagate here could propagate under different
load. It is left as a **known, precisely-signatured residue** rather than patched: the last
confident one-shot fix (0068) cost a round and had to be reverted, and this one lacks the thing
that made 0067's diagnosis solid — a measured mechanism. Anyone picking it up starts from
vehicle `8e00a933`, stall `fa4f4d72`, sim `2026-08-23 04:00:00`, and asks what made that stall
occupied in one arm and not the other.

**Consequence for the harness itself, worth its own line:** the digest's coverage is narrower
than the phrase "determinism certification" suggests. It compares frames, not command outcomes.
Extending `ottoq_twin_run_digest` to fold in command status/reason_code would have caught this
automatically instead of it surfacing as an unexplained row-count mismatch — a candidate
improvement to C7.1's instrument, filed alongside the residue.

**Re-certification #21 — MY HYPOTHESIS WAS FALSIFIED ON BOTH COUNTS, AND 0068 IS REVERTED**
(post-0068, 2026-08-22; arms `9ea1a855` / `7e8bb433`, ab_group `…424260`, both
`sim_clock_start = 2026-08-22 22:00:00+00`).

0068 predicted two things in writing before the run: determinism would REMAIN true (confirming
the tiebreak owned the certification), and throughput would recover toward #19's 60–62 sessions
(confirming the sim-domain move owned the regression). The migration header also committed, in
advance, that **if throughput did not recover the attribution was wrong and would be rewritten
rather than defended.** It did not recover. This is that rewrite.

| | #19 (pre-0067) | #20 (0067) | **#21 (0068)** |
|---|---|---|---|
| predicate | `expires <= now()` (real clock) | `expires <= p_sim_clock` | `reserved_by = v_veh.id` |
| tiebreak | absent | present | present |
| **deterministic** | false (10/20) | **TRUE (20/20)** | **false (15/20, first div 480)** |
| charge sessions A / B | 62 / 49 | 41 / 41 | **23 / 23** |
| vehicles charged | 60 / 47 | 41 / 41 | **23 / 23** |
| DCFC sessions | 18 / 18 | 13 / 13 | **9 / 9** |
| `begin_charge`/`target_occupied` | 80 / 128 | 219 / 219 | **328 / 328** |
| reactor backlog | 0 / 2 | 68 / 69 | **177 / 177** |

**0068 is strictly worse than 0067 on both axes** — it lost the certification *and* cut
throughput almost in half again. It has been **reverted in production**, by reversing its own
patch and asserting the result is byte-identical to 0067's post-image
(`3d7fa12fec5fe860854d8416dd8e4840`, verified). Production is back in the last founder-merged
state. The revert restores previously-authorised behaviour; it introduces nothing new.

**TWO THINGS I GOT WRONG, STATED PLAINLY.**

1. **"A tiebreak cannot move throughput."** This was the load-bearing claim behind the whole
   attribution, and it is false. Compare #19 and #21: their reservation predicates are
   *behaviourally equivalent* — #19's real-clock comparison sat ~21h behind the sim clock and so
   was effectively always false, which is precisely "never reuse another vehicle's hold," which
   is what #21 says explicitly. The only difference between those two rounds is the tiebreak,
   and sessions went **62/49 → 23/23**. A tiebreak does not merely order indistinguishable
   candidates: by always preferring the same member of a tied pair (`stall_code ASC`) it
   systematically biases which stall is consumed first, and `v_used` plus downstream availability
   propagates that bias through the rest of the tick. Heap order was accidentally spreading the
   load across tied stalls; a deterministic order concentrates it.

2. **"The tiebreak owns the certification."** Also false. #20 and #21 both carry the tiebreak;
   #20 is deterministic and #21 is not. The sim-domain expiry predicate was contributing to
   determinism too, and removing it exposed a *different*, deeper non-determinism — the first
   divergence moved from sim-min 330 to 480, so it is not the same seed re-emerging.

**WHAT THE EVIDENCE ACTUALLY SUPPORTS NOW.** Only one configuration has ever certified:
0067's exact pair of changes together (tiebreak + sim-domain expiry), at 41 sessions. #19's 62
was never a stable number — it is one arm of a *non-deterministic* pair whose sibling scored 49,
so "62" was partly a coin flip, and the honest pre-fix figure is "somewhere between 49 and 62,
irreproducible." The real open question is therefore not "how do we get 62 back" but:
**can the depot reach ~60 sessions in a configuration that also certifies?** That is a genuine
design problem — the tiebreak's load-concentration effect versus determinism's need for a total
order — and not something to patch blind. A plausible direction is a tiebreak that is total but
*load-aware* (e.g. order tied stalls by current utilisation, then `stall_code`, then `id`), which
keeps a total order while restoring the spreading heap order was doing by accident. Untested;
recorded as a hypothesis, not a plan.

**Standing conclusion for C7.1:** the certification holds and is now reproduced. Re-cert #20
(20/20) and re-cert #22 (20/20, hands-off, post-0069) both pass on the same production state,
so the result no longer rests on a single sample. **What is certified is the within-session
property — same seed + same session → byte-identical scored event stream.** #22 also showed that
the same seed does *not* reproduce the same world across sessions (see the finding recorded with
#22 below), so the earlier framing of the throughput cost as "41 sessions vs an irreproducible
49–62" is withdrawn: those numbers were never comparable to each other. The trade-off is real but
unmeasured, and measuring it requires a decision the founder owns.

**Harness note:** arm B's first attempt was discarded at `tick_count = 1` (metronome contamination
in the arm_start → shield gap) and re-armed clean at 26 seconds into a minute — the third time
this has cost an arm, and the reason the `ottoq_cert_arm_finish` teardown fix was owed.
**That fix is 0069, applied 2026-08-22 and proven by re-cert #22, which ran end-to-end with no
manual sweep.** Mid-minute arming is still required; the metronome hazard is separate from the
tether hazard and is not addressed by 0069.

**Re-certification #22 — C7.1 PASSES AGAIN, AND THIS TIME HANDS-OFF (post-0069, 2026-08-22
20:10–20:13Z; arms `288d24fc` / `914214a4`, ab_group `…424261`, both `sim_clock_start =
2026-08-22 22:00:00+00`).**

```
ticks_compared 20 | ticks_identical 20 | ticks_divergent 0 | deterministic = TRUE
```

Every scored metric matches exactly across the two arms: **10 / 10 charge sessions, 89 / 89
vehicles cycled, 1736 / 1736 decisions, 1205 / 1205 enacted, 589.30 / 589.30 peak kW,
8.9 / 8.9 throughput per hour, 0 / 0 safety violations.**

**This is the second certification the series has ever produced, and the first that needed no
human hand in the middle.** Until now the certification rested on a single sample (#20).

**0069 did what it was written to do, and the proof is the run itself.** Arm A ended with **one
vehicle still tethered** — the exact condition that killed an arm in #19, #20 and #21. Teardown
released it (0 tethered immediately after `ottoq_cert_arm_finish`), and **arm B armed clean with
`tick_count = 0` and no manual `twin.ottoq_arm_emergency_release` sweep.** The sweep is retired.

0069 was also exercised against real pre-existing residue before this pair ran: the stranded arm B
of re-cert #21 (`7e8bb433`, left `running` for 18 hours) was finished under the new teardown, which
released 2 tethers and closed the open `twin.arm_cycles` row with outcome `emergency_released`
stamped at `2026-08-23 08:00:00+00` — **the run's own `sim_clock_current`, not the real clock.**
That timestamp is the migration's whole point, and it is now observed rather than argued.

Applied post-md5: **`02beeffec29daad712b8e19271c9adf4`**. Post-conditions re-verified against the
live catalog after the apply, not only inside the DO block: exactly one release call, ordered
before the `status='aborted'` flip, handed the run's own sim clock, filtered to
`robotic_tether_until IS NOT NULL`.

**Free evidence recovered along the way.** Finishing #21's stranded arm made its pair scorable for
the first time: `9ea1a855` vs `7e8bb433` → **15/20, first divergence sim-min 480**. That is the
number `MIGRATION_LOG` already records for 0068, reproduced independently 18 hours later from
frames captured at 02:00Z and 02:02Z. Two things follow: the 0068 measurement was sound, and the
frame digest is stable over time — it reads `ottoq_decision_snapshots`, which teardown does not
touch. (Checked, not assumed: the divergent frames pre-date today's teardown call by 18 hours.)

---

### The finding this run turned up: determinism is session-local, and throughput numbers are not comparable across sessions

**Same seed, same policy, same code — and #22 does not reproduce #20.** The decide path is
byte-identical between them (`ottoq_l2_optimize_assignments` verified live at
`3d7fa12fec5fe860854d8416dd8e4840` immediately before 0069; 0068 was applied and reverted to a
byte-identical image in between; 0069 touches only harness teardown, which runs after the run).
Yet:

```
#22 arm A vs #20 arm A: struct_hash differs at tick 1 and at every tick thereafter
  stall side  ....... IDENTICAL
  vehicle side ...... 30 / 100 vehicles in a different state
                      81 / 100 vehicles at a different SoC
                      mean SoC 90.2 vs 90.2 (distribution preserved)
                      max per-vehicle delta 11.0 points
  charge sessions ... 41 (#20) vs 10 (#22)
```

The divergence is present **in the very first frame**, before the decide path has had a chance to
do anything. So it is an initial-condition difference, not a scheduling difference. The stall side
resets cleanly; the fleet side does not come back to the same place.

**What this costs us, stated plainly:**

1. **The determinism certification is intact but narrower than the words suggest.** What #20 and
   #22 each prove is *same seed + same session → identical*. Neither proves *same seed → same
   world*, which is the property the founder has asked for and the property "no number ships
   without a run ID" ultimately leans on. A run ID currently identifies a run, not a reproducible
   world.
2. **Every cross-session throughput comparison in this series is confounded**, including the one
   this document and `MIGRATION_LOG` use to conclude that *"0068 is strictly worse than 0067 on
   both axes."* The **determinism** half of that conclusion is a within-pair comparison and stands
   untouched (15/20 vs 20/20). The **throughput** half — 41 → 23 — compared runs booted ~40
   minutes apart from different fleet states, and cannot carry the weight put on it. Marked here
   rather than deleted, and marked in `MIGRATION_LOG` at the same time. The 62 / 49 / 41 / 23 / 10
   series is best read as *what the fleet happened to be carrying at arm time*, not as a ranking of
   configurations.

**What is already ruled out.** The per-vehicle condition draw in `ottoq_run_boot_draw` is
clock-free: every draw is `ottoq_sim_seeded_random(v_seed, '<salt>:' || vehicle_id)`, a pure
function of (seed, vehicle). `ottoq_benchmark_reset` sets all 100 autonomous vehicles to
`current_soc = 30` and `current_state = 'arrived_at_gate'`, and all 100 vehicles at this depot are
`category = 'autonomous'`, so the reset's category filter is not leaking anyone. The world day-0
draw buckets on `sim_clock_start::date`, which is the same date for both runs. **The salt has not
been found, and is deliberately not guessed at here.**

**Not fixed, and not to be fixed without the founder's call** — the choice is a product decision,
not a bug fix. Per-run variability is *intended* to be redrawn (that is the thesis: OTTO-Q
orchestrates correctly whatever the world looks like). The open question is narrower: should a
*pinned seed* also pin the fleet's boot state, so that a run ID reproduces a world? Answering yes
buys reproducible benchmarks and costs nothing at the depot; answering no keeps the harness honest
about variability but means throughput can only ever be compared within a session. Recorded as the
sharpest form of the standing throughput question.


---

**Re-certification #20 — C7.1 PASSES (post-0067, 2026-08-22; arms `677bca9c` / `43fbecf4`,
ab_group `…42425f`, both `sim_clock_start = 2026-08-22 22:00:00+00`).**

```
ticks_compared 20 | ticks_identical 20 | ticks_divergent 0 | deterministic = TRUE
```

**Twenty rounds after the first attempt, the determinism certification passes.** Same seed, same
scenario, same policy → byte-identical scored event stream across all 20 ticks. 0067 verified
applied (post-md5 `3d7fa12fec5fe860854d8416dd8e4840`, matching its dry-run exactly).

The root cause it fixed was the one predicted from the #19 baseline: the `greedy_constrained`
stall pick had no tiebreak, so two L2 stalls at `distance_from_entrance = 176` scored identically
and `LIMIT 1` returned heap order. The prediction was specific and it held — the tick-10 stall
swap is gone, and with it every downstream divergence.

The arms now agree on throughput as well as on the event stream: **523 / 523 commands,
41 / 41 charge sessions, 41 / 41 vehicles charged, 13 / 13 DCFC sessions.** Compare re-cert #19,
where the same two numbers were 60 and 47. **The 13-vehicle spread is closed.**

**One residual asymmetry, recorded rather than glossed:** refusals are 310 vs 311 and
never-reacted 68 vs 69 — a single row. The certified property (the scored event stream over 20
ticks) is byte-identical, so this sits outside what the digest scores. **The guess originally
recorded here — "most likely a trailing boundary command after the final tick" — was wrong, and
is corrected in the run-down above: it is a mid-run `stage` command at tick 12.** It is not covered by the passing verdict and should be
chased before the certification is called complete.

---

**AND THE BASELINE IMMEDIATELY EARNED ITS KEEP: 0067 COSTS THROUGHPUT.**

This is the first comparison in the whole series that is *valid across rounds* — #19 and #20 ran
the same seed at the same pinned sim clock — and it says something I did not want it to say:

| metric (arm A) | #19 (pre-0067) | #20 (post-0067) |
|---|---|---|
| charge sessions | **62** | **41** |
| vehicles charged (of 100) | **60** | **41** |
| DCFC sessions | 18 | 13 |
| refusals, all types | 155 | 310 |
| `begin_charge` / `target_occupied` | **80** | **219** |
| refusals never examined | 0 | **68** |

Determinism was bought at the cost of roughly a third of the depot's charging throughput, and
the reactor backlog is back. **This is a regression introduced by 0067, caught by the very
instrument built to catch it — 0065 exists for exactly this.**

**The mechanism, and it is 0067's second half, not the tiebreak.** The tiebreak only orders
stalls whose score was already identical; it cannot change *which* score wins, so it cannot
move throughput. The sim-domain fix can and did. Before it, `reservation_expires_at <= now()`
compared a sim-stamped column to a real clock ~21 hours behind, so the test was effectively
always false and the proposer skipped **every** stall carrying any reservation. After it, the
proposer correctly offers stalls whose sim reservation has expired — and those are precisely the
contended ones. The proposer's own filter is satisfied at propose time (`current_vehicle_id IS
NULL`, reservation expired), but the confirm walk runs a tick later (30 sim-min), by which point
the stall has been taken: `begin_charge` / `target_occupied` nearly triples, 80 → 219.

So the old behaviour was wrong *and* accidentally protective: by refusing to reuse any reserved
stall it never handed away a hold that a vehicle was still travelling toward. The corrected
domain test removes that accidental protection without replacing it — the same class of problem
0064 addressed for the command-issuing path, now on the proposal path.

**The fix is not to restore `now()`** — that comparison is simply wrong and would re-break the
moment sim and real clocks diverge. The candidate is to make the proposer decline a stall still
reserved to a *different* vehicle regardless of expiry (`reserved_by IS NULL OR reserved_by =
v_veh.id`), which keeps the domain correct and restores the protection deliberately instead of
by accident.

**Next, in order:** (1) isolate — re-run with the tiebreak alone, reverting only the sim-domain
half, to confirm the split above rather than assert it; the determinism win should survive; (2)
then re-land the domain fix with the hold protection; (3) then the `ottoq_cert_arm_finish`
tether teardown; (4) the reactor drain-rate change is un-deferred if the backlog stays.

**Re-certification #19 — THE FIRST PINNED-CLOCK BASELINE (post-0065 + 0066, 2026-08-22; arms
`88ed727f` / `81ee350d`, ab_group `…42425e`, both `sim_clock_start = 2026-08-22 22:00:00+00`).**
0065 and 0066 verified applied (post-md5s `00314bb9…` — matching the locally computed post-image
byte-for-byte — and `c5caed3f…`). Verdict: **10/20, first divergence sim-min 330.** Still FAIL.
**But this is the first round that can ever be differenced against another**, and from here
`ticks_identical` becomes a real score rather than a diagnostic.

**0065 is proven in operation, not just in the diff.** Both arms report
`sim_clock_start = 2026-08-22 22:00:00+00` exactly, with `tick_count = 0` at shield time. The
heartbeat trap the migration was written to close was real: after tick 1 of arm A, **40 chargers
sat inside the proposer's `last_heartbeat_at >= sim_clock_current - 90s` window and
`noop_no_candidate` was 0.** Without the `v_sim0` charger stamp both numbers would have been
zero-and-everything, silently — the run would have looked like a scheduling collapse rather than
a domain mismatch. An unplanned bonus: because the pin is absolute rather than arming-relative,
the two arms of a pair now begin at an *identical* sim clock instead of ~2 minutes apart, which
removes one more source of cross-arm variation.

**The depot is no longer livelocked.** Against re-cert #18 (the last pre-fix round):

| metric | #18 A | #18 B | **#19 A** | **#19 B** |
|---|---|---|---|---|
| vehicle commands | 1,562 | 1,598 | 627 | 485 |
| `begin_charge` executed | 12 | 5 | **62** | **49** |
| `begin_charge` refused | 1,179 | 1,277 | 81 | 128 |
| refusals, all types | 1,286 | 1,404 | 155 | 219 |
| **refusals never examined** | **926** | **1,044** | **0** | **2** |
| rerouted | 22 | 42 | 16 | 14 |
| `no_capacity` escalations | 331 | 315 | 81 | 159 |
| charge sessions | 12 | 5 | 62 | 49 |
| distinct vehicles charged (of 100) | — | — | **60** | **47** |
| DCFC sessions | — | — | 18 | 18 |

**The reactor backlog is gone.** 926 unexamined refusals became 0. At ~8 refusals per tick the
`LIMIT 20` cursor drains completely, so the cap is no longer binding — **which is why 0067 (the
drain-rate fix) is now deferred rather than shipped.** It would only matter again at the refusal
volumes the duplicate emit was manufacturing. Holding it was the right call: shipping it here
would have "fixed" a queue that no longer backs up and taken credit for it.

**ATTRIBUTION, STATED HONESTLY.** The throughput jump cannot be assigned to 0066 alone: the slice
also moved (pinned 22:00 versus #18's 00:32 arming), and 0065 and 0066 landed together. What is
*not* confounded is the **within-round** comparison, and that is now the sharper finding:

> **Non-determinism costs 13 charging sessions.** Two arms, same seed, same pinned clock, same
> code: arm A charged 60 vehicles, arm B charged 47 — a 21% spread. DCFC sessions are identical
> (18 / 18), so the DCFC path is stable and the divergence lives in the L2 / allocation path.

That is a far better statement of why determinism matters than any tick count: the residual
defect is not a cosmetic hash mismatch, it is a fifth of the depot's charging throughput.

**A NEW HARNESS GAP, exposed by success (not by 0065).** Arming the second arm failed with
`arm interlock: vehicle … is held by the arm at stall … refusing to move it to nowhere`.
`ottoq_arm_interlock_guard` reads `vehicles.robotic_tether_until` and compares it against the sim
clock of the *running* run — but between arms there is no running run, so it falls back to
`now()`, and a sim-dated tether (`2026-08-23 08:02`) reads as far-future forever. Six vehicles
were still tethered at the end of arm A (3 `charging/charging`, 3 `demate/unlatch`) and
`twin.ottoq_arm_emergency_release` cleared all six.

This never fired before because the depot was livelocked: with 5-12 charge sessions per run and
almost none on DCFC, a run essentially never ended with a live mate. With 18 DCFC sessions per
arm it fires every time. **`ottoq_cert_arm_finish` should release its run's tethers as part of
teardown** — filed as the next harness fix, ahead of 0067.

**Harness lesson 6 (procedural).** Arm B's first attempt was discarded at `tick_count = 2`: two
stray metronome ticks landed in the arm_start → shield gap. Re-armed 27 seconds into a minute
(mid-minute, away from the metronome's minute-top firing) and the retry shielded clean at
`tick_count = 0`. The BAND RULE itself is now **obsolete** — it existed to keep both arms inside
one 30-minute sim slice, and the pinned clock guarantees that by construction — but the
mid-minute arming discipline still matters.

**THE LIVELOCK, ROOT-CAUSED (2026-08-21). It is a drain-rate defect, not a race.**
Found by following the founder's own question — *"if a vehicle missed an assignment because
of timing, OTTO-Q should be aware of why and re-orchestrate because of that"* — to the
function that is supposed to do exactly that: `ottoq.ottoq_react_to_refusals`. It exists, it
is wired, and it is the bottleneck.

Ruled out first, by reading the source rather than guessing: **staging does not steal
chargers.** Both staging pickers filter explicitly — the gate-intake cursor in
`ottoq_decide_tick` selects `WHERE s.stall_type = 'staging'`, and `ottoq.ottoq_book_hold_stall`
constrains every one of its five tiers to `s.stall_type::text = 'staging'` over the
staging-ring zones. The `proceed_to_stall` commands observed against DCFC/L2 stalls come from
the reactor's own reroutes, not from parking.

The reactor's cursor is `... ORDER BY issued_at, vehicle_id, command_type, payload->>'stall_id'
LIMIT 20` — **twenty refusals per tick, a fixed cap with an unbounded queue behind it.** The
ledger shows what that costs:

| round / arm | refused | never reacted to | rerouted | escalated | of which `no_capacity` |
|---|---|---|---|---|---|
| #17 A | 904 | **624** | 18 | 262 | 261 |
| #17 B | 1,005 | **725** | 17 | 263 | 260 |
| #18 A | 1,286 | **926** | 22 | 338 | 331 |
| #18 B | 1,404 | **1,044** | 42 | 318 | 315 |

Two independent failures, and they compound:

1. **72% of refusals are never examined at all.** 20 per tick × 17 ticks = a ceiling of 340;
   #18 arm A handled 360 and left 926 with `reacted_at IS NULL` at the end of the run. The
   backlog grows monotonically — every tick adds more refusals than the reactor can read. This
   is the livelock: not a race between two arms, but a queue that fills faster than it drains.
   It is also why the same 131 (vehicle, stall) pairs reappear ~9 times each: nothing ever
   retires them.

2. **Of the refusals it does examine, ~92% find nowhere to go** (`escalated` /
   `no_capacity`: 331 of 338 in #18 A). The reroute path reserves its new stall for
   `ottoq_reserve_stall(..., 3600)` and books it for a further 60 minutes, so each *successful*
   reroute removes a stall from the pool for an hour — and each *failed* reroute leaves nothing
   behind but an escalation. Combined with 0064's 70-minute holds, capacity drains faster than
   vehicles are seated.

**The duplicate emit (finding 1 above) is a multiplier on both.** Because
`ottoq_decide_tick` emits `begin_charge` twice per enactment, roughly half of the reactor's
20-per-tick budget is spent re-reading duplicate rows of a decision it has already handled.
Fixing the duplicate does not just clean the audit trail; it doubles the reactor's effective
throughput at zero cost.

**What this changes about the 0064 hypothesis.** The earlier suspicion — that 0064's longer
holds deepened the jam — is still plausible but is now clearly *second order*. The dominant
term is the drain rate. A depot that never reads 72% of its own refusals will livelock at any
hold length. The pinned-clock harness (0065) lands first precisely so the fixes that follow
can be differenced rather than argued.

**Re-certification #18 (post-0064, 2026-08-21; arms `da724f40` / `97b5b360`, ab_group `…42425d`,
armed 00:32:37Z / 00:34:15Z).** 0064 verified applied (`ottoq.ottoq_emit_vehicle_command`
post-md5 `05785c84…`, patch present, and it is the ONLY function of that name in any schema —
the unqualified call sites cannot resolve past it). Verdict: **4/20, first divergence sim-min
150.** Per the confound above this is NOT comparable to #17's 9/20: this pair ran ~45% more
commands.

**0064 fires, and the ledger shows it working mechanically.** The `stall.state_changed` diffs
carry the proof: contended stalls now reserve with `reservation_expires_at` **70 sim-minutes**
past `reserved_at` instead of the `ottoq_reserve_stall` default TTL of 600 s = 10 sim-minutes.
Since the confirm walk runs one tick (30 sim-min) after issue, the hold now genuinely outlives
the command it serves. That was the whole claim of 0064 and it is satisfied.

**0064's THROUGHPUT effect is unmeasured, and the reason is the confound, not a failure.**
Absolute numbers got worse (#18 arm A: 12 `begin_charge` executed vs 1,179 refused; arm B: 5 vs
1,277 — against #17's 22/832 and 14/918), but the load also rose ~45%, so the pairs cannot be
differenced. Measuring 0064 honestly needs one pinned-clock pair WITH it and one WITHOUT —
i.e. a deliberate temporary revert as an experiment. That is a founder call, not a unilateral one.

**Two NEW findings, both product bugs, both found by reading the source rather than the verdict.**

1. **The engine emits every `begin_charge` TWICE.** `public.ottoq_decide_tick` line 268 and line
   323 sit inside the SAME `IF ottoq_reserve_stall(…) THEN` branch and both
   `PERFORM …ottoq_emit_vehicle_command(…, 'begin_charge', …)` for the same vehicle, same stall,
   same tick — differing only in payload (line 268 carries `new_state`, line 323 carries
   `requested_kw`). The data confirms the lockstep exactly: in `da724f40`, 589 refusals on the
   `new_state` variant and 584 on the `requested_kw` variant. Every stall enactment therefore
   costs two commands, and the pair is byte-tied on (vehicle, `issued_at`, `command_type`,
   `stall_id`) — **this is the source of the genuine duplicate rows that broke the supersede
   ordering in #16 and forced 0062.** The duplicate is a defect in its own right; it also
   roughly doubles every refusal count quoted in these records.

2. **The depot livelocks on reservations, not on cars.** In `da724f40` the 1,173
   `target_occupied` refusals span only **131 distinct (vehicle, stall) pairs over 17 ticks** —
   ~9 refusals per pair, the same vehicles re-proposing the same stalls tick after tick and being
   refused every time. Forty stalls are involved: **all 10 DCFC plus 30 L2**, and not one of them
   ever seated a single command in the whole run (`proceed_to_stall` against them was refused 51
   times too; zero executions). On those stalls the event stream carries **137 `reserved_by`
   changes against 23 `current_vehicle_id` changes** — reservation churn outruns physical
   occupancy 6:1 — and an as-of reconstruction of the confirm-time state attributes **291
   refusals to another vehicle's LIVE reservation versus 50 to another car physically present**
   (the remaining 832 the reconstruction cannot place, because `occurred_at` ordering does not
   resolve within-tick sequence; the 6:1 ratio is the robust part). The stalls are locked to
   vehicles that never arrive.

   **The open question this raises about 0064.** 0064 lengthened exactly those locks, 10 → 70
   sim-minutes. A hold that outlives its command is right; a hold that outlives a vehicle which
   never shows up is a stall taken out of service for over an hour. The hypothesis for #19 is
   that 0064 fixed the race it aimed at and deepened the livelock beside it, and the honest test
   is the pinned-clock A/B above. **Stated as a hypothesis, not a finding** — the confound
   forbids concluding it from #18's numbers.

Re-certification #19 waits on the pinned-clock harness change; determinism work is not the
bottleneck here — the reservation-lifetime policy is.

**Re-certification #17 (post-0063, 2026-08-20; arms `ead7911f` / `35a907e7`, ab_group `…42425c`,
armed 22:40:26Z / 22:42:23Z).** 0063 verified applied (post-md5s `92fdb5e9…` / `30174e9f…`).
Verdict: **9/20, first divergence sim-min 300** — 0063 did NOT close the cert.

**The ordering-totality work is nonetheless DONE, and this round is what proves it.** The first
96 reservation events are IDENTICAL across the two arms, and vehicles receive their reservations
in the SAME ORDER in both; only the stall each one lands on differs, shifted by one. That is no
longer an ordering defect — every cursor and window in the path now has a total, run-stable key
(0050, 0054, 0059, 0062, 0063). What remains is **availability at one instant**: the two arms
disagree about which stalls are free at the moment the walk runs, not about who goes first.

**The root cause, found here and fixed by 0064: a hold could expire between the tick that ISSUES
a stall command and the tick that CONFIRMS it.** Vehicle `02734f04`, DCFC stall `906cbfff`:
reserved at sim-min 210 with a 600 s (10 sim-min) TTL, expiring 280; `begin_charge` issued at
270; hold expired at 280; at tick 300 the reassignment path and the confirm walk raced. Arm B
seated the vehicle (charged 32→90); arm A had already reassigned the stall and refused both
`begin_charge` rows `target_occupied`. The boundary case is systemic, not a one-off: **66 of 271
holds (arm A) and 64 of 257 (arm B) expired EXACTLY on a tick boundary**, because the TTLs are
exact multiples or halves of the 1,800 sim-second tick.

**This is a product bug, not a test artifact,** and the cost on this pair (fleet of 100) is the
depot-throughput collapse the founder saw in the 3D view before the ledger confirmed it: arm A
819 `begin_charge` refused `target_occupied` against 22 executed, 34 vehicles parked in staging,
80 of 100 hitting a stolen-stall refusal, and only 2 of 22 sessions on DCFC (the rest fell back
to L2); arm B 909 against 14, 23 parked, 86 of 100. In production this is a charger given away
while the vehicle is already under instruction to take it. → 0064.

**The robotic arms are a RENDERER bug; the engine is correct.** Chased in the same round because
the founder reported arms activating without extending. `twin.ottoq_sim_start_charge_session`
gates `twin.ottoq_arm_begin_cycle(… 'mate' …)` on `stall_type = 'dcfc'` — deliberate, and
documented in-code. Measured: arms fire on **100% of DCFC sessions** (arm A 2→2, arm B 5→5) and
**0% of L2** (A 20→0, B 9→0). The engine starts exactly the arm cycles it should. The 3D layer
in `ottoyarddepot-sim` animates an arm for L2 sessions where the engine correctly starts none.
**Open, unticketed, belongs to depot-sim — do not change the engine gate to satisfy the
renderer.**

**A negative result worth recording, because it saved a 20-site migration.** The ~20
`ORDER BY vn.created_at DESC LIMIT 1` picks over `ottoq_visit_needs` were left alone: the data
shows **zero** `(vehicle_id, created_at)` tie groups across both arms, so those picks are already
effectively total. Migrating 20 call sites on a hypothesis the data refutes would be churn, not
a fix.

**Re-certification #16 (post-0061, 2026-08-20; arms `2010f408` / `c507bce2`, ab_group
`…42425b`; two earlier arms discarded for metronome contamination — see the harness lessons
below).** 0061 verified applied (post-md5 `1b88f383…`, sim-domain fallback present). Verdict:
**11/20, first divergence sim-min 360**. This is NOT a regression against #15's 19/20:
the two pairs started at different sim times, so they exercise different scenario slices and
`ticks_identical` is a diagnostic, not a score. Both are FAIL; what matters is the residue.

Residue: exactly ONE vehicle, `1520dd3c` — `arrived_at_gate` in A, `charging_dcfc` on stall
`fc5d1dab` in B, SoC 32.0 in both. The vehicle-state stream shows arm B carrying one EXTRA
transition with everything after it shifted by one (245 vs 246 transitions), so this is a
**membership difference in a capacity-gated admission**, not an ordering difference.

Ruled out this round, each by measurement: real-clock reads on the gate/stall/cooldown path
(swept `now()`/`clock_timestamp()` across assign_tick/gate/admit/place_unplaced/
book_appointment/stall_free/reserve_stall/cooldown — only `cuopt_log_gate`, logging only);
explicit `last_state_change = now()` writers (only `ottoq_benchmark_reset`,
`ottoq_sim_release_depot`, `ottoq_tick_invariance_reset_fleet`, `twin.ottoq_sim_seed_fleet` —
all reset/seed paths, and their stamp is run-relative-consistent because each arm's sim clock
is anchored to its own real start, so `sim_clock − last_state_change = 30·k` identically in
both arms); cuOpt (quiesced, 20 `policy_disabled` + 8 `first_refusal_arm` per arm, identical);
and the twin auto-assigner — there is **no `twin.auto_charge_assign` event for this vehicle in
either arm**, so the seating came from the ENGINE's command path, not the twin's assigner.
`ottoq_benchmark_reset` was also confirmed to clear `stalls.current_vehicle_id`, so both arms
start with identical physical occupancy.

**What the ledger actually shows.** In BOTH arms stall `fc5d1dab` was first reserved for
`1520dd3c`. In arm B the vehicle was seated (`available→occupied`), charged 32→90, and
released. In arm A no occupancy event ever fired: the reservation churned onward to five other
vehicles (`14b02ad9`, `03812c6f`, `ad5abf3e`, `55a6bddc`, `983002e6`) before the vehicle could
be seated, and its `begin_charge` commands were refused `target_occupied`. **The open question
for #17 is therefore the reservation-churn path, upstream of the confirm walk** — not the
assigner and not the confirm cursor.

**A defect of our own, found en route → 0062.** 0060 replaced the supersede window's
`command_id DESC` tiebreak with content keys `(command_type, stall_id)` because `command_id`
is `gen_random_uuid()`. The reasoning was right; the replacement was not. Content keys do not
uniquely identify a row, and the data contains genuine duplicates — this very vehicle has TWO
`begin_charge` rows sharing vehicle, `issued_at`, `command_type` AND `stall_id` (arm A refused
both `target_occupied`; arm B retired one `superseded` and executed the other). For such a pair
the 0060 ordering is fully tied, so `dup_rn` — which decides which command counts as current
intent — fell back to physical row order. **0060 turned "random but TOTAL" into "no total order
at all," which is strictly worse.** 0062 restores totality: content keys still dominate,
`payload::text` separates commands differing anywhere in payload, and `command_id` survives
only as the last-resort tiebreak between byte-identical rows, for which the choice is
interchangeable by construction. 0062 is a repair, and is **not** claimed to be the cause of
#16's divergence.

**Harness lessons (procedural, recorded so they stop costing rounds).**
1. The window between `ottoq_cert_arm_start` and the shield UPDATE is the contamination risk;
   under a flaky proxy two arms were lost this round to stray metronome ticks landing in that gap.
2. The tempting atomic form **does not work**:
   `WITH armed AS (SELECT ottoq_cert_arm_start(…)) UPDATE ottoq_sim_runs … FROM armed` returns
   zero rows, because the run row the CTE's function inserts is not visible to the same
   statement's UPDATE. Shield **by predicate** instead — `UPDATE … WHERE status='running' AND
   depot_id='2222…'  RETURNING sim_run_id, tick_count` — which needs no id round-trip and was
   the form that finally worked.
3. BAND RULE: compute `min_to_midnight = 1440 − (UTC hour·60 + minute)`; both arms must share
   `floor(min_to_midnight / 30)` and sit ≥2 min inside the band. 18:30:00 exactly (offset 330)
   is ON the edge — never arm there.
4. The MCP tool timeout is 60 s, so never `pg_sleep` more than ~45 s.
5. On a step timeout, check `tick_count` AND `pg_stat_activity` for an active
   `ottoq_cert_arm_step` before re-issuing — the batch may have landed.

Re-certification #17 runs after 0062 is applied and targets the reservation-churn path.

**Reservation-churn follow-up (read-only, same evidence) → 0063.** Chasing #16's open question
without waiting on a cert produced the answer. Ruled out first, by measurement:
`public.ottoq_reserve_stall` is correctly guarded (it overwrites only when the stall is
physically free AND unreserved | same-vehicle | expired) and **every one of its ~20 call sites
passes the SIM clock**, never `now()` — so its `reservation_expires_at <= p_now` test never
crosses clock domains. The ~20 `ORDER BY vn.created_at DESC LIMIT 1` picks over
`ottoq_visit_needs` look like the same tie-prone class, but across both #16 arms there are
**zero** `(vehicle_id, created_at)` tie groups — so those sites are effectively total and are
deliberately left alone. **The negative result mattered: it stopped a 20-site migration that
the data refutes.**

The real seam is one table over. `ottoq_stall_bookings.booked_at` defaults to `now()` — one
real-clock value per statement — and the same two arms hold **261 `(vehicle_id, booked_at)` tie
groups, the largest with 15 bookings**. Two functions pick a single row out of exactly that tie
with `ORDER BY b.booked_at DESC LIMIT 1`, and `booking_id` is `gen_random_uuid()`, so nothing
run-stable remains: `ottoq.ottoq_enact_space_assignment` (which picks the PREFERRED STALL and
calls `ottoq_reserve_stall` on it on the very next line — the churn seam itself) and
`ottoq.ottoq_record_enacted_booking` (which picks which forward reservation to adopt rather than
duplicate). **0063** applies the 0062 principle: `booked_at DESC` stays dominant, ties break on
the booking window, stall and purpose, and `booking_id` goes last so the order is total.


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
