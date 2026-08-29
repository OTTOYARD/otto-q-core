-- migration-version: 20260829171500
-- migration-name:    no_command_left_dangling
-- 0087 -- R4 and R7 of the run-reconciliation audit (db/checks/0045), both living in the same
-- function: public.ottoq_sim_release_depot, the run finalizer.
--
-- R4. MEASURED on run 9291ec6d: 18 stage commands were issued by decide_tick in the run's FINAL
-- wall-second (created_at 03:50:09, run ended 03:50:12) and no reactor pass ever ran again --
-- so they sat 'issued' forever, on vehicles the finalizer itself stands down to offline two
-- statements later. The finalizer already closes sessions, bookings, dispatches, stalls,
-- tethers, arm cycles, and vehicles. Commands were the one ledger it forgot. A command that the
-- run's end orphaned is now closed as status='expired', reason_code='run_ended' (vocabulary
-- added by 0086) -- truthful: the vehicle neither executed nor refused it; the world ended
-- first.
--
-- R7. tasks_completed counted ottoq_events rows of type 'twin.service_completed' -- an event
-- that fired 9 times on a run where 116 legs finished and 65 SDRs settled. A headline metric
-- that matches NO ledger is the 'looks like evidence' defect (0073's family). It now counts
-- SDRs: the settlement-grade definition of a completed task, equal to done service legs
-- whenever check R2 holds. Not backfilled -- the archived run keeps its 9 as evidence of what
-- the old expression measured.
--
-- Pre-image pin, read live 2026-08-29:
--   public.ottoq_sim_release_depot   8720821ff507618501aa09445029809a
-- (db/baseline's ottoq_sim_stop_and_reset text is STALE: live stop_and_reset is now a thin
--  wrapper over ottoq_sim_mark_stopped + ottoq_sim_release_depot. Anchors verified live.)

DO $do$
DECLARE
  v_oid oid; v_src text; v_new text; v_cnt int;

  -- R7 anchor: the tally expression.
  v_a1_old text := E'        tasks_completed    = (SELECT count(*) FROM ottoq_events  WHERE sim_run_id = p_sim_run_id\n                                AND event_type = ''twin.service_completed''),';
  v_a1_new text := E'        -- 0087: settlement-grade definition -- one completed task, one SDR. The old\n'
                || E'        -- expression counted twin.service_completed events: 9 on a run with 65 settled\n'
                || E'        -- operations, a headline matching no ledger.\n'
                || E'        tasks_completed    = (SELECT count(*) FROM ottoq_service_detail_records\n                                WHERE sim_run_id = p_sim_run_id),';

  -- R4 anchor: the dispatches close. The command sweep goes immediately before it.
  v_a2_old text := E'  UPDATE ottoq_vehicle_dispatches\n     SET status=''completed'',';
  v_a2_new text := E'  -- 0087: a run that ends leaves no command dangling. 18 final-second stage commands\n'
                || E'  -- on 9291ec6d stayed ''issued'' forever; the vehicles they addressed are stood down\n'
                || E'  -- to offline below, so nothing could ever have reacted.\n'
                || E'  UPDATE ottoq_vehicle_commands\n'
                || E'     SET status=''expired'', reason_code=''run_ended'',\n'
                || E'         confirmed_at=now(), confirmed_by=''run_finalizer'',\n'
                || E'         payload = COALESCE(payload,''{}''::jsonb) || jsonb_build_object(''expired_reason'',''run_ended_before_reaction'')\n'
                || E'   WHERE sim_run_id = p_sim_run_id AND status IN (''issued'',''confirmed'');\n\n'
                || E'  UPDATE ottoq_vehicle_dispatches\n     SET status=''completed'',';
BEGIN
  SELECT p.oid INTO STRICT v_oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_release_depot';
  v_src := pg_get_functiondef(v_oid);

  IF md5(v_src) <> '8720821ff507618501aa09445029809a' THEN
    RAISE EXCEPTION '0087 abort: release_depot drifted from the pinned pre-image (md5 %)', md5(v_src);
  END IF;

  v_cnt := (length(v_src) - length(replace(v_src, v_a1_old, ''))) / length(v_a1_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0087 abort: tasks_completed anchor found % times, expected 1', v_cnt;
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a2_old, ''))) / length(v_a2_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0087 abort: dispatches anchor found % times, expected 1', v_cnt;
  END IF;

  v_new := replace(v_src, v_a1_old, v_a1_new);
  v_new := replace(v_new, v_a2_old, v_a2_new);
  EXECUTE v_new;

  v_src := pg_get_functiondef(v_oid);
  IF position('run_ended_before_reaction' in v_src) = 0
     OR position('ottoq_service_detail_records' in v_src) = 0 THEN
    RAISE EXCEPTION '0087 abort: patched finalizer does not carry both fixes';
  END IF;

  RAISE NOTICE '0087 applied: the finalizer closes dangling commands; tasks_completed counts SDRs.';
END
$do$;
