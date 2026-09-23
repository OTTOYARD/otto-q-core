# OTTO-Q engine review — ranked findings, 2026-09-22

**Scope.** The agentic layer through to dispatch, the solvers, the deterministic core, and the learning
loop. Everything is measured on the twin depot `11111111-…` only (CLAUDE.md rule 8).

**Ranking.** Findings are ranked by impact per engineering hour, and fixes ship in that order. Each fix
is validated on a fresh twin run and in the cockpit's 2D/3D view before it is called done.

**How to read a number here.** Every figure carries the run or query it came from. A figure from a
purged run is marked as recorded in its check file, where the SQL that produced it lives.

---

## Shipped in this session

| # | Finding | Evidence | Fix | State |
|---|---|---|---|---|
| S1 | **The orchestrator agent was setting the work side's demand — the curve its own run is judged against — from a board that misreported it.** On `0682752c` the board said `deploy_peak_fraction = 0.90`; the dispatcher used busy_day's 0.45. The agent's first move was 0.95 (doubling the peak target). It then asked for 0.35–0.45 on 96 of 106 writes, every one clamped to the 0.50 floor, and it was never told. **All 312 stored rows of that dial were agent-written.** Riding along with it: 71%/68% of energy-dial changes reversed the previous one; v18's drift limiter never ran on two of its six dials; the ops path reported refusals as `applied`; `ottoq_dial_clamp` reads `agent_writable` and ignores it. | [`db/checks/0352`](../db/checks/0352_the_agent_rewrote_the_demand_it_is_measured_against_because_its_board_showed_the_wrong_value.sql) | [`0432`](../db/migrations/0432_the_agent_could_rewrite_the_simulated_demand_it_is_measured_against_and_could_not_see_its_own_clamps.sql) (applied `20260922231738`) + edge function v19 | Applied. Live proof in progress on `7a42982a` (below). |
| S2 | **A quarter of departures left without the readiness check.** 24 of 93 on `0682752c`, 26 of 106 on `6a8a7029`. The cause is tick order: the check completes at world-advance call 1, and only for `staged_for_departure`. Staging happens at call 15 and dispatch at call 27, so a vehicle staged and released in the same tick never met it. | [`db/checks/0351`](../db/checks/0351_a_quarter_of_departures_leave_without_the_readiness_check_and_the_tick_order_is_why.sql) | [`0431`](../db/migrations/0431_a_quarter_of_departures_skipped_the_readiness_check_because_it_runs_before_the_vehicle_is_staged.sql) (applied `20260922224038`) | Applied, recertified. Live proof in progress. |
| S3 | **The agent never saw the per-asset view built for it.** 0350's asset block (SoC distribution, DCFC interlocks with their causes, deadlines, a named attention list) had **one** run-scoped row in its life. Every demo run since 09-19 planned charging from counts, blind to the 18–20 DCFC-blocked vehicles. | `0352` §1, `0432` §1 | `0432` (G): the arm switches it on | Shipped. The agent names specific vehicles on its first pass. |
| S4 | **Cockpit fidelity** — traffic, a wait-loop deadlock, and a 3× motion cap. | sim repo | OTTOYARD/ottoyarddepot-sim#105, #106, #107 | Merged. |

### Live proof so far, run `7a42982a` (busy_day, same seed as `0682752c`, started 6:22 PM CT)

**First 8 agent passes:**
- all 8 grounded and carrying the asset block;
- **0 proposed writes to the demand dial, 0 agent rows on it**;
- 8 of 8 solver handoffs completed;
- the drift limiter now runs on `deploy_surge_catchup` and `forecast_horizon_min` (`limited_by: drift`).

**Departures:** 0 of the first 4 left without the readiness check.

**Cockpit:** in 2D and 3D, 115 cars, 13.7% of taxi time stopped, zero stuck. It renders the backend's counts.

The end-of-run numbers are recorded in `db/checks/0353` when the run completes.

### What v19's disposer does to `0682752c`'s own request stream

This replays the stream offline, counting reversals change-to-change. It is counterfactual: under v19
the agent sees its rejections and would have asked for different things.

| dial | v18 changes | v18 reversals | v19 changes | v19 reversals |
|---|---|---|---|---|
| `energy_demand_factor_peak` | 123 | 84% | 23 | 45% |
| `energy_demand_factor_expensive` | 76 | 80% | 19 | 39% |

---

## Open, in the order they will ship

