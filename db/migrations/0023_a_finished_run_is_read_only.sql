-- migration-version: PENDING
-- migration-name:    a_finished_run_is_read_only
--
-- 0023_a_finished_run_is_read_only.sql
-- ============================================================================
-- A FINISHED RUN'S LEDGER IS READ-ONLY, AND A RUN-SCOPED READ TAKES THE RUN
-- ============================================================================
--
-- 0020 fixed WHICH ROW a run writes.  0022 fixed WHETHER A ROW STILL HAS A RUN.
-- 0023 fixes A RUN WRITING INTO ANOTHER RUN'S ROWS — and finishes the read half
-- that 0022 started.
--
-- ══════════════════════════════════════════════════════════════════════════
-- PART 0 — TWO PREMISES I WAS GIVEN THAT THE CODE DOES NOT SUPPORT
-- ══════════════════════════════════════════════════════════════════════════
--
-- FALSIFIED (1): "ottoq_build_decision_frame has no run scoping at all."
--   It has, since 0022 applied at 20260808182226.  The live body reads
--       FROM site_energy_snapshots se WHERE se.depot_id = p_depot_id
--         AND se.sim_run_id = public.ottoq_current_sim_run_id()
--       ORDER BY se.timestamp DESC LIMIT 1
--   and every OTHER site_energy_snapshots reader in the database is already
--   scoped by sim_run_id (23 read sites across 15 routines were enumerated from
--   pg_get_functiondef; the list is in the report).  The named orphan runs
--   (29b72b2b…, 6256a99f…) no longer exist — 0022's purge cleared them, taking
--   28,789 + 5,825 rows with them.  So the stated defect is already gone.
--   WHAT IS STILL WRONG IS SUBTLER, AND IT IS THE SAME BUG ONE LEVEL DOWN:
--   `ottoq_current_sim_run_id()` is a GLOBAL lookup — "the running run, else the
--   most recently started".  It is not the run the caller is asking about.
--       ottoq_capture_decision_snapshot(p_sim_run_id, …)  records a frame
--       ottoq_api_twin_get_state(p_sim_run_id)            serves a frame
--       ottoq_score_run(p_sim_run_id)                     scores a frame
--   all three name their run in their own signature and then throw it away at
--   the energy read.  Under 0022's own two-runs-on-one-clock recipe — and any
--   time the recorder is called for a run that is not the newest — the recorded
--   frame carries run A's vehicles and run B's grid import, stamped run A.
--   0023 threads the run id through instead of re-deriving it globally.
--
-- FALSIFIED (2): "narrowing the supersede is enough."
--   Read the START path before narrowing anything.  `ottoq_start_demo_run` —
--   the start button — does this FIRST:
--       UPDATE ottoq_sim_runs SET status = 'aborted'
--        WHERE COALESCE(run_by,'') <> 'production_live'
--          AND status IN ('running','paused');
--   and only THEN calls ottoq_sim_run_scenario.  So by the time the supersede
--   block runs, the previous run is ALREADY TERMINAL.  A rule of the form
--   "do not touch a terminal run's rows" would, on the button path, clear
--   NOTHING — and the stale rows are genuinely reachable, because the readers
--   are not run-scoped.  That is not a guess: `idx_visit_needs_open_by_vehicle`
--   is a partial index on (vehicle_id, created_at DESC) WHERE status IN
--   ('open','in_progress') — an index that exists precisely to serve run-blind
--   "open needs for this vehicle" lookups.  Grepping every routine that touches
--   ottoq_visit_needs, 38 of them carry at least one reference with no
--   sim_run_id anywhere within 250 characters of it.
--
-- ══════════════════════════════════════════════════════════════════════════
-- PART 1 — WHAT THE SUPERSEDE IS ACTUALLY FOR, AND WHY IT REACHES ACROSS RUNS
-- ══════════════════════════════════════════════════════════════════════════
--
--   -- a superseded run's open needs must not leak into the new world
--   UPDATE ottoq_visit_needs vn SET status = 'superseded'
--     FROM vehicles v
--    WHERE vn.vehicle_id = v.id AND v.home_depot_id = <depot>
--      AND vn.status IN ('open','in_progress');
--
-- The purpose is real and must be preserved: a need left 'open' by a run that
-- is over is indistinguishable, to a run-blind reader, from a need raised by the
-- run that is starting.  The reason it has to reach across runs is a GAP AT THE
-- OTHER END, and that is the actual defect:
--
--   ottoq_sim_stop_and_reset finalises ocpp_sessions, stall_bookings,
--   vehicle_dispatches, stalls and vehicles — and does NOT touch
--   ottoq_visit_needs at all (`pg_get_functiondef` … ILIKE '%ottoq_visit_needs%'
--   → false).  A properly stopped run therefore leaves its needs open forever.
--   That is why 0022 measured 99 of run A's 182 rows moving when run B started:
--   the ONLY code that ever closed them was the NEXT run's start.
--
-- THE FIX IS TO MOVE THE CLOSING ACT TO THE RUN THAT IS BEING CLOSED.
-- A run closes its own needs as part of its own terminal transition, wherever
-- that transition happens — stop, abort, supersede, or natural completion — via
-- an AFTER UPDATE trigger on ottoq_sim_runs.  That is TOTAL by construction: it
-- does not matter which of the four paths ends the run, and no future path can
-- forget.  It is also not a cross-run write: the only rows it touches belong to
-- the row being transitioned.
--
-- The start-time supersede then narrows to the one class of row no run
-- transition can ever reach: OWNERLESS needs, `sim_run_id IS NULL`.  Those
-- belong to no run, so no run can close them, and they would otherwise leak
-- exactly as described.  (Today there are 0 of them, and 0 open needs on a
-- terminal run — see the honest-vacuity note in PART 4.)
--
-- ══════════════════════════════════════════════════════════════════════════
-- PART 2 — THE ENERGY READS
-- ══════════════════════════════════════════════════════════════════════════
--
-- (a) ottoq_build_decision_frame gains a 2-arg overload that takes the run id.
--     The 1-arg form is KEPT and delegates with ottoq_current_sim_run_id(), so
--     every caller not listed here behaves exactly as it does today.  Nothing is
--     dropped; the new body is derived from the live 1-arg body by text
--     transform under an md5 guard, so the two cannot silently diverge.
-- (b) The three named callers pass their own run: capture_decision_snapshot,
--     api_twin_get_state, score_run.
-- (c) ottoq_energy_cost_for_run loses its silent cross-run fallback.  It read
--         WHERE CASE WHEN v_has_tagged THEN sim_run_id = p_sim_run_id
--                    ELSE depot_id = v_depot
--                     AND created_at >= v_start AND created_at <= v_end END
--     — a REAL-CLOCK window over every run's rows at that depot, taken whenever
--     the run itself wrote none.  That is the silent fallback to another run's
--     numbers this migration exists to remove, and it feeds the energy-$ figures.
--
-- ══ TOTAL BEHAVIOUR WHEN THIS RUN HAS NO SNAPSHOT — DECIDED AND STATED ══
--     The read returns NOTHING.  Concretely, `frame->'energy'` is JSON null, and
--     ottoq_energy_cost_for_run returns zeros with `snapshots = 0`.  It never
--     falls back to another run, to a depot-wide row, or to a default.  Empty is
--     not clean — but "this run measured no energy" is a true statement and
--     "the grid imported 812 kW" borrowed from a dead run is not.  The caller
--     can tell the two apart: null/0-snapshots is unambiguous.
--
-- ══ NULL-RUN ROWS — 2,907 OF THEM, AND HOW THEY ARE TREATED ══
--     site_energy_snapshots holds 2,907 rows with sim_run_id IS NULL (2,455 at
--     depot 1111…, 452 at depot 2222… — that depot has NEVER had a run-tagged
--     row).  `se.sim_run_id = <uuid>` is NULL, not TRUE, for every one of them,
--     so they are EXCLUDED by construction — no extra predicate needed, and this
--     is deliberate, not incidental.  It matters: the newest row at depot 1111…
--     by sim timestamp is a NULL-run row dated 2026-08-15 23:00, a sim WEEK ahead
--     of the live run's clock.  An unscoped `ORDER BY timestamp DESC LIMIT 1`
--     returns that row.  Assertion A6 proves the frame does not.
--     They are NOT deleted here.  Deleting 2,907 rows nobody has justified is the
--     unearned action 0022 exists to stop.  They are named, excluded, and left.
--
-- ══ OTHER UNSCOPED READS FOUND WHILE IN HERE — REPORTED, NOT ALL FIXED ══
--     twin.ottoq_sim_advance_site_energy guards BOTH of its reads with
--         (CASE WHEN p_sim_run_id IS NULL THEN TRUE ELSE sim_run_id = p_sim_run_id END)
--     — when called with a NULL run it reads EVERY run's rows at that depot, and
--     one of those reads computes billing_period_peak (a month-to-date MAX).  It
--     is on the twin's WRITE path, so changing it changes what the twin records;
--     it is named here and deliberately left for a migration that can certify a
--     full run against it.  NOT FIXED IN 0023.
--
-- ══ WHICH PUBLISHED FIGURES THIS TAINTS — NOT RE-CERTIFIED HERE ══
--     Do not re-quote, pending re-certification against a run made after 0023:
--       · the −41% GRID-PEAK headline (already flagged);
--       · ottoq_ab_runs.energy_peak_kw and .peak_demand_pct_of_cap for every row
--         written before 0022 — ottoq_score_run's v_peak was an unfiltered
--         depot-wide MAX(grid_import_kw) at the time;
--       · any $/day or demand-charge figure from ottoq_energy_cost_for_run for a
--         run that wrote no tagged snapshot — those came from the wall-clock
--         fallback removed in §5, i.e. from other runs' rows;
--       · the 'energy' block of any ottoq_decision_snapshots row recorded for a
--         run that was not the globally-newest run at record time.
--     0023 makes the numbers honest GOING FORWARD.  It does not restate them.
--
-- ══ SAFETY ══
--     Nothing dropped.  No VACUUM FULL.  No cron created, altered or disabled —
--     cron 12 is the START engine and is not touched.  No run started or stopped
--     by this file.  Every routine replaced is md5-guarded against the exact
--     pre-image it was written for, and every pre-image is snapshotted first.
--     Single transaction: any failing assertion rolls back all of it.
-- ============================================================================

