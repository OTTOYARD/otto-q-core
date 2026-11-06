-- lab/research/findings/P2.sql -- what the research wing published to public.ottoq_research_findings (0793) for Phase 2
-- (the capacity curve, the gap to the perfect day, the battery's foresight prize). Idempotent: re-running it updates each
-- finding in place (keyed by depot and slug). The repo keeps the history; the table keeps the latest. measured_at is when
-- the numbers were read (UTC). Twin depot only (rule 8). Every number is from the research lab, on production's engine.

-- E5, the first perfect day (2026-11-05 CT), CORRECTED 2026-11-06: the first model gave each charge its session's length
-- on a post; a car holds its post about 5 minutes longer while the robot unplugs it. bound_ops.py --post-occupancy.
-- CORRECTED AGAIN 2026-11-06 06:46 UTC (G522): work released at the gate, every bay booking a job, a tick's readiness
-- check, and rule 9's hold on immediate dispatches (--immediate-first).
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p2-perfect-day-first', 'P2', 'E5', 'measurement', 'measured',
   'The best possible day, corrected again: about a tenth less time in the depot found, and no schedule can save more than a fifth',
   'Corrected twice on 2026-11-06. First, a car holds its post about 5 minutes longer than its session while the robot '
   'unplugs it. Then the model turned out to let work start when a car was called home rather than when it reached the '
   'gate (a visit opens while the car drives, 10 minutes on average), to drop service-bay work for trouble codes that no '
   'task names, to close a visit 3 minutes after its last job where the lab''s tick takes 5, and to let the solver serve an '
   'owner''s immediate dispatch later than the engine did, which rule 9 does not allow. With all of that fixed, on the '
   'lab''s first full day at the twin depot (a normal day, 116 cars, 12 hours from 6 AM, the engine''s own job order, every '
   'immediate dispatch no later than the engine served it) the real day used 24,332 car-minutes from arrival to ready; the '
   'best day the solver found needs 21,977 (9.7% less) and no schedule can go below 19,911 (18.2% less). Holding every '
   'owner to no worse still costs nothing (22,035). Most of the room is the lab day''s 6 AM start, when the whole fleet is '
   'at the depot at once: the cars that reached the gate in its first two hours carry 1,447 of the 2,355 minutes, and past '
   'the start-up the engine is within 6.6% of the best day found. The solved day serves short and middle charges sooner '
   '(standard charges under 20 minutes wait 2 minutes from the gate instead of 12) and long ones a little later, and every '
   'owner waits less on average. Minutes past the 30-minute contract wait, from the gate: 2,740 real, 1,394 best. The '
   'first readings (22% better found, a third at most) are withdrawn. One day, one seed.',
   '{"scenario": "normal_day", "fleet": 116, "seed": 171717, "visits": 292, "hours": 12,
     "model": {"post_occupancy": true, "engine_order": true, "release": "the car at the gate", "bay_bookings": "all",
               "ready_min": 5, "immediate_first": true, "workers": 4, "seconds_per_solve": 120},
     "corrections_2026_11_06": ["the car''s time on its post", "work released at the gate, not the call home (G522)",
                                "every bay booking a job (184 of 980 service-bay minutes had been dropped)",
                                "the readiness check one 5-minute tick, every visit through the gate",
                                "immediate dispatches no later than the kernel served them (rule 9)"],
     "minutes_to_ready": {"real": 24332,
                          "corrected": {"best_found": 21977, "bound": 19911},
                          "corrected_no_owner_worse": {"best_found": 22035, "bound": 19862},
                          "corrected_without_rule9_hold": {"best_found": 21805, "bound": 19810},
                          "published_first": {"best_found": 18939, "bound": 16673}},
     "gap_by_when_the_car_reached_the_gate": {"start_up_first_2h": {"visits": 94, "real": 10470, "solved": 9023},
                                              "rest_of_day": {"visits": 198, "real": 13862, "solved": 12954}},
     "waits_after_the_car_was_free_min": {"post": {"real": 3527, "solved": 2577}, "service_bay": {"real": 744, "solved": 327},
                                          "wash_bay": {"real": 655, "solved": 32}},
     "past_contract_wait_from_gate_min": {"real": 2740, "best": 1394, "bound": 305},
     "solver": "CP-SAT, OR-Tools 9.15.6755"}',
   'otto-q-core lab/research/p2_perfect_day/ (README correction 2, bound_ops.jsonl, bound_ops.py --post-occupancy --engine-order --immediate-first, regret_split.py); FINDINGS G522',
   '{}', '2026-11-06 06:45:54+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();

