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

-- E1, the lab (2026-11-04; Chase: "Begin frontier build step 1"). Published the same way; lab runs have no production
-- run id, so run_ids is empty. Evidence: lab/engine/reports/e1_acceptance_2026-11-04.md, db/checks/0477, 0794.
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p0-lab-built', 'P0', 'E1', 'lab', 'built',
   'The research lab is now an exact copy of production''s engine, and runs a depot day in three minutes',
   'The lab was rebuilt from production''s own records, read without changing anything, instead of from the code '
   'repository. Every one of the engine''s 1,037 database functions and 453 tables matches production''s, and the twin '
   'depot''s state matches production''s own fingerprint of it. It simulates a full depot day in about three minutes on '
   'one processor (21 days an hour), and 55 an hour on four copies at once. It can branch a day at any moment and show '
   'exactly what one decision changes: the world stays the same and only the decision''s effect differs. Nothing it '
   'runs touches production.',
   '{"routines_identical": 1037, "routines_total": 1037, "tables_identical": 453, "tables_total": 453,
     "triggers_identical": 236, "acls_identical": 1693, "deparse_round_trips": 6, "reference_tables": 90,
     "reference_rows": 9278, "world_fingerprint": "3f2aa2ac0bcc532e35f36c8bc257ff0e",
     "depot_day_seconds_one_stream": 172.7, "depot_days_per_hour_one_stream": 20.84,
     "depot_days_per_hour_four_replicas": 54.63, "fork_tick": 6, "changed_branch_first_differs_at_tick": 7}',
   'otto-q-core lab/engine/reports/e1_acceptance_2026-11-04.md', '{}', '2026-11-04 23:45:10+00'),
  ('p0-pair-minted-id', 'P0', 'E1', 'measurement', 'measured',
   'The engine''s own repeatability check fails today on an ID it makes up, not on anything the depot does',
   'Run twice from the same start, the twin made identical decisions, commands, bookings and energy use, over a '
   'six-hour and a 24-hour day. The check still says failed, because since 23 October every robot-cleaned visit carries '
   'a freshly made-up ID, different on every run, and the check''s end-of-day snapshot includes it. Nothing caught this '
   'because the check has not run since 14 October. Production runs the same code with the same setting, so it would '
   'fail the same way.',
   '{"atoms": 14, "atoms_agreeing": 13, "disagreeing_atom": "end_state", "visit_needs": 116,
     "visit_needs_differing": 90, "visit_needs_differing_without_the_id": 0, "minted_ids_12_ticks": 90,
     "minted_ids_48_ticks": 154, "dial": "stall_cabin_robot", "dial_value": 2, "dial_set_at": "2026-10-23 14:19:53+00",
     "last_production_pair": "2026-10-14 15:09:32+00", "finding": "G510"}',
   'otto-q-core db/checks/0477', '{}', '2026-11-04 23:33:00+00'),
  ('p0-end-state-fix', 'P0', 'E1', 'recommendation', 'recommended',
   'Recommended: leave the made-up ID out of the repeatability check (0794)',
   'A small change to the check''s end-of-day snapshot sets the made-up ID aside, as the check already does for every '
   'other ID the engine makes up. Tried in the lab only: the check then passes on all 14 of its parts, over a six-hour '
   'and a 24-hour day. It changes what the check measures, not what the depot does, and it waits for a person to ship '
   'it.',
   '{"migration": "0794", "migration_status": "PENDING", "pair_12_ticks": "passed 14 of 14",
     "pair_48_ticks": "passed 14 of 14", "forces_recert": true, "finding": "G510"}',
   'otto-q-core db/migrations/0794', '{}', '2026-11-04 23:33:00+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();

-- P0.2, per owner (2026-11-04 CT; Chase: "keep going"). Evidence: db/checks/0478, lab/research/p0_referee_per_owner/.
INSERT INTO public.ottoq_research_findings
  (slug, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at)
VALUES
  ('p0-referee-per-owner', 'P0', 'P0.2', 'measurement', 'measured',
   'Counted owner by owner, most of the AI orders the referee accepted helped one owner at another''s expense',
   'The lab re-checked all 370 of the referee''s past calls and got exactly production''s answers. Looked at one owner '
   'at a time, of the 32 AI charging orders the referee accepted, only 5 were good for every owner. 22 helped one '
   'owner''s cars at another''s expense, and 5 hurt all three. The AI''s orders leaned toward Waymo''s cars and away from '
   'Tesla''s and Zoox''s. The referee cannot yet tell which owner an order will help (it is right about half the time), '
   'so the owner safeguard switched on on 25 October works by refusing almost every AI order. The next build makes the '
   'referee judge each owner on its own, with honest estimates.',
   '{"decisions": 370, "regraded_exactly": 370, "taken": 32, "taken_good_for_every_owner": 5,
     "taken_trade_owners": 22, "taken_bad_for_every_owner": 5, "missed_wins": 143,
     "missed_wins_good_for_every_owner": 30,
     "by_owner": {"Waymo Nashville": {"better": 182, "worse": 146}, "Tesla Robotaxi TN": {"better": 145, "worse": 180},
                  "Zoox Southeast": {"better": 153, "worse": 171}},
     "expected_vs_hindsight_same_direction": 0.543, "guard_would_refuse": 322, "guard_passes": 48,
     "guard_passes_hurting_an_owner": 39, "median_contract_wait_min_lost_by_a_hurt_owner": 23.1, "runs": 25, "keys": 18,
     "finding": "G511"}',
   'otto-q-core db/checks/0478', '{}', '2026-11-05 01:18:01+00')
ON CONFLICT (depot_id, slug) DO UPDATE SET
  phase = EXCLUDED.phase, item = EXCLUDED.item, kind = EXCLUDED.kind, status = EXCLUDED.status,
  title = EXCLUDED.title, summary = EXCLUDED.summary, metrics = EXCLUDED.metrics, evidence = EXCLUDED.evidence,
  run_ids = EXCLUDED.run_ids, measured_at = EXCLUDED.measured_at, updated_at = now();
