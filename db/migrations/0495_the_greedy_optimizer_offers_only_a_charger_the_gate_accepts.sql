-- migration-version: 20260926201658
-- migration-name:    the_greedy_optimizer_offers_only_a_charger_the_gate_accepts
--
-- 0495  **The in-kernel greedy optimizer still offered a charger promised to another car (G226, the third part).**
--       `db/checks/0368` §3 and §10.
--
-- ══ §1 WHAT WAS WRONG ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   The charge step takes its charger through `ottoq_honour_reservation_proposal`, which asks for an external proposal
--   first (`ottoq_l2_external_proposal`) and falls back to the per-car proposer
--   (`ottoq_l2_propose_stall_assignment`). 0494 made the per-car proposer ask the emission gate. But one of the
--   "external" sources is the kernel's own: `public.ottoq_l2_optimize_assignments`, called by
--   `ottoq_sim_decide_and_dispatch` before the decide tick, writes a `greedy_constrained` proposal for each car at the
--   gate. Its pick reads the pointer and the charger's state and never the calendar, so a charger promised to an
--   arriving car still looked free to it.
--
--   Measured on the canon under 0494 (verdicts 393-401, arm A) and on the validation run `394e1e83`: every `begin_charge`
--   the charge step issued and the gate refused was a `greedy_constrained` proposal, matched by stall: 3, 3, 3, 6, 7, 8
--   and 3 on the busy_day and normal_day arms, 3 by sim 8:04 AM on the live run, and 0 from the per-car proposer.
--   On `394e1e83` at 13:03:22 the optimizer offered L2 f517a13e to car 5cee8fb3 while car 99ddf4ff held a charge
--   booking there from 13:02:23 to 14:11:35, booked the tick before. The gate refused it, 0493 logged it
--   `charger_refused`, and the reactor put the car on another L2 in the same pass. So the cost is one refused command
--   and one reroute per case, not a car left waiting, and the external solvers (cuOpt, CP-SAT) are not touched here:
--   a proposal from outside the kernel is disposed by the gate, which is what propose/dispose is for.
--
-- ══ §2 WHAT THIS DOES ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   The optimizer's candidate filter also asks `ottoq.ottoq_validate_assignment` for `begin_charge` at the tick's clock,
--   the call the emission gate makes, as 0494 did for the per-car proposer and 0467 for the gate intake. A charger
--   promised to another car is passed over and the car is offered the next one in the same order (DCFC first, then
--   nearest the entrance); when none is left the optimizer writes no proposal for it and the per-car proposer
--   answers, as before.
--
-- ══ §3 forces_recert TRUE ═══════════════════════════════════════════════════════════════════════════════════════
--
--   The optimizer runs in the certified tick. Proposals, commands, bookings and decisions move.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0495 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured, and 0494 beside it ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_l2_optimize_assignments(uuid,uuid,timestamptz)'::regprocedure))
     <> '1bbf937adb54a1015a144a3352984538' THEN
    RAISE EXCEPTION '0495 P2: public.ottoq_l2_optimize_assignments is not the body this file patches';
  END IF;
  IF position('0494 (G226)' IN pg_get_functiondef('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0495 P2: 0494 is not applied, so the per-car proposer does not ask the gate either';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0495_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_l2_optimize_assignments(uuid,uuid,timestamptz)'::regprocedure;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_l2_optimize_assignments(uuid,uuid,timestamptz)'::regprocedure);
  v_old text := $o$       AND c.station_state = 'Available'
       AND c.last_heartbeat_at >= p_sim_clock - INTERVAL '90 seconds'
$o$;
  v_new text := $n$       AND c.station_state = 'Available'
       AND c.last_heartbeat_at >= p_sim_clock - INTERVAL '90 seconds'
       /* 0495 (G226): the calendar is a gate here too. This pick read the pointer and the charger only, so a
          charger promised to an arriving car looked free, and the charge step honoured the proposal and was refused
          at the emission gate (every refusal of its begin_charge on the canon under 0494). A candidate is now a
          charger the gate accepts for this car at this clock, as 0494 made the per-car proposer ask. */
       AND COALESCE((ottoq.ottoq_validate_assignment(v_veh.id, s.id, 'begin_charge', p_sim_clock, p_sim_run_id)->>'ok')::boolean, false)
$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0495: the charger filter matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f    regprocedure := 'public.ottoq_l2_optimize_assignments(uuid,uuid,timestamptz)'::regprocedure;
  v_def  text := pg_get_functiondef('public.ottoq_l2_optimize_assignments(uuid,uuid,timestamptz)'::regprocedure);
  v_call text := 'ottoq.ottoq_validate_assignment(v_veh.id, s.id, ''begin_charge'', p_sim_clock, p_sim_run_id)';
BEGIN
  -- V1: the gate's check sits in the charger pick, once, after the vehicle loop's query and above the score that orders it.
  IF (length(v_def) - length(replace(v_def, v_call, ''))) / length(v_call) <> 1
     OR position(v_call IN v_def) < position('FOR v_veh IN' IN v_def)
     OR position(v_call IN v_def) > position('DCFC FIRST, L2 OVERFLOW' IN v_def) THEN
    RAISE EXCEPTION '0495 V1: the optimizer does not ask the gate inside its charger pick';
  END IF;
  -- V2: still volatile and security definer, privileges kept (CREATE OR REPLACE keeps the ACL).
  IF (SELECT provolatile FROM pg_proc WHERE oid = v_f) <> 'v' OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f)
        <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres' THEN
    RAISE EXCEPTION '0495 V2: ottoq_l2_optimize_assignments changed volatility or privileges';
  END IF;
END $verify$;

-- Rollback: restore public.ottoq_l2_optimize_assignments from ottoq_schema_snapshots label '0495_pre' (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0495_the_greedy_optimizer_offers_only_a_charger_the_gate_accepts', true,
  'ottoq_l2_optimize_assignments (greedy_constrained) offers only a charger ottoq_validate_assignment accepts for '
  'begin_charge at the tick''s clock, so a charger promised to another car is not proposed. Proposals, commands, '
  'bookings and decisions move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
