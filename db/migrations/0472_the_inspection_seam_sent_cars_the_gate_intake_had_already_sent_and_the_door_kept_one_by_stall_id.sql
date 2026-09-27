-- migration-version: 20260926070905
-- migration-name:    the_inspection_seam_sent_cars_the_gate_intake_had_already_sent_and_the_door_kept_one_by_stall_id
--
-- 0472  **The inspection seam sent cars the gate intake had already sent to a stall in the same tick, and the command
--       door kept one of the two by stall id.** `db/checks/0359`. FINDINGS G204.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Validation run 49c45bd4 (busy_day, twin depot `11111111-…`), sim 8:00-8:30 AM CT, read live: 12 arriving cars were
--   sent to two stalls in the same tick, a staging stall by the gate intake (`ottoq_decide_tick` (3b), `reason
--   gate_intake`) and an inspection stall by `ottoq.ottoq_enact_inspection_seam` (`inspect_seam_interior_inspection`).
--   The door (`twin.ottoq_sim_confirm_commands`) keeps one stall command per car per pass; both carry the same
--   `issued_at` and `command_type`, so its tie-break reached `stall_id DESC`: the inspection won 6 times and the
--   intake 6 times, each time the side whose stall uuid sorted higher. The loser's calendar row was not released:
--   every losing intake left its `staging` booking `held` and the staging stall reserved to the car, for a window
--   that runs to the car's itinerary end (up to `staging_hold_max_min`, 480 minutes); every losing inspection left its
--   `inspect` booking until `window_elapsed`.
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   The seam runs last in the decide tick, and its own comment states the contract: "charging (3), the bay loop and
--   service sequencing (5) have all already run, so the seam can only take vehicles nothing else claimed." Its cursor
--   enforces that only against charge, wash, detail and service bookings. The gate intake (3b) books a `staging`
--   stall, reserves it, emits `proceed_to_stall` and plans the car's itinerary, which gives it a planned `inspect`
--   leg with no stall. The car is still `arrived_at_gate` until the next tick's door, so the seam's cursor matches it.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The seam's cursor also skips a car that already has a stall-bearing command issued this tick (`issued_at` = the
--   tick's clock, still `issued`). That is exactly the set the door would arbitrate. The door confirms or refuses
--   every issued command on its next pass (0 left over from earlier ticks, measured on 49c45bd4), so the skip lasts
--   one tick: a staged car with a planned `inspect` leg is still the seam's on a later tick, as before.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   Commands, bookings and decisions move for arriving cars.
--
--   PREDICTED on the next busy_day run: no `proceed_to_stall` refused `superseded` where the other command in the same
--   tick is the intake's or the seam's; no intake `staging` booking left `held` for a car that went to inspection.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0472 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamp with time zone)'::regprocedure))
     <> '6d2035ec5fce42b3df8eaa272975971a' THEN
    RAISE EXCEPTION '0472 P2: ottoq.ottoq_enact_inspection_seam is not the body this file patches';
  END IF;
  -- the seam still runs last in the decide tick, after the gate intake
  IF strpos(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure), 'ottoq_enact_inspection_seam')
     <= strpos(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure), $x$'reason', 'gate_intake',$x$) THEN
    RAISE EXCEPTION '0472 P2: the seam no longer runs after the gate intake';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0472_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamp with time zone)'::regprocedure;

DO $patch_seam$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamp with time zone)'::regprocedure);
  v_pat text := $p$AND NOT EXISTS \(SELECT 1 FROM public\.stalls s2\s+WHERE s2\.id = v\.current_stall_id AND s2\.zone = 'arrival_inspection'\)\s+ORDER BY public\.ottoq_urgency_rank$p$;
  v_new text := $r$AND NOT EXISTS (SELECT 1 FROM public.stalls s2
                        WHERE s2.id = v.current_stall_id AND s2.zone = 'arrival_inspection')
       -- 0472 (G204): nothing else sent this car to a stall this tick. The gate intake (3b) had, and the door kept
       -- one of the two commands by stall id, leaving the other's booking held.
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands vc
                        WHERE vc.vehicle_id = v.id AND vc.sim_run_id = p_sim_run_id
                          AND vc.issued_at = p_clock AND vc.status = 'issued'
                          AND vc.payload ? 'stall_id')
     ORDER BY public.ottoq_urgency_rank$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0472: the seam cursor matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat, v_new);
  EXECUTE v_def;
END $patch_seam$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_s text := pg_get_functiondef('ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamp with time zone)'::regprocedure);
BEGIN
  -- V1: the skip sits in the cursor, once, before the ORDER BY.
  IF (SELECT count(*) FROM regexp_matches(v_s, $x$0472 \(G204\)$x$, 'g')) <> 1
     OR v_s !~ $x$AND vc\.issued_at = p_clock AND vc\.status = 'issued'\s+AND vc\.payload \? 'stall_id'\)\s+ORDER BY public\.ottoq_urgency_rank$x$ THEN
    RAISE EXCEPTION '0472 V1: the seam is not the body this file writes';
  END IF;
  -- V2: one overload, the same ACL (owner and service_role; the decide tick is its one caller).
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'ottoq' AND p.proname = 'ottoq_enact_inspection_seam') <> 1 THEN
    RAISE EXCEPTION '0472 V2: an overload appeared';
  END IF;
  IF has_function_privilege('anon', 'ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamp with time zone)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamp with time zone)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamp with time zone)', 'EXECUTE') THEN
    RAISE EXCEPTION '0472 V2: the ACL moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0472_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0472_the_inspection_seam_sent_cars_the_gate_intake_had_already_sent_and_the_door_kept_one_by_stall_id', true,
  'Tick path: ottoq_enact_inspection_seam skips a car with a stall command already issued this tick (the gate intake). '
  'Commands, bookings and decisions move for arriving cars.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
