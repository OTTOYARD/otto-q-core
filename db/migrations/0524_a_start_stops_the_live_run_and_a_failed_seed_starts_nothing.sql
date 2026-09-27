-- migration-version: PENDING
-- migration-name:    a_start_stops_the_live_run_and_a_failed_seed_starts_nothing
--
-- 0524  **G249: a run whose fleet seed failed ran anyway, on the previous run's world. The seed tripped on an arm
--       tether the previous run had left, `ottoq_sim_run_scenario` noted `seed_fleet {"ok": false}` in the payload
--       and started the run. Now the seed lets go of the arms first and closes leftover charges on their own run's
--       clock, a start stops a live run through the stop door, and a seed that still fails starts nothing.**
--       `db/checks/0392`.
--
-- ══ §1 WHAT WAS WRONG ══════════════════════════════════════════════════════════════════════════════════════════
--
--   Validation run 929e323c started at 11:18 UTC with `seed_fleet {"ok": false, "error": "arm interlock: vehicle
--   137ab789... is held by the arm at stall 9753cfd9... until 2026-09-27 16:32:00+00 (sim 2026-09-27 13:00:00+00)"}`.
--   The run before it, 11f15672, had been stopped with `ottoq_sim_mark_stopped` alone, which releases nothing, and left
--   Waymo-AV-031 tethered to NASH-DCFC-STALL-08 until 16:32 on its own clock. The seed moves every car off its stall;
--   the interlock judged the tether on the newest running run's clock -- the new run's start, 13:00 -- and refused; the
--   `EXCEPTION WHEN OTHERS` around the seed rolled all of it back, recorded `ok: false`, and the start went on. For
--   five sim-hours the engine ran 11f15672's end state: 33 of its first 36 charges were 11f15672's picked up again, 11
--   cars held 11f15672's dispatches and never came home, and 4 of 10 fast chargers were reserved for four of them
--   (0392 §2).
--   Two paths reach a seed with a live tether. A stop through `ottoq_sim_mark_stopped` alone (a stop by hand, as here),
--   and this function's own supersede, which marked a live run `completed` with a bare UPDATE -- no release, no archive
--   -- and is what the control edge function's start, `ottoq_start_demo_run` and `ottoq_start_busy_run` all call. And the
--   seed closed any leftover open charge with `ended_at = COALESCE(ended_at, NOW())`, the wall-clock fallback 0357
--   removed from the release door and not from here.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   `twin.ottoq_sim_seed_fleet(uuid,bigint,integer)`:
--   (1) releases every tether on the cars it is about to move, before it moves them -- the release door's own rule,
--       hoisted there on 2026-08-13 for this reason -- on a sim-feed depot only, as there;
--   (2) closes a leftover open twin charge the way the release door does: `cancelled`, `sim_reset`, ended on its own
--       run's last clock (the charge's start if it has no run). The `sim_reset` fires the evidence capture (0514), which
--       files it as a charge cut short by its run's end -- the censored observation 0516 counts -- instead of never
--       seeing it.
--   `public.ottoq_sim_run_scenario(text,bigint,text,timestamptz)`:
--   (3) stops every live run at the depot -- running or paused, since the seed rewrites the world under both -- through
--       `ottoq_sim_stop_and_reset`, the door the cockpit's Stop and the governor use, and keeps the old note. That door
--       pins the run it tears down (`ottoq.sim_run_id`) and an 8-second lock timeout for the rest of the transaction; the
--       new run is neither, so both are put back after the loop;
--   (4) raises when the seed fails, so the start rolls back whole, the supersede included, and the caller reads why.
--       The agentic arm's failure stays a receipt ("a run that could not be armed is still a valid run"); a run the
--       seed could not deal is not.
--   The interlock is not changed: it is right to refuse moving a car an arm holds. What was wrong was leaving it held.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   Neither function is on a certified or dial-pair path: certification arms and A/B-harness arms reset their own fleet
--   and carry no `seed_fleet` key (0392 §1), nothing but `ottoq_start_demo_run` and `ottoq_start_busy_run` calls
--   `ottoq_sim_run_scenario`, and nothing but it calls the seed (P2 asserts both). An operator run's day changes only
--   where it used to start on the wrong one. forces_dial_restart FALSE (0523) for the same reason: a dial pair's arms
--   start through `ottoq_dial_pair`, not this door, so no arm can come out differently.
--
--   Applied with no run live at the depot: V3 starts runs of its own inside a rolled-back block.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0524 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
DECLARE v_seed text; v_start text; v_guard text;
BEGIN
  v_seed  := pg_get_functiondef('twin.ottoq_sim_seed_fleet(uuid,bigint,integer)'::regprocedure);
  v_start := pg_get_functiondef('public.ottoq_sim_run_scenario(text,bigint,text,timestamptz)'::regprocedure);
  IF position('0524 (G249)' IN v_seed) > 0 OR position('0524 (G249)' IN v_start) > 0 THEN
    RAISE EXCEPTION '0524 P2: already applied';
  END IF;
  -- the start calls this seed, and only the two start wrappers call the start; nothing else calls the seed
  IF position('PERFORM ottoq_sim_seed_fleet(v_scenario.default_depot_id, v_seed, v_start_hour);' IN v_start) = 0 THEN
    RAISE EXCEPTION '0524 P2: the start does not call the three-argument seed as this file expects';
  END IF;
  IF (SELECT array_agg(p.oid::regprocedure::text ORDER BY p.oid::regprocedure::text)
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc ~ 'ottoq_sim_run_scenario\s*\('
         AND p.proname <> 'ottoq_sim_run_scenario')
     IS DISTINCT FROM ARRAY['ottoq_start_busy_run(numeric,integer,bigint)',
                            'ottoq_start_demo_run(text,numeric,integer,bigint)'] THEN
    RAISE EXCEPTION '0524 P2: something other than the two start wrappers calls ottoq_sim_run_scenario';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc ~ 'ottoq_sim_seed_fleet\s*\('
                AND p.proname NOT IN ('ottoq_sim_run_scenario','ottoq_sim_seed_fleet')) THEN
    RAISE EXCEPTION '0524 P2: something other than the start calls the seed';
  END IF;
  -- the stop door exists as the cockpit and the governor call it
  IF to_regprocedure('public.ottoq_sim_stop_and_reset(uuid,text)') IS NULL THEN
    RAISE EXCEPTION '0524 P2: ottoq_sim_stop_and_reset(uuid,text) is missing';
  END IF;
  -- the interlock lets a car go once its tether is cleared, which is what (1) relies on
  v_guard := pg_get_functiondef('public.ottoq_arm_interlock_guard()'::regprocedure);
  IF position('IF NEW.robotic_tether_until IS NULL THEN RETURN NEW; END IF;' IN v_guard) = 0
     OR NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.vehicles'::regclass
                       AND t.tgfoid = 'public.ottoq_arm_interlock_guard()'::regprocedure AND t.tgenabled <> 'D') THEN
    RAISE EXCEPTION '0524 P2: the arm interlock is not the guard this file reads';
  END IF;
  -- a sim_reset close is cancelled/sim_reset everywhere it is written today
  IF EXISTS (SELECT 1 FROM public.ocpp_sessions WHERE stopped_reason = 'sim_reset' AND status::text <> 'cancelled') THEN
    RAISE EXCEPTION '0524 P2: a sim_reset session is not cancelled; the release door''s shape has changed';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0524_pre', 'function', s.schema_name, s.object_name, pg_get_functiondef(s.oid), md5(pg_get_functiondef(s.oid))
  FROM (VALUES ('twin',   'ottoq_sim_seed_fleet',   'twin.ottoq_sim_seed_fleet(uuid,bigint,integer)'::regprocedure::oid),
               ('public', 'ottoq_sim_run_scenario', 'public.ottoq_sim_run_scenario(text,bigint,text,timestamptz)'::regprocedure::oid))
       AS s(schema_name, object_name, oid);