-- E5, the battery's half (2026-11-05 CT), with the G370 comparison. Evidence: lab/research/p2_perfect_day/bound_energy.py.
-- Every policy pays for its own highest half hour at the daily share of the monthly demand charge (the lab day starts a
-- fresh run, so nothing was billed before it). A first publication read the month's billed peak from the day's first
-- snapshot (330.6 kW), which shifted every bill by $224 and left the differences unchanged; it is replaced here.
-- CORRECTED 2026-11-06 (research wing, reading the planner study): the battery ends a lab day fuller than it starts (here
-- 579 kWh), and the first text set the day plan's bill, which paid for that energy, against no battery's, which did not.
-- Every bill is now at the day plan's end-of-day charge, as the policies already were (stored energy at the plan's own
-- replacement cost, $0.070 a kWh): no battery $1,739, not $1,699, so the plan saves $357, not $317. The same correction
-- in p2-battery-day-shape, p2-battery-reserves and p2-battery-reserves-shipped ($8 more than no battery, not $68);
-- the four republished 2026-11-06 08:44:21 UTC.
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p2-battery-foresight-prize', 'P2', 'E5', 'measurement', 'measured',
   'The battery''s day plan saves $357 on a 12-hour day, and $835 against the old rule; foresight would add about $298',
   'On the lab''s first full day (a normal day, 116 cars, 12 hours), the depot''s energy bill with no battery would have '
   'been $1,739 (half-hour peak 1,679 kW), counting the 579 kWh the day plan left stored in the battery at the day''s end '
   'at the plan''s own replacement cost ($1,699 as billed; every bill here is at that end-of-day charge, corrected '
   '2026-11-06 from a first text that set $1,699 against the plan). The battery''s day plan, the setting the twin depot '
   'runs (energy_reserve_shave on), brought it to $1,382 (peak 1,160 kW). The same day with that setting off, the older '
   'fixed-target rule, cost $2,217: that rule charged the battery into the peak (2,336 kW), worse than no battery at all. '
   'With perfect foresight '
   'of the day''s load the bill would have been $1,085 (peak 735 kW). Plans that see the next 1 to 4 hours perfectly but '
   'assume the load then holds steady do worse than the day plan ($1,515 to $1,583): the money is in knowing the shape of '
   'the whole day, so the AI build is a forecast of the depot''s own charging demand across the day. One day, one seed.',
   '{"scenario": "normal_day", "fleet": 116, "seed": 171717, "hours": 12, "load_kwh": 6803.3,
     "billing": "each policy pays its own highest 30-minute average at 21.40 USD/kW-month (NES GSA-3 summer, a September day) over 30 days",
     "bills_at": "the day plan''s end-of-day charge (2,701.8 kWh, from 2,123.1 at the start), stored energy at 0.070 USD/kWh",
     "no_battery": {"total_usd": 1739.37, "as_billed_usd": 1698.86, "peak30_kw": 1679.0},
     "day_plan_energy_reserve_shave_1": {"total_usd": 1382.34, "peak30_kw": 1159.6},
     "old_rule_energy_reserve_shave_0": {"total_usd": 2217.34, "as_billed_usd": 2224.84, "end_kwh": 2808.9, "peak30_kw": 2335.7},
     "perfect_foresight": {"total_usd": 1084.61, "peak30_kw": 735.3},
     "rolling_lookahead_usd": {"persistence": 1583.27, "1h": 1514.99, "2h": 1549.56, "4h": 1535.47},
     "battery": {"capacity_kwh": 3000, "max_kw": 1500}, "finding": "G370"}',
   'otto-q-core lab/research/p2_perfect_day/bound_energy.jsonl', '{}', '2026-11-05 23:04:40+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();

