-- lab/research/findings/P1.sql -- what the research wing published to public.ottoq_research_findings (0793) for Phase 1.
-- Idempotent: re-running it updates each finding in place (keyed by depot and slug). The repo keeps the history; the table
-- keeps the latest. measured_at is when the numbers were read (UTC). Twin depot only (rule 8).

-- E2/E7, the first replay report (2026-11-04 CT; Chase: "keep going"). Evidence: db/checks/0479,
-- lab/research/p1_referee_owner_futures/.
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p1-fair-reorders-are-rare', 'P1', 'E2', 'measurement', 'measured',
   'A referee that never lets an owner lose would accept almost no AI charging orders',
   'Replaying the referee''s own predictions one owner at a time, an AI order that is good for every owner turned out '
   'to be rare: 35 of 370 past orders in hindsight, and the referee''s predictions never showed one convincingly. With '
   'three owners sharing one charging line, moving one car up moves another owner''s car down. So a smarter referee alone '
   'will not make the AI''s orders fair. The fix is to let the AI reorder only within each owner''s own cars, so each '
   'owner keeps its places, or to give the AI other jobs. That choice is Chase''s.',
   '{"decisions": 370, "futures_reproduced": 370, "good_for_every_owner_in_hindsight": 35,
     "most_futures_good_for_every_owner": 8, "decisions_with_no_such_future": 153,
     "rules": {"referee_before_owner_guard": {"takes": 32, "good_for_every_owner": 5},
               "with_owner_guard": {"takes": 5, "good_for_every_owner": 1},
               "no_owner_worse_in_10_of_12": {"takes": 0}, "good_for_every_owner_in_10_of_12": {"takes": 0}},
     "runs": 25, "keys": 18, "finding": "G512"}',
   'otto-q-core db/checks/0479', '{}', '2026-11-05 01:38:29+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();