-- ── (1) and (2): the seed lets go of the arms before it moves a car, and closes a leftover charge on its own clock ──
DO $patch_seed$
DECLARE
  v_def text;
  v_pairs text[][] := ARRAY[
    ARRAY[$o1$     SET status = 'completed', ended_at = COALESCE(ended_at, NOW())$o1$,
          $n1$     -- 0524 (G249): closed as the release door closes a run's charges -- cancelled, `sim_reset`, on the charge's
     -- OWN run's last clock. Was `completed` at NOW(): a wall clock in a sim column, the fallback 0357 removed from
     -- ottoq_sim_release_depot, on a charge that did not complete.
     SET status = 'cancelled',
         ended_at = COALESCE(cs.ended_at,
                             (SELECT COALESCE(r.sim_clock_current, r.sim_clock_start) FROM ottoq_sim_runs r
                               WHERE r.sim_run_id = cs.sim_run_id),
                             cs.started_at),
         stopped_reason = COALESCE(cs.stopped_reason, 'sim_reset')$n1$],
    ARRAY[$o2$
  UPDATE vehicles v
     SET current_state = CASE$o2$,
          $n2$
  -- 0524 (G249): LET GO OF THE ARMS FIRST, as ottoq_sim_release_depot does (hoisted there 2026-08-13). A tether is a
  -- deadline on the clock of the run that set it, and the interlock judges it on the newest running run's clock -- at
  -- seed time, the new run's own start. 11f15672 ended without the release door and left one on Waymo-AV-031 until
  -- 16:32 sim; 929e323c started at 13:00 sim, the interlock refused the move below, and the whole seed rolled back
  -- (db/checks/0392). A seed deals a new day: no arm of the old one is holding anything in it. Sim feed only, as in
  -- the release door: on an external feed a tether mirrors a real latch.
  IF COALESCE((SELECT d.feed_mode FROM depots d WHERE d.id = p_depot_id), 'sim') = 'sim' THEN
    UPDATE vehicles
       SET robotic_tether_until = NULL, robotic_tether_stall_id = NULL,
           robotic_tether_direction = NULL, robotic_tether_phase = NULL
     WHERE home_depot_id = p_depot_id AND category = 'autonomous'
       AND (robotic_tether_until IS NOT NULL OR robotic_tether_stall_id IS NOT NULL);
  END IF;

  UPDATE vehicles v
     SET current_state = CASE$n2$]];
  i int; n int;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_seed_fleet(uuid,bigint,integer)'::regprocedure);
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0524: seed patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch_seed$;

