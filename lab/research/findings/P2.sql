-- lab/research/findings/P2.sql -- what the research wing published to public.ottoq_research_findings (0793) for Phase 2
-- (the capacity curve, the gap to the perfect day, the battery's foresight prize). Idempotent: re-running it updates each
-- finding in place (keyed by depot and slug). The repo keeps the history; the table keeps the latest. measured_at is when
-- the numbers were read (UTC). Twin depot only (rule 8). Every number is from the research lab, on production's engine.

-- E5, the first perfect day (2026-11-05 CT), CORRECTED 2026-11-06: the first model gave each charge its session's length
-- on a post; a car holds its post about 5 minutes longer while the robot unplugs it. bound_ops.py --post-occupancy.
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p2-perfect-day-first', 'P2', 'E5', 'measurement', 'measured',
   'The best possible day, corrected: about a sixth less time in the depot found, and no schedule can save more than a third',
   'Corrected 2026-11-06. The first version of this measure counted a car''s time on a charger as its charging session '
   'only; on the lab days a car holds its post about 5 minutes longer while the robot unplugs it (4.8 minutes a charge, '
   '10% more post time), so the solver could turn posts over faster than the depot can, and its best day was too good. '
   'With the car''s time on the post, on the lab''s first full day at the twin depot (a normal day, 116 cars, 12 hours '
   'from 6 AM, in the engine''s own job order) the real day used 24,332 car-minutes from arrival to ready; the best day '
   'the solver found needs 20,055 (18% less, against 18,043 or 26% in the first model on the same solver time), and no '
   'schedule can go below 16,185 (33% less). The first version''s other results (no owner has to be worse off for the '
   'gain; the chargers carry the larger share of it; 48 of 93 due cars could be ready by their due time) come from the '
   'first model and will be re-solved on the corrected one. On the chargers the gain is the order in which cars get a '
   'post, not posts left idle: on the lab days a working post almost never stood free while a car waited.',
   '{"scenario": "normal_day", "fleet": 116, "seed": 171717, "visits": 292, "hours": 12,
     "correction": "2026-11-06: a charge holds its post for the car''s time on it (sessions 12,470 min, posts 13,740 min)",
     "minutes_to_ready": {"real": 24332,
                          "post_occupancy_engine_order_1worker_120s": {"best_found": 20055, "bound": 16185},
                          "session_only_engine_order_1worker_120s": {"best_found": 18043, "bound": 14915},
                          "session_only_engine_order_4workers_120s": {"best_found": 17154, "bound": 15307},
                          "session_only_any_order_4workers": {"best_found": 16687, "bound": 15079},
                          "session_only_no_owner_worse": {"best_found": 17057, "bound": 15354}},
     "session_only_by_owner_minutes_to_ready": {"Tesla Robotaxi TN": {"real": 6710, "fair_best": 4463},
                                   "Waymo Nashville": {"real": 11890, "fair_best": 8941},
                                   "Zoox Southeast": {"real": 5732, "fair_best": 3653}},
     "session_only_past_contract_wait_min": {"real": 3365, "fair_best": 1116, "best_on_its_own": 839, "bound": 231},
     "session_only_due_cars_on_time": {"real": 38, "best": 48, "of": 93},
     "session_only_regret_split": {"posts_free_bays_held": 18614, "bays_free_posts_held": 20796},
     "solver": "CP-SAT, OR-Tools 9.15.6755"}',
   'otto-q-core lab/research/p2_perfect_day/ (README correction, bound_ops.jsonl, bound_ops.py --post-occupancy), lab/research/p2_capacity/post_idle_while_waiting.sql',
   '{}', '2026-11-06 03:30:31+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();