-- The battery on two days (2026-11-05 CT): a typical day's shape as the forecast. Evidence: bound_energy.jsonl
-- (--forecast-db; --dr-reserve-kwh 600 for the reserve needed from 2 PM).
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p2-battery-day-shape', 'P2', 'E5', 'measurement', 'measured',
   'A rough idea of the day''s shape is worth most of the battery''s prize, but only to a planner that plans its refill',
   'On two lab days (a normal day, 116 cars, 12 hours, two seeds), each day''s battery was planned on the other day''s '
   'charging load as its forecast, which was off by 217 kW on average, and re-planned every five minutes on what had '
   'actually happened. It came to $1,152 against the battery''s day plan''s $1,382 and perfect foresight''s $1,085 on the '
   'first day, and $1,243 against $1,543 and $1,098 on the second. Plans that see the next one to four hours exactly but '
   'assume the load then holds steady did worse on both days. Part of each gap is the day plan''s two reserves, which these '
   'plans do not hold (see the reserves finding); holding a 600 kWh demand-response reserve from 2 PM costs them $0 and $3. '
   'These plans are linear programs that plan the battery''s refill along with its discharge. The twin''s day plan does '
   'not, and given the same typical shape it moved nothing ($1,382 against $1,382; $1,301 against $1,301 on the second '
   'day with both reserves off): the 6 AM start-up surge sets the billed half hour before the rest of the day''s forecast '
   'can matter, and what decides the bill is how deep the battery may go into that surge. So the build is the reserves '
   'first, then a planner that plans its own refill, then a learned forecast of the day''s shape inside it (worth $431 on '
   'the first day to such a planner against holding the load flat), with the AI proposing tomorrow''s adjustments from '
   'what is known, which the plan takes only as a forecast. Two days: a reading, not a range.',
   '{"scenario": "normal_day", "fleet": 116, "seeds": [171717, 424242], "hours": 12,
     "forecast": "the other lab day''s load before the battery, step by step", "forecast_mae_kw": 217.3,
     "bills_at": "each day plan''s end-of-day charge (no battery corrected 2026-11-06 from as billed: 1698.86 and 1498.97)",
     "day_1_seed_171717_usd": {"no_battery": 1739.37, "day_plan": 1382.34, "typical_day_shape": 1151.82,
                               "next_1h_then_shape": 1135.01, "next_1h": 1514.99, "next_4h": 1535.47, "perfect": 1084.61},
     "day_2_seed_424242_usd": {"no_battery": 1552.96, "day_plan": 1543.13, "typical_day_shape": 1243.38,
                               "next_1h_then_shape": 1207.46, "next_1h": 1378.06, "next_4h": 1313.10, "perfect": 1098.47},
     "with_600_kwh_dr_reserve_from_2pm_usd": {"day_1": {"typical_day_shape": 1151.82, "perfect": 1084.61},
                                             "day_2": {"typical_day_shape": 1245.99, "perfect": 1098.47}},
     "day_plan_with_the_typical_shape_usd": {"day_1": 1382.20, "day_2_both_reserves_off": 1300.64,
                                             "against": {"day_1": 1382.34, "day_2_both_reserves_off": 1301.28}},
     "billing": "each policy pays its own highest 30-minute average at 21.40 USD/kW-month (NES GSA-3 summer) over 30 days"}',
   'otto-q-core lab/research/p2_perfect_day/bound_energy.jsonl, README.md; lab/research/p2_capacity/ (tags shape, shape_dr0res0)',
   '{}', '2026-11-06 00:30:00+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();