-- ── (3) and (4): a start stops a live run through the stop door, and a failed seed starts nothing ──
DO $patch_start$
DECLARE
  v_def text;
  v_pairs text[][] := ARRAY[
    ARRAY[$o1$  UPDATE ottoq_sim_runs SET status='completed', ended_at=NOW(),
         notes = COALESCE(notes,'') || ' | superseded by ' || p_scenario_code
   WHERE depot_id = v_scenario.default_depot_id AND status='running';$o1$,
          $n1$  -- 0524 (G249): A START IS A STOP AND A START, NEVER A RELABEL. This was a bare UPDATE to 'completed': no
  -- release, no archive, and the old run's charges, tethers, pointers and dispatches left for the seed to trip over
  -- (db/checks/0392 §3). A live run at the depot -- running or paused, since the seed rewrites the world under both --
  -- now goes through the operator's stop door, as the cockpit's Stop and the governor take it. That door pins the run
  -- it tears down (ottoq.sim_run_id) and an 8-second lock timeout for the rest of the transaction; the new run is
  -- neither, so both are put back once the old runs are down.
  DECLARE
    v_live      uuid;
    v_stopped   int  := 0;
    v_lock_prev text := current_setting('lock_timeout');
  BEGIN
    FOR v_live IN
      SELECT r.sim_run_id FROM ottoq_sim_runs r
       WHERE r.depot_id = v_scenario.default_depot_id AND r.status IN ('running','paused')
       ORDER BY r.started_at, r.sim_run_id
    LOOP
      PERFORM public.ottoq_sim_stop_and_reset(v_live, 'superseded by ' || p_scenario_code);
      UPDATE ottoq_sim_runs SET notes = COALESCE(notes,'') || ' | superseded by ' || p_scenario_code
       WHERE sim_run_id = v_live;
      v_stopped := v_stopped + 1;
    END LOOP;
    IF v_stopped > 0 THEN
      PERFORM set_config('ottoq.sim_run_id', '', true);
      PERFORM set_config('lock_timeout', v_lock_prev, true);
    END IF;
  END;$n1$],
    ARRAY[$o2$  EXCEPTION WHEN OTHERS THEN
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('seed_fleet', jsonb_build_object('ok', false, 'error', SQLERRM))
     WHERE sim_run_id = v_sim_run_id;
  END;$o2$,
          $n2$  EXCEPTION WHEN OTHERS THEN
    -- 0524 (G249): a run the seed could not deal is not the scenario's day; it is whatever the depot held last. This
    -- wrote {"ok": false} into the payload and started the run anyway, and 929e323c ran five sim-hours on the
    -- previous run's cars (db/checks/0392). The start now fails and rolls back whole, the supersede above included,
    -- and says why. Unlike the agentic arm below, a run that could not be seeded is not a valid run.
    RAISE EXCEPTION 'fleet seed failed at depot %, so no run was started: %', v_scenario.default_depot_id, SQLERRM
      USING HINT = 'db/checks/0392 (G249)';
  END;$n2$]];
  i int; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_sim_run_scenario(text,bigint,text,timestamptz)'::regprocedure);
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0524: start patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch_start$;

