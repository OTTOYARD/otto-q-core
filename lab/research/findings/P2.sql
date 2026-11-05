-- lab/research/findings/P2.sql -- what the research wing published to public.ottoq_research_findings (0793) for Phase 2
-- (the capacity curve, the gap to the perfect day, the battery's foresight prize). Idempotent: re-running it updates each
-- finding in place (keyed by depot and slug). The repo keeps the history; the table keeps the latest. measured_at is when
-- the numbers were read (UTC). Twin depot only (rule 8). Every number is from the research lab, on production's engine.

-- E5, the first perfect day (2026-11-05 CT). Evidence: lab/research/p2_perfect_day/.
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p2-perfect-day-first', 'P2', 'E5', 'measurement', 'measured',
   'The best possible day, measured: the depot''s cars spent about half again as long as they needed to',
   'On the lab''s first full day at the twin depot (a normal day, today''s 116 cars, 12 hours from 6 AM), a solver with '
   'perfect hindsight scheduled the same cars, arriving when they did, owing the same work, on the same chargers and '
   'bays. The real day used 24,332 car-minutes from arrival to ready; the best day found needs 16,687, and no schedule '
   'can go below 15,079. Minutes past the 30-minute contract wait fell from 3,365 to 660. At most 48 of the 93 cars with '
   'a due time could have been ready by it (38 were): the rest were due sooner than their work allows. Rescheduling the '
   'chargers alone recovers about three quarters of the gap, the bays alone under half. The solver may do a car''s jobs '
   'in any order, so this is an optimistic bound; a stricter one keeps the engine''s order.',
   '{"scenario": "normal_day", "fleet": 116, "seed": 171717, "visits": 292, "hours": 12,
     "minutes_to_ready": {"real": 24332, "best_found": 16687, "bound": 15079},
     "past_contract_wait_min": {"real": 3365, "best_found": 660, "bound": 72},
     "due_cars_on_time": {"real": 38, "best": 48, "of": 93},
     "regret_split": {"posts_free_bays_held": 18614, "bays_free_posts_held": 20796},
     "solver": "CP-SAT, OR-Tools 9.15.6755, 120 s per solve"}',
   'otto-q-core lab/research/p2_perfect_day/', '{}', '2026-11-05 22:12:00+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();

-- E5, the battery's half (2026-11-05 CT). Evidence: lab/research/p2_perfect_day/bound_energy.py.
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p2-battery-foresight-prize', 'P2', 'E5', 'measurement', 'measured',
   'The battery earns $317 on a 12-hour day; knowing the day''s shape would be worth about $298 more',
   'On the same lab day, the depot''s energy bill with no battery would have been $1,463. The battery''s current day plan '
   'brought it to $1,147, mostly by cutting the half-hour peak from 1,679 kW to 1,160 kW. With perfect foresight of the '
   'day''s load the bill would have been $849 (peak 735 kW). Plans that see the next 1 to 4 hours perfectly but assume '
   'the load then holds steady do worse than the current plan ($1,300 to $1,387): the money is in knowing the shape of '
   'the whole day, so the AI build is a forecast of the depot''s own charging demand across the day. Priced the way the '
   'battery''s own plan prices demand (the monthly charge spread over 30 days). One day, one seed.',
   '{"scenario": "normal_day", "fleet": 116, "seed": 171717, "hours": 12, "load_kwh": 6803.3,
     "no_battery": {"total_usd": 1463.03, "peak30_kw": 1679.0}, "day_plan": {"total_usd": 1146.51, "peak30_kw": 1159.6},
     "perfect_foresight": {"total_usd": 848.78, "peak30_kw": 735.3},
     "rolling_lookahead_usd": {"persistence": 1387.46, "1h": 1338.82, "2h": 1313.73, "4h": 1299.64},
     "battery": {"capacity_kwh": 3000, "max_kw": 1500}, "demand_usd_kw_month": 20.34}',
   'otto-q-core lab/research/p2_perfect_day/bound_energy.jsonl', '{}', '2026-11-05 22:03:00+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();
