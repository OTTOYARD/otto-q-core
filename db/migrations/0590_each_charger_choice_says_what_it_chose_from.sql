-- migration-version: PENDING
-- migration-name:    each_charger_choice_says_what_it_chose_from
--
-- 0590  **Each charger choice says what it had to choose from.** One read-only cockpit contract,
--       `ottoq_decision_options(run, vehicle)`: for every charger decision a car got in a run (each pick, and the first
--       tick of each wait) it rebuilds the options the assigner had, from the frame that tick decided on, through the
--       assigner's own gates and its own ranking, and says whether the rebuild reproduces what the engine did.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-09-28, on the twin's plain-English decision trail: "Just easy to understand reasoning and decision logic
--   trail. Like scenario requested by vehicle, scanned, found best solution, proposed, passed, dispatched."
--   The trail (ottoyarddepot-sim PR #118) reads every step from existing contracts except two: "Found N ways" and
--   "Picked the best, and why". The rule-based assigner (ottoq_l2_propose_stall_assignment, seat 0) makes nearly every
--   charger pick -- 72 of 72 on run 1ebae97a before this file -- and records only its pick. The planners' proposals
--   (ottoq_external_proposals) are almost all abstentions (80 of 86 on that run). So the trail printed "not recorded"
--   on every car. The facts to answer it are already stored: every decision points at the frame its tick decided on
--   (ottoq_decisions.snapshot_id -> ottoq_decision_snapshots.frame), and the frame carries each charger's state,
--   booking, calendar holder, plugs and power (0265, 0498). Nothing has to be added to the engine; it has to be read.
--
-- ══ §2 WHAT THIS ADDS (read-only; no table, no tick path, no engine change) ═════════════════════════════════════════════
--
--   `public.ottoq_decision_options(p_sim_run_id uuid, p_vehicle_id uuid) RETURNS jsonb`, STABLE SECURITY DEFINER,
--   granted like its siblings (0536). For each of the car's decisions with action_context 'stall_assignment' that is a
--   pick (enacted assign_stall) or the first tick of a wait (noop_no_candidate after anything else):
--     options        the assigner's candidate set, gate for gate: a dcfc or l2 stall with no car, a charger that is
--                    Available with a heartbeat inside 90 s, no live booking or calendar hold for ANOTHER car, a plug the
--                    car's inlet fits (Multi by its supported list, NACS for NACS/Tesla), the car below its charge cap;
--                    minus chargers an earlier decision in the same tick had already taken. Ranked by the assigner's own
--                    ORDER BY: fits the power limit (when it prefers a fit), booked for this car, the kind it wants
--                    (fast when the battery is under 45% or the car is due out now), first in its row.
--     agrees         the rebuild's check on itself: its first option IS the engine's pick (for a wait: it finds none).
--     options_found  the count, only where agrees; otherwise NULL. A frame without the selector's facts (the cert
--                    harness's frames carry none) gives agrees NULL and no count. Unknown is never printed as a number.
--     options_by_kind  of those, fast (dcfc) and standard (l2): whether a car that got the other kind had its own.
--     why            which ranking key separated the pick from the next option: power_limit, booked, wanted_kind,
--                    row_order, or only_option (and 'booked' for reservation_honoured). Only for the rule-based
--                    assigner and only where agrees; NULL otherwise.
--     depot          the frame's own vehicle-blind verdicts at the start of the tick: fast and standard chargers
--                    offerable, cars waiting, and cars waiting for a charge.
--     top three options, each with charge_min: the minutes its charge would take from that moment, by the call
--                    twin.ottoq_sim_start_charge_session makes when it opens a charge leg (ottoq_estimate_charge_minutes
--                    with the car's pack, inlet, soh from config, the site's air + the car's seeded battery offset, the
--                    run's charge_time rate). Minutes, not a clock time: a visit plan can start the charge later.
--
-- ══ §3 MEASURED (read-only dry run, 2026-09-29, 1:55-2:20 PM CT) ════════════════════════════════════════════════════
--
--   Picks where the rebuild's first option is the engine's pick: operator runs 4b0999db 125/125, 8ddd0752 55/55,
--   e9e3b922 44/44, 1ebae97a 84/84. Waits where the rebuild also finds no option: 1ebae97a 52/52 first-ticks (7,344/7,344
--   every tick). cert_harness runs: their frames carry no selector facts, so the function returns agrees NULL for each
--   (never a count). Charge minutes against the charge legs the twin planned on 1ebae97a: 48 of 50 legs opened by the
--   charge orchestrator (basis 'charge_curve') within 1 minute; legs of flow-contract visit plans differ because those
--   charges start later, under other conditions, which is why the contract returns minutes and not a finish time.
--   Cost: all 77 cars of 1ebae97a in 1.5 s (about 20 ms a car).
--
-- ══ §4 WHAT IT DOES NOT DO ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   It does not record anything and changes no engine path: the assigner still records only its pick. If the assigner's
--   gates or ranking change, P1 refuses this file (the assigner's md5 is pinned) and, once applied, `agrees` goes false
--   on the choices it no longer reproduces, so a cockpit shows "not recorded" rather than a wrong count.
--
-- ══ §5 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════════
--
--   One new read-only function and its lineage row. Nothing on a tick path, in a pair or in the canon.
--
-- ══ §6 WHEN TO APPLY ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   With no run live and no pair in flight (P0). After 0564.

BEGIN;

-- ── P0: nothing in flight, no run live ──
DO $inflight$
DECLARE v_pairs int; v_live int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names ottoq_determinism_pair past pg_stat_activity's 1 kB; its lock key is early.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0590 P0: a pair or the recert runner is running right now'; END IF;
  SELECT count(*) INTO v_live FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused');
  IF v_live > 0 THEN RAISE EXCEPTION '0590 P0: % run(s) live; apply with no run live', v_live; END IF;
END $inflight$;

-- ── P1: the contracts this reads, as measured ──
DO $premises$
BEGIN
  IF to_regprocedure('public.ottoq_decision_options(uuid,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0590 P1: ottoq_decision_options already exists';
  END IF;
  -- the assigner this rebuilds, exactly as measured (gates, want rule, taper, ORDER BY)
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure)
     IS DISTINCT FROM '9f7981089f4b7051a472fb6b39ef9dac' THEN
    RAISE EXCEPTION '0590 P1: ottoq_l2_propose_stall_assignment changed since it was measured; re-measure the rebuild';
  END IF;
  -- the charge-time call and battery temperature the twin plans a charge leg with
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_start_charge_session'
                    AND p.prosrc ~ $re$ottoq_estimate_charge_minutes\(\s+v_vehicle\.current_soc, v_target_soc, v_charger\.max_kw, v_vehicle\.inlet_max_kw,\s+v_vehicle\.battery_capacity_kwh, v_battery_temp, COALESCE\(v_vehicle\.soh, 95\),\s+GREATEST\(0\.2, ottoq_profile_rate_mult\(p_sim_run_id, 'charge_time'\)\)\)$re$
                    AND p.prosrc ~ $re$v_battery_temp := v_ambient_temp \+ 5 \+ ottoq_sim_seeded_random\(42, 'btemp:' \|\| p_vehicle_id::text\) \* 10;$re$
                    AND p.prosrc ~ $re$\(config->>'battery_soh_pct'\)::NUMERIC AS soh$re$) THEN
    RAISE EXCEPTION '0590 P1: twin.ottoq_sim_start_charge_session no longer plans a charge with the inputs measured';
  END IF;
  IF to_regprocedure('public.ottoq_estimate_charge_minutes(numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric)') IS NULL
     OR to_regprocedure('public.ottoq_profile_rate_mult(uuid,text)') IS NULL
     OR to_regprocedure('public.ottoq_target_soc_cap(text,timestamptz)') IS NULL
     OR to_regprocedure('public.ottoq_target_soc_cap(text,timestamptz,uuid)') IS NULL
     OR to_regprocedure('public.ottoq_default_target_soc()') IS NULL
     OR to_regprocedure('twin.ottoq_sim_site_ambient_c(uuid,timestamptz)') IS NULL
     OR to_regprocedure('twin.ottoq_sim_seeded_random(bigint,text)') IS NULL THEN
    RAISE EXCEPTION '0590 P1: a function this reads is missing';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns
       WHERE table_schema = 'public'
         AND (table_name, column_name) IN (('ottoq_decisions', 'snapshot_id'), ('ottoq_decisions', 'context_frame'),
                                           ('ottoq_decisions', 'enacted_action'), ('ottoq_decisions', 'l2_engine'),
                                           ('ottoq_decisions', 'action_context'), ('ottoq_decisions', 'outcome_status'),
                                           ('ottoq_decision_snapshots', 'frame'), ('stalls', 'relative_y'),
                                           ('stalls', 'stall_code'), ('vehicles', 'inlet_max_kw'),
                                           ('vehicles', 'battery_capacity_kwh'), ('vehicles', 'config'),
                                           ('ottoq_ocpp_chargers', 'max_kw'))) <> 13 THEN
    RAISE EXCEPTION '0590 P1: a column this reads is missing';
  END IF;
END $premises$;

CREATE FUNCTION public.ottoq_decision_options(p_sim_run_id uuid, p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  /* 0590. What each of one car's charger decisions had to choose from: rebuilt from the frame that tick decided on
     (ottoq_decision_snapshots), through the assigner's own gates and its own ranking, and checked against what the engine
     actually did. Read-only. See the migration header. */
  WITH car AS (
    -- the inputs twin.ottoq_sim_start_charge_session plans a charge with
    SELECT v.id, v.inlet_max_kw, v.battery_capacity_kwh, v.target_soc,
           COALESCE(CASE WHEN v.config->>'battery_soh_pct' ~ '^[0-9]+(\.[0-9]+)?$'
                         THEN (v.config->>'battery_soh_pct')::numeric END, 95) AS soh
      FROM public.vehicles v
     WHERE v.id = p_vehicle_id),
  dec AS (
    SELECT d.decision_seq, d.tick_seq, d.sim_clock, d.snapshot_id, d.outcome_status, d.l2_engine,
           d.enacted_action, d.context_frame,
           COALESCE(NULLIF(d.context_frame->>'now_ts', '')::timestamptz, d.sim_clock) AS clk,
           lag(d.outcome_status) OVER (ORDER BY d.decision_seq) AS prev_outcome
      FROM public.ottoq_decisions d
     WHERE d.sim_run_id = p_sim_run_id AND d.entity_id = p_vehicle_id
       AND d.action_context = 'stall_assignment'),
  pick AS (
    -- every pick, and the first tick of every wait
    SELECT dec.decision_seq, dec.tick_seq, dec.sim_clock, dec.clk, dec.outcome_status, dec.l2_engine,
           dec.enacted_action->>'stall_id' AS chosen,
           dec.enacted_action->'rationale' AS r,
           COALESCE(CASE WHEN dec.enacted_action->'rationale'->>'soc' ~ '^-?[0-9]+(\.[0-9]+)?$'
                         THEN (dec.enacted_action->'rationale'->>'soc')::numeric END,
                    CASE WHEN dec.context_frame->>'current_soc' ~ '^-?[0-9]+(\.[0-9]+)?$'
                         THEN (dec.context_frame->>'current_soc')::numeric END) AS soc,
           COALESCE(dec.enacted_action->'rationale'->>'inlet', dec.context_frame->>'inlet_type') AS inlet,
           sn.frame,
           COALESCE(sn.frame->'selector' ? 'facts_version', false) AS has_facts
      FROM dec
      LEFT JOIN public.ottoq_decision_snapshots sn ON sn.snapshot_id = dec.snapshot_id
     WHERE (dec.outcome_status = 'enacted' AND dec.enacted_action->>'verb' = 'assign_stall')
        OR (dec.outcome_status = 'noop_no_candidate' AND dec.prev_outcome IS DISTINCT FROM 'noop_no_candidate')),
  opt AS (
    -- the assigner's candidate set (ottoq_l2_propose_stall_assignment, seat 0), gate for gate, read from the frame
    SELECT p.decision_seq, st->>'id' AS stall_id, s.id AS sid, s.stall_code, st->>'type' AS kind,
           COALESCE((st->>'connector_max_kw')::numeric, 50) AS kw, c.max_kw AS charger_kw,
           COALESCE(st->>'reserved_by' = p_vehicle_id::text, false) AS booked,
           s.relative_y,
           LEAST(COALESCE((st->>'connector_max_kw')::numeric, 50), COALESCE(car.inlet_max_kw, 250))
             * CASE WHEN COALESCE((st->>'connector_max_kw')::numeric, 50) <= 50 THEN 1.0
                    WHEN p.soc < 55 THEN 0.85 WHEN p.soc < 75 THEN 0.55 ELSE 0.30 END AS eff_kw
      FROM pick p
      CROSS JOIN car
      CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.frame->'stalls', '[]'::jsonb)) st
      LEFT JOIN public.stalls s ON s.id::text = st->>'id'
      LEFT JOIN public.ottoq_ocpp_chargers c ON c.charger_id::text = st->>'ocpp_charger_id'
     WHERE p.has_facts
       AND st->>'type' IN ('dcfc', 'l2')
       AND st->>'vehicle_id' IS NULL
       AND st->>'ocpp_charger_id' IS NOT NULL
       AND st->>'charger_state' = 'Available'
       AND COALESCE((st->>'charger_fresh')::boolean, false)
       AND (st->>'reserved_by' IS NULL OR st->>'reserved_by' = p_vehicle_id::text
            OR NULLIF(st->>'reservation_expires_at', '')::timestamptz <= p.clk)
       AND (st->>'calendar_held_by' IS NULL OR st->>'calendar_held_by' = p_vehicle_id::text)
       AND p.soc < LEAST(COALESCE(car.target_soc, public.ottoq_default_target_soc()),
                         public.ottoq_target_soc_cap(st->>'type', p.clk)) - 0.5
       AND (p.inlet IS NULL OR st->>'connector_type' = p.inlet
            OR (st->>'connector_type' = 'Multi' AND COALESCE(st->'supported_inlet_types', '[]'::jsonb) ? p.inlet)
            OR (st->>'connector_type' = 'NACS' AND p.inlet IN ('NACS', 'Tesla_Proprietary')))
       -- a charger taken earlier in the same tick is not an option for a car decided later in it
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_decisions e
                        WHERE e.sim_run_id = p_sim_run_id AND e.tick_seq = p.tick_seq
                          AND e.decision_seq < p.decision_seq AND e.outcome_status = 'enacted'
                          AND e.enacted_action->>'stall_id' = st->>'id')),
  ranked AS (
    -- the assigner's own ORDER BY: fits the power limit (when it prefers a fit), booked for this car, the kind it
    -- wants, first in its row
    SELECT o.*,
           (COALESCE(p.r->>'held_for_wanted', '-') = '-'
            AND (NOT COALESCE(p.r->>'headroom_kw' ~ '^-?[0-9]+(\.[0-9]+)?$', false)
                 OR o.eff_kw <= (p.r->>'headroom_kw')::numeric)) AS k_fit,
           COALESCE(o.kind = p.r->>'wanted_type', false) AS k_kind,
           row_number() OVER (PARTITION BY o.decision_seq ORDER BY
             (COALESCE(p.r->>'held_for_wanted', '-') = '-'
              AND (NOT COALESCE(p.r->>'headroom_kw' ~ '^-?[0-9]+(\.[0-9]+)?$', false)
                   OR o.eff_kw <= (p.r->>'headroom_kw')::numeric)) DESC,
             o.booked DESC,
             COALESCE(o.kind = p.r->>'wanted_type', false) DESC,
             o.relative_y ASC NULLS LAST, o.sid) AS rk,
           count(*) OVER (PARTITION BY o.decision_seq) AS n
      FROM opt o JOIN pick p USING (decision_seq)),
  choice AS (
    SELECT p.*, t.stall_id AS top_id, t.k_fit AS t_fit, t.booked AS t_booked, t.k_kind AS t_kind,
           u.stall_id AS second_id, u.k_fit AS u_fit, u.booked AS u_booked, u.k_kind AS u_kind,
           COALESCE(t.n, 0) AS n_opts, kc.n_fast, kc.n_standard,
           CASE WHEN NOT p.has_facts THEN NULL
                WHEN p.outcome_status = 'enacted' THEN COALESCE(t.stall_id = p.chosen, false)
                ELSE t.stall_id IS NULL END AS agrees
      FROM pick p
      LEFT JOIN ranked t ON t.decision_seq = p.decision_seq AND t.rk = 1
      LEFT JOIN ranked u ON u.decision_seq = p.decision_seq AND u.rk = 2
      LEFT JOIN LATERAL (SELECT count(*) FILTER (WHERE k.kind = 'dcfc') AS n_fast,
                                count(*) FILTER (WHERE k.kind = 'l2') AS n_standard
                           FROM ranked k WHERE k.decision_seq = p.decision_seq) kc ON true)
  SELECT jsonb_build_object(
    'contract', 'ottoq_decision_options/0590',
    'sim_run_id', p_sim_run_id,
    'vehicle_id', p_vehicle_id,
    'choices', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'decision_seq', ch.decision_seq,
        'tick_seq', ch.tick_seq,
        'at', ch.sim_clock,
        'outcome', ch.outcome_status,
        'engine', ch.l2_engine,
        'chosen', CASE WHEN ch.outcome_status = 'enacted' THEN
                    (SELECT jsonb_build_object('stall_id', s.id, 'stall_code', s.stall_code, 'kind', s.stall_type)
                       FROM public.stalls s WHERE s.id::text = ch.chosen) END,
        -- the frame's own vehicle-blind verdicts, at the start of the tick
        'depot', CASE WHEN ch.has_facts THEN jsonb_build_object(
                    'free_fast', (SELECT count(*) FROM jsonb_array_elements(ch.frame->'stalls') st
                                   WHERE st->>'type' = 'dcfc' AND COALESCE((st->>'offerable')::boolean, false)),
                    'free_standard', (SELECT count(*) FROM jsonb_array_elements(ch.frame->'stalls') st
                                       WHERE st->>'type' = 'l2' AND COALESCE((st->>'offerable')::boolean, false)),
                    'cars_waiting', (SELECT count(*) FROM jsonb_array_elements(ch.frame->'vehicles') vv
                                      WHERE vv->>'state' IN ('arrived_at_gate', 'staged_awaiting_service')),
                    'waiting_for_charge', (SELECT count(*) FROM jsonb_array_elements(ch.frame->'vehicles') vv
                                            WHERE vv->>'state' IN ('arrived_at_gate', 'staged_awaiting_service')
                                              AND vv->>'svc_step' = 'need_charge')) END,
        'car', jsonb_build_object(
                 'soc', ch.soc,
                 'wanted_kind', ch.r->>'wanted_type',
                 -- the assigner's own rule: a fast charger when the battery is under 45% or the car is due out now
                 'why_wanted', CASE WHEN ch.r->>'wanted_type' = 'dcfc' AND ch.soc < 45 THEN 'low_battery'
                                    WHEN ch.r->>'wanted_type' = 'dcfc' AND ch.r->>'urgency' = 'immediate_dispatch' THEN 'due_now'
                                    WHEN ch.r->>'wanted_type' = 'l2' THEN 'enough_battery' END),
        -- the rebuild's own check: its first pick is the engine's pick (or, for a wait, it finds nothing either)
        'agrees', ch.agrees,
        -- counted only where the rebuild reproduces the engine; otherwise unknown, never a guess
        'options_found', CASE WHEN ch.agrees THEN ch.n_opts END,
        -- of those, how many of each kind: says whether a car that got the other kind had its wanted kind to take
        'options_by_kind', CASE WHEN ch.agrees THEN jsonb_build_object('dcfc', ch.n_fast, 'l2', ch.n_standard) END,
        'why', CASE WHEN ch.agrees AND ch.outcome_status = 'enacted' THEN
                 CASE WHEN ch.l2_engine = 'reservation_honoured' THEN 'booked'
                      WHEN ch.l2_engine = 'deterministic_v1' AND NOT COALESCE(ch.r ? 'seat', false) THEN
                        CASE WHEN ch.second_id IS NULL THEN 'only_option'
                             WHEN ch.t_fit IS DISTINCT FROM ch.u_fit THEN 'power_limit'
                             WHEN ch.t_booked IS DISTINCT FROM ch.u_booked THEN 'booked'
                             WHEN ch.t_kind IS DISTINCT FROM ch.u_kind THEN 'wanted_kind'
                             ELSE 'row_order' END END END,
        'downgrade', COALESCE((ch.r->>'power_downgrade')::boolean, false),
        -- the first three options, each with the minutes its charge would take from that moment: the same call, with
        -- the same inputs, twin.ottoq_sim_start_charge_session makes when it opens a charge leg
        'options', CASE WHEN ch.agrees AND ch.outcome_status = 'enacted' THEN (
            SELECT jsonb_agg(jsonb_build_object(
                     'rank', k.rk, 'stall_code', k.stall_code, 'kind', k.kind, 'kw', k.kw,
                     'chosen', k.stall_id = ch.chosen,
                     'charge_min', public.ottoq_estimate_charge_minutes(
                         ch.soc,
                         LEAST(COALESCE(car.target_soc, public.ottoq_default_target_soc()),
                               public.ottoq_target_soc_cap(k.kind, ch.clk, p_sim_run_id)),
                         COALESCE(k.charger_kw, k.kw), car.inlet_max_kw, car.battery_capacity_kwh,
                         COALESCE(twin.ottoq_sim_site_ambient_c(p_sim_run_id, ch.clk), 20) + 5
                           + twin.ottoq_sim_seeded_random(42, 'btemp:' || p_vehicle_id::text) * 10,
                         car.soh,
                         GREATEST(0.2, public.ottoq_profile_rate_mult(p_sim_run_id, 'charge_time'))))
                   ORDER BY k.rk)
              FROM ranked k CROSS JOIN car
             WHERE k.decision_seq = ch.decision_seq AND k.rk <= 3) END)
        ORDER BY ch.decision_seq)
        FROM choice ch), '[]'::jsonb));
