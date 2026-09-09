# What the engine actually decides — the measured inventory

Chase, 2026-09-09: *"I'll also want a bullet list of the exact items or sequences
the deterministic core and the agent layer is either solving for or proposing …
This is more of just an architecture question to make sure we are capturing
what's needed, and our engine operates and orchestrates to the depth or in the
manner that it should."*

This is the answer, and it is an **inventory**, not a design document.
`docs/DECISION_BOUNDARY.md` says *where* a decision belongs; this says *which
decisions exist today*. Every row was read out of the live `otto-q-core`
database or the repo on **2026-09-09 between 12:50 and 13:05 UTC (7:50–8:05 AM CT)**
— catalog reads and function bodies, not memory and not an older document.

Where something is missing, it is in **§8 Gaps**. That section is the part of
this file worth arguing with.

---

## 1. The tick — the sequence, in the order it actually runs

Read from `public.ottoq_sim_decide_and_dispatch`, which is the entry point for
every certified run and every production tick. Sixteen steps. Steps 1–7 are the
**propose** half; step 8 is the **dispose**; steps 9–14 are reconciliation;
step 15 is the LLM orchestrator; step 16 is the receipt.

| # | step | what it solves for |
|---|---|---|
| 1 | `ottoq_inbound_forecast(depot, 60)` | who is coming back in the next 60 minutes, attached to the run payload before anyone plans |
| 2 | `ottoq_close_satisfied_charge_needs` | **a satisfied need is a done need.** Closes charge atoms on cars already at target *before* any planner can book a charger against them. Exists because run `c99e4435` sent nine vehicles to chargers with 0.00 kWh to deliver |
| 3 | `ottoq_reoptimize_reservation_book` | upgrade existing bookings to better stalls, under a per-vehicle cooldown (`reopt_cooldown_min`), a per-tick cap (`reopt_max_per_tick`) and a final-approach freeze (`reopt_min_eta_min`) |
| 4 | `ottoq_cuopt_refresh` *(conditional)* | fires the NVIDIA cuOpt proposer — but only when the dedicated fire beat's heartbeat is stale, because `net.http_post` cannot transmit until this transaction commits and a fire from here lands one tick late by construction |
| 5 | `ottoq_cuopt_first_refusal_arm` | holds a decide-beat arrival out of the greedy cursor for **exactly one tick** so the next fire beat can offer it to cuOpt. Right of first refusal, never veto; releases unconditionally next tick |
| 6 | `ottoq_l2_optimize_assignments` | the L2 tenant/SLA layer's assignment pass |
| 7 | `ottoq_service_priority_propose` | the in-tick service-priority proposer (1,904 proposals across 821 certification runs) |
| 8 | **`ottoq_decide_tick`** | **the disposer.** 82,688 characters. Everything in §3 |
| 9 | `ottoq_sim_auto_dispatch_tick` | redeployment — who leaves the depot this tick |
| 10 | `ottoq_itin_close_travel_legs` | close travel legs whose arrival has happened |
| 11 | `ottoq_sweep_stranded_deployments` | catch assets deployed but never accounted for (45-minute sweep) |
| 12 | `ottoq_release_expired_bookings` | return calendar space nobody showed up for |
| 13 | `ottoq_place_unplaced_vehicles` | anything physically present with no space assignment gets one |
| 14 | `ottoq.ottoq_react_to_refusals` | **work-side refusal is a first-class event.** A refused recall triggers a re-solve, not an error |
| 15 | orchestrator agent (Nemotron, edge function) | every 3rd tick **or** on `ottoq_orchestrator_trigger`. Quiesced entirely inside a certification (`run_by IN ('benchmark','cert_harness')`, benchmark depots, and `orchestrator_agent_enabled=0`) |
| 16 | `ottoq_record_event('twin.sim_tick_advanced')` | the signed receipt: decisions built, enacted, redeployed |

Steps 2, 3, 4, 5, 7, 10, 11, 12–14 and 15 are each wrapped so they **can never
abort the tick** — a proposer failure degrades the tick, it does not stop the
depot.

---

## 2. The L1 shield — what is scanned on every single action

29 active rules, 8 categories, every evaluation logged. This is the **constraint
set, not the policy**: it defines which actions are feasible, and it sits on the
hold-constant side of every A/B (CLAUDE.md C5 correction, `db/checks/0146`).