-- G517, sized with the plan as it runs (2026-11-05 CT). Evidence: lab/research/p2_capacity/ (tags dr0, res0, dr0res0),
-- lab/research/p2_perfect_day/whatif_table.py.
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p2-battery-reserves', 'P2', 'E5', 'measurement', 'measured',
   'The battery sat out the morning surge holding 600 kWh for a call that never came; fixing its two reserves saved $242 that day',
   'On the second lab day (a normal day, 116 cars, seed 424242) the battery started 25% full. In summer the day plan holds '
   '600 kWh for a possible demand-response call between 2 and 8 PM, from the first minute of the day, and its floor rises '
   'to 33% at every surge; so it never discharged, and the half-hour peak was 1,475 kW with the battery and without it. The '
   'same day re-run in the lab with every car''s day identical: the demand-response reserve off saves $88, the rising floor '
   'off saves nothing while the reserve still holds the battery, and both off save $242 (peak 1,132 kW), 54% of the gap to '
   'perfect foresight (each bill at the same end-of-day charge). No call came on either lab day, and needed only from 2 PM '
   'the reserve costs nothing in hindsight. The reserve keeps cars charging through a call, so the fix keeps it and needs it '
   'by its window, and the floor hedges the plan''s own forecast error instead of the surge; it is tested on a day with a '
   'call before anyone switches it on (FINDINGS G517). One day, one seed.',
   '{"scenario": "normal_day", "fleet": 116, "seed": 424242, "hours": 12, "battery_start_pct": 24.6,
     "reserve_dr_kwh": 600, "dr_window_ct": "14:00-20:00", "floor_during_a_surge_pct": 33,
     "bill_at_base_end_state_usd": {"as_run": 1543.13, "dr_reserve_off": 1455.43, "rising_floor_off": 1541.71,
                                    "both_off": 1301.28, "no_battery": 1552.96, "no_battery_as_billed": 1498.97,
                                    "perfect": 1098.47},
     "half_hour_peak_kw": {"as_run": 1474.5, "dr_reserve_off": 1354.1, "rising_floor_off": 1474.5, "both_off": 1132.0,
                           "perfect": 850.1},
     "stored_kwh_at_day_end": {"as_run": 1508.4, "dr_reserve_off": 2690.7, "rising_floor_off": 2362.2, "both_off": 2490.9},
     "stored_energy_valued_at_usd_kwh": 0.070, "cars": "every car-facing scorecard line identical", "finding": "G517"}',
   'otto-q-core lab/research/p2_capacity/results.jsonl, lab/research/p2_perfect_day/bound_energy.jsonl, FINDINGS.md G517',
   '{}', '2026-11-06 00:03:21+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();

-- E5 at 150 cars (2026-11-05 CT), CORRECTED 2026-11-06 as p2-perfect-day-first (the car's time on the post).
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p2-perfect-day-150', 'P2', 'E5', 'measurement', 'measured',
   'At 150 cars, corrected again: the best day found is 7% better and no schedule can be more than 21% better',
   'Corrected twice on 2026-11-06 (see the first perfect day: the car''s time on its post; then work released at the gate, '
   'the service bays'' whole load, a tick''s readiness check and rule 9''s hold on immediate dispatches). On a normal day at '
   '150 cars (seed 171717, 324 visits, 12 hours) the real day used 29,100 car-minutes from arrival to ready; the best day '
   'found keeping every immediate dispatch no later than the engine served it needs 27,012 (7.2% less), and no schedule can '
   'go below 23,026 (20.9% less). The 6 AM start-up and the rest of the day carry the room about evenly (967 and 1,121 '
   'minutes); past the start-up the engine is within 6.6% of the best day found, as at 116 cars. The solved day gains most '
   'on the wash bays (1,152 minutes of waiting real, 55 solved), then the posts (5,591 against 5,136) and the service bays '
   '(279 against 75); short and middle charges are served sooner, long ones a little later. Holding every owner to no '
   'worse, the solver found no day in 120 s, which is not a proof that none exists. Minutes past the contract wait from '
   'the gate: 3,665 real, 2,520 best. The earlier readings (19% better found, 35% at most) are withdrawn. One day, one seed.',
   '{"scenario": "normal_day", "fleet": 150, "seed": 171717, "visits": 324, "hours": 12,
     "model": {"post_occupancy": true, "engine_order": true, "release": "the car at the gate", "bay_bookings": "all",
               "ready_min": 5, "immediate_first": true, "workers": 4, "seconds_per_solve": 120},
     "minutes_to_ready": {"real": 29100,
                          "corrected": {"best_found": 27012, "bound": 23026},
                          "corrected_no_owner_worse": {"status": "UNKNOWN in 120 s"},
                          "corrected_without_rule9_hold": {"best_found": 26670, "bound": 22572},
                          "published_first_two_workers": {"best_found": 23506, "bound": 18935}},
     "gap_by_when_the_car_reached_the_gate": {"start_up_first_2h": {"visits": 109, "real": 12130, "solved": 11163},
                                              "rest_of_day": {"visits": 215, "real": 16970, "solved": 15849}},
     "waits_after_the_car_was_free_min": {"post": {"real": 5591, "solved": 5136}, "service_bay": {"real": 279, "solved": 75},
                                          "wash_bay": {"real": 1152, "solved": 55}},
     "past_contract_wait_from_gate_min": {"real": 3665, "best": 2520, "bound": 250},
     "service_bay_minutes_dropped_by_the_first_models": 344,
     "solver": "CP-SAT, OR-Tools 9.15.6755"}',
   'otto-q-core lab/research/p2_perfect_day/ (README correction 2, bound_ops.jsonl, bound_ops.py --post-occupancy --engine-order --immediate-first, regret_split.py); FINDINGS G522',
   '{}', '2026-11-06 06:45:54+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();

