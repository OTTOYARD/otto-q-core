-- lab/research/findings/P0.sql -- what the research wing published to public.ottoq_research_findings (0793) for Phase 0.
-- Idempotent: re-running it updates each finding in place (keyed by depot and slug). The repo keeps the history; the table
-- keeps the latest. Numbers are as read; measured_at is when they were read (UTC). Twin depot only (rule 8).
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p0-referee-key-clustered', 'P0', 'P0.0', 'measurement', 'measured',
   'The referee ranks the AI''s orders better than chance, but its percentages aren''t trustworthy yet',
   'Counted by the 18 independent test days rather than 370 separate decisions, the referee still tells better orders '
   'from worse ones more often than chance. Its win percentages, though, are no better than always guessing the average. '
   'So its ranking can be used; its numbers can''t yet be read as probabilities.',
   '{"decisions": 370, "keys": 18, "runs": 25, "auc": 0.6535, "auc_ci95_independent": [0.5971, 0.7100],
     "auc_ci95_by_key": [0.5803, 0.7070], "brier_skill": 0.0294, "brier_skill_ci95_by_key": [-0.0608, 0.0998]}',
   'otto-q-core db/checks/0475', '{}', '2026-11-03 15:40:54+00'),
  ('p0-yardstick-priced', 'P0', 'P0.2', 'measurement', 'measured',
   'How we value lateness, waiting and road time decides 43% of the referee''s verdicts',
   'For 140 of 329 past decisions, whether the AI''s order or OTTO-Q''s own order was better depends only on what a minute '
   'of lateness, of waiting past the contract, or of time on the road is worth. At equal weights OTTO-Q''s own order was '
   'better 185 times and the AI''s 102, and only 12 of the 29 AI orders the referee accepted actually helped. Owner prices '
   'matter.',
   '{"decisions": 329, "price_points": 63, "agent_never_worse": 46, "kernel_never_worse": 101, "same_every_price": 42,
     "depends_on_price": 140, "equal_prices": {"agent_better": 102, "kernel_better": 185, "same": 42, "taken": 29,
     "taken_helped": 12}}',
   'otto-q-core db/checks/0476', '{}', '2026-11-03 15:46:00+00'),
  ('p0-research-area-live', 'P0', 'P0.4', 'build', 'built',
   'The Research tab''s data feed is live',
   'Research findings now have their own place in the OTTO-Q database, which the twin can read and nothing in the engine '
   'does. A recommendation here changes nothing at the depot until a person ships it.',
   '{"migration": "0793", "ledger": "20261103155140"}',
   'otto-q-core db/migrations/0793', '{}', '2026-11-03 15:51:48+00'),
  ('p0-lab-building', 'P0', 'E1', 'lab', 'in_progress',
   'The research lab is being built',
   'A private copy of OTTO-Q that runs depot days fast and can rewind any moment to try a different decision. The first '
   'copy is being rebuilt from the repository and checked against production function by function; the full copy needs a '
   'Supabase access token in the environment.',
   '{}', 'otto-q-core lab/ (in progress)', '{}', NULL),
  ('p0-safety-model-building', 'P0', 'E3', 'safety', 'in_progress',
   'A proven safety model of the faulted-charger post is being built',
   'The charging post, its two robot arms, the car and the charger are being modelled so a tool can prove which states '
   'are safe, then check last night''s run against the model. It must catch the two cars held on dead chargers '
   '(DCFC-22 and DCFC-02) and nothing else.',
   '{}', 'otto-q-core lab/safety (in progress)', '{8c0b2e04-8ea9-49a8-bfed-bed10ddfbc8b}', NULL)
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();
