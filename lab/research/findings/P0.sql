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
  ('p0-lab-building', 'P0', 'E1', 'lab', 'retracted',
   'The research lab is being built',
   'Superseded by p0-lab-repo-rebuild, which reports the first build.',
   '{}', 'otto-q-core lab/engine', '{}', NULL),
  ('p0-lab-repo-rebuild', 'P0', 'E1', 'lab', 'measured',
   'The engine can''t be rebuilt from its own repository yet, so the lab will copy what production ran',
   'Rebuilt from the repository alone, the lab''s copy matched production on 300 of 1,037 database functions and 177 '
   'of 453 tables. Most migration files were changed after they ran, 84 applied changes have no file, and the old '
   'snapshot has no triggers. A faithful lab copies production''s own migration record or a schema export. That needs '
   'the Supabase access token in the session.',
   '{"postgres": "17.11", "routines_identical": 300, "routines_total": 1037, "tables_identical": 177,
     "tables_total": 453, "triggers_in_copy": 3, "triggers_total": 236, "migrations_tried": 718,
     "migrations_applied": 77, "files_matching_ledger": 101, "files_with_ledger_copy": 586,
     "ledger_rows_without_file": 84}',
   'otto-q-core lab/engine/reports/fidelity_2026-11-03.md', '{}', '2026-11-03 16:54:00+00'),
  ('p0-safety-model-building', 'P0', 'E3', 'safety', 'retracted',
   'A proven safety model of the faulted-charger post is being built',
   'Superseded by p0-safety-model, which reports the built model.',
   '{}', 'otto-q-core lab/safety', '{8c0b2e04-8ea9-49a8-bfed-bed10ddfbc8b}', NULL),
  ('p0-safety-model', 'P0', 'E3', 'safety', 'built',
   'A tool-proven safety model catches last night''s dead-charger holds, and only those',
   'The charging post, its two robot arms, the car and the charger were modelled, and a synthesis tool computed every '
   'safe move. Replayed on run 8c0b2e04, the model flags the two cars held on dead chargers (339 s and 309 s) and none '
   'of the other four faulted posts. Without the 0792 rule the tool allows exactly 8 more moves, and each one is that '
   'hold. It also shows a gap already on record. On 3 of the 6 faults the engine let the car leave at the instant of '
   'the fault with the connector still latched. A real depot needs the robots'' own clear signal.',
   '{"tool": "Eclipse ESCET 13.0", "states": 302, "transitions": 831, "transitions_without_0792_rule": 839,
     "extra_moves_without_rule_all_g506_holds": 8, "posts_checked": 6, "posts_flagged": 2,
     "held_s": {"DCFC-22": 339.1, "DCFC-02": 309.2}, "released_at_fault_with_connector_latched": 3,
     "tests": 24}',
   'otto-q-core lab/safety (README, synthesis/SUMMARY.md)', '{8c0b2e04-8ea9-49a8-bfed-bed10ddfbc8b}',
   '2026-11-03 15:33:00+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();