$function$;

GRANT EXECUTE ON FUNCTION public.ottoq_decision_options(uuid, uuid) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.ottoq_decision_options(uuid, uuid) IS
  '0590. What each of a car''s charger decisions in a run had to choose from: the assigner''s candidate set rebuilt from '
  'the frame its tick decided on, ranked by the assigner''s own ORDER BY, with agrees (the rebuild reproduces the '
  'engine''s pick), options_found (only where it agrees), why (the key that separated the pick), the depot at that tick, '
  'and each top option''s charge minutes by the twin''s own estimate. Read-only; unknown stays NULL.';

-- V1: read-only, pinned, and open to the cockpits
DO $verify$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p
              WHERE p.oid = 'public.ottoq_decision_options(uuid,uuid)'::regprocedure
                AND (p.provolatile <> 's' OR NOT p.prosecdef
                     OR NOT COALESCE(p.proconfig::text ILIKE '%search_path%', false)
                     OR NOT has_function_privilege('anon', p.oid, 'EXECUTE'))) THEN
    RAISE EXCEPTION '0590 V1: ottoq_decision_options is not STABLE, pinned SECURITY DEFINER and open to the cockpits';
  END IF;
END $verify$;

-- This file's own classification goes in before the verification that reads data (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0590_each_charger_choice_says_what_it_chose_from', false, false,
  'One read-only cockpit contract: ottoq_decision_options (the options each charger decision had, rebuilt from its '
  'tick''s frame and checked against the pick). No table, no tick path.', now())