-- G517's fix, shipped (2026-11-06, 8:57 PM CT on 11-05). Evidence: lab/research/p2_capacity/g517_lab_2026-11-06.md,
-- db/migrations/0797 (applied 02:53:54 UTC, switched on at the twin depot 02:57:21 UTC).
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p2-battery-reserves-shipped', 'P2', 'E5', 'build', 'shipped',
   'The battery''s reserve fix is on at the twin: it keeps the 600 kWh call reserve from 11 AM, and on a day with a call every car was the same and the battery was fuller',
   'Shipped to production as 0797 and switched on at the twin depot at 8:57 PM CT on 2026-11-05. Before it, on a summer day the '
   'battery''s day plan held 600 kWh for a possible 2-8 PM demand-response call from the first minute of the day, and its floor '
   'rose at every surge, so a battery under about half full sat out the morning surge. Now the plan takes up the reserve 3 hours '
   'before the window and its floor no longer rises with every surge. Three lab tests on a copy of production''s engine came '
   'first. At its old settings the change reproduces a day exactly. Switched on, the two normal lab days bill $1,301 and $1,295 '
   'instead of $1,543 and $1,382 (each at the same end-of-day charge), every car''s day identical. And on a day with a 2 PM call '
   '(forced in the lab, since the scenario''s own call never fires, G518), every car''s day was identical, the grid and battery '
   'through the call were identical at every 5-minute reading, and the battery met the call 85.5% full instead of 74.9%; that day''s bill '
   'went from $1,737 to $1,477 at the same end-of-day charge, where the old reserves had cost $8 more than no battery at all '
   '($1,729 at that charge; first published as $68 more, setting the plan, which stored 854 kWh, against no battery as billed). '
   'The reserve only matters June to September (the tariff''s summer); the floor change acts all year. Not yet seen in a demo run.',
   '{"migration": "0797", "ledger_version": "20261106025354", "switched_on_utc": "2026-11-06T02:57:21Z",
     "dials": {"bess_plan_dr_reserve_lead_h": {"default": 24, "twin": 3}, "bess_reserve_uncertainty_weight": {"default": 20, "twin": 0}},
     "gate_defaults": {"day": "normal_day 116 cars seed 424242", "energy_commands_md5": "580be767", "sessions_md5": "e297dd82", "equal": true},
     "gate_on_bill_at_base_end_state_usd": {"normal_day_424242": {"before": 1543.13, "after": 1301.28},
                                             "normal_day_171717": {"before": 1382.34, "after": 1294.82}},
     "gate_call_day": {"scenario": "dr_event_cascade", "fleet": 116, "seed": 171717, "call_ct": "14:00", "call_minutes": 122,
                       "call_cap_kw": 160.9, "battery_at_call_pct": {"before": 74.9, "after": 85.5},
                       "bill_usd": {"before": 1737.07, "after": 1499.00, "after_at_base_end_state": 1476.66,
                                    "no_battery_at_base_end_state": 1729.08, "no_battery_as_billed": 1669.31},
                       "half_hour_peak_kw": {"before": 1679.0, "after": 1305.8},
                       "grid_and_battery_through_the_call_md5": "47a8c44b", "cars": "every car-facing scorecard line identical"},
     "demand_reserve_months": [6, 7, 8, 9], "finding": "G517", "seen_in_demo_run": false}',
   'otto-q-core db/migrations/0797, lab/research/p2_capacity/g517_lab_2026-11-06.md, lab/research/p2_capacity/results.jsonl, lab/research/p2_perfect_day/bound_energy.jsonl, FINDINGS.md G517 and G518',
   '{}', '2026-11-06 03:04:02+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();

