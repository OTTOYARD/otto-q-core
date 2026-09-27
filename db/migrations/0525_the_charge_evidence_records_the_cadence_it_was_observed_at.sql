-- migration-version: 20260927131932
-- migration-name:    the_charge_evidence_records_the_cadence_it_was_observed_at
--
-- 0525  **G248: the charge-duration evidence did not record the cadence a charge was observed at, and its reader did
--       not ask. A charge on a run ticking every 30 sim-minutes starts and ends on the half-hour and its length is known
--       to 30 minutes; the next fit of the charge window would have read it beside charges seen at half a minute. The
--       capture now records the run's sim-minutes per tick at the stop, the reader leaves out anything coarser than two
--       minutes, and a reaped session -- ended on another run's clock -- is no longer filed as a charge.**
--       `db/checks/0391`.
--
-- ══ §1 WHAT WAS WRONG ══════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_charge_duration_ledger` records `tick_interval_seconds`, which is 30 on a live run and a fixed one alike: the
--   cadence lives in the run's payload (`tick_minutes_actual`, written every tick) and the demo-run purge can delete the
--   run row. This morning's first validation start, 11f15672, ran at the fixed 30 sim-minutes a tick (started without
--   `ottoq_set_playback`) and filed 6 charges, all on the half-hour grid; every operator run before it was live and has
--   0 there (0391 §1). The fit read none of them only because of filters written for other reasons: the 6 completed
--   charges span 90 minutes against kept fit 6's 120-minute minimum, and the 33 reaped ones carry `orphaned_run`.
--   The reaped ones are the second half. The next run's first tick reaped 11f15672's open sessions in
--   `twin.ottoq_sim_advance_charge_sessions`, whose orphan branch stamps the REAPING run's clock as `ended_at`, and the
--   capture filed each: 33 charges that ended before they started. That reap was possible only because the next run's
--   fleet seed failed (G249); 0524 closes such leftovers in the seed, on their own run's clock, as `sim_reset`.
--   Which is exactly why this file is needed beside it: after 0524, a hand-stopped fixed-cadence run's leftovers are
--   filed as `sim_reset` charges -- the kind the reader keeps as censored observations -- with 30-minute ends.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `ottoq_charge_duration_ledger.tick_minutes`: the sim-minutes per tick of the charge's run when it stopped --
--       `payload.tick_minutes_actual`, else the run's fixed `tick_interval_seconds * time_scale / 60`. NULL on every row
--       filed before this file (the ledger is append-only, so nothing is backfilled); of those, the only coarse ones are
--       11f15672's, which the reader already leaves out (§1).
--   (2) `ottoq_capture_charge_duration` fills it (`capture_version` 3) and no longer files a session stopped as
--       `orphaned_run`: its end is another run's clock, not an observation. `ocpp_sessions` keeps the reap.
--   (3) `ottoq_charge_window_evidence` keeps a charge only if `COALESCE(tick_minutes, 0) <= 2`: the live cadence is
--       0.3-1.5 sim-minutes (G161) and a production feed ticks at 2; the dial pairs' 6 and the fixed 30 are out. The
--       dial arms' own metric (`ottoq_dial_arm_metrics`) reads the ledger directly and is unchanged.
--   The reaper is left as it is: it is on the certified tick path, and after 0524 nothing leaves an open session for it.
--
-- ══ §3 forces_recert FALSE, forces_dial_restart FALSE ═════════════════════════════════════════════════════════════
--
--   The capture returns before filing anything for a certification arm, and neither the reader nor the fit is on a
--   certified path. A dial arm's rows gain a column; its metrics read none of what changed.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0525 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                AND table_name = 'ottoq_charge_duration_ledger' AND column_name = 'tick_minutes') THEN
    RAISE EXCEPTION '0525 P2: already applied';
  END IF;
  -- the reader is read only by the fit, and the dial arms read the ledger without it
  IF (SELECT array_agg(p.oid::regprocedure::text) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc LIKE '%ottoq_charge_window_evidence%'
         AND p.proname <> 'ottoq_charge_window_evidence')
     IS DISTINCT FROM ARRAY['ottoq_fit_charge_window_calibration(uuid,numeric,numeric,integer,integer,numeric[],timestamp with time zone,text)'] THEN
    RAISE EXCEPTION '0525 P2: something other than the fit reads ottoq_charge_window_evidence';
  END IF;
  -- nothing reads capture_version, so bumping it changes no reader
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc LIKE '%capture_version%'
                AND p.proname <> 'ottoq_capture_charge_duration') THEN
    RAISE EXCEPTION '0525 P2: something reads capture_version';
  END IF;
  -- the only rows on the half-hour grid the reader could see are 11f15672's, and it keeps none of them today
  IF EXISTS (SELECT 1 FROM public.ottoq_charge_duration_ledger l
              WHERE l.run_by IN ('operator_demo','production_live')
                AND extract(second FROM l.started_at) = 0 AND extract(minute FROM l.started_at)::int % 30 = 0
                AND extract(second FROM l.ended_at) = 0 AND extract(minute FROM l.ended_at)::int % 30 = 0
                AND l.sim_run_id IS DISTINCT FROM '11f15672-bb3b-407d-ba39-90859577d7ec'::uuid) THEN
    RAISE EXCEPTION '0525 P2: a charge on the half-hour grid from a run other than 11f15672';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0525_pre', 'function', 'public', s.object_name, pg_get_functiondef(s.oid), md5(pg_get_functiondef(s.oid))
  FROM (VALUES ('ottoq_capture_charge_duration', 'public.ottoq_capture_charge_duration()'::regprocedure::oid),
               ('ottoq_charge_window_evidence',
                'public.ottoq_charge_window_evidence(uuid,timestamptz,numeric,integer,numeric[])'::regprocedure::oid))
       AS s(object_name, oid);

-- what the reader returns today, to prove below that the filter leaves every row filed before it
CREATE TEMP TABLE v0525_reader_before ON COMMIT DROP AS
SELECT e.session_id FROM public.ottoq_charge_window_evidence('11111111-1111-1111-1111-111111111111', now(), 2.0, 120,
                                                             ARRAY[10, 20, 30]::numeric[]) e;

-- ── (1) the column ──
ALTER TABLE public.ottoq_charge_duration_ledger ADD COLUMN tick_minutes numeric;
COMMENT ON COLUMN public.ottoq_charge_duration_ledger.tick_minutes IS
  '0525 (G248): the sim-minutes per tick of the charge''s run when it stopped (payload.tick_minutes_actual, else the '
  'fixed tick_interval_seconds * time_scale / 60). A charge seen at a coarse cadence is known only to one tick; the '
  'evidence reader keeps charges at 2 minutes or finer. NULL on rows filed before 0525, which are not backfilled.';

-- ── (2) the capture records it, and files no reap ──
DO $patch_capture$
DECLARE
  v_def text;
  v_pairs text[][] := ARRAY[
    ARRAY[$o1$  v_bk_source text;          -- 0515$o1$,
          $n1$  v_bk_source text;          -- 0515
  v_tick_min  numeric;       -- 0525 (G248)$n1$],
    ARRAY[$o2$    SELECT r.run_by, r.tick_interval_seconds INTO v_run_by, v_tick
      FROM public.ottoq_sim_runs r WHERE r.sim_run_id = NEW.sim_run_id;$o2$,
          $n2$    -- 0525 (G248): and the cadence the charge was seen at, which the run row may not outlive (the demo purge)
    SELECT r.run_by, r.tick_interval_seconds,
           COALESCE((r.payload->>'tick_minutes_actual')::numeric, r.tick_interval_seconds * r.time_scale / 60.0)
      INTO v_run_by, v_tick, v_tick_min
      FROM public.ottoq_sim_runs r WHERE r.sim_run_id = NEW.sim_run_id;$n2$],
    ARRAY[$o3$BEGIN
  IF NEW.sim_run_id IS NOT NULL THEN$o3$,
          $n3$BEGIN
  -- 0525 (G248): a reaped session ended on the REAPING run's clock (twin.ottoq_sim_advance_charge_sessions' orphan
  -- branch), so its length is not an observation of anything; ocpp_sessions keeps the reap
  IF NEW.stopped_reason = 'orphaned_run' THEN
    RETURN NULL;
  END IF;
  IF NEW.sim_run_id IS NOT NULL THEN$n3$],
    ARRAY[$o4$    booking_id, booked_from, booked_to, booking_state, booking_source)$o4$,
          $n4$    booking_id, booked_from, booked_to, booking_state, booking_source, tick_minutes)$n4$],
    ARRAY[$o5$    2, v_tgt, v_vis_tgt, v_vis_id, v_vsoc,
    v_bk_id, v_bk_from, v_bk_to, v_bk_state, v_bk_source)$o5$,
          $n5$    3, v_tgt, v_vis_tgt, v_vis_id, v_vsoc,   -- 0525: capture_version 3 records the cadence
    v_bk_id, v_bk_from, v_bk_to, v_bk_state, v_bk_source, v_tick_min)$n5$]];
  i int; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_capture_charge_duration()'::regprocedure);
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0525: capture patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch_capture$;

-- ── (3) the reader keeps a charge only at the live cadence or finer ──
DO $patch_reader$
DECLARE
  v_def text;
  v_old text := $o$       AND l.stopped_reason IN ('completed', 'sim_reset')$o$;
  v_new text := $n$       AND l.stopped_reason IN ('completed', 'sim_reset')
       -- 0525 (G248): a charge seen at a coarse cadence is known only to one tick (30 minutes on a fixed-cadence run);
       -- live runs tick 0.3-1.5 sim-minutes and a production feed 2. NULL: filed before 0525 (0391 §1 read them all).
       AND COALESCE(l.tick_minutes, 0) <= 2$n$;
  n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_charge_window_evidence(uuid,timestamptz,numeric,integer,numeric[])'::regprocedure);
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0525: reader patch matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch_reader$;

DO $verify$
DECLARE v_cap text; v_rdr text;
BEGIN
  v_cap := pg_get_functiondef('public.ottoq_capture_charge_duration()'::regprocedure);
  v_rdr := pg_get_functiondef('public.ottoq_charge_window_evidence(uuid,timestamptz,numeric,integer,numeric[])'::regprocedure);
  -- V1: the capture reads the cadence, files it, bumps its version and skips a reap before anything else; the reader
  --     filters on it; both keep SECURITY DEFINER on their search_path; and the filter leaves every row the reader
  --     returned before it
  IF position('INTO v_run_by, v_tick, v_tick_min' IN v_cap) = 0
     OR position('booking_source, tick_minutes)' IN v_cap) = 0
     OR position('v_bk_source, v_tick_min)' IN v_cap) = 0
     OR position('    3, v_tgt, v_vis_tgt' IN v_cap) = 0
     OR position('IF NEW.stopped_reason = ''orphaned_run'' THEN' IN v_cap) = 0
     OR position('IF NEW.stopped_reason = ''orphaned_run'' THEN' IN v_cap) > position('IF NEW.sim_run_id IS NOT NULL THEN' IN v_cap)
     OR position('AND COALESCE(l.tick_minutes, 0) <= 2' IN v_rdr) = 0
     OR NOT (SELECT bool_and(prosecdef) FROM pg_proc
              WHERE oid IN ('public.ottoq_capture_charge_duration()'::regprocedure,
                            'public.ottoq_charge_window_evidence(uuid,timestamptz,numeric,integer,numeric[])'::regprocedure))
     OR EXISTS (SELECT 1 FROM pg_proc
                 WHERE oid IN ('public.ottoq_capture_charge_duration()'::regprocedure,
                               'public.ottoq_charge_window_evidence(uuid,timestamptz,numeric,integer,numeric[])'::regprocedure)
                   AND proconfig IS DISTINCT FROM ARRAY['search_path=public, twin, ottoq, extensions'])
     OR EXISTS (SELECT session_id FROM v0525_reader_before
                EXCEPT
                SELECT e.session_id FROM public.ottoq_charge_window_evidence('11111111-1111-1111-1111-111111111111', now(),
                                                                           2.0, 120, ARRAY[10, 20, 30]::numeric[]) e) THEN
    RAISE EXCEPTION '0525 V1: the capture or the reader is not as intended';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule: the dial floor reads it).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0525_the_charge_evidence_records_the_cadence_it_was_observed_at', false, false,
  'Charge-duration evidence only: the capture records the run''s sim-minutes per tick and files no reaped session, and '
  'the calibration''s evidence reader keeps charges at 2 minutes a tick or finer (G248). The capture returns before '
  'filing anything for a certification arm, and the dial arms'' metrics read none of what changed.', now())
ON CONFLICT (name) DO NOTHING;

-- V3: rolled back. On two finished runs -- 11f15672 (fixed, 30 sim-minutes a tick) and 4bc19d29 (live) -- one planted
--     charge each, stopped `completed`: (a) both are filed, capture_version 3, with 30 and the live run's cadence;
--     (b) the reader keeps the live one and leaves out the fixed one; (c) a third, reaped as `orphaned_run`, is not
--     filed at all.
DO $v3$
DECLARE
  v_msg text; v_coarse uuid := '11f15672-bb3b-407d-ba39-90859577d7ec'; v_live uuid := '4bc19d29-790c-4cb0-9e2e-ae090a7da57b';
  v_stall uuid; v_cp text; v_car uuid; s_coarse uuid; s_live uuid; s_reap uuid; v_t0 timestamptz; v_row record;
BEGIN
  BEGIN
    SELECT s.id, c.ocpp_identifier INTO v_stall, v_cp FROM public.stalls s
      JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'l2'
     ORDER BY s.stall_code LIMIT 1;
    SELECT v.id INTO v_car FROM public.vehicles v
     WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous' ORDER BY v.id LIMIT 1;
    IF v_stall IS NULL OR v_car IS NULL
       OR (SELECT payload->>'tick_minutes_actual' FROM public.ottoq_sim_runs WHERE sim_run_id = v_coarse)::numeric <> 30
       OR (SELECT payload->>'tick_minutes_actual' FROM public.ottoq_sim_runs WHERE sim_run_id = v_live)::numeric > 2 THEN
      RAISE EXCEPTION '0525 V3 FAILED: the two runs or the stall to plant on are not as this test expects';
    END IF;

    v_t0 := '2026-09-27 15:00:00+00';
    -- planted already closed, with no stop reason yet: the capture fires on the reason, and one stall may hold only one
    -- ACTIVE session (uniq_ocpp_active_session_per_stall), which a live run's own charge could be
    INSERT INTO public.ocpp_sessions (depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id, connector_id,
                                      status, started_at, id_token, sim_run_id, soc_start, ambient_temp_c)
    VALUES ('11111111-1111-1111-1111-111111111111', v_stall, v_car, v_cp, 'TX-0525-V3-C', 1, 1, 'completed', v_t0,
            'TWIN-0525-V3', v_coarse, 30, 20),
           ('11111111-1111-1111-1111-111111111111', v_stall, v_car, v_cp, 'TX-0525-V3-L', 1, 1, 'completed', v_t0,
            'TWIN-0525-V3', v_live, 30, 20),
           ('11111111-1111-1111-1111-111111111111', v_stall, v_car, v_cp, 'TX-0525-V3-R', 1, 1, 'completed', v_t0,
            'TWIN-0525-V3', v_coarse, 30, 20);
    SELECT id INTO s_coarse FROM public.ocpp_sessions WHERE transaction_id = 'TX-0525-V3-C';
    SELECT id INTO s_live   FROM public.ocpp_sessions WHERE transaction_id = 'TX-0525-V3-L';
    SELECT id INTO s_reap   FROM public.ocpp_sessions WHERE transaction_id = 'TX-0525-V3-R';
    UPDATE public.ocpp_sessions SET ended_at = v_t0 + interval '95 minutes', soc_end = 60, stopped_reason = 'completed'
     WHERE id IN (s_coarse, s_live);
    UPDATE public.ocpp_sessions SET ended_at = v_t0 - interval '60 minutes', stopped_reason = 'orphaned_run'
     WHERE id = s_reap;

    SELECT tick_minutes, capture_version INTO v_row FROM public.ottoq_charge_duration_ledger WHERE session_id = s_coarse;
    IF v_row.tick_minutes IS DISTINCT FROM 30 OR v_row.capture_version IS DISTINCT FROM 3 THEN
      RAISE EXCEPTION '0525 V3 FAILED (a): the fixed-cadence charge was filed with % / version %', v_row.tick_minutes, v_row.capture_version;
    END IF;
    SELECT tick_minutes, capture_version INTO v_row FROM public.ottoq_charge_duration_ledger WHERE session_id = s_live;
    IF v_row.tick_minutes IS NULL OR v_row.tick_minutes > 2 OR v_row.capture_version IS DISTINCT FROM 3 THEN
      RAISE EXCEPTION '0525 V3 FAILED (a): the live charge was filed with % / version %', v_row.tick_minutes, v_row.capture_version;
    END IF;

    IF EXISTS (SELECT 1 FROM public.ottoq_charge_window_evidence('11111111-1111-1111-1111-111111111111', now(), 2.0, 0,
                                                                ARRAY[10, 20, 30]::numeric[]) e WHERE e.session_id = s_coarse)
       OR NOT EXISTS (SELECT 1 FROM public.ottoq_charge_window_evidence('11111111-1111-1111-1111-111111111111', now(), 2.0, 0,
                                                                ARRAY[10, 20, 30]::numeric[]) e WHERE e.session_id = s_live) THEN
      RAISE EXCEPTION '0525 V3 FAILED (b): the reader did not keep the live charge and leave out the fixed one';
    END IF;

    IF EXISTS (SELECT 1 FROM public.ottoq_charge_duration_ledger WHERE session_id = s_reap) THEN
      RAISE EXCEPTION '0525 V3 FAILED (c): a reaped session was filed as a charge';
    END IF;
    RAISE EXCEPTION '0525 V3 PASSED: filed at 30 and at the live cadence (%), version 3; the reader kept the live charge and left out the fixed one; the reap was not filed', v_row.tick_minutes;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0525 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0525 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0525_pre'; the column may stay (NULL is
--   what every earlier row holds) or go with ALTER TABLE public.ottoq_charge_duration_ledger DROP COLUMN tick_minutes.
COMMIT;