| Rank | Finding | Evidence | Proposed fix | Est. |
|---|---|---|---|---|
| **1** | **Demand response: the number the generator samples as a *reduction* is read everywhere as an absolute *ceiling*, and the charge gate ignores the battery.** `twin.ottoq_sim_maybe_ignite_dr_call` samples `50 + U·350` with the comment *"required load cap (50-400 kW reduction)"* and stores it in `required_load_cap_kw`. `ottoq_effective_charge_cap_kw` then computes `LEAST(service_max_kw = 2500, that number)`. So a call asking the depot to shed ~205 kW caps **all EV charging** at ~205 kW for 90–240 minutes, on a program named `TVA_VOLUNTARY`. `ottoq_decide_tick` refuses any charge that takes committed EV kW over that cap (`deferred_site_power_cap`), counting no battery, solar or building load. Meanwhile `ottoq_energy_orchestrate` lowers its *grid* target to the same number and discharges the battery to meet it — so the two disagree, and new charges are refused while the battery has load it could cover. The BESS-aware rule written for this, `EN.004` (`allow_bess_offset` default true, remedy `engage_bess_or_defer`), reads `ottoq_grid_events`, which has **never held a `demand_response_called` row**: the mirror `ottoq_mirror_dr_call` exists and nothing calls it. The ignition probability on a hot afternoon (≥32 °C, 14:00–19:00 CT) is ≥3% **per tick**. The roll's seed carries the run-relative sim clock, so it is redrawn every tick. That hazard is per tick rather than per sim-hour, G130's defect class:
- at the demo cadence (~0.5 sim-min per tick), a call ignites within minutes of 14:00 on a hot day, and again as soon as one expires;
- at the cert cadence (30 sim-min per tick), the same five-hour window has about 26% odds (0.97¹⁰).