`enforcement` is one of `block` (the action cannot happen), `warn`, or
`log_only`.

### energy_safety — 5 rules
- `EN.001.grid_capacity_ceiling` — **safety_critical, block, depot scope.** The site power cap. Evaluated on `task_start`, `stall_assignment`, `charge_session_start`, `power_increase`
- `EN.002.stall_power_ceiling` — critical, block. Per-stall kW ceiling
- `EN.003.bess_limits` — **safety_critical, block.** BESS state-of-charge + thermal limits, on `bess_charge` / `bess_discharge` / `bess_dispatch`
- `EN.004.demand_response_compliance` — critical, block, depot scope. DR window compliance, with `allow_bess_offset=true`
- `EN.005.grid_event_hardstop` — **safety_critical, block.** A grid event stops task starts, charge starts and stall assignments outright

### hardware_safety — 3 rules
- `HW.001.connector_compatibility` — **safety_critical, block**, `strict=true`. Connector/inlet pairing
- `HW.002.charger_state_precondition` — critical, block. OCPP charger must be `Available` and seen within `max_offline_seconds=90`
- `HW.006.physical_presence_verification` — critical, block, on `task_completion`. **You cannot complete a task on a vehicle that is not physically there**

### concurrency — 2 rules
- `HW.004.stall_single_vehicle` — critical, block. One vehicle per stall (the software half; the EXCLUDE constraint on `ottoq_stall_bookings` is the physical half)
- `HW.005.vehicle_one_active_task` — critical, block. One active task per vehicle

### sensor_liveness — 1 rule
- `HW.003.sensor_liveness` — **safety_critical, block**, fleet-operator scope. SoC reading older than `max_stale_seconds=300` gates `task_start`, `task_completion` and `redeployment`. A stale sensor is not a usable sensor

### state_machine — 4 rules
- `SM.001` vehicle transition validity · `SM.002` task transition validity · `SM.003` stall transition validity · `SM.006` BESS transition validity. All critical, all block

### sla_contract — 7 rules (the per-OEM layer, `fleet_operator` scope, versioned per tenant)
- `SLA.001.min_soc_at_deployment` — critical, block. **No asset leaves below its operator's floor**
- `SLA.004.required_services_complete` — critical, block. Contracted services must be done before release
- `SLA.007.redeployment_readiness` — critical, block. The composite readiness gate
- `SLA.002.max_queue_depth` — warn. Per-operator queue depth
- `SLA.003.max_visit_duration` — warn. Visit overrun
- `SLA.006.maintenance_window` — warn. Maintenance-window restriction
- `SLA.005.oem_acceptance_timing` — log_only. OEM acceptance gate configuration

### time_window — 5 rules (depot scope)
- `TW.001.operational_hours` — warn · `TW.003.quiet_hours` — warn (noise) · `TW.005.shift_change_buffer` — warn, `buffer_minutes=15` · `TW.002.overnight_staging` — log_only, `threshold_minutes=120` · `TW.004.tariff_window` — log_only, `peak_start=14:00 / peak_end=20:00`

### role_authorization + audit_integrity — 2 rules
- `SM.004.role_gated_actions` — critical, block. Gates `tech_override`, `flag_abnormality`, `resolve_abnormality`, `oem_accept`, `oem_flag_midflow`, `emergency_stop`, `brain_pause`
- `SM.005.audit_note_required_on_overrides` — **critical, block**, `min_chars=3`. **You cannot override without saying why**

> **52 rows, 29 codes.** The other 23 rows are superseded versions of the same
> codes, kept because the rules layer is versioned and tenant-parameterizable.

---

## 3. What the disposer solves for, inside one tick

`ottoq_decide_tick`, read from its live body. Six ordered sections.

- **Booking lifecycle** — promote `held → active` for every booking whose vehicle
  has arrived; **honour or re-plan, never let it rot**; then the release sweep.
- **No bay entry without a booking** — entry and calendar are one act. A wash bay
  is claimed *and* booked in the same statement, or neither.
- **The in-depot move door** (`0011-TETHER`) — a vehicle mechanically tethered to
  a charge arm cannot be moved. The tether phase is part of the world hash
  (`0243`).