BEGIN;

SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout = '15s';

-- ---------------------------------------------------------------------------
-- §1  PRE-IMAGES — capture before touching anything
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0023_pre', 'function', 'public', p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace
   AND p.proname IN ('ottoq_sim_run_scenario','ottoq_build_decision_frame',
                     'ottoq_capture_decision_snapshot','ottoq_api_twin_get_state',
                     'ottoq_score_run','ottoq_energy_cost_for_run',
                     'ottoq_sim_stop_and_reset','ottoq_start_demo_run');

-- ---------------------------------------------------------------------------
-- §2  A RUN CLOSES ITS OWN NEEDS — one routine, called by the run's own
--     terminal transition.  This is the write that replaces the cross-run one.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_close_run_needs(
  p_sim_run_id uuid,
  p_reason     text DEFAULT 'run_terminated')
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
DECLARE n integer;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 0; END IF;
  UPDATE public.ottoq_visit_needs vn
     SET status = 'superseded',
         meta   = COALESCE(vn.meta,'{}'::jsonb)
                  || jsonb_build_object('closed_by','ottoq_close_run_needs',
                                        'close_reason', p_reason,
                                        'closed_at', now())
   WHERE vn.sim_run_id = p_sim_run_id
     AND vn.status IN ('open','in_progress');
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$fn$;

