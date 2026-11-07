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
   'owner keeps its places, or to give the AI other jobs. Chase chose other jobs on 2026-11-05 (see the next finding).',
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

-- E8 / D5, the AI moved off the per-tick charge line (2026-11-05 CT; Chase: "Okay I agree with you on all fronts. Begin
-- building"). Evidence: db/migrations/0795, db/checks/0480, lab/research/p1_agent_challenger/.
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p1-ai-off-the-charging-line', 'P1', 'E8', 'build', 'shipped',
   'The AI no longer orders the charging line: it challenges in the background and is called for exceptions',
   'The AI still writes its charging order, and the referee still checks it and grades it against what actually '
   'happened, but the order never takes effect: the depot''s own fair line seats every car. That keeps a running score '
   'of whether the AI ever finds a better order, owner by owner, at no cost to any car. The AI is now consulted when '
   'something exceptional happens (a charger fault or repair, a car past its contract wait, an emergency, a '
   'demand-response call, a scout''s finding, the line suddenly backing up or clearing) plus a check-in every 30 '
   'minutes, instead of on every pass: about 20 times in a 9-hour busy day instead of 150 to 400. Tested in the lab on '
   'a copy of production; switched on at the twin depot on 2026-11-05 at 3:34 PM CT under Chase''s name.',
   '{"migration": "0795", "ledger_version": "20261105213348", "switched_on_at": "2026-11-05 21:34:09+00",
     "dials": {"agent_charge_order_shadow": 1, "agent_wake_enabled": 1},
     "wake_replay": {"runs": 12, "sim_hours": 59.4, "passes_as_run": 1691, "consults_estimated": 143,
                     "exception_wakes": 61, "heartbeats": 82},
     "lab_test": "all assertions passed (325 s)", "next_tick_same_as_no_order": true, "finding": "G512"}',
   'otto-q-core db/checks/0480', '{}', '2026-11-05 21:34:09+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();

-- E7, found while building 0795 (G513). Evidence: db/checks/0480 §4 and its query (3).
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p1-grader-misses-owner-guard', 'P1', 'E7', 'measurement', 'measured',
   'The report card skips the referee''s owner-protecting refusals',
   'Since the owner-fairness guard went on (Oct 25), the referee refused 30 AI orders because one owner''s cars would '
   'have paid for another''s. The grader that scores the referee files those 30 as "no decision", so the referee''s '
   'report card leaves out exactly the refusals that protect owners. The fix belongs with the per-owner grader the plan '
   'already calls for (E2/E7), not as a quick patch. No car is affected: the grader decides nothing.',
   '{"since": "2026-10-25 17:01:29+00", "refused_worse_for_an_owner": 30, "graded_no_decision_mattered": 27,
     "graded_no_decision": 3, "graded_decisions_beside": 33, "echoes_of_kernel_order": 89, "finding": "G513"}',
   'otto-q-core db/checks/0480', '{}', '2026-11-05 21:12:00+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();