-- E5, the battery's half (2026-11-05 CT), with the G370 comparison. Evidence: lab/research/p2_perfect_day/bound_energy.py.
-- Every policy pays for its own highest half hour at the daily share of the monthly demand charge (the lab day starts a
-- fresh run, so nothing was billed before it). A first publication read the month's billed peak from the day's first
-- snapshot (330.6 kW), which shifted every bill by $224 and left the differences unchanged; it is replaced here.
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p2-battery-foresight-prize', 'P2', 'E5', 'measurement', 'measured',
   'The battery''s day plan saves $317 on a 12-hour day, and $843 against the old rule; foresight would add about $298',
   'On the lab''s first full day (a normal day, 116 cars, 12 hours), the depot''s energy bill with no battery would have '
   'been $1,699 (half-hour peak 1,679 kW). The battery''s day plan, the setting the twin depot runs (energy_reserve_shave '
   'on), brought it to $1,382 (peak 1,160 kW). The same day with that setting off, the older fixed-target rule, cost '
   '$2,225: that rule charged the battery into the peak (2,336 kW), worse than no battery at all. With perfect foresight '
   'of the day''s load the bill would have been $1,085 (peak 735 kW). Plans that see the next 1 to 4 hours perfectly but '
   'assume the load then holds steady do worse than the day plan ($1,515 to $1,583): the money is in knowing the shape of '
   'the whole day, so the AI build is a forecast of the depot''s own charging demand across the day. One day, one seed.',
   '{"scenario": "normal_day", "fleet": 116, "seed": 171717, "hours": 12, "load_kwh": 6803.3,
     "billing": "each policy pays its own highest 30-minute average at 21.40 USD/kW-month (NES GSA-3 summer, a September day) over 30 days",
     "no_battery": {"total_usd": 1698.86, "peak30_kw": 1679.0},
     "day_plan_energy_reserve_shave_1": {"total_usd": 1382.34, "peak30_kw": 1159.6},
     "old_rule_energy_reserve_shave_0": {"total_usd": 2224.84, "peak30_kw": 2335.7},
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
     "day_1_seed_171717_usd": {"no_battery": 1698.86, "day_plan": 1382.34, "typical_day_shape": 1151.82,
                               "next_1h_then_shape": 1135.01, "next_1h": 1514.99, "next_4h": 1535.47, "perfect": 1084.61},
     "day_2_seed_424242_usd": {"no_battery": 1498.97, "day_plan": 1543.13, "typical_day_shape": 1243.38,
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
                                    "both_off": 1301.28, "no_battery": 1498.97, "perfect": 1098.47},
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
   'At 150 cars, corrected: the best day found is 13% better and no schedule can be more than 35% better',
   'Corrected 2026-11-06 (the first model counted a car''s time on a charger as its session only, and a car holds its post '
   'about 5 minutes longer while the robot unplugs it). On a normal day at 150 cars (seed 171717, 324 visits, 12 hours), '
   'a solver with perfect hindsight keeping the engine''s own job order found a day with 25,188 car-minutes from arrival '
   'to ready against the real 29,100 (13% less; 22,333 or 23% in the first model on the same solver time), and no schedule '
   'can go below 18,935 (35% less). The first version said the room better decisions can win does not shrink as the '
   'depot fills; that is withdrawn: found, it fell from 18% at 116 cars to 13% at 150 while the bound held at about a '
   'third, and a single solver worker for 120 seconds is a weak search on the larger day, so neither number yet says how '
   'the room moves with the fleet. The first version''s owner and due-time figures are from the first model. One day, '
   'one seed.',
   '{"scenario": "normal_day", "fleet": 150, "seed": 171717, "visits": 324, "hours": 12, "charger_faults": 20,
     "correction": "2026-11-06: a charge holds its post for the car''s time on it (sessions 14,945 min, posts 16,375 min)",
     "minutes_to_ready": {"real": 29100,
                          "post_occupancy_engine_order_1worker_120s": {"best_found": 25188, "bound": 18935},
                          "session_only_engine_order_1worker_120s": {"best_found": 22333, "bound": 17505},
                          "session_only_engine_order_2workers_120s": {"best_found": 20993, "bound": 17505},
                          "session_only_no_owner_worse": {"best_found": 20950, "bound": 17505}},
     "session_only_by_owner_minutes_to_ready": {"Tesla Robotaxi TN": {"real": 12430, "own_best": 7630},
                                   "Waymo Nashville": {"real": 11090, "own_best": 7129},
                                   "Zoox Southeast": {"real": 5580, "own_best": 2918}},
     "session_only_due_cars_on_time": {"real": 18, "best": 39, "of": 89},
     "session_only_past_contract_wait_min": {"real": 4290, "best_on_its_own": 1459},
     "solver": "CP-SAT, OR-Tools 9.15.6755"}',
   'otto-q-core lab/research/p2_perfect_day/ (README correction, bound_ops.jsonl, bound_ops.py --post-occupancy)', '{}',
   '2026-11-06 03:35:08+00')
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
   'went from $1,737 to $1,477 at the same end-of-day charge, where the old reserves had cost $68 more than no battery at all. '
   'The reserve only matters June to September (the tariff''s summer); the floor change acts all year. Not yet seen in a demo run.',
   '{"migration": "0797", "ledger_version": "20261106025354", "switched_on_utc": "2026-11-06T02:57:21Z",
     "dials": {"bess_plan_dr_reserve_lead_h": {"default": 24, "twin": 3}, "bess_reserve_uncertainty_weight": {"default": 20, "twin": 0}},
     "gate_defaults": {"day": "normal_day 116 cars seed 424242", "energy_commands_md5": "580be767", "sessions_md5": "e297dd82", "equal": true},
     "gate_on_bill_at_base_end_state_usd": {"normal_day_424242": {"before": 1543.13, "after": 1301.28},
                                             "normal_day_171717": {"before": 1382.34, "after": 1294.82}},
     "gate_call_day": {"scenario": "dr_event_cascade", "fleet": 116, "seed": 171717, "call_ct": "14:00", "call_minutes": 122,
                       "call_cap_kw": 160.9, "battery_at_call_pct": {"before": 74.9, "after": 85.5},
                       "bill_usd": {"before": 1737.07, "after": 1499.00, "after_at_base_end_state": 1476.66, "no_battery": 1669.31},
                       "half_hour_peak_kw": {"before": 1679.0, "after": 1305.8},
                       "grid_and_battery_through_the_call_md5": "47a8c44b", "cars": "every car-facing scorecard line identical"},
     "demand_reserve_months": [6, 7, 8, 9], "finding": "G517", "seen_in_demo_run": false}',
   'otto-q-core db/migrations/0797, lab/research/p2_capacity/g517_lab_2026-11-06.md, lab/research/p2_capacity/results.jsonl, lab/research/p2_perfect_day/bound_energy.jsonl, FINDINGS.md G517 and G518',
   '{}', '2026-11-06 03:04:02+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();