COMMENT ON FUNCTION public.ottoq_close_run_needs(uuid, text) IS
'Closes ONE run''s own still-open visit needs. Scoped to the run named, never to a '
'depot: this is the run finalising its own ledger, not a later run editing it. '
'Called by the ottoq_sim_runs_close_needs trigger on every terminal transition. '
'Total: a NULL run id, an unknown run id, or a run with nothing open all return 0.';

CREATE OR REPLACE FUNCTION public.ottoq_tg_close_run_needs_on_terminal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
DECLARE n integer;
BEGIN
  -- No EXCEPTION handler on purpose. A swallowed failure here would silently
  -- restore the exact defect this migration removes: a run reaching terminal
  -- with its needs still open, for the NEXT run to clean up.
  n := public.ottoq_close_run_needs(NEW.sim_run_id, 'run_' || NEW.status);
  RETURN NULL;
END;
$fn$;

DROP TRIGGER IF EXISTS ottoq_sim_runs_close_needs ON public.ottoq_sim_runs;
CREATE TRIGGER ottoq_sim_runs_close_needs
AFTER UPDATE OF status ON public.ottoq_sim_runs
FOR EACH ROW
WHEN (OLD.status IN ('initializing','running','paused')
  AND NEW.status IN ('completed','failed','aborted'))
EXECUTE FUNCTION public.ottoq_tg_close_run_needs_on_terminal();

COMMENT ON FUNCTION public.ottoq_tg_close_run_needs_on_terminal() IS
'A run''s needs close when the RUN ends, not when the next one starts. Fires on '
'every path out of a live status: ottoq_sim_stop_and_reset (completed), '
'ottoq_start_demo_run (aborted), ottoq_sim_run_scenario''s supersede (completed), '
'and natural end-of-clock. Deliberately does NOT fire on running -> paused: a '
'paused run is still live and its open needs are still its own.';