-- The capacity curve on whole days (2026-11-06). Evidence: lab/research/p2_capacity/README.md, results.jsonl.
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p2-capacity-curve', 'P2', 'P2.1', 'measurement', 'measured',
   'The twin depot comfortably serves about 116 cars; at 150 it saturates near 22 visits an hour, and the two service bays are the wall',
   'Corrected 2026-11-06: the contract''s queue wait now runs from the gate. A visit opens when its car is called home, and '
   'the first version counted the drive home (7-10 minutes a visit) as queueing. Whole lab days (24 hours from 6 AM) at the '
   'twin depot as built, 30 fast-charger posts, 2 service bays and 3 wash bays, two seeds a size, on production''s engine. '
   'At 116 cars the depot takes 18-20 visits an hour and 91-99% of the cars that charge do so within the 30-minute contract '
   'wait (median wait under 3 minutes). At 150 cars it takes 20-22 an hour and 70-72% charge within the wait (the slowest 5% '
   'wait 1.5-2.3 hours); at 200 cars 22-23 an hour and 40-43%, with a median wait of 1.5-1.7 hours. (From the call home, '
   'the first version: 78-91%, 62-64%, 37-39%.) More cars still put more to work in the afternoon, about 77 at 116, 98 at '
   '150 and 115 at 200, against the work side''s ask of 87% of the fleet, so each car added past 116 adds less. The wall '
   'the engine''s own constraint board names most is the two service bays (93% busy over the whole day at 200 cars); the '
   'posts are full at the afternoon peak and lose time to charger faults. On the busy-day stress scenario (trouble codes at '
   '7 times the rate) the bays fail at today''s 116 cars: by noon 96 charged cars wait for maintenance or calibration, '
   'which no car leaves without. Levers, none of them on a vehicle: a third service bay lets 22 more cars out of the day at '
   '150 cars (+5%) and 10 at 200 (+2%) and moves the wall to the posts, so the next 50 cars need posts as well as bays; '
   'fewer charger faults; better ordering of who gets a post. Two seeds a size: where the curve bends, not a range.',
   '{"depot": "twin as built: 30 dcfc posts, 2 service bays, 3 wash bays", "days": "normal_day, 24 h from 6 AM CT, arrivals 9 AM-5 AM",
     "wait_measured_from": "the car''s first arrival at the gate after its call home (corrected 2026-11-06 06:12 UTC)",
     "by_fleet": {
       "116": {"seeds": [171717, 424242], "visits_per_hour": [19.8, 18.3], "within_contract_wait_pct": [99, 91], "wait_p50_min": [0, 2.5], "wait_p95_min": [20, 45],
               "afternoon_out_pct": [68, 65], "service_bays_busy_pct": [74, 60], "posts_busy_pct": [48, 48], "drive_home_mean_min": [9.1, 9.8]},
       "150": {"seeds": [171717, 424242], "visits_per_hour": [22.3, 19.8], "within_contract_wait_pct": [72, 70], "wait_p50_min": [10, 10], "wait_p95_min": [90, 140],
               "afternoon_out_pct": [69, 61], "service_bays_busy_pct": [74, 80], "posts_busy_pct": [58, 55], "drive_home_mean_min": [8.7, 8.7]},
       "200": {"seeds": [171717, 424242], "visits_per_hour": [22.7, 22.4], "within_contract_wait_pct": [43, 40], "wait_p50_min": [92.5, 102.5], "wait_p95_min": [295, 317.8],
               "afternoon_out_pct": [59, 56], "service_bays_busy_pct": [93, 93], "posts_busy_pct": [72, 67], "drive_home_mean_min": [7.5, 7.5]}},
     "first_reading_from_the_call_within_contract_wait_pct": {"116": [91, 78], "150": [62, 64], "200": [39, 37]},
     "afternoon_asked_pct": 87, "third_service_bay_seed_171717": {"150": {"cars_left": [466, 488], "within_contract_wait_pct": [72, 62], "wall": ["service_bay", "posts"]}, "200": {"cars_left": [464, 474], "within_contract_wait_pct": [43, 43], "wall": ["service_bay", "posts"]}}, "busy_day_116": {"cars_inside_at_noon_waiting_for_bays": 96, "owing_mechanical_pm": 71, "owing_sensor_calibration": 37,
     "in_depot_at_6pm": 111}, "phantom_visits_left_out": "G520"}',
   'otto-q-core lab/research/p2_capacity/README.md (the capacity curve on whole days; the queue wait runs from the gate), steady_state.jsonl, steady_state.py, uptime_by_hour.sql',
   '{}', '2026-11-06 06:12:09+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();

