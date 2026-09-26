-- migration-version: 20260926033252
-- migration-name:    stopping_a_run_relabelled_every_interrupted_bay_booking_so_the_interruption_record_vanished
--
-- 0459  **Stopping a run relabelled every interrupted bay booking `released / run_stopped`, so the record of the
--       interruption vanished with it.** `db/checks/0355` §5. FINDINGS G192.
--
-- ══ §1 MEASURED 2026-09-26 on run 689095e2 (busy_day, stopped 2026-09-25) ══════════════════════════════════════
--
--   18 bookings carry an `ottoq.booking_interrupted` event (`bay_exit_before_planned_end`, 0.65–0.95 of 9 minutes)
--   and all 18 now read `state = 'released', release_reason = 'run_stopped'`, with `released_at` moved to the run's
--   final sim clock. Run 736406cf, which ended on the governor rather than a stop, kept its 598 as `interrupted`.
--   So whether a run's interruptions are countable afterwards depended on how it ended, and PULSE's
--   `reservation_ledger` (0460: "done / released / superseded / interrupted side by side") reads interrupted = 0
--   for any stopped run.
--
-- ══ §2 WHY THE RELEASE IS RIGHT AND THE RELABEL IS NOT ═══════════════════════════════════════════════════════════
--
--   `public.ottoq_sim_release_depot` releases `interrupted` rows on purpose (0127): `ottoq_stall_bookings`' EXCLUDE
--   constraint covers held / active / done / interrupted, `during` is in SIM time, and the next run replays the same
--   sim day, so a leaked interrupted row blocks the next run's bookings on that stall (the 171717/24t carrier). The
--   state has to leave the exclusion set. The REASON and the TIME did not have to go with it.
--
-- ══ §3 WHAT THIS DOES ════════════════════════════════════════════════════════════════════════════════════════════
--
--   Same statement, same rows, same new state. For a row that was `interrupted`: `release_reason` keeps its own
--   reason and appends `; run_stopped` (so `bay_exit_before_planned_end; run_stopped`), and `released_at` keeps the
--   interruption's own time. Held and active rows read exactly as before. A query for interruptions on a stopped run
--   is `release_reason LIKE '%; run_stopped'`.
--
-- ══ §4 forces_recert TRUE ════════════════════════════════════════════════════════════════════════════════════════
--
--   Called by `ottoq_sim_advance_tick` and `ottoq_sim_stop_and_reset`. Conservative: if the bookings atom digests
--   `release_reason` this moves it. It lands in the same recertification sweep as 0458.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0459 P0: a pair is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_sim_release_depot(uuid,text)'::regprocedure))
     <> 'bccdf764b34fd6970021b5a8d2fa97c4' THEN
    RAISE EXCEPTION '0459 P2: public.ottoq_sim_release_depot is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0459_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_sim_release_depot(uuid,text)'::regprocedure;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_sim_release_depot(uuid,text)'::regprocedure);
  v_pat text := $p$SET state='released', released_at=\(SELECT COALESCE\(r\.sim_clock_current, r\.sim_clock_start\) /\* 0357: was now\(\) -- a WALL fallback in a SIM column \*/ FROM ottoq_sim_runs r WHERE r\.sim_run_id = p_sim_run_id\) /\* 0194 \*/, release_reason='run_stopped'$p$;
  v_new text := $r$SET state='released',
           -- 0459 (G192): an interruption keeps its own time and reason; the state still leaves
           -- the exclusion set, which is all 0127 needed.
           released_at = CASE WHEN state = 'interrupted' AND released_at IS NOT NULL THEN released_at
                              ELSE (SELECT COALESCE(r.sim_clock_current, r.sim_clock_start) /* 0357: was now() -- a WALL fallback in a SIM column */ FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id) END /* 0194 */,
           release_reason = CASE WHEN state = 'interrupted'
                                 THEN COALESCE(release_reason, 'interrupted') || '; run_stopped'
                                 ELSE 'run_stopped' END$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0459: the release statement matched % times, not once', n; END IF;
  EXECUTE regexp_replace(v_def, v_pat, v_new);
END $patch$;

DO $verify$
DECLARE v_d text := pg_get_functiondef('public.ottoq_sim_release_depot(uuid,text)'::regprocedure);
BEGIN
  IF position($x$COALESCE(release_reason, 'interrupted') || '; run_stopped'$x$ IN v_d) = 0
     OR position($x$WHERE sim_run_id = p_sim_run_id AND state IN ('held','active','interrupted');$x$ IN v_d) = 0 THEN
    RAISE EXCEPTION '0459 V1: the patched release statement is not in the live body';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_sim_release_depot(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_sim_release_depot(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION '0459 V2: the ACL moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0459_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0459_stopping_a_run_relabelled_every_interrupted_bay_booking_so_the_interruption_record_vanished', true,
  'public.ottoq_sim_release_depot (called by ottoq_sim_advance_tick and ottoq_sim_stop_and_reset): an interrupted '
  'booking keeps its reason and time when a run ends; release_reason may be digested by the bookings atom.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
