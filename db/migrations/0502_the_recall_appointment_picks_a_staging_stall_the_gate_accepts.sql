-- migration-version: 20260926232454
-- migration-name:    the_recall_appointment_picks_a_staging_stall_the_gate_accepts
--
-- 0502  **The recall appointment picked its staging stall on the pointer alone, so the gate refused it, and the
--       refusal became an hour's hold nothing used (G235, first half).** `db/checks/0372` §6, `db/checks/0373`.
--
-- ══ §1 WHAT WAS WRONG (measured 2026-09-26) ════════════════════════════════════════════════════════════════════
--
--   A recall books the car an appointment while it is still on the road (`ottoq.ottoq_book_appointment`): a charger
--   if one is free, else a staging stall, reserved on the pointer and sent as `stage {appointment: true}`. The staging
--   pick reads the stall pointer and the reservation only. The gate every command passes
--   (`ottoq.ottoq_validate_assignment`, called by `ottoq_emit_vehicle_command`) also refuses a stall whose calendar
--   holds another car's live booking. On validation run `b0fdc92b` all 7 refused staging appointments were refused
--   for that: "calendar booking held by <another car>", on NASH-STG-B006, B007, B008 and B010, the first stalls in the
--   pick's own order. Each then went to the refusal reactor, which booked a 60-minute `temp_hold` on another stall
--   that the car never used (0503).
--
--   It is the last picker that did not ask the gate's question: 0467 (the gate intake), 0494 (the charge proposer),
--   0495 (the greedy optimizer) and 0498-0499 (CP-SAT's frame and the selector) each made its own pick ask it.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The staging pick takes the first stall, in its own order, that the gate accepts for this car at this moment: the
--   call `ottoq_emit_vehicle_command` makes next, with the command type the appointment sends (`stage`). The charger
--   pick is unchanged: its refusals are rerouted to chargers the car does use (0373 §1).
--
-- ══ §3 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   Recalls run in the certified tick, and the canon's busy arms carry refused staging appointments (1-4 an arm), so
--   commands, bookings and events move where one was refused.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0502 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P1: no run is live (V3 plants its case on the depot's own rows, inside a rolled-back block) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN
    RAISE EXCEPTION '0502 P1: a run is live; apply between runs';
  END IF;
END $live$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('ottoq.ottoq_book_appointment(uuid,uuid,timestamptz,text,text,boolean,numeric,numeric,uuid)'::regprocedure))
     <> 'aa843c193f147eb34b63b7d2ceb20e39' THEN
    RAISE EXCEPTION '0502 P2: ottoq.ottoq_book_appointment is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0502_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'ottoq.ottoq_book_appointment(uuid,uuid,timestamptz,text,text,boolean,numeric,numeric,uuid)'::regprocedure;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_book_appointment(uuid,uuid,timestamptz,text,text,boolean,numeric,numeric,uuid)'::regprocedure);
  v_old text := $o$       AND (s.reserved_by IS NULL OR s.reserved_by = p_vehicle_id OR s.reservation_expires_at <= p_clock)
     ORDER BY (s.staging_role = 'temp') DESC$o$;
  v_new text := $n$       AND (s.reserved_by IS NULL OR s.reserved_by = p_vehicle_id OR s.reservation_expires_at <= p_clock)
       /* 0502 (G235): the calendar is a gate too. This pick read the pointer only, so it took a stall another
          car's live booking held, the gate refused the appointment (7 of 7 staging refusals on b0fdc92b), and the
          reactor booked the car an hour on a stall it never used. A candidate is now a stall the gate accepts for
          this car at this moment, the call ottoq_emit_vehicle_command makes next (0467 and 0494 did the same). */
       AND COALESCE((ottoq.ottoq_validate_assignment(p_vehicle_id, s.id, 'stage', p_clock, p_sim_run_id)->>'ok')::boolean, false)
     ORDER BY (s.staging_role = 'temp') DESC$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0502: the staging pick matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f   regprocedure := 'ottoq.ottoq_book_appointment(uuid,uuid,timestamptz,text,text,boolean,numeric,numeric,uuid)'::regprocedure;
  v_def text := pg_get_functiondef('ottoq.ottoq_book_appointment(uuid,uuid,timestamptz,text,text,boolean,numeric,numeric,uuid)'::regprocedure);