-- What it takes to serve 150-250 cars comfortably (2026-11-06, published 07:54:39 UTC). Evidence: lab/research/p2_capacity/
-- README.md (build-outs on whole days), buildout_table.py, capacity_day.py --add-stall.
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
('p2-buildout', 'P2', 'P2.1', 'measurement', 'measured',
   'What it takes to serve 200 cars comfortably: 3-4 service bays and 50 fast-charger posts, and then the wash bays',
   'Whole lab days (24 hours from 6 AM) at the twin depot with posts and service bays added (each post with its own '
   'charger, the site''s power limits raised with them: rule 13), seed 171717, waits counted from the gate. The depot as '
   'built (2 service bays, 30 posts) serves 116 cars comfortably: 99% charge inside the 30-minute contract wait. A third '
   'service bay alone buys little (150 cars: 488 visits a day against 466, and the charge wait gets worse). Bays and posts '
   'together change everything: with 3 bays and 40 posts, 150 cars are as comfortable as 116 are today (98% inside the wait, '
   'median wait 0, 556 visits a day); with 3 or 4 bays and 50 posts, 200 cars are (97-99%, 665-690 visits a day, against '
   '43% and 464 on the depot as built); and 250 cars on 4 bays and 50 posts still charge 98% inside the wait (702 visits a '
   'day). The next wall is the three wash bays. The afternoon share of the fleet out at work stays 66-71% against an ask of '
   '87% whatever the build: past the depot''s own capacity, uptime is set by how long a full charge takes (rule 9), not by '
   'the depot''s size. One seed, one day each: where the curve moves, not a range.',
   '{"days": "normal_day, 24 h from 6 AM CT, arrivals 9 AM-5 AM, seed 171717", "wait_measured_from": "the gate",
     "by_site": {
       "2_bays_30_posts": {"116": {"served": 435, "within_contract_wait_pct": 99, "wait_p95_min": 20},
                           "150": {"served": 466, "within_contract_wait_pct": 72, "wait_p95_min": 90},
                           "200": {"served": 464, "within_contract_wait_pct": 43, "wait_p95_min": 295}},
       "3_bays_30_posts": {"150": {"served": 488, "within_contract_wait_pct": 62}, "200": {"served": 474, "within_contract_wait_pct": 43}},
       "3_bays_40_posts": {"150": {"served": 556, "within_contract_wait_pct": 98, "wait_p95_min": 20}, "200": {"served": 613, "within_contract_wait_pct": 69}},
       "4_bays_40_posts": {"200": {"served": 589, "within_contract_wait_pct": 67}},
       "3_bays_50_posts": {"200": {"served": 665, "within_contract_wait_pct": 97, "wait_p95_min": 20}},
       "4_bays_50_posts": {"200": {"served": 690, "within_contract_wait_pct": 99, "wait_p95_min": 15},
                           "250": {"served": 702, "within_contract_wait_pct": 98, "wait_p95_min": 25}}},
     "afternoon_out_at_work_pct_range": [59, 71], "afternoon_asked_pct": 87, "next_wall": "wash_bay",
     "power_limits": "each added post with its own 350 kW charger; DC and service limits raised by the chargers'' rating"}',
   'otto-q-core lab/research/p2_capacity/README.md (what it takes to serve 150-250 cars comfortably), buildout_table.py, capacity_day.py --add-stall, results.jsonl',
   '{}', '2026-11-06 07:47:47+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();