-- ---------------------------------------------------------------------------
-- §3  ONE-TIME REPAIR — needs left open by a run that already ended.
--     Declared, counted, and done once here rather than by every future start.
--     Measured before writing this file: 0 rows. Recorded anyway, because the
--     invariant asserted in A4 must hold for ledgers that predate the trigger.
-- ---------------------------------------------------------------------------
DO $backfill$
DECLARE n integer;
BEGIN
  UPDATE public.ottoq_visit_needs vn
     SET status = 'superseded',
         meta   = COALESCE(vn.meta,'{}'::jsonb)
                  || jsonb_build_object('closed_by','0023_backfill_terminal_run',
                                        'close_reason','run_already_terminal',
                                        'closed_at', now())
    FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id = vn.sim_run_id
     AND r.status IN ('completed','failed','aborted')
     AND vn.status IN ('open','in_progress');
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE '0023 backfill: % need(s) closed on already-terminal runs', n;
END
$backfill$;

-- ---------------------------------------------------------------------------
-- §4  NARROW THE CROSS-RUN WRITE.  Surgical, md5-guarded — the pre-image is
--     9,084 bytes of START path and is not retyped.
-- ---------------------------------------------------------------------------
DO $patch_scenario$
DECLARE v_def text; v_new text; v_from text; v_to text; v_md5 text;
BEGIN
  SELECT pg_get_functiondef(oid), md5(pg_get_functiondef(oid)) INTO v_def, v_md5
    FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='ottoq_sim_run_scenario';
  IF v_md5 <> '51475802c5357d99bf5d3f3a6db2c7e5' THEN
    RAISE EXCEPTION '0023 refused: ottoq_sim_run_scenario is not the audited pre-image (md5 %)', v_md5;
  END IF;

  -- (i) the predicate: ownerless rows only.
  v_from := '   WHERE vn.vehicle_id = v.id AND v.home_depot_id = v_scenario.default_depot_id';
  IF (length(v_def) - length(replace(v_def, v_from, ''))) / length(v_from) <> 1 THEN
    RAISE EXCEPTION '0023 refused: expected exactly one depot-wide visit-needs predicate';
  END IF;
  v_to := v_from || E'\n     AND vn.sim_run_id IS NULL';
  v_new := replace(v_def, v_from, v_to);

  -- (ii) the comment must say what the statement now does.
  v_from := '  -- a superseded run''s open needs must not leak into the new world';
  IF (length(v_new) - length(replace(v_new, v_from, ''))) / length(v_from) <> 1 THEN
    RAISE EXCEPTION '0023 refused: expected exactly one supersede comment line';
  END IF;
  v_to :=
    '  -- 0023: OWNERLESS needs only. A run''s own open needs are closed by the run''s'  || E'\n' ||
    '  -- OWN terminal transition (trigger ottoq_sim_runs_close_needs), including the'   || E'\n' ||
    '  -- run this call is superseding one statement above and the run the start button' || E'\n' ||
    '  -- aborted before calling here. What no run transition can ever reach is a need'  || E'\n' ||
    '  -- with no sim_run_id at all -- that, and only that, is cleared here. A finished' || E'\n' ||
    '  -- run''s ledger is read-only.';
  v_new := replace(v_new, v_from, v_to);

  EXECUTE v_new;
  RAISE NOTICE '0023 narrowed ottoq_sim_run_scenario to ownerless visit needs';
END
$patch_scenario$;

-- ---------------------------------------------------------------------------
-- §5  THE ENERGY READS TAKE THE RUN THEY WERE ASKED ABOUT
-- ---------------------------------------------------------------------------
DO $patch_energy$
DECLARE v_def text; v_new text; v_from text; v_to text; v_md5 text;
BEGIN
  ---------------------------------------------------------------- frame ------
  SELECT pg_get_functiondef(oid), md5(pg_get_functiondef(oid)) INTO v_def, v_md5
    FROM pg_proc WHERE pronamespace='public'::regnamespace
      AND proname='ottoq_build_decision_frame'
      AND pg_get_function_identity_arguments(oid) = 'p_depot_id uuid';
  IF v_md5 <> 'cf815226fa0ff97ee20605e977b3ffd0' THEN
    RAISE EXCEPTION '0023 refused: ottoq_build_decision_frame(uuid) is not the audited 0022 post-image (md5 %)', v_md5;
  END IF;

  -- Build the 2-arg overload from the live 1-arg body by transform, so the
  -- vehicles/stalls/sessions/bess blocks cannot drift between the two forms.
  v_from := 'public.ottoq_build_decision_frame(p_depot_id uuid)';
  IF (length(v_def) - length(replace(v_def, v_from, ''))) / length(v_from) <> 1 THEN
    RAISE EXCEPTION '0023 refused: could not locate the frame signature exactly once';
  END IF;
  v_new := replace(v_def, v_from, 'public.ottoq_build_decision_frame(p_depot_id uuid, p_sim_run_id uuid)');

  v_from := 'AND se.sim_run_id = public.ottoq_current_sim_run_id()';
  IF (length(v_new) - length(replace(v_new, v_from, ''))) / length(v_from) <> 1 THEN
    RAISE EXCEPTION '0023 refused: expected exactly one energy run-filter in the frame';
  END IF;
  v_new := replace(v_new, v_from, 'AND se.sim_run_id = p_sim_run_id');
  EXECUTE v_new;
  RAISE NOTICE '0023 created ottoq_build_decision_frame(uuid, uuid)';