ON CONFLICT (name) DO NOTHING;

-- V2: on the latest operator run whose frames carry the selector's facts, every rule-based pick is the rebuild's first
--     option and every wait's first tick has none. (If none is left after pruning, this says so and passes.)
DO $v2$
DECLARE
  v_run uuid; v_car uuid; j jsonb; c jsonb;
  v_picks int := 0; v_picks_ok int := 0; v_waits int := 0; v_waits_ok int := 0;
BEGIN
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.run_by IN ('operator_demo', 'production_live')
     AND EXISTS (SELECT 1 FROM public.ottoq_decision_snapshots s
                  WHERE s.sim_run_id = r.sim_run_id AND s.frame->'selector' ? 'facts_version')
   ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE '0590 V2: no operator run with frames is left to measure against; skipped';
    RETURN;
  END IF;
  FOR v_car IN SELECT DISTINCT d.entity_id FROM public.ottoq_decisions d
                WHERE d.sim_run_id = v_run AND d.action_context = 'stall_assignment' AND d.l2_engine = 'deterministic_v1'
  LOOP
    j := public.ottoq_decision_options(v_run, v_car);
    FOR c IN SELECT x FROM jsonb_array_elements(j->'choices') x WHERE x->>'engine' = 'deterministic_v1' LOOP
      IF c->>'outcome' = 'enacted' THEN
        v_picks := v_picks + 1;
        IF (c->>'agrees')::boolean AND (c->>'options_found')::int >= 1 AND c->>'why' IS NOT NULL
           AND jsonb_array_length(c->'options') >= 1 AND (c->'options'->0->>'chosen')::boolean
           AND (c->'options'->0->>'charge_min') IS NOT NULL THEN
          v_picks_ok := v_picks_ok + 1;
        END IF;
      ELSE
        v_waits := v_waits + 1;
        IF (c->>'agrees')::boolean AND (c->>'options_found')::int = 0 THEN v_waits_ok := v_waits_ok + 1; END IF;
      END IF;
    END LOOP;
  END LOOP;
  IF v_picks = 0 OR v_picks_ok <> v_picks OR v_waits_ok <> v_waits THEN
    RAISE EXCEPTION '0590 V2 FAILED on run %: picks % of % reproduced, waits % of %', v_run, v_picks_ok, v_picks, v_waits_ok, v_waits;
  END IF;
  RAISE NOTICE '0590 V2: run %: picks % of % reproduced, waits % of %', v_run, v_picks_ok, v_picks, v_waits_ok, v_waits;