- **Space assignment**, ranked by an explicit, seed-stable key:
  1. `fits_window DESC` — do not burn a scarce bay on work that will not finish
  2. `minutes_to_deploy ASC` — **earliest deadline first (EDF)**
  3. `open_must_do_min ASC` — **shortest job first**, so a scarce bay clears
  4. `vehicle_id` — deterministic tiebreak
- **Charge first** (full-service visit doctrine): if energy is still a `must_do`,
  the charge leg is the anchor. **Unfinished work outranks fresh work.**
- **Anti-starvation budget** (`0003`) — a bounded exception so a vehicle that
  keeps losing the ranking cannot lose forever.
- **Separate staff pools** — charging capped by `charging_staff`, wash by its own
  pool. Staff is a resource, not an assumption.
- **The space map is data** — read from `service_cadence_policy.lane`, never
  hardcoded, and it is TOTAL (every operation maps to a lane).
- **Shield blocks ⇒ take NO space.** A vehicle the L1 shield refuses stays in
  staging. It does not get a degraded assignment.

Every disposal lands in `ottoq_decisions` with one of ten outcomes:

`enacted` · `overridden_to_default` · `deferred_noop` · `errored` ·
`noop_no_candidate` · `shield_disarmed` · `deferred_stale_entity` ·
`context_insufficient` · `deferred_site_power_cap` · `deferred_tick_budget`

…and a gate of `A` or `B`. **Four of those ten are refusals with a named reason**
— which is the point: the engine records why it did *not* act.

---

## 4. The proposer layer — who proposes, and what

Three registered proposers in `ottoq_certified_proposers`, plus two out-of-band
planners. **No proposer writes a final assignment** (CLAUDE.md rule 6).

| proposer | proposes | volume (at registration, `0241`) |
|---|---|---|
| `greedy_constrained` | stall assignments — the local deterministic proposer | 12,403 proposals / 542 cert runs since 2026-08-29 |
| `ottoq_service_priority` | which service to do next, from inside the certified tick | 1,904 proposals / 821 cert runs |
| `cuopt` | NVIDIA cuOpt's assignment plan, over the approach window | 1 proposal / 1 cert run — it is **quiesced inside every certification** by `cuopt_propose_enabled=0` |
| energy MPC bridge (`ottoq-energy-mpc`) | BESS setpoints; followed only when `energy_mpc_follow=1` | out-of-band |
| orchestrator agent (Nemotron edge fn) | depot-level orchestration intents | every 3rd tick, quiesced in certs |

**The contract that makes this safe:** every proposal stream is hashed into the
certification verdict as `h_prop`, and every deferral as `h_defr`. A proposer
cannot introduce nondeterminism into the disposed path without a pair going red.
cuOpt's own right-of-first-refusal is capped at `cuopt_first_refusal_max_defers`
(default 1) per vehicle per run and releases unconditionally — first refusal,
never veto.

### What the agent layer optimizes for — the commander's intent

`intent/intent_v1.json`, fingerprint `a2214eeaf222514dba85f55dd9323e08`,
generated 2026-09-06. **Eleven objectives, resolved lexicographically — never
summed into one dollar scale**, because (R-10) no robotaxi operator has published
a dollar value for a late minute, and a weight would be a price on lateness
nobody agreed to.

Two are **floors**, not objectives:
- `readiness` — `tardy_minutes` past required-ready. A floor
- `service_completion` — wash/tire/brake/software/inspection completion rate. A floor

Nine are objectives, each carrying whether its dollar value is `sourced` or
`NOT_FOUND`:
- `energy_cost` (**sourced** — NES GSA-3 demand charge $21.40/kW first 1,000 kW)
- `bess_peak_shave` (**sourced** — 500 kWh BESS shaving 200 kW ≈ $48–60k/yr)
- `degradation` (**sourced** — Wikner & Thiringer 2018; JRSE/IEEE 2024)
- `staff` (**sourced** — Rocsys 2026, ~$1.7M/yr per 50-bay depot)
- `risk_hedge` (**sourced** — ETH Zurich 2026, <0.1% cost for 10% deviation cover)
- `throughput`, `dwell`, `deadhead`, `staging` (all **NOT_FOUND** — and labelled
  so, rather than given an invented weight)