BEGIN
  -- V1: the gate's question sits in the staging pick, once, and the charger pick is untouched.
  IF (length(v_def) - length(replace(v_def, 'ottoq.ottoq_validate_assignment(p_vehicle_id, s.id, ''stage''', '')))
       / length('ottoq.ottoq_validate_assignment(p_vehicle_id, s.id, ''stage''') <> 1
     OR position('ottoq_validate_assignment(p_vehicle_id, s.id, ''proceed_to_stall''' IN v_def) > 0
     OR position('AND c.station_state = ''Available''' IN v_def) = 0 THEN
    RAISE EXCEPTION '0502 V1: ottoq_book_appointment is not the body this file leaves';
  END IF;
  -- V2: privileges, security definer and search path kept (CREATE OR REPLACE keeps the ACL).
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f) <> 'postgres=X/postgres,service_role=X/postgres'
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = v_f) <> 'search_path=twin, ottoq, public, extensions' THEN
    RAISE EXCEPTION '0502 V2: ottoq_book_appointment''s privileges or settings changed';
  END IF;
END $verify$;

-- V3: the case, planted on the newest stopped operator run and rolled back. Every charger at the depot is set
-- faulted so the appointment falls to staging; another car's live `temp_hold` is booked on the stall the pick takes
-- first. The appointment must take a different stall, and its `stage` must pass the gate.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_clock timestamptz;
  v_depot uuid := '11111111-1111-1111-1111-111111111111';
  v_car uuid; v_other uuid; v_first uuid; v_res jsonb; v_cmd record;
BEGIN
  BEGIN
    SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock FROM public.ottoq_sim_runs r
     WHERE r.depot_id = v_depot AND r.validation_status IS NULL AND r.status = 'completed' AND r.sim_clock_current IS NOT NULL
     ORDER BY r.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0502 V3 FAILED: no stopped operator run to plant on'; END IF;
    UPDATE public.ottoq_ocpp_chargers SET station_state = 'Faulted' WHERE depot_id = v_depot;
    SELECT v.id INTO v_car FROM public.vehicles v
     WHERE v.home_depot_id = v_depot AND v.current_stall_id IS NULL ORDER BY v.id LIMIT 1;
    SELECT v.id INTO v_other FROM public.vehicles v
     WHERE v.home_depot_id = v_depot AND v.id <> v_car ORDER BY v.id LIMIT 1;
    SELECT s.id INTO v_first FROM public.stalls s
     WHERE s.depot_id = v_depot AND s.stall_type = 'staging' AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reserved_by = v_car OR s.reservation_expires_at <= v_clock)
     ORDER BY (s.staging_role = 'temp') DESC, s.distance_from_entrance NULLS LAST, s.id LIMIT 1;
    IF ottoq.ottoq_book_stall(v_run, v_first, v_other, 'temp_hold', v_clock, v_clock + interval '30 minutes',
                              NULL, NULL, 'v3_0502') IS NULL THEN
      RAISE EXCEPTION '0502 V3 FAILED: could not plant the other car''s booking';
    END IF;
    v_res := ottoq.ottoq_book_appointment(v_car, v_run, v_clock, 'v3_0502', 'normal', true, 15, 60, v_depot);
    SELECT c.status, c.reason_detail, c.payload->>'stall_id' AS stall INTO v_cmd
      FROM public.ottoq_vehicle_commands c
     WHERE c.sim_run_id = v_run AND c.vehicle_id = v_car AND c.command_type = 'stage' AND c.issued_at = v_clock
       AND (c.payload->>'appointment')::boolean
     ORDER BY c.command_seq DESC LIMIT 1;
    IF NOT COALESCE((v_res->>'secured')::boolean, false) OR v_res->>'stall_type' <> 'staging'
       OR (v_res->>'stall_id')::uuid = v_first OR v_cmd.status IS DISTINCT FROM 'issued' THEN
      RAISE EXCEPTION '0502 V3 FAILED: appointment % / command % % %', v_res, v_cmd.status, v_cmd.reason_detail, v_cmd.stall;
    END IF;
    RAISE EXCEPTION '0502 V3 PASSED: appointment on % past the held %, command %', v_res->>'stall_id', v_first, v_cmd.status;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0502 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0502 V3: no verdict'); END IF;
END $v3$;

-- Rollback: restore ottoq.ottoq_book_appointment from ottoq_schema_snapshots label '0502_pre' (CREATE OR REPLACE,
-- ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0502_the_recall_appointment_picks_a_staging_stall_the_gate_accepts', true,
  'ottoq_book_appointment''s staging pick takes the first stall the gate accepts (ottoq_validate_assignment, stage), '
  'so a recall no longer sends an appointment the gate refuses on another car''s live booking. Commands, bookings and '
  'events move on busy arms where one was refused.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