END $v2$;

-- V3: a frame without the selector's facts gives no count and no verdict, never 0; a car with no decisions gives none.
DO $v3$
DECLARE v_run uuid; v_car uuid; j jsonb;
BEGIN
  SELECT d.sim_run_id, d.entity_id INTO v_run, v_car
    FROM public.ottoq_decisions d JOIN public.ottoq_decision_snapshots s ON s.snapshot_id = d.snapshot_id
   WHERE d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
     AND NOT (s.frame->'selector' ? 'facts_version')
   LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE '0590 V3: no frame without selector facts is left; the NULL path is not exercised';
  ELSE
    j := public.ottoq_decision_options(v_run, v_car);
    IF jsonb_array_length(j->'choices') = 0
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(j->'choices') x
                   WHERE x->'agrees' <> 'null'::jsonb OR x->'options_found' <> 'null'::jsonb OR x->'depot' <> 'null'::jsonb) THEN
      RAISE EXCEPTION '0590 V3 FAILED: a frame without facts read as known: %', left(j::text, 800);
    END IF;
  END IF;
  j := public.ottoq_decision_options(COALESCE(v_run, gen_random_uuid()), gen_random_uuid());
  IF j->>'contract' <> 'ottoq_decision_options/0590' OR j->'choices' <> '[]'::jsonb THEN
    RAISE EXCEPTION '0590 V3 FAILED: an unknown car read %', j;
  END IF;
END $v3$;

COMMIT;
