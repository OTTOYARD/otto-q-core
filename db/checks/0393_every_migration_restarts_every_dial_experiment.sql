-- 0393  **G250: a dial experiment counts only the pairs run on the current engine, and the engine is the md5 of every
--       migration version ever applied -- so any migration restarts every experiment, including one that changes a
--       cron schedule. 0522 moved the dial window's close by 19 minutes and left the G240 experiment with 0 of its 3
--       pairs, and the energy experiment with 0 of the 4 it had run since 0521.**
--
--       Written on 2026-09-27 (12:15-12:35 UTC, 7:15-7:35 AM CT). Read-only. Found while correcting 0389 §3, which said
--       G240 was "collecting, 3 of 6": true when written, and false since 0522's apply at 11:15 UTC.

-- ══ §1 WHAT THE VERDICT COUNTS ════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0393 §1 — the engine, the recert floor, and each active experiment counted both ways ==='
SELECT public.ottoq_engine_hash() AS engine_now, public.ottoq_cert_recert_floor() AS recert_floor,
       left(e.experiment_id::text, 8) AS exp, e.param_key,
       (SELECT count(*) FROM public.ottoq_dial_pair_ledger l WHERE l.experiment_id = e.experiment_id) AS recorded,
       (SELECT count(*) FROM public.ottoq_dial_pair_ledger l
         WHERE l.experiment_id = e.experiment_id AND l.engine_hash = public.ottoq_engine_hash()) AS on_this_engine,
       (SELECT count(*) FROM public.ottoq_dial_pair_ledger l
         WHERE l.experiment_id = e.experiment_id AND l.ran_at >= public.ottoq_cert_recert_floor()) AS since_recert_floor,
       (SELECT string_agg(DISTINCT left(l.engine_hash, 8), ',') FROM public.ottoq_dial_pair_ledger l
         WHERE l.experiment_id = e.experiment_id) AS engines
  FROM public.ottoq_dial_experiments e WHERE e.status = 'active' ORDER BY e.created_at;
-- READ (2026-09-27 12:18 UTC, before 0523):
--     engine_now 1bb3a2c1..., recert floor 08:52:18 UTC (0521's apply)
--     82c5568b  energy_reserve_shave           recorded 5  on this engine 0  since the recert floor 4  engines dc03a921, f03cf4ee
--     143a11c7  charge_window_calibration_id   recorded 3  on this engine 0  since the recert floor 3  engine  f03cf4ee
--   `ottoq_engine_hash()` is `md5(string_agg(version ORDER BY version))` over `supabase_migrations.schema_migrations`:
--   every migration is a new engine. The verdict (`ottoq_dial_experiment_verdict`) counts a pair only if its
--   `engine_hash` equals it; the runner picks the experiment with the fewest pairs on it and the next seed not yet
--   paired on it; `ottoq_dial_pair` refuses a seed already paired on it. G240's verdict at 12:18 UTC: "0 of 6 counted
--   pairs needed for the first look", recorded 3, stale_engine 3. Its three pairs (09:40, 10:10, 10:40 UTC) ran after
--   0521, the last change that could move an arm, and before 0522, which could not.

-- ══ §2 WHY THE RECERT FLOOR IS NOT ENOUGH ON ITS OWN ══════════════════════════════════════════════════════════════
--
--   The canon already solves the same problem the right way: `ottoq_cert_recert_floor()` moves only for a migration
--   whose lineage row says `forces_recert` (or has no row), so a change that cannot move a certified digest does not
--   restart the streaks (2.9a). Counting dial pairs from that floor would keep all 7 pairs above.
--   But `forces_recert` answers "can this move a canon column?", and every canon column runs at the dials' defaults. A
--   dial pair's treatment arm runs off the default, where a change can move it and no canon column can see it. 0517 is
--   the example on record: `forces_recert = false`, correctly -- its booking-window calibration does nothing at
--   `charge_window_calibration_id = 0` -- and it is exactly the code G240's treatment arm runs at 6. A pair before
--   0517 and a pair after it are not the same experiment. So a dial experiment needs its own classification, with the
--   same safe default the canon's has: unclassified restarts.

-- ══ §3 THE FIX: 0523 ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `ottoq_cert_lineage.forces_dial_restart`, nullable: NULL restarts (as an unclassified migration forces recert),
--       FALSE is the author's statement that no dial arm can come out differently.
--   (2) `ottoq_dial_pair_floor()`: the later of the recert floor and the last migration that restarts dial pairs,
--       read the way the recert floor is read (schema_migrations joined on the unprefixed name, and the lineage rows'
--       own times for anything applied outside it).
--   (3) The verdict, the runner and `ottoq_dial_pair` count, choose and refuse by "ran since the dial floor" instead of
--       "ran on this engine". The ledger keeps each pair's engine hash as recorded.
--   (4) The counted pairs take each seed once, its first pair since the floor -- G153's rule, made structural rather
--       than left to the refusal in `ottoq_dial_pair`.
--   (5) 0522 is classified: a cron schedule, `forces_dial_restart = false`. G240 counts its three pairs again.

\echo '=== 0393 §4 — 0523 in the migration ledger, the floor it computes, and what the verdicts count ==='
SELECT m.version, md5(m.statements[1]) AS body_md5, public.ottoq_dial_pair_floor() AS dial_floor,
       public.ottoq_cert_recert_floor() AS recert_floor,
       public.ottoq_dial_experiment_verdict('143a11c7-6740-4624-b747-e145f3533e60')->'pairs' AS g240_pairs,
       public.ottoq_dial_experiment_verdict('82c5568b-d661-4469-84d5-5799a5be1f1d')->'pairs' AS energy_pairs,
       (SELECT forces_dial_restart FROM public.ottoq_cert_lineage
         WHERE name = '0522_the_dial_window_closes_before_its_last_pair_could_outlast_it') AS g0522_restarts
  FROM supabase_migrations.schema_migrations m
 WHERE m.name = 'a_dial_experiment_restarts_only_for_a_change_that_can_move_an_arm';
-- READ (2026-09-27 12:25 UTC, 7:25 AM CT): version 20260927122408, body md5 4a83aa7595976ffe0492beac3d7f6887 -- the
--   file's body byte for byte once a trailing blank line the ledger does not keep was taken out of the file. The dial
--   floor is 08:52:18.750117 UTC, the recert floor's own value (0521's apply). G240: counted 3, recorded 3, stale 0,
--   "3 of 6 counted pairs needed for the first look". Energy: counted 4, recorded 5, stale 1 (its 08:40 UTC pair ran
--   before 0521, correctly stale). 0522 reads forces_dial_restart FALSE. Dry run and apply passed first time; V3 moved
--   the floor to the transaction's own time for an unclassified lineage row and for a forces_recert one, put it back
--   for a FALSE one, and found no seed counted twice.
