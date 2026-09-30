-- migration-version: PENDING
-- migration-name:    a_replicate_is_judged_on_what_it_did_not_on_its_own_run_id
--
-- 0578  **A replicate, or the same cell on another night, is judged on what it did, not on its own run id.** Lane A,
--       harness only. (G301)
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Night 1's replicate (arm 9) repeats arm 3: dcfc10.otto_q, seed 1. Their boot images are equal, and so is every hash
--   in their atoms: events, decisions, bookings, energy, proposals, rules, commands, arrivals, recalls, SDRs and end state.
--   Their metrics match too. Yet `ottoq_throughput_sweep_replicates` reported identical = false, moved = ["run"]
--   (db/checks/0413 §5). The live `ottoq_ab_arm_atoms` includes `run`, the arm's own sim_run_id. Two arms always differ
--   there, so the check could never pass. `ottoq_throughput_cross_sweep_twins` (0571, re-created by 0572) compares atoms
--   the same way. The stub's atoms carry no `run` key, which is why the tests passed.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   Both views compare `atoms - 'run'` and leave `run` out of `moved`. Nothing else changes: the same columns, joins and
--   floor. `run` stays in the atoms, where it is what identifies the arm's evidence.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: 0572 is applied, since this re-creates its twins view. P2: neither view already leaves
--   `run` out. P3: not already applied. Both views go to `ottoq_schema_snapshots` as '0578_pre'.
--   V1: `run` is in no row's `moved`. V2: a replicate whose boot image and atoms without `run` equal its primary's reads
--   identical, in both views. It says how many replicates are current: applied between 0572 and 0573, night 1's arm 9
--   is one.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: two read-only views of evidence, and nothing the engine reads.
--
-- ROLLBACK: re-create both views from their '0578_pre' snapshots; DELETE FROM public.ottoq_cert_lineage
--   WHERE name = '0578_a_replicate_is_judged_on_what_it_did_not_on_its_own_run_id'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0578 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: 0572 first ──
DO $order$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0572_a_fleet_build_out_borrows_cars_for_one_test_day') THEN
    RAISE EXCEPTION '0578 P1: 0572 is not applied, and this re-creates its twins view';
  END IF;
END $order$;

-- ── P2: neither view already leaves `run` out ──
DO $premises$
BEGIN
  IF to_regclass('public.ottoq_throughput_sweep_replicates') IS NULL OR to_regclass('public.ottoq_throughput_cross_sweep_twins') IS NULL THEN
    RAISE EXCEPTION '0578 P2: a view is missing';
  END IF;
  IF position('''run''' IN pg_get_viewdef('public.ottoq_throughput_sweep_replicates'::regclass, true)) > 0
     OR position('''run''' IN pg_get_viewdef('public.ottoq_throughput_cross_sweep_twins'::regclass, true)) > 0 THEN
    RAISE EXCEPTION '0578 P2: a view already leaves run out';
  END IF;
END $premises$;

-- ── P3: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0578_a_replicate_is_judged_on_what_it_did_not_on_its_own_run_id') THEN
    RAISE EXCEPTION '0578 P3: already applied';
  END IF;
END $once$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0578_pre', 'view', 'public', v, d, md5(d)
  FROM (SELECT v, 'CREATE OR REPLACE VIEW public.' || v || ' WITH (security_invoker = true) AS '
                  || pg_get_viewdef(('public.' || v)::regclass, true) AS d
          FROM unnest(ARRAY['ottoq_throughput_sweep_replicates', 'ottoq_throughput_cross_sweep_twins']) AS v) z;

CREATE OR REPLACE VIEW public.ottoq_throughput_sweep_replicates
WITH (security_invoker = true) AS
SELECT s.sweep_code, c.cell_code, r.seed, p.arm_id AS primary_arm, r.arm_id AS replicate_arm,
       p.ran_at AS primary_ran_at, r.ran_at AS replicate_ran_at,
       r.boot_md5 = p.boot_md5 AND (r.atoms - 'run') = (p.atoms - 'run')                     AS identical,
       (SELECT COALESCE(jsonb_agg(k ORDER BY k), '[]'::jsonb)
          FROM jsonb_object_keys(COALESCE(p.atoms - 'run', '{}'::jsonb) || COALESCE(r.atoms - 'run', '{}'::jsonb)) AS k
         WHERE (p.atoms -> k) IS DISTINCT FROM (r.atoms -> k))                               AS moved
  FROM public.ottoq_throughput_sweep_arms r
  JOIN public.ottoq_throughput_sweep_arms p ON p.cell_id = r.cell_id AND p.seed = r.seed AND NOT p.replicate
                                           AND p.complete AND p.ran_at >= public.ottoq_dial_pair_floor()
  JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = r.cell_id
  JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = r.sweep_id
 WHERE r.replicate AND r.complete AND r.ran_at >= public.ottoq_dial_pair_floor();