So the canon and the demo see different DR worlds. | Source, verified today: the generator, `ottoq_effective_charge_cap_kw`, the 0132 gate in `ottoq_decide_tick`, `ottoq_energy_orchestrate`, `EN.004`. **Cost not yet measured** — `0682752c`'s rows were purged and the current run ends before 14:00 sim. | (a) Generator records the reduction and a prior-hour baseline; the cap becomes `baseline − reduction`. (b) The gate admits EV kW up to `cap − building + solar + sustainable BESS discharge` for the call's remaining minutes, which is what the orchestrator already assumes. (c) Wire the mirror so `EN.004` sees the calls, only once (b) makes it and the gate agree. Recert required. | 4–6 h |
| **1b** | **The battery is spent flattening cheap morning load and is near its floor before the expensive afternoon (G169).** The reserve water-fill (`ottoq_bess_reserve_target`, switched on by the agent) looks 8 hours ahead, so at 04:00 CT it cannot see the 13:00–20:00 on-peak window. Run `7a42982a`: SoC 94.7% → 43.2% by 08:04 CT, discharging 349 kW at 05:00 (off-peak, $0.052/kWh) and 495 kW at 06:00. The depot's tariff (NES GSA-3: $21.40/kW on the monthly 30-minute peak, any hour) rewards cutting the day's *max*, which a myopic horizon cannot find; on-peak energy is 3–4.5× dearer. It also defeats rank 1's fix: an empty battery credits nothing during a 2 PM DR call. | `site_energy_snapshots` on `7a42982a`; `ottoq_depot_tariffs` (sourced: NES GSA-123 PDF, retrieved 2026-07-09) | **Drafted as [`0435`](../db/migrations/0435_the_battery_planned_eight_hours_ahead_on_a_forecast_where_charging_stops_and_was_empty_before_the_expensive_afternoon.sql)** (forces_recert FALSE, dry-run passed on the live run). It is a day-length plan re-solved every tick: 30-min steps to local midnight, a demand-charge vs TOU-price allocation above the billed peak, and a 600 kWh DR reserve released 14:00–20:00. The forecast half was worse than the horizon: EV load was assumed to stop when today's sessions end, so the water-fill aimed the grid at 125–262 kW against ~700 kW of real charging. Two defects found on the way: G172 (efficiency units) and G171 (the twin's temperature peaks at 20:00, fixed by [`0436`](../db/migrations/0436_the_twins_afternoon_peaked_at_eight_pm_because_a_sine_was_written_where_its_comment_meant_a_cosine.sql)). | 3–5 h |
| **1c** | **The primary solver changes nothing (G167).** On `7a42982a`'s first 3.7 sim-hours, CP-SAT `forward_lex` (rank 0) enacted **0 of 179** proposals. 170 are abstentions whose own rationale is *"planned to start at +N min … beyond this tick's 30-min window"* (`bridge:not_due`): a 30-minute due window, which is the cert cadence, while a demo tick advances ~0.3–0.5 sim-min. The 9 due proposals lost to stale frames. Every agent→solver handoff reads `completed`, yet nothing the primary solver planned was enacted. | `ottoq_proposal_disposition_ledger` + proposal rationales | **Re-diagnosed 2026-09-23 (G173):** the solver's hard power cap is the energy orchestrator's advisory cap, and while the water-fill shaved it equalled the EV load already running — 16 kW of headroom on average over 811 ticks. So every new charge had to wait for one to end, which is the "+N min" the abstentions report. 0435's plan mode lifts the level; re-measure enactments on the validation run **before** touching the due window. | 0 h beyond 0435; then measure |
| **2** | **The learning loop cannot learn: every cell with enough runs has one dial set, and every run with a different dial set is a cell of one.** Twin depot, `ottoq_run_dial_ledger` (evidence class): 172 rows across 35 cells. The 166 cert rows fill 12 cells of ≥6 runs, each holding exactly **one** dial set, so there is no contrast. The 6 agentic demo runs each sit in a cell of their own, because the cell key includes `sim_min_per_tick` — a continuous value derived from wall-clock pacing (0.3002…, 1.5464…, 0.1047…), different on every live run — and the promoter needs ≥6 runs per cell. The demo runs' dials are also a trajectory the agent moved mid-run, not a treatment, so even pooled they would attribute reward to end-state dials. | `ottoq_run_dial_ledger`, measured today | Learn from designed contrasts, not from observation. Give the determinism pair a `p_dials` override (C5's "give the pair rig a `p_policy`"), run treatment-vs-incumbent arms under CRN at a fixed cadence, and have the promoter read pairs. Bucket the cadence key. | 6–10 h |
| **3** | **(drafted: [`0434`](../db/migrations/0434_three_consumers_of_the_deploy_demand_defaulted_it_three_ways_and_one_saw_double.sql)) The three consumers of `deploy_peak_fraction` default differently when nothing overrides it.** Measured on `7a42982a`: service_flow's target was exactly 2× the dispatcher's at every hour, fast-tracking 85 vehicles past optional services in three sim-hours. The dispatcher uses the scenario's value, else 0.90; `ottoq_decide_tick` uses the scenario's value, else 0.55; `twin.ottoq_sim_advance_service_flow`'s deploy-pressure check uses a fixed 0.90. On busy_day the first two agree (0.45) and service_flow reads **twice the demand**. The agent's tick-1 write used to paper over this; since 0432 it no longer does. | source, `0432` §4.1 | One resolver function used by all three. Recert. | 1–2 h |
| **4** | **`vehicle_need_profile` is shared across runs.** `ottoq_run_boot_draw` re-seeds it per run, so a certification sweep during a demo run overwrites the demo's profiles with the canon's. Measured after tonight's sweep: 107 of 116 twin profiles carry `next_deploy_at` on 2026-09-01, the canon start date. The asset block's deadline pressure is right during a live run and wrong after any sweep. | measured today | Run-scope the profile (key on `sim_run_id`), or snapshot it at boot and read the snapshot. | 2–4 h |
| **5** | **(superseded by G175, fixed in `0438` + v20) The agent reads `deploy_surge_catchup` as a service-backlog lever — and nothing reads the dial at all.** Neither does anything read `forecast_horizon_min`, and the two energy factors are dead while the agent's own reserve switch is on (G174). So one of five dials was live on `7a42982a`. Its first v19 pass raised it "to clear the 67-vehicle service backlog" while deployed (4) was already above target (3), where the dial does nothing. | `7a42982a` tick 1 decision | Publish `deploy_gap = target − deployed` in grounding and say in the prompt that the dial acts only on a positive gap. | 0.5 h |
| 5b | **The readiness check can still be skipped by the `staged_awaiting_service` door (G170)** — the dispatcher admits `svc_step='ready'` vehicles there, and the check only runs in `staged_for_departure`. 1 of 79 on `7a42982a`, against 24.5–25.8% before 0431. | `ottoq_assert_departure_readiness` | route the door through `staged_for_departure` | 1 h |
| 5c | **The energy MPC bridge is dormant (G168)**: `energy_mpc_follow` = 0, zero plans ever, no caller. The heuristic is the whole energy strategy. | measured | wire it or retire the claim, after 1b | — |
| 6 | G121 / G157 — a writer of `stalls.current_vehicle_id` outside the signed event stream. | `FINDINGS.md` | existing register | — |
| — | **Security surface** (G69 and the anon/authenticated sweep). | — | **Deferred by Chase**, 2026-09-22. | — |

### Not yet reviewed in this pass

These areas have not had this session's depth yet, and nothing above should be read as clearing them.

- **The solver layer:** CP-SAT `forward_lex` as rank-0 proposer, cuOpt as specialist, the MPC bridge.
- **The deterministic core beyond the dispatch path:** the charge-reconciliation and service-flow
  orchestrators.

Both are next after rank 3.