### Six regimes — the agent's situational pass order

| regime | fires on | priority order |
|---|---|---|
| `weather_event` | `weather_hold` signal | readiness → service_completion → risk_hedge → degradation |
| `grid_peak` | `grid_peak_imminent` | bess_peak_shave → energy_cost → risk_hedge → degradation |
| `demand_surge` | `demand_surge` | readiness → throughput → deadhead → staging |
| `dispatch_rush` | hours 05–10 | readiness → throughput → deadhead → energy_cost |
| `overnight` | hours 20–05 | service_completion → energy_cost → degradation → dwell |
| `steady_state` | default | readiness → service_completion → energy_cost → degradation → throughput → deadhead → staff → dwell → staging → bess_peak_shave → risk_hedge |

**Three signals** raise those regimes, and each is derived, not asserted:
`demand_surge` (nowcast arrivals ≥ `surge_multiplier` × the *same window's*
climatological baseline), `grid_peak_imminent` (max p90 site load over the
window ≥ `peak_fraction` × site power target), and `weather_hold` (passed through
from an external feed — explicitly *not* derivable from the statistical forecast).

---

## 5. The Recall Decision — the one touchpoint with the work side

`naive_threshold_v1` (`impl_id=1`), deliberately naive and documented as naive:
fixed thresholds, top-down, first hit wins. **Eleven rungs.** `is_deferrable`
says whether the work side may refuse; `lead_ticks` is how far ahead it asks.

| rung | trigger | urgency | deferrable | lead |
|---|---|---|---|---|
| 0 | `critical_reserve` | critical | no | 0 |
| 1 | `fault_safety_critical` | critical | no | 0 |
| 2 | `fault_major` | urgent | no | 1 |
| 3 | `low_soc_reserve` | urgent | no | 1 |
| 4 | `rider_flag_cleaning` | urgent | no | 0 |
| 4 | `service_interval_due` | routine | **yes** | 2 |
| 5 | `sensor_soil` | routine | **yes** | 1 |
| 6 | `overnight_prestage` | scheduled | **yes** | 1 |
| 7 | `wash_cadence` | routine | **yes** | 2 |
| 8 | `comms_stale` | urgent | no | 0 |
| 9 | `timer_backstop` | anomaly | no | 0 |
| 10 | *(no recall)* | none | — | — |

A second implementation, `fixed_window_dummy` (`impl_id=2`, PARKED), exists only
to prove the swap: selecting it is a policy write, **zero call sites change**.

The work side may refuse a deferrable recall with one of five reason codes —
`mission_overrun`, `passenger_onboard`, `safety_hold`, `operator_override`,
`unreachable` — plus a `retry_after_min` bounded to `(0, 720]`. The refusal is
recorded, holds for `work_side_refusal_hold_min`, and **triggers a re-solve**
(tick step 14). In the twin the refusal rate is drawn from the run's CRN stream,
so a refusal is reproducible.

**Two observations, stated rather than fixed:** `rung 4` is used by two triggers
of different urgency (`rider_flag_cleaning`/urgent and `service_interval_due`/routine).
Ordering is by code position, first hit wins, so the rung number is a label and
not the ordering key — but a duplicate label in a ladder is worth a second look.
And the ladder has no forecasting, no cost model and no learning, by design:
every smarter successor has this baseline to beat on the same ledger.

---

## 6. Energy — what is commanded, and where the boundary is

Five command types in `ottoq_energy_commands`: `charge_cap_kw`,
`bess_setpoint_kw`, `load_shed`, `tou_shift`, `clear`. Status is one of
`pending`, `executed`, `superseded`, `failed`.

The decisions behind them:
- peak-shave vs. autopilot (`energy_orchestration_enabled`)
- demand target: fixed `service_max × factor`, or the **causal water-fill reserve
  target** (`energy_reserve_shave`), with separate factors for cheap and
  expensive wholesale power
- whether to follow the MPC's BESS setpoint or the built-in heuristic
  (`energy_mpc_follow`)
- what to do when the wanted charge type will not fit site headroom
  (`charge_downgrade_policy`: wait, or take the lesser charger)

**The boundary holds:** OTTO-Q publishes forward demand, it does not issue
real-time setpoints to physical inverters. The MPC bridge is a planning input
inside the twin.

