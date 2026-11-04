-- 0477  **The research lab's first determinism pair on today's engine agrees on 13 of 14 atoms, and the 14th, the end
--        state, differs in nothing but the itinerary-leg id the post's cleaning arm mints in each arm. Set that id
--        aside (0794, in a lab replica only) and the pair passes 14 of 14.**
--        -> G510 (new). Frontier plan Phase 0, item 1 (E1, docs/FRONTIER_PLAN_2026-11-03.md). Chase, 2026-11-04:
--        "Begin frontier build step 1".
--        Measured in the research lab (lab/engine/, PostgreSQL 17.11), on a copy of production's engine exported from
--        gxdrcyphqjzjsuhxuqtg's catalog, read-only, at 21:43:40-21:43:47 UTC (3:43 PM CT), with the twin depot's
--        reference data read at 22:00:45-22:01:11 UTC (4:00 PM CT). Twin depot only (rule 8). Nothing in this file
--        writes to production; sections (4) and (5) read it through the read-only endpoint.
--        Full numbers: lab/engine/reports/e1_acceptance_2026-11-04.md and its evidence directory.
--
-- ══ §1 THE LAB IS PRODUCTION'S ENGINE AND PRODUCTION'S WORLD ═══════════════════════════════════════════════════════
--
--   Object by object (lab/engine/lib/fidelity_full.py; census run on both sides 2026-11-04 22:17 UTC): all 1,037
--   routines, 453 tables, 236 triggers, 889 indexes, 210 policies, 453 RLS switches, 30 types, 80 sequences, 646
--   comments, 1,693 ACLs, 18 default ACLs, 24 cron jobs and the ledger's 1,337 versions (engine hash aae920a7)
--   identical. Six objects differ only as deparse round-trips with identical meaning: three CHECKs whose BETWEEN-born
--   nested AND flattens on re-parse, three views whose second UNION branch's unused column name re-derives as "text".
--   The twin depot's world fingerprint (ottoq.ottoq_world_fingerprint_sections) is 3f2aa2ac0bcc532e35f36c8bc257ff0e in
--   the lab, at export time in production, and in production read again at 23:13:47 UTC (5:13 PM CT).
--
-- ══ §2 THE PAIR (reproduce: (1), (2)) ══════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_determinism_pair(171717, 12, 'busy_day', twin, '2026-09-01 02:00+00'), unmodified, in a lab replica
--   cloned from the copy, with production's session settings (23:05:27-23:13:47 UTC, 5:05-5:13 PM CT):
--
--     outcome failed, complete, 13 of 14 atoms agree: fingerprint, commands, decisions, events, bookings, energy,
--     proposals, deferrals, calibration, rules, recalls, sdrs, tick count. end_state disagrees.
--     In the end state only visit_needs/vis/h differs; in visit_needs only the atoms column (90 of 116 rows); in the
--     atoms only one key, robot_leg_id (90 in each arm, one per cleaned visit). With that key removed from each atom,
--     0 of 116 visit needs differ.
--
--   The same 13 digests came out of every other run of this cell that day -- pairs, fork-driver trunks (their own
--   transactions), the 0794 replicas -- across three builds and several databases: h_evt 86543fcc, h_dec fcf0630f,
--   h_cmd 7f477766 each time (the acceptance report lists the runs).
--
-- ══ §3 THE FIX, IN THE LAB ONLY (db/migrations/0794, PENDING) ═══════════════════════════════════════════════════════
--
--   0794 applied to a second replica (its V1/V2 pass; new body md5 10901fb7), the same pair, at the same time: passed,
--   14 of 14. Over a full depot-day (48 ticks, 23:05:27-23:33:00 UTC) the same: production's engine 13 of 14, the end
--   state differing only in 154 robot_leg_ids per arm; with 0794, 14 of 14. The fork test on that replica (lab/engine/acceptance/forks.py, fork at tick 6 of 12): the unchanged
--   branch reproduces the trunk on all 14 atoms and every per-tick digest; the branch that sets charge_order_minutes
--   = 0 at the fork first differs at tick 7, with the same arrivals.
--
-- ══ §4 WHY PRODUCTION WOULD READ THE SAME (reproduce: (4), (5)) ════════════════════════════════════════════════════
--
--   - The code is the code the lab copied (§1), and 0764 writes robot_leg_id only at stall_cabin_robot = 2, which the
--     twin depot has run since 2026-10-23 14:19:53 UTC, set by Chase.
--   - 0764 was classified forces_recert FALSE: "at 0 and 1 the starter and the completion step decide exactly as
--     before". True; and the depot that holds the canon was switched to 2 the same day.
--   - No pair has run in production since 2026-10-14 15:09 UTC (engine 9b561d56); rule 12 turned certification off on
--     2026-10-20. So nothing has seen this. The lab is the first place a pair has run since.
--
-- ══ §5 WHAT WAS NOT VERIFIED ═══════════════════════════════════════════════════════════════════════════════════════
--
--   - That production's own pair fails this way: inferred from the identical code and dial, not run (rule 12; the lab
--     reads production and never writes it).
--   - 0794 in production: PENDING, for a person to ship (rule 10). It changes what a pair measures, not what the depot
--     does; under rule 12 nothing acts on it until testing resumes.