DO $verify$
DECLARE v_seed text; v_start text;
BEGIN
  v_seed  := pg_get_functiondef('twin.ottoq_sim_seed_fleet(uuid,bigint,integer)'::regprocedure);
  v_start := pg_get_functiondef('public.ottoq_sim_run_scenario(text,bigint,text,timestamptz)'::regprocedure);
  -- V1: the seed releases tethers before it moves a car and closes leftovers as sim_reset on their own clock, with no
  --     NOW() left in the close; the start stops live runs through the stop door, the bare supersede is gone, and a
  --     failed seed raises; both keep SECURITY DEFINER on their search_path
  IF position('SET robotic_tether_until = NULL, robotic_tether_stall_id = NULL' IN v_seed) = 0
     OR position('SET robotic_tether_until = NULL' IN v_seed) > position('  UPDATE vehicles v' IN v_seed)
     OR position('stopped_reason = COALESCE(cs.stopped_reason, ''sim_reset'')' IN v_seed) = 0
     OR position('COALESCE(ended_at, NOW())' IN v_seed) > 0
     OR position('PERFORM public.ottoq_sim_stop_and_reset(v_live, ''superseded by '' || p_scenario_code);' IN v_start) = 0
     OR position('UPDATE ottoq_sim_runs SET status=''completed'', ended_at=NOW(),' IN v_start) > 0
     OR position('RAISE EXCEPTION ''fleet seed failed at depot %, so no run was started: %''' IN v_start) = 0
     OR position('jsonb_build_object(''seed_fleet'', jsonb_build_object(''ok'', false' IN v_start) > 0
     OR position('jsonb_build_object(''seed_fleet'', jsonb_build_object(''ok'', true))' IN v_start) = 0
     OR NOT (SELECT bool_and(prosecdef) FROM pg_proc
              WHERE oid IN ('twin.ottoq_sim_seed_fleet(uuid,bigint,integer)'::regprocedure,
                            'public.ottoq_sim_run_scenario(text,bigint,text,timestamptz)'::regprocedure))
     OR EXISTS (SELECT 1 FROM pg_proc
                 WHERE oid IN ('twin.ottoq_sim_seed_fleet(uuid,bigint,integer)'::regprocedure,
                               'public.ottoq_sim_run_scenario(text,bigint,text,timestamptz)'::regprocedure)
                   AND proconfig IS DISTINCT FROM ARRAY['search_path=twin, ottoq, public, extensions']) THEN
    RAISE EXCEPTION '0524 V1: the patched seed or start is not as intended';
  END IF;
END $verify$;