END
$patch_energy$;

-- The 1-arg form is KEPT and delegates. Callers not named in this migration
-- keep today's behaviour exactly; nothing is dropped, nothing is ambiguous
-- (one argument resolves to this, two to the overload).
CREATE OR REPLACE FUNCTION public.ottoq_build_decision_frame(p_depot_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
  SELECT public.ottoq_build_decision_frame(p_depot_id, public.ottoq_current_sim_run_id());
$fn$;

COMMENT ON FUNCTION public.ottoq_build_decision_frame(uuid) IS
'Run-blind compatibility form: resolves the run with ottoq_current_sim_run_id() and '
'delegates. Any caller that KNOWS its run must call the two-argument form instead — '
'the global "current run" is not necessarily the run being recorded or scored.';

COMMENT ON FUNCTION public.ottoq_build_decision_frame(uuid, uuid) IS
'The decision frame for one depot AS SEEN BY ONE RUN. The energy block is the newest '
'site_energy_snapshots row belonging to p_sim_run_id, or JSON null if that run wrote '
'none — never another run''s row, never a NULL-run row (se.sim_run_id = p_sim_run_id '
'is NULL, not TRUE, for the 2,907 untagged rows), never a default.';

DO $patch_callers$
DECLARE v_def text; v_new text; v_from text; v_to text; v_md5 text;
BEGIN
  ------------------------------------------------- decision recorder ---------
  SELECT pg_get_functiondef(oid), md5(pg_get_functiondef(oid)) INTO v_def, v_md5
    FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='ottoq_capture_decision_snapshot';
  IF v_md5 <> '7b68fcabdc5ab0f481cbb45c16b12abb' THEN
    RAISE EXCEPTION '0023 refused: ottoq_capture_decision_snapshot is not the audited pre-image (md5 %)', v_md5;
  END IF;
  v_from := 'ottoq_build_decision_frame(p_depot_id)';
  IF (length(v_def) - length(replace(v_def, v_from, ''))) / length(v_from) <> 1 THEN
    RAISE EXCEPTION '0023 refused: capture_decision_snapshot frame call not found exactly once';
  END IF;
  EXECUTE replace(v_def, v_from, 'ottoq_build_decision_frame(p_depot_id, p_sim_run_id)');

  ------------------------------------------------------- cockpit API ---------
  SELECT pg_get_functiondef(oid), md5(pg_get_functiondef(oid)) INTO v_def, v_md5
    FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='ottoq_api_twin_get_state';
  IF v_md5 <> '3e42aab4b127deef324b9f2eaa13bac2' THEN
    RAISE EXCEPTION '0023 refused: ottoq_api_twin_get_state is not the audited pre-image (md5 %)', v_md5;
  END IF;
  v_from := 'ottoq_build_decision_frame(r.depot_id)';
  IF (length(v_def) - length(replace(v_def, v_from, ''))) / length(v_from) <> 1 THEN
    RAISE EXCEPTION '0023 refused: api_twin_get_state frame call not found exactly once';
  END IF;
  EXECUTE replace(v_def, v_from, 'ottoq_build_decision_frame(r.depot_id, r.sim_run_id)');

  ------------------------------------------------------------ scorer ---------
  SELECT pg_get_functiondef(oid), md5(pg_get_functiondef(oid)) INTO v_def, v_md5
    FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='ottoq_score_run';
  IF v_md5 <> '41a3e2e192142f2fba879f6776ffa865' THEN
    RAISE EXCEPTION '0023 refused: ottoq_score_run is not the audited pre-image (md5 %)', v_md5;
  END IF;
  v_from := 'ottoq_build_decision_frame(v_run.depot_id)';
  IF (length(v_def) - length(replace(v_def, v_from, ''))) / length(v_from) <> 1 THEN
    RAISE EXCEPTION '0023 refused: score_run frame call not found exactly once';
  END IF;
  EXECUTE replace(v_def, v_from, 'ottoq_build_decision_frame(v_run.depot_id, p_sim_run_id)');

  ------------------------------------------- energy $ — kill the fallback ----
  SELECT pg_get_functiondef(oid), md5(pg_get_functiondef(oid)) INTO v_def, v_md5
    FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='ottoq_energy_cost_for_run';
  IF v_md5 <> '40005c90c58ab1d277933b45b5e6982e' THEN
    RAISE EXCEPTION '0023 refused: ottoq_energy_cost_for_run is not the audited pre-image (md5 %)', v_md5;
  END IF;
  v_from :=
    '     WHERE CASE WHEN v_has_tagged'                                             || E'\n' ||
    '                THEN sim_run_id = p_sim_run_id'                                || E'\n' ||
    '                ELSE depot_id = v_depot AND created_at >= v_start AND created_at <= v_end' || E'\n' ||
    '           END';
  IF (length(v_def) - length(replace(v_def, v_from, ''))) / length(v_from) <> 1 THEN
    RAISE EXCEPTION '0023 refused: energy_cost_for_run fallback block not found exactly once';
  END IF;
  v_to :=
    '     -- 0023: no fallback. A run with no snapshot of its own costs nothing and'  || E'\n' ||
    '     -- says so (snapshots = 0). The removed ELSE branch took a REAL-CLOCK window' || E'\n' ||
    '     -- over every run''s rows at this depot, which is another run''s money.'      || E'\n' ||
    '     WHERE sim_run_id = p_sim_run_id';
  v_new := replace(v_def, v_from, v_to);
  -- v_has_tagged is left assigned but unused on purpose: it is now an honesty
  -- probe, not a switch, and removing the DECLARE would widen this patch.
  EXECUTE v_new;
  RAISE NOTICE '0023 threaded the run id through all four energy readers';
END
$patch_callers$;

-- ---------------------------------------------------------------------------
-- §6  ASSERTIONS — every claim above, proved before COMMIT
-- ---------------------------------------------------------------------------
DO $assert$
DECLARE
  n int; v_src text; v_ok boolean;
  v_depot uuid := '22222222-2222-2222-2222-222222222222';  -- no live run here
  v_scen  uuid;
  v_runA  uuid := gen_random_uuid();   -- terminates while live  -> must self-close
  v_runB  uuid := gen_random_uuid();   -- already terminal       -> must be untouchable
  v_vehA  uuid; v_vehB uuid; v_vehC uuid;
  v_nA uuid := gen_random_uuid(); v_nB uuid := gen_random_uuid(); v_nC uuid := gen_random_uuid();
  v_st text; v_at timestamptz; v_expect timestamptz; d record;
BEGIN
  SELECT scenario_id INTO v_scen FROM public.ottoq_scenarios LIMIT 1;
  SELECT id INTO v_vehA FROM public.vehicles WHERE home_depot_id = v_depot ORDER BY id LIMIT 1;
  SELECT id INTO v_vehB FROM public.vehicles WHERE home_depot_id = v_depot ORDER BY id OFFSET 1 LIMIT 1;
  SELECT id INTO v_vehC FROM public.vehicles WHERE home_depot_id = v_depot ORDER BY id OFFSET 2 LIMIT 1;
  IF v_scen IS NULL OR v_vehC IS NULL THEN
    RAISE EXCEPTION 'A0 FAILED: no scenario, or fewer than 3 vehicles at the test depot';
  END IF;

  INSERT INTO public.ottoq_sim_runs
    (sim_run_id, scenario_id, scenario_code, status, sim_clock_start, sim_clock_current,
     sim_clock_end, depot_id, run_by, notes)
  VALUES
    (v_runA, v_scen, '0023_assert', 'initializing', now(), now(), now(), v_depot, '0023_assert', '0023 assertion scaffold'),
    (v_runB, v_scen, '0023_assert', 'initializing', now(), now(), now(), v_depot, '0023_assert', '0023 assertion scaffold');

  ---- A1  the trigger exists, is enabled, and is on the right event ----------
  SELECT t.tgenabled = 'O' INTO v_ok
    FROM pg_trigger t WHERE t.tgrelid='public.ottoq_sim_runs'::regclass
                        AND t.tgname='ottoq_sim_runs_close_needs';
  IF NOT COALESCE(v_ok,false) THEN
    RAISE EXCEPTION 'A1 FAILED: ottoq_sim_runs_close_needs is missing or disabled';
  END IF;
  RAISE NOTICE 'A1 PASSED: a run''s terminal transition is trapped';

  ---- A2  BEHAVIOURAL: a run closes its OWN needs when IT ends ---------------
  --       (this is what stop/abort/supersede never did — 99 rows in 0022)
  INSERT INTO public.ottoq_visit_needs
    (visit_id, vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, urgency, atoms, status, source)
  VALUES (v_nA, v_vehA, v_runA, v_depot, now(), '0023_assert_A', 'standard', '[]'::jsonb, 'open', '0023_assert');

  UPDATE public.ottoq_sim_runs SET status='completed' WHERE sim_run_id = v_runA;

  SELECT status INTO v_st FROM public.ottoq_visit_needs WHERE visit_id = v_nA;
  IF v_st <> 'superseded' THEN
    RAISE EXCEPTION 'A2 FAILED: a run ended with its own need still %', v_st;
  END IF;
  RAISE NOTICE 'A2 PASSED: the run that ends closes its own ledger';

  ---- A3  BEHAVIOURAL: a TERMINAL run''s rows cannot be moved by a new start --
  --       runB is made terminal FIRST, then given an open need — a legacy row
  --       the trigger never saw. Then the EXACT narrowed predicate from the
  --       patched ottoq_sim_run_scenario is executed against this depot.
  UPDATE public.ottoq_sim_runs SET status='completed' WHERE sim_run_id = v_runB;
  INSERT INTO public.ottoq_visit_needs
    (visit_id, vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, urgency, atoms, status, source)
  VALUES (v_nB, v_vehB, v_runB, v_depot, now(), '0023_assert_B', 'standard', '[]'::jsonb, 'open', '0023_assert');
  -- and an OWNERLESS need, which the narrowed statement MUST still clear
  INSERT INTO public.ottoq_visit_needs
    (visit_id, vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, urgency, atoms, status, source)
  VALUES (v_nC, v_vehC, NULL, v_depot, now(), '0023_assert_C', 'standard', '[]'::jsonb, 'open', '0023_assert');

  UPDATE public.ottoq_visit_needs vn SET status = 'superseded'
    FROM public.vehicles v
   WHERE vn.vehicle_id = v.id AND v.home_depot_id = v_depot
     AND vn.sim_run_id IS NULL
     AND vn.status IN ('open','in_progress');

  SELECT status INTO v_st FROM public.ottoq_visit_needs WHERE visit_id = v_nB;
  IF v_st <> 'open' THEN
    RAISE EXCEPTION 'A3 FAILED: a new run moved a finished run''s need to %', v_st;
  END IF;
  SELECT status INTO v_st FROM public.ottoq_visit_needs WHERE visit_id = v_nC;
  IF v_st <> 'superseded' THEN
    RAISE EXCEPTION 'A3 FAILED: the supersede stopped clearing ownerless stale needs (got %)', v_st;
  END IF;
  RAISE NOTICE 'A3 PASSED: finished run untouched, ownerless stale need still cleared';

  -- scaffold down: children first, then the parent, or 0022's FKs refuse.
  DELETE FROM public.ottoq_visit_needs WHERE visit_id IN (v_nA, v_nB, v_nC);
  DELETE FROM public.ottoq_sim_runs   WHERE sim_run_id IN (v_runA, v_runB);

  ---- A4  the invariant now holds across the whole ledger --------------------
  SELECT count(*) INTO n
    FROM public.ottoq_visit_needs vn
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = vn.sim_run_id
   WHERE r.status IN ('completed','failed','aborted')
     AND vn.status IN ('open','in_progress');
  IF n <> 0 THEN
    RAISE EXCEPTION 'A4 FAILED: % need(s) still open on a finished run', n;
  END IF;
  RAISE NOTICE 'A4 PASSED: no finished run holds an open need';

  ---- A5  the source really is narrowed, and the depot-wide write is gone ----
  SELECT prosrc INTO v_src FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='ottoq_sim_run_scenario';
  IF v_src NOT LIKE '%vn.sim_run_id IS NULL%' THEN
    RAISE EXCEPTION 'A5 FAILED: the supersede is not narrowed to ownerless rows';
  END IF;
  IF v_src LIKE '%a superseded run''s open needs must not leak%' THEN
    RAISE EXCEPTION 'A5 FAILED: the old depot-wide supersede comment is still present';
  END IF;
  RAISE NOTICE 'A5 PASSED: ottoq_sim_run_scenario writes only ownerless needs';

  ---- A6  BEHAVIOURAL: the energy read lands on THIS run''s row or on nothing -
  --       plpgsql loop, not a CTE: each depot is evaluated separately.
  FOR d IN SELECT id FROM public.depots LOOP
    SELECT (public.ottoq_build_decision_frame(d.id, public.ottoq_current_sim_run_id())
            -> 'energy' ->> 'at')::timestamptz INTO v_at;
    SELECT max(se.timestamp) INTO v_expect
      FROM public.site_energy_snapshots se
     WHERE se.depot_id = d.id AND se.sim_run_id = public.ottoq_current_sim_run_id();
    IF v_at IS DISTINCT FROM v_expect THEN
      RAISE EXCEPTION 'A6 FAILED: depot % resolved energy to % , this run''s newest is %',
        d.id, v_at, v_expect;
    END IF;
    -- and it must NOT be the globally newest row when that row is not ours
    SELECT max(se.timestamp) INTO v_expect
      FROM public.site_energy_snapshots se WHERE se.depot_id = d.id;
    IF v_at IS NOT NULL AND v_at = v_expect
       AND NOT EXISTS (SELECT 1 FROM public.site_energy_snapshots se
                        WHERE se.depot_id = d.id AND se.timestamp = v_expect
                          AND se.sim_run_id = public.ottoq_current_sim_run_id()) THEN
      RAISE EXCEPTION 'A6 FAILED: depot % returned a foreign newest row', d.id;
    END IF;
  END LOOP;
  RAISE NOTICE 'A6 PASSED: every depot resolves energy to its own run''s row, or to nothing';

  ---- A7  the three callers pass their run, and the $ fallback is gone -------
  SELECT prosrc INTO v_src FROM pg_proc WHERE pronamespace='public'::regnamespace
     AND proname='ottoq_capture_decision_snapshot';
  IF v_src NOT LIKE '%ottoq_build_decision_frame(p_depot_id, p_sim_run_id)%' THEN
    RAISE EXCEPTION 'A7 FAILED: the decision recorder still builds a run-blind frame';
  END IF;
  SELECT prosrc INTO v_src FROM pg_proc WHERE pronamespace='public'::regnamespace
     AND proname='ottoq_api_twin_get_state';
  IF v_src NOT LIKE '%ottoq_build_decision_frame(r.depot_id, r.sim_run_id)%' THEN
    RAISE EXCEPTION 'A7 FAILED: the cockpit API still builds a run-blind frame';
  END IF;
  SELECT prosrc INTO v_src FROM pg_proc WHERE pronamespace='public'::regnamespace
     AND proname='ottoq_score_run';
  IF v_src NOT LIKE '%ottoq_build_decision_frame(v_run.depot_id, p_sim_run_id)%' THEN
    RAISE EXCEPTION 'A7 FAILED: the scorer still builds a run-blind frame';
  END IF;
  SELECT prosrc INTO v_src FROM pg_proc WHERE pronamespace='public'::regnamespace
     AND proname='ottoq_energy_cost_for_run';
  IF v_src LIKE '%created_at >= v_start%' THEN
    RAISE EXCEPTION 'A7 FAILED: energy_cost_for_run still falls back to a wall-clock window';
  END IF;
  RAISE NOTICE 'A7 PASSED: recorder, cockpit, scorer and costing all name their run';

  ---- A8  no orphan creatable — 0022''s guarantees are intact ----------------
  SELECT count(*) INTO n FROM pg_constraint
   WHERE contype='f' AND confrelid='public.ottoq_sim_runs'::regclass;
  IF n <> 45 THEN
    RAISE EXCEPTION 'A8 FAILED: % FKs reference ottoq_sim_runs, expected 45', n;
  END IF;
  SELECT count(*) INTO n FROM pg_constraint
   WHERE contype='f' AND confrelid='public.ottoq_sim_runs'::regclass AND confdeltype='c';
  IF n <> 0 THEN
    RAISE EXCEPTION 'A8 FAILED: % run FK(s) are ON DELETE CASCADE', n;
  END IF;
  SELECT count(*) INTO n FROM public.ottoq_check_run_scope_registry() WHERE severity='block';
  IF n <> 0 THEN
    RAISE EXCEPTION 'A8 FAILED: % blocking run-scope registry defect(s)', n;
  END IF;
  -- and the scaffold left nothing behind
  SELECT count(*) INTO n FROM public.ottoq_sim_runs WHERE run_by = '0023_assert';
  IF n <> 0 THEN RAISE EXCEPTION 'A8 FAILED: assertion scaffold survived'; END IF;
  SELECT count(*) INTO n FROM public.ottoq_visit_needs WHERE source = '0023_assert';
  IF n <> 0 THEN RAISE EXCEPTION 'A8 FAILED: assertion needs survived'; END IF;
  RAISE NOTICE 'A8 PASSED: 45 run FKs, 0 CASCADE, 0 registry defects, scaffold clean';

  ---- A9  the compatibility form still exists and still resolves -------------
  SELECT count(*) INTO n FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='ottoq_build_decision_frame';
  IF n <> 2 THEN
    RAISE EXCEPTION 'A9 FAILED: % ottoq_build_decision_frame form(s), expected 2', n;
  END IF;
  PERFORM public.ottoq_build_decision_frame(
            (SELECT id FROM public.depots ORDER BY id LIMIT 1));
  RAISE NOTICE 'A9 PASSED: the one-argument frame is intact and delegates';

  RAISE NOTICE '0023 assertions A1-A9 PASSED';
END
$assert$;

COMMIT;