-- (1) LAB. The newest verdict: outcome, disagreeing atoms, the arms.
SELECT certified_at, scenario, seed, ticks, outcome, disagreeing_atoms, null_atoms, engine_hash, arm_a_run, arm_b_run
  FROM public.ottoq_determinism_verdict_ledger ORDER BY certified_at DESC LIMIT 1;

-- (2) LAB. Visit needs that differ between the two arms, with and without robot_leg_id in their atoms.
WITH r AS (SELECT arm_a_run a, arm_b_run b FROM public.ottoq_determinism_verdict_ledger ORDER BY certified_at DESC LIMIT 1),
v AS (
  SELECT t.sim_run_id, t.vehicle_id,
         to_jsonb(t) - 'visit_id' - 'sim_run_id' - 'created_at' - 'updated_at' - 'meta' AS raw,
         (to_jsonb(t) - 'visit_id' - 'sim_run_id' - 'created_at' - 'updated_at' - 'meta' - 'atoms')
           || jsonb_build_object('atoms', (SELECT jsonb_agg(x.e - 'robot_leg_id' ORDER BY x.o)
                                             FROM jsonb_array_elements(t.atoms) WITH ORDINALITY x(e, o))) AS stripped
    FROM public.ottoq_visit_needs t, r WHERE t.sim_run_id IN (r.a, r.b))
SELECT count(*) FILTER (WHERE va.raw IS DISTINCT FROM vb.raw)           AS differ_as_hashed,
       count(*) FILTER (WHERE va.stripped IS DISTINCT FROM vb.stripped) AS differ_without_robot_leg_id,
       count(*)                                                         AS visit_needs
  FROM r, v va JOIN v vb USING (vehicle_id)
 WHERE va.sim_run_id = r.a AND vb.sim_run_id = r.b;

-- (3) LAB. The keys that differ inside the atoms of one visit (expected: robot_leg_id only).
WITH r AS (SELECT arm_a_run a, arm_b_run b FROM public.ottoq_determinism_verdict_ledger ORDER BY certified_at DESC LIMIT 1),
e AS (SELECT t.sim_run_id, t.vehicle_id, x.o, x.e FROM public.ottoq_visit_needs t, r,
             jsonb_array_elements(t.atoms) WITH ORDINALITY x(e, o) WHERE t.sim_run_id IN (r.a, r.b))
SELECT k, count(*) FROM r, e ea JOIN e eb USING (vehicle_id, o), jsonb_object_keys(ea.e) k
 WHERE ea.sim_run_id = r.a AND eb.sim_run_id = r.b AND ea.e->k IS DISTINCT FROM eb.e->k GROUP BY k;

-- (4) PRODUCTION, read-only. The dial at the twin depot.
SELECT scope_type, scope_id, param_value, updated_by, updated_at
  FROM public.ottoq_policy_params WHERE param_key = 'stall_cabin_robot' ORDER BY scope_type;

-- (5) PRODUCTION, read-only. The newest pair verdict, and its engine hash against today's.
SELECT max(certified_at) AS newest_verdict,
       (SELECT engine_hash FROM public.ottoq_determinism_verdict_ledger ORDER BY certified_at DESC LIMIT 1) AS its_engine,
       (SELECT md5(string_agg(version, ',' ORDER BY version)) FROM supabase_migrations.schema_migrations) AS todays_engine
  FROM public.ottoq_determinism_verdict_ledger;