COMMENT ON VIEW public.ottoq_throughput_sweep_replicates IS
'0568, 0578. Each replicate arm against its primary: identical when the boot image and every atom but run (ottoq_ab_arm_atoms; run is the arm''s own sim_run_id) agree. Two arms in different transactions, hours apart: the cross-transaction determinism G140 asked for, at the sweep''s step and on its build-out.';

CREATE OR REPLACE VIEW public.ottoq_throughput_cross_sweep_twins
WITH (security_invoker = true) AS
WITH cur AS (
  SELECT a.arm_id, a.seed, a.ran_at, a.boot_md5, a.atoms, a.sweep_id, s.sweep_code, s.depot_id, s.scenario, s.sim_start,
         s.sim_min_per_tick, s.ticks, s.fleet_code, c.cell_code, c.seat, c.buildout_code, c.fixed_params
    FROM public.ottoq_throughput_sweep_arms a
    JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
    JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
   WHERE NOT a.replicate AND a.complete AND a.ran_at >= public.ottoq_dial_pair_floor()
)
SELECT e.sweep_code AS earlier_sweep, e.cell_code AS earlier_cell, l.sweep_code AS later_sweep, l.cell_code AS later_cell,
       l.seed, e.arm_id AS earlier_arm, l.arm_id AS later_arm, e.ran_at AS earlier_ran_at, l.ran_at AS later_ran_at,
       l.boot_md5 = e.boot_md5 AND (l.atoms - 'run') = (e.atoms - 'run')                     AS identical,
       (SELECT COALESCE(jsonb_agg(k ORDER BY k), '[]'::jsonb)
          FROM jsonb_object_keys(COALESCE(e.atoms - 'run', '{}'::jsonb) || COALESCE(l.atoms - 'run', '{}'::jsonb)) AS k
         WHERE (e.atoms -> k) IS DISTINCT FROM (l.atoms -> k))                               AS moved
  FROM cur e
  JOIN cur l ON l.sweep_id <> e.sweep_id AND l.ran_at > e.ran_at AND l.seed = e.seed AND l.depot_id = e.depot_id
            AND l.scenario = e.scenario AND l.sim_start = e.sim_start AND l.sim_min_per_tick = e.sim_min_per_tick
            AND l.ticks = e.ticks AND l.seat = e.seat AND l.buildout_code = e.buildout_code
            AND l.fixed_params = e.fixed_params AND l.fleet_code IS NOT DISTINCT FROM e.fleet_code;
COMMENT ON VIEW public.ottoq_throughput_cross_sweep_twins IS
'0571, 0572, 0578. Two primary arms of different sweeps that ran one cell definition on one seed at one fleet size: identical when the boot image and every atom but run (the arm''s own sim_run_id) agree. Different sweeps, nights and transactions: cross-transaction determinism (G140), and a real-engine check that an engine change classified as default-neutral moved nothing.';

-- ── V1: run is in no row's moved ──
DO $v1$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_replicates WHERE moved ? 'run')
     OR EXISTS (SELECT 1 FROM public.ottoq_throughput_cross_sweep_twins WHERE moved ? 'run') THEN
    RAISE EXCEPTION '0578 V1: run is still counted as moved';
  END IF;
END $v1$;

-- ── V2: equal boot and equal atoms but run read identical, in both views ──
DO $v2$
DECLARE v_n int; v_same int;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_replicates v
               JOIN public.ottoq_throughput_sweep_arms p ON p.arm_id = v.primary_arm
               JOIN public.ottoq_throughput_sweep_arms r ON r.arm_id = v.replicate_arm
              WHERE v.identical IS DISTINCT FROM (r.boot_md5 = p.boot_md5 AND (r.atoms - 'run') = (p.atoms - 'run')))
     OR EXISTS (SELECT 1 FROM public.ottoq_throughput_cross_sweep_twins v
               JOIN public.ottoq_throughput_sweep_arms e ON e.arm_id = v.earlier_arm
               JOIN public.ottoq_throughput_sweep_arms l ON l.arm_id = v.later_arm
              WHERE v.identical IS DISTINCT FROM (l.boot_md5 = e.boot_md5 AND (l.atoms - 'run') = (e.atoms - 'run'))) THEN
    RAISE EXCEPTION '0578 V2: a view does not judge a pair on its boot image and its atoms without run';
  END IF;
  SELECT count(*), count(*) FILTER (WHERE identical) INTO v_n, v_same FROM public.ottoq_throughput_sweep_replicates;
  RAISE NOTICE '0578 V2: % current replicate(s), % identical to their primary', v_n, v_same;
END $v2$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0578_a_replicate_is_judged_on_what_it_did_not_on_its_own_run_id', false, false,
  'Lane A harness (G301). ottoq_throughput_sweep_replicates and ottoq_throughput_cross_sweep_twins compare atoms without '
  'run, the arm''s own sim_run_id, which made two arms always differ: night 1''s replicate (arm 9) matched arm 3 on every '
  'hash and was reported not identical, moved = [run]. Read-only views of evidence; nothing the engine reads.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