-- V3: rolled back, with no run live at the depot. (a) G249 as it happened: a car tethered to a DCFC stall until far
--     past any sim clock, and an open twin charge of the newest finished operator run left on it; a start deals the
--     day -- the seed succeeds, the tether is gone, the charge is closed `cancelled`/`sim_reset` on its run's own last
--     clock. (b) A start over that live run: the first run goes down through the stop door (archived, noted, its
--     failure_reason the supersede), the second runs seeded, and the transaction's run pin is not the first run.
--     (c) A seed that fails: a trigger planted to refuse the seed's move makes the start raise, no third run exists,
--     and the second run is still running, the supersede rolled back with it.
DO $v3$
DECLARE
  v_msg text; v_old uuid; v_old_end timestamptz; v_car uuid; v_dcfc uuid; v_cp text; v_sess uuid;
  v_r1 uuid; v_r2 uuid; v_r3 uuid; v_row record; v_err text := NULL; v_runs_before int;
BEGIN
  BEGIN
    IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
                WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status IN ('running','paused')) THEN
      RAISE EXCEPTION '0524 V3 FAILED: a run is live at the twin depot; this test starts its own';
    END IF;
    SELECT sr.sim_run_id, COALESCE(sr.sim_clock_current, sr.sim_clock_start) INTO v_old, v_old_end
      FROM public.ottoq_sim_runs sr
     WHERE sr.run_by = 'operator_demo' AND sr.status = 'completed'
       AND sr.depot_id = '11111111-1111-1111-1111-111111111111'
     ORDER BY sr.started_at DESC LIMIT 1;
    SELECT v.id INTO v_car FROM public.vehicles v
     WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
       AND v.current_stall_id IS NULL AND v.robotic_tether_until IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = v.id)
     ORDER BY v.id LIMIT 1;
    SELECT s.id, c.ocpp_identifier INTO v_dcfc, v_cp FROM public.stalls s
      JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'dcfc'
       AND s.current_vehicle_id IS NULL AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.current_stall_id = s.id)
     ORDER BY s.stall_code LIMIT 1;
    IF v_old IS NULL OR v_car IS NULL OR v_dcfc IS NULL THEN
      RAISE EXCEPTION '0524 V3 FAILED: nothing to plant on (run %, car %, stall %)', v_old, v_car, v_dcfc;
    END IF;

    -- (a) the car on the DCFC, held by its arm far past any clock, with the old run's charge still open on it
    UPDATE public.vehicles
       SET current_stall_id = v_dcfc, robotic_tether_stall_id = v_dcfc,
           robotic_tether_until = '2099-01-01 00:00:00+00', robotic_tether_direction = 'charging',
           robotic_tether_phase = 'charging'
     WHERE id = v_car;
    INSERT INTO public.ocpp_sessions (depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id,
                                      connector_id, status, started_at, id_token, sim_run_id, soc_start)
    VALUES ('11111111-1111-1111-1111-111111111111', v_dcfc, v_car, v_cp, 'TX-0524-V3', 1, 1, 'active',
            v_old_end - interval '20 minutes', 'TWIN-0524-V3', v_old, 40)
    RETURNING id INTO v_sess;

    v_r1 := public.ottoq_sim_run_scenario('busy_day', 523001, 'operator_demo', '2026-09-27 13:00:00+00');
    IF (SELECT payload->'seed_fleet'->>'ok' FROM public.ottoq_sim_runs WHERE sim_run_id = v_r1) IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION '0524 V3 FAILED (a): the seed did not succeed over a leftover tether';
    END IF;
    IF (SELECT robotic_tether_until FROM public.vehicles WHERE id = v_car) IS NOT NULL THEN
      RAISE EXCEPTION '0524 V3 FAILED (a): the tether survived the seed';
    END IF;
    SELECT status::text AS st, stopped_reason, ended_at INTO v_row FROM public.ocpp_sessions WHERE id = v_sess;
    IF v_row.st <> 'cancelled' OR v_row.stopped_reason IS DISTINCT FROM 'sim_reset' OR v_row.ended_at IS DISTINCT FROM v_old_end THEN
      RAISE EXCEPTION '0524 V3 FAILED (a): the leftover charge closed as % / % at %, not cancelled / sim_reset at %',
        v_row.st, v_row.stopped_reason, v_row.ended_at, v_old_end;
    END IF;

    -- (b) a second start over the first, live
    v_r2 := public.ottoq_sim_run_scenario('busy_day', 523002, 'operator_demo', '2026-09-27 13:00:00+00');
    IF (SELECT status FROM public.ottoq_sim_runs WHERE sim_run_id = v_r1) <> 'completed'
       OR (SELECT failure_reason FROM public.ottoq_sim_runs WHERE sim_run_id = v_r1) IS DISTINCT FROM 'superseded by busy_day'
       OR position(' | superseded by busy_day' IN (SELECT COALESCE(notes, '') FROM public.ottoq_sim_runs WHERE sim_run_id = v_r1)) = 0
       OR NOT EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = v_r1) THEN
      RAISE EXCEPTION '0524 V3 FAILED (b): the first run did not go down through the stop door';
    END IF;
    IF (SELECT status FROM public.ottoq_sim_runs WHERE sim_run_id = v_r2) <> 'running'
       OR (SELECT payload->'seed_fleet'->>'ok' FROM public.ottoq_sim_runs WHERE sim_run_id = v_r2) IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION '0524 V3 FAILED (b): the second run is not running seeded';
    END IF;
    IF NULLIF(current_setting('ottoq.sim_run_id', true), '') = v_r1::text THEN
      RAISE EXCEPTION '0524 V3 FAILED (b): the transaction is still pinned to the run it stopped';
    END IF;

    -- (c) a seed that fails. The planted refusal takes only the seed's own move -- a car leaving `offline`, which the
    --     stop door has just put every car in -- so the supersede before it runs as it would, and is rolled back only
    --     because the start fails after it.
    CREATE FUNCTION public.ottoq_v3_0524_refuse() RETURNS trigger LANGUAGE plpgsql AS $f$
    BEGIN
      IF current_setting('ottoq.v3_0524', true) = 'refuse'
         AND OLD.current_state::text = 'offline' AND NEW.current_state::text <> 'offline' THEN
        RAISE EXCEPTION 'v3 0524: this move is refused';
      END IF;
      RETURN NEW;
    END $f$;
    CREATE TRIGGER v3_0524_refuse BEFORE UPDATE ON public.vehicles FOR EACH ROW
      EXECUTE FUNCTION public.ottoq_v3_0524_refuse();
    v_runs_before := (SELECT count(*) FROM public.ottoq_sim_runs);
    BEGIN
      PERFORM set_config('ottoq.v3_0524', 'refuse', true);
      v_r3 := public.ottoq_sim_run_scenario('busy_day', 523003, 'operator_demo', '2026-09-27 13:00:00+00');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
    END;
    PERFORM set_config('ottoq.v3_0524', '', true);
    IF v_err IS NULL OR v_err NOT LIKE 'fleet seed failed at depot %, so no run was started: %' THEN
      RAISE EXCEPTION '0524 V3 FAILED (c): a failed seed did not stop the start (%)', COALESCE(v_err, 'it returned ' || v_r3::text);
    END IF;
    IF (SELECT count(*) FROM public.ottoq_sim_runs) <> v_runs_before
       OR (SELECT status FROM public.ottoq_sim_runs WHERE sim_run_id = v_r2) <> 'running' THEN
      RAISE EXCEPTION '0524 V3 FAILED (c): the failed start left a run behind or stopped the live one';
    END IF;
    RAISE EXCEPTION '0524 V3 PASSED: the seed dealt a day over a leftover tether and closed the old charge cancelled/sim_reset at its run''s % clock; a second start stopped the first through the stop door; a failed seed raised "%" and left the live run running', v_old_end, left(v_err, 60);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0524 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0524 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: restore both functions from ottoq_schema_snapshots WHERE label = '0524_pre'
--   (EXECUTE the stored `definition` of each).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0524_a_start_stops_the_live_run_and_a_failed_seed_starts_nothing', false, false,
  'The start door and the fleet seed only, neither on a certified or dial-pair path (P2): the seed releases tethers '
  'and closes leftover charges as sim_reset on their own run''s clock, a start stops a live run through the stop door, '
  'and a failed seed raises instead of starting an unseeded run (G249).', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
