-- migration-version: 20260926190651
-- migration-name:    the_charge_proposer_offers_only_a_charger_the_gate_accepts
--
-- 0494  **The charge proposer offered a charger promised to another car to every car in the tick (G226, the second
--       half).** `db/checks/0367` §6.
--
-- ══ §1 WHAT WAS WRONG ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_l2_propose_stall_assignment` is the charge step's proposer (through
--   `ottoq_honour_reservation_proposal`). Its candidates are chargers free on the pointer (no car on the stall, no live
--   reservation by another car) with a charger that is Available and answering. It never reads the calendar, so a
--   charger promised to an arriving car (the itinerary's forward booking for that car's charge leg) looks free.
--
--   Before 0493 the first car offered such a charger took it: the emission gate refused the command, and the charge step
--   superseded the other car's booking and booked this car anyway (G226). 0493 stopped that, and released the
--   reservation the refused command had taken, so the next car in the cursor was offered the same charger and refused
--   too. On busy_day/171717/12 under 0493 (verdict 386, each arm) 70 of 160 `begin_charge` were refused, on 6 chargers,
--   22 of them on one L2 in the 04:00 tick. Its booking belonged to a car whose planned charge began at 03:35 and which
--   took that L2 at 04:00, so the calendar was right each time. busy_day/314159/12 (verdict 387): 131 of 223 on 11.
--   The throughput held (87 and 90 cars charged against 88 and 92 under 0492), so the cost was noise in the decisions
--   stream and cars that could have gone to a free charger that tick waiting a tick instead.
--
-- ══ §2 WHAT THIS DOES ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   A candidate must also be a charger the gate accepts for this car at this moment: the proposer asks
--   `ottoq.ottoq_validate_assignment` for `begin_charge`, the call `ottoq_emit_vehicle_command` makes next. That is the
--   fix 0467 gave the gate intake (G199). A charger promised to another car is no longer offered, the car is offered
--   the next one, and when none is left the proposer abstains, as it does when every charger is taken.
--
-- ══ §3 forces_recert TRUE ═══════════════════════════════════════════════════════════════════════════════════════
--
--   The proposer runs in the certified decide tick. Proposals, commands, bookings and decisions move.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0494 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured, and 0493 underneath it ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure))
     <> '74594c73f2d73917f3b63204984e6d2b' THEN
    RAISE EXCEPTION '0494 P2: public.ottoq_l2_propose_stall_assignment is not the body this file patches';
  END IF;
  IF position('0493 (G226)' IN pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0494 P2: 0493 is not applied, so a refused charge still books over the promise';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0494_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure);
  v_old text := $o$       AND (v_inlet IS NULL OR s.connector_type = v_inlet
$o$;
  v_new text := $n$       /* 0494 (G226): the calendar is a gate too. The pick asked only the pointer, so a charger promised to an
          arriving car looked free, and each car in the charge step's cursor was offered it and refused at the
          emission gate in turn (22 in one tick on busy_day/171717/12 under 0493). A candidate is now a charger the
          gate accepts for this car at this moment, the call ottoq_emit_vehicle_command makes next (0467 did the
          same for the gate intake). */
       AND COALESCE((ottoq.ottoq_validate_assignment(p_vehicle_id, s.id, 'begin_charge', v_now, v_run)->>'ok')::boolean, false)
       AND (v_inlet IS NULL OR s.connector_type = v_inlet
$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0494: the candidate filter matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f   regprocedure := 'public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure;
  v_def text := pg_get_functiondef('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure);
BEGIN
  -- V1: the gate's check sits in the candidate filter, once, above the ORDER BY that picks.
  IF (length(v_def) - length(replace(v_def, 'ottoq.ottoq_validate_assignment(p_vehicle_id, s.id, ''begin_charge'', v_now, v_run)', '')))
       / length('ottoq.ottoq_validate_assignment(p_vehicle_id, s.id, ''begin_charge'', v_now, v_run)') <> 1
     OR position('ottoq.ottoq_validate_assignment(' IN v_def) > position('ORDER BY (v_prefer_fit' IN v_def) THEN
    RAISE EXCEPTION '0494 V1: the proposer does not ask the gate before it picks';
  END IF;
  -- V2: still STABLE and security definer, privileges kept (CREATE OR REPLACE keeps the ACL).
  IF (SELECT provolatile FROM pg_proc WHERE oid = v_f) <> 's' OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f)
        <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres' THEN
    RAISE EXCEPTION '0494 V2: ottoq_l2_propose_stall_assignment changed volatility or privileges';
  END IF;
END $verify$;

-- Rollback: restore public.ottoq_l2_propose_stall_assignment from ottoq_schema_snapshots label '0494_pre' (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0494_the_charge_proposer_offers_only_a_charger_the_gate_accepts', true,
  'ottoq_l2_propose_stall_assignment offers only a charger ottoq_validate_assignment accepts for begin_charge, so a '
  'charger promised to another car is not offered. Proposals, commands, bookings and decisions move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