---

## 7. The tuning surface

**65 parameters** in `ottoq_policy_param_catalog`, every one documented in-place
and resolvable per run. By prefix: **OTTO-CHARGE ARM 24** · cuOpt 5 · energy 5 ·
deploy/release 4 · reservation re-optimizer 3 · recall 3 · and 21 others
(approach band, in-depot reassignment, the occupied-stall oracle, work-side
refusal, staffing and bay share, fault handling, wash cadence).

The arm block — more than a third of the whole tuning surface — is worth naming because it is the physical layer modelled honestly:
mate is five phases (`unstow → approach → align → insert → latch`), demate is
three (`unlatch → extract → retract`), **no current flows before latch completes**,
and the model separates TRUE pose (where the car actually stopped —
`robotic_park_lateral_sigma_mm`, vertical, yaw) from BELIEVED pose (what the arm
thinks it sees — `robotic_fiducial_sigma_mm` when the marker is detected,
`robotic_uwb_sigma_mm` when it is not) from the TOLERANCE ENVELOPE (what the
connector can actually capture) from the RE-STAGE BOUNDARY (beyond which the car
must be re-parked). Registration error inside tolerance on all three axes is a
successful mate; outside it is a retry with `robotic_retry_sigma_shrink` applied,
up to `robotic_mate_retry_max`, then the cycle is declared failed.

---

## 8. Gaps — what is NOT decided today, and should be

This is the section Chase asked for. Each is stated as a capability the engine
does not currently have, with what it would take.

1. **No forward power schedule is published.** §6 commands the present; nothing
   emits the ServiceProfile (the smart-charging-profile-shaped forward schedule)
   that CLAUDE.md 2.6 names as the publication boundary. Tracked as **G9**. This
   is the single largest gap between what the engine decides and what a site
   controller or vendor EMS could consume.
2. **No outbound command lifecycle.** Commands are written; there is no lease,
   ack, retry, TTL or dead-letter. A command that is never acted on is
   indistinguishable from one that was. Tracked as **G8**.
3. **The recall ladder has no cost model and no forecast input.** It reads SoC,
   faults, comms age and cadence timers — it does not read the site forecast it
   is handed, or price windows, or predicted congestion. The 2.7 interface takes
   `site: SiteForecast`; `naive_threshold_v1` largely does not use it. That is
   the deliberate baseline, but it is also the most obvious place intelligence
   would pay.
4. **`deadhead` is an objective with no decision behind it.** Inter-point moves
   are modelled as operations with duration, but nothing in the disposer
   minimizes empty moves; the ranking key has no move-cost term.
5. **`staging` likewise.** It appears in the lexicographic order and in the
   regime priorities; no tick step optimizes staging footprint.
6. **Calibration priors sit outside the reproducibility key.** The weekly ingest
   can refit them mid-round. Tracked as **G14** — this is a *correctness* gap in
   the certification, not just a feature gap.
7. **Cross-operator settlement does not exist.** SDRs are emitted (§ moat layer
   L2 partial), but there is no settlement flow between operators and no
   per-(asset_class, operation, operator, window) service tariff.
8. **The A/B instrument is empty.** `ottoq_ab_runs` has 68 rows, one policy, one
   seed, and no function anywhere writes it (`db/checks/0145`). The CRN engine
   exists — `ottoq_determinism_pair` is one — but nothing yet scores two
   *different policies* on an identical world. Until that lands, "OTTO-Q beats
   greedy" is not a claim we can make with a run ID.
9. **The baselines do not pay the shield** (`db/checks/0146`). `ottoq_fifo_tick`,
   `ottoq_greedy_tick` and `ottoq_baseline_fifo` evaluate **no rules at all**, and
   three of them never touch the calendar. Any comparison run today would let
   greedy win on throughput because it checks nothing. The shield must move to
   the hold-constant side of the A/B before a single comparison number ships.
10. **Production and the proof harness share one database.** Tracked as **G26** —
    the root cause behind G43, and still open.

---

*Every figure in this file was read from the live database or the repo on
2026-09-09 12:50–13:05 UTC. Row counts move; the structures do not. Re-measure
before quoting — the queries are one `SELECT` each, and `CLAUDE.md` Part 3's
refresh history is what happens when you don't.*
