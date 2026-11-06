-- lab/research/findings/P2.sql -- what the research wing published to public.ottoq_research_findings (0793) for Phase 2
-- (the capacity curve, the gap to the perfect day, the battery's foresight prize). Idempotent: re-running it updates each
-- finding in place (keyed by depot and slug). The repo keeps the history; the table keeps the latest. measured_at is when
-- the numbers were read (UTC). Twin depot only (rule 8). Every number is from the research lab, on production's engine.

-- E5, the first perfect day (2026-11-05 CT). Evidence: lab/research/p2_perfect_day/.
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p2-perfect-day-first', 'P2', 'E5', 'measurement', 'measured',
   'The best possible day, measured: every owner''s cars could have spent a quarter to a third less time in the depot',
   'On the lab''s first full day at the twin depot (a normal day, today''s 116 cars, 12 hours from 6 AM), a solver with '
   'perfect hindsight scheduled the same cars, arriving when they did, owing the same work, on the same chargers and '
   'bays, in the engine''s own job order. The real day used 24,332 car-minutes from arrival to ready; the best day found '
   'needs about 17,100, and no schedule can go below 15,307. That gain does not have to come from one owner at another''s '
   'expense: holding every owner to no worse than the real day, the best day found still gives Tesla 33%, Waymo 25% and '
   'Zoox 36% less time in the depot, cuts minutes past the 30-minute contract wait from 3,365 to 1,116, and gets 48 of the '
   '93 cars with a due time ready by it (38 were; the rest were due sooner than their own work takes). Rescheduling the '
   'chargers carries the larger share of the gap.',
   '{"scenario": "normal_day", "fleet": 116, "seed": 171717, "visits": 292, "hours": 12,
     "minutes_to_ready": {"real": 24332, "any_order": {"best_found": 16687, "bound": 15079},
                          "engine_order": {"best_found": 17154, "bound": 15307},
                          "engine_order_no_owner_worse": {"best_found": 17057, "bound": 15354}},
     "by_owner_minutes_to_ready": {"Tesla Robotaxi TN": {"real": 6710, "fair_best": 4463},
                                   "Waymo Nashville": {"real": 11890, "fair_best": 8941},
                                   "Zoox Southeast": {"real": 5732, "fair_best": 3653}},
     "past_contract_wait_min": {"real": 3365, "fair_best": 1116, "best_on_its_own": 839, "bound": 231},
     "due_cars_on_time": {"real": 38, "best": 48, "of": 93},
     "regret_split": {"posts_free_bays_held": 18614, "bays_free_posts_held": 20796},
     "solver": "CP-SAT, OR-Tools 9.15.6755, 120 s per solve"}',
   'otto-q-core lab/research/p2_perfect_day/', '{}', '2026-11-05 22:21:00+00')
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

-- E5 at 150 cars (2026-11-05 CT). Evidence: lab/research/p2_perfect_day/bound_ops.jsonl.
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p2-perfect-day-150', 'P2', 'E5', 'measurement', 'measured',
   'At 150 cars the best possible day is still about 28% better, with no owner worse off',
   'On a normal day at 150 cars (seed 171717, 324 visits, 12 hours), a solver with perfect hindsight, keeping the engine''s '
   'own job order, found a day with 20,993 car-minutes from arrival to ready against the real 29,100 (28% less), and no '
   'schedule can go below 17,505 (40% less). Holding every owner to no worse than the real day costs nothing (20,950). The '
   'gap is the same size as at today''s 116 cars (30% found, 37% bound): the room better decisions can win does not shrink '
   'as the depot fills. At most 39 of the 89 cars with a due time could have been ready by it (18 were). Solved on 2 '
   'workers beside running lab days, so the best found is conservative. One day, one seed.',
   '{"scenario": "normal_day", "fleet": 150, "seed": 171717, "visits": 324, "hours": 12, "charger_faults": 20,
     "minutes_to_ready": {"real": 29100, "engine_order": {"best_found": 20993, "bound": 17505},
                          "engine_order_no_owner_worse": {"best_found": 20950, "bound": 17505}},
     "by_owner_minutes_to_ready": {"Tesla Robotaxi TN": {"real": 12430, "own_best": 7630},
                                   "Waymo Nashville": {"real": 11090, "own_best": 7129},
                                   "Zoox Southeast": {"real": 5580, "own_best": 2918}},
     "due_cars_on_time": {"real": 18, "best": 39, "of": 89},
     "past_contract_wait_min": {"real": 4290, "best_on_its_own": 1459},
     "solver": "CP-SAT, OR-Tools 9.15.6755, 120 s per solve, 2 workers"}',
   'otto-q-core lab/research/p2_perfect_day/bound_ops.jsonl, README.md', '{}', '2026-11-05 23:55:47+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();
