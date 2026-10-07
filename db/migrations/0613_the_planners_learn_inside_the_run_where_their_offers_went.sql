-- migration-version: 20261007135127
-- migration-name:    the_planners_learn_inside_the_run_where_their_offers_went
--
-- 0613  **The planners learn, inside the run, where their offers went.** Chase, 2026-10-07: *"Maybe it should have a
--       learning loop attached to the final dispatch so that it becomes aware of what has actually passed through all
--       layers of OTTO-Q ... If it propose something that doesn't pass, there should either be a function where it
--       finds an adjacent solution, such as a different L2 charger ... or it gets kicked back to the agent layer ...
--       Either way, there's learning within each run."* Nothing here is stored past the run: every figure is read from
--       the run's own rows when it is asked for.
--
--   MEASURED BEFORE THIS FILE, run fd6ed035 (busy_day, 116 cars, 40 chargers, 46 solver passes). The solver made 49
--   real offers and none was used: 48 refused (24 stall_occupied, 24 stall_reserved), 1 superseded. On EVERY tick a
--   pass landed, the kernel's charge queue held about 34 cars and seated about 0.9 of them (33.3 got no charger). The
--   solver planned 8 cars per pass, chosen by deadline and SoC, while the kernel seats cars in its own order
--   (immediate dispatch first, then the longest wait for the charge still owed, 0545/0551). So its offers went to
--   cars behind the head of the line, and the one charger that came free went to the head car through the kernel's
--   own path. The refusals were capacity, not bad offers -- and the proposer could not see either fact. 436 more rows
--   were abstentions ("no charge operation in the returned plan"), and the edge function's feedback query read the
--   last 24 refused-or-expired rows, which those abstentions crowded out: the solver was told about almost nothing.
--
--   THREE PARTS, all run-scoped:
--
--   1. public.ottoq_run_learning(run, lookback_ticks, detail): what the planners need to know NOW and what happened to
--      their offers. Chargers by type across the three gates (pointer, OCPP charger, calendar -- the frame's own
--      `offerable`), the chargers that are down and when each comes back, the kernel's charge queue in the order the
--      kernel seats it, the batch the solver should plan (max_assets = the free chargers, 1..8; priority = the
--      queue's head), each source's offers (made, used, moved, refused by reason, abstained), the last refusals with
--      the car each charger went to, the last assignments that passed every layer, and a one-line lesson. Read-only,
--      anon-executable like the other twin boards (0609), never on the tick path.
--
--      THE QUEUE MIRRORS ottoq_decide_tick's stall-assignment cursor (its WHERE and ORDER BY, P1 pins both), less
--      three things that are right for the cursor and wrong for a plan: the one-tick right-of-first-refusal hold (a
--      held car is the car waiting for this very plan), the "a charger is free" test on a staged car (it is still in
--      line when none is), and the charging-staff LIMIT (neutral at the twin depot).
--
--   2. ottoq_promote_proposal_candidates gains the ADJACENT RESCUE. A planner offer (a holds_tick source) whose charger
--      is no longer free, and which carries no ranked fallbacks of its own, moves to the nearest EQUAL charger that is
--      free across all three gates: same stall type, same plug capacity (so requested_kw stays right, 0359's rule),
--      the car's inlet fits, no other car's booking covers the clock, and no other car's pending offer names it. It
--      stays pending and is used when the car is seated. With nothing equal free it is refused exactly as before, and
--      the car keeps its place in line (its wait keeps counting, 0551). The candidate walk for proposals that DO
--      carry fallbacks is unchanged; the loop's last sort key moves from proposal_id (a random uuid, the 0238 defect)
--      to the proposal's content, so two offers that compete for one free charger resolve the same way in any arm.
--
--   3. ottoq_agent_board_grounding gains `planner_learning`, the brief form of part 1, so a refusal pattern reaches the
--      agent layer that sets the solver's objective (the edge function's prompt names it).
--
--   forces_recert FALSE, forces_dial_restart FALSE, MEASURED (V5): the rescue acts only on a pending offer from a
--   holds_tick source or one carrying ranked candidates, and across every surviving run 90 cert_harness and 49
--   ab_harness runs carry neither (all such offers are on operator_demo and production_live runs). Parts 1 and 3 are
--   reads nothing on the tick path calls.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0613 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies this file replaces or patches are the ones it was written against; the cursor it mirrors ──
DO $premises$
DECLARE v_tick_src text;
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p
       WHERE p.oid = 'public.ottoq_promote_proposal_candidates(uuid,bigint,timestamp with time zone,integer)'::regprocedure)
     IS DISTINCT FROM '003ca0d0c7774c0dfabce5a50107147a' THEN
    RAISE EXCEPTION '0613 P1: ottoq_promote_proposal_candidates is not the body this file replaces (md5 003ca0d0); read it again';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p
       WHERE p.oid = 'public.ottoq_agent_board_grounding(uuid,uuid,timestamp with time zone)'::regprocedure)
     IS DISTINCT FROM '2df16fea6aa3bf0ae723d89e8eb548db' THEN
    RAISE EXCEPTION '0613 P1: ottoq_agent_board_grounding is not the body this file patches (md5 2df16fea); read it again';
  END IF;
  -- The queue in part 1 mirrors these fragments of the kernel's stall-assignment cursor. If one is gone, the cursor
  -- changed and the mirror must be re-read before it is published.
  SELECT p.prosrc INTO v_tick_src FROM pg_proc p WHERE p.oid = 'public.ottoq_decide_tick(uuid)'::regprocedure;
  IF strpos(v_tick_src, 'AND NOT public.ottoq_vehicle_fault_open(v.config)') = 0
     OR strpos(v_tick_src, 'AND (v.current_state = ''arrived_at_gate''') = 0
     OR strpos(v_tick_src, 'OR (v.current_state = ''staged_awaiting_service'' AND EXISTS (') = 0
     OR strpos(v_tick_src, 'ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), public.ottoq_default_target_soc()) - 1') = 0
     OR strpos(v_tick_src, 'ORDER BY COALESCE((SELECT vn.urgency = ''immediate_dispatch'' FROM ottoq_visit_needs vn') = 0
     OR strpos(v_tick_src, 'CASE WHEN v_seat = 1 THEN v.last_state_change END ASC NULLS FIRST,') = 0
     OR strpos(v_tick_src, 'CASE WHEN v_seat = 2 THEN v.current_soc END ASC,') = 0
     OR strpos(v_tick_src, '(public.ottoq_charge_wait_min(v.config, v.last_state_change, v_clock, p_sim_run_id)') = 0
     OR strpos(v_tick_src, '+ GREATEST(public.ottoq_effective_target_soc_at(v.id, v_clock) - v.current_soc, 1))') = 0
     OR strpos(v_tick_src, '/ GREATEST(public.ottoq_effective_target_soc_at(v.id, v_clock) - v.current_soc, 1)') = 0
     OR strpos(v_tick_src, 'v.current_soc ASC, v.id') = 0
     OR strpos(v_tick_src, 'v_seat := COALESCE(public.ottoq_policy_get(p_sim_run_id, ''proposer_seat'', 0), 0)::int;') = 0 THEN
    RAISE EXCEPTION '0613 P1: ottoq_decide_tick''s stall-assignment cursor is not the one the queue mirrors; read it again';
  END IF;
  IF to_regprocedure('public.ottoq_run_learning(uuid,integer,boolean)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0613_the_planners_learn_inside_the_run_where_their_offers_went') THEN
    RAISE EXCEPTION '0613 P1: already applied';
  END IF;
END $premises$;

-- ── snapshots before the replace and the patch ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0613_pre', 'function', 'public', x.name, x.def, md5(x.def)
  FROM (VALUES
          ('ottoq_promote_proposal_candidates',
           pg_get_functiondef('public.ottoq_promote_proposal_candidates(uuid,bigint,timestamp with time zone,integer)'::regprocedure)),
          ('ottoq_agent_board_grounding',
           pg_get_functiondef('public.ottoq_agent_board_grounding(uuid,uuid,timestamp with time zone)'::regprocedure))) x(name, def);

-- ═══ 1. public.ottoq_run_learning ══════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_run_learning(p_sim_run_id uuid, p_lookback_ticks integer DEFAULT 20, p_detail boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_zero    constant uuid := '00000000-0000-0000-0000-000000000000';
  v_depot   uuid; v_clock timestamptz; v_tick bigint; v_status text; v_seat int;
  v_look    int := LEAST(GREATEST(COALESCE(p_lookback_ticks, 20), 1), 500);
  v_chg     jsonb; v_down jsonb; v_free int := 0;
  v_head    jsonb; v_waiting int := 0; v_need int := 0; v_batch int; v_priority jsonb;
  v_recent  jsonb; v_run jsonb; v_plan jsonb; v_run_plan jsonb; v_live boolean;
  v_refusals jsonb; v_dispatched jsonb;
  v_off int; v_used int; v_moved int; v_lost int;
  v_code text; v_text text;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'run_required'); END IF;
  SELECT r.depot_id, r.sim_clock_current, r.tick_count, r.status
    INTO v_depot, v_clock, v_tick, v_status
    FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'run_not_found'); END IF;
  v_clock := COALESCE(v_clock, now());
  v_tick  := COALESCE(v_tick, 0);
  v_seat  := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'proposer_seat', 0), 0)::int;
  -- Stalls, chargers and cars are one depot's rows shared by every run, so the chargers and the queue below are the
  -- depot NOW. That is the run's own state only while it is running; `live` says which.
  v_live  := (v_status = 'running');

  -- ── chargers: the frame's `offerable` (0265/0498), counted by type, and the ones that are down ──
  WITH s AS (
    SELECT st.id, st.stall_type::text AS kind, COALESCE(st.display_name, st.stall_code) AS name,
           (st.current_vehicle_id IS NOT NULL) AS in_use,
           (st.current_vehicle_id IS NULL AND st.reserved_by IS NOT NULL
            AND COALESCE(st.reservation_expires_at, 'infinity'::timestamptz) > v_clock) AS reserved,
           COALESCE(c.station_state = 'Faulted', false) AS faulted,
           (c.station_state = 'Available' AND c.last_heartbeat_at >= v_clock - interval '90 seconds') AS charger_ok,
           c.last_fault_code, c.station_state_changed_at, c.last_fault_payload ->> 'repair_minutes' AS repair_min,
           cal.vehicle_id AS cal_holder
      FROM stalls st
      LEFT JOIN ottoq_ocpp_chargers c ON c.charger_id = st.ocpp_charger_id
      LEFT JOIN LATERAL (
        SELECT b.vehicle_id FROM ottoq_stall_bookings b
         WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = st.id
           AND b.state IN ('held','active','done','interrupted') AND b.during @> v_clock
         ORDER BY lower(b.during), b.vehicle_id, b.booking_id LIMIT 1) cal ON true
     WHERE st.depot_id = v_depot AND st.stall_type::text IN ('dcfc','l2')
  ), f AS (
    SELECT s.*, (NOT s.in_use AND NOT s.reserved AND COALESCE(s.charger_ok, false) AND s.cal_holder IS NULL) AS free
      FROM s
  )
  SELECT (SELECT jsonb_object_agg(q.kind, jsonb_build_object(
                   'total', q.n, 'free', q.nf, 'in_use', q.nu, 'reserved', q.nr,
                   'held_by_calendar', q.ncal, 'faulted', q.nflt, 'not_heartbeating', q.nhb))
            FROM (SELECT kind, count(*) n, count(*) FILTER (WHERE free) nf, count(*) FILTER (WHERE in_use) nu,
                         count(*) FILTER (WHERE reserved) nr,
                         count(*) FILTER (WHERE NOT in_use AND NOT reserved AND NOT faulted
                                            AND COALESCE(charger_ok, false) AND cal_holder IS NOT NULL) ncal,
                         count(*) FILTER (WHERE faulted) nflt,
                         count(*) FILTER (WHERE NOT faulted AND NOT COALESCE(charger_ok, false)) nhb
                    FROM f GROUP BY kind) q),
         (SELECT count(*) FROM f WHERE free),
         (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                   'stall_id', f.id, 'name', f.name, 'kind', f.kind, 'fault_code', f.last_fault_code,
                   'back_at', CASE WHEN f.repair_min ~ '^[0-9]+(\.[0-9]+)?$'
                                   THEN f.station_state_changed_at + (f.repair_min || ' minutes')::interval END)
                   ORDER BY f.name, f.id), '[]'::jsonb)
            FROM f WHERE f.faulted)
    INTO v_chg, v_free, v_down;

  -- ── the kernel's charge queue, in the order ottoq_decide_tick seats it (P1 pins the fragments mirrored) ──
  WITH q AS (
    SELECT v.id, COALESCE(v.display_name, v.id::text) AS name, v.current_state::text AS state,
           v.current_soc, v.last_state_change,
           COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
                      WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                        AND COALESCE(vn.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)
                      ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), public.ottoq_default_target_soc()) AS visit_target,
           COALESCE((SELECT vn.urgency = 'immediate_dispatch' FROM ottoq_visit_needs vn
                      WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                        AND COALESCE(vn.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)
                      ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), false) AS immediate,
           public.ottoq_charge_wait_min(v.config, v.last_state_change, v_clock, p_sim_run_id) AS wait_min,
           GREATEST(public.ottoq_effective_target_soc_at(v.id, v_clock) - v.current_soc, 1) AS gap,
           EXISTS (SELECT 1 FROM stalls s2
                    WHERE s2.reserved_by = v.id AND s2.reservation_expires_at > v_clock
                      AND s2.stall_type::text IN ('dcfc','l2')) AS holds_charger
      FROM vehicles v
     WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
       AND NOT public.ottoq_vehicle_fault_open(v.config)
       AND v.current_state::text IN ('arrived_at_gate','staged_awaiting_service')
  ), o AS (
    SELECT q.*, row_number() OVER (
             ORDER BY q.immediate DESC,
                      CASE WHEN v_seat = 1 THEN q.last_state_change END ASC NULLS FIRST,
                      CASE WHEN v_seat = 2 THEN q.current_soc END ASC,
                      CASE WHEN v_seat = 0 THEN (q.wait_min + q.gap) / q.gap END DESC NULLS LAST,
                      q.current_soc ASC, q.id) AS pos
      FROM q WHERE q.current_soc < q.visit_target - 1
  )
  SELECT count(*), count(*) FILTER (WHERE NOT o.holds_charger),
         COALESCE(jsonb_agg(jsonb_build_object(
           'pos', o.pos, 'vehicle_id', o.id, 'name', o.name, 'state', o.state,
           'soc', round(o.current_soc::numeric, 1), 'target_soc', o.visit_target,
           'wait_min', round(o.wait_min::numeric, 1), 'immediate', o.immediate, 'holds_charger', o.holds_charger)
           ORDER BY o.pos) FILTER (WHERE o.pos <= 24), '[]'::jsonb),
         COALESCE(jsonb_agg(to_jsonb(o.id) ORDER BY o.pos) FILTER (WHERE NOT o.holds_charger), '[]'::jsonb)
    INTO v_waiting, v_need, v_head, v_priority
    FROM o;

  -- The batch: plan as many cars as there are free chargers, at least one (a plan for the head of the line is still
  -- worth having when a charger frees mid-pass) and at most the 8 a 30-second tick can solve (proposer/README.md).
  v_batch := GREATEST(1, LEAST(8, LEAST(v_need, v_free)));
  v_priority := COALESCE((SELECT jsonb_agg(e.value ORDER BY e.ord)
                            FROM jsonb_array_elements(v_priority) WITH ORDINALITY e(value, ord)
                           WHERE e.ord <= 24), '[]'::jsonb);

  -- ── each source's offers, in the last v_look ticks and over the run ──
  WITH p AS (
    SELECT x.source, x.status, x.disposition_reason, x.tick_seq,
           COALESCE(x.proposal ->> 'abstain', '') IN ('true','t','1') AS abstain,
           (COALESCE(x.proposal ->> 'promotion_count', '') ~ '^[1-9][0-9]*$') AS moved,
           x.source IN (SELECT pp.source FROM ottoq_proposer_precedence pp WHERE pp.holds_tick) AS planner
      FROM ottoq_external_proposals x
     WHERE x.sim_run_id = p_sim_run_id AND x.action_context = 'stall_assignment'
  ), agg AS (
    SELECT p.source, (p.tick_seq >= v_tick - v_look) AS recent,
           count(*) FILTER (WHERE NOT p.abstain) AS offered,
           count(*) FILTER (WHERE NOT p.abstain AND p.status = 'enacted') AS used,
           count(*) FILTER (WHERE NOT p.abstain AND p.moved) AS moved,
           count(*) FILTER (WHERE NOT p.abstain AND p.moved AND p.status = 'enacted') AS moved_used,
           count(*) FILTER (WHERE NOT p.abstain AND p.status = 'superseded') AS superseded,
           count(*) FILTER (WHERE NOT p.abstain AND p.status = 'expired') AS expired,
           count(*) FILTER (WHERE NOT p.abstain AND p.status = 'pending') AS pending,
           count(*) FILTER (WHERE p.abstain) AS abstained,
           bool_or(p.planner) AS planner
      FROM p GROUP BY p.source, (p.tick_seq >= v_tick - v_look)
  ), refused AS (
    SELECT x.source, x.recent, jsonb_object_agg(x.reason, x.n) AS by_reason, sum(x.n)::int AS n
      FROM (SELECT p.source, (p.tick_seq >= v_tick - v_look) AS recent,
                   COALESCE(p.disposition_reason, 'unstated') AS reason, count(*)::int AS n
              FROM p WHERE NOT p.abstain AND p.status = 'refused'
             GROUP BY 1, 2, 3) x
     GROUP BY x.source, x.recent
  ), per AS (
    SELECT a.source, a.recent, a.planner,
           jsonb_build_object('planner', a.planner, 'offered', a.offered, 'used', a.used, 'moved', a.moved,
                              'moved_then_used', a.moved_used, 'refused', COALESCE(r.n, 0),
                              'refused_by_reason', COALESCE(r.by_reason, '{}'::jsonb),
                              'superseded', a.superseded, 'expired', a.expired, 'pending', a.pending,
                              'abstained', a.abstained) AS j,
           a.offered, a.used, a.moved, COALESCE(r.n, 0) AS refused
      FROM agg a LEFT JOIN refused r ON r.source = a.source AND r.recent = a.recent
  )
  SELECT
    -- recent window, per source
    (SELECT COALESCE(jsonb_object_agg(per.source, per.j), '{}'::jsonb) FROM per WHERE per.recent),
    -- whole run, per source (recent and older summed)
    (SELECT COALESCE(jsonb_object_agg(t.source, jsonb_build_object(
              'planner', t.planner, 'offered', t.offered, 'used', t.used, 'moved', t.moved, 'refused', t.refused)), '{}'::jsonb)
       FROM (SELECT per.source, bool_or(per.planner) planner, sum(per.offered)::int offered, sum(per.used)::int used,
                    sum(per.moved)::int moved, sum(per.refused)::int refused
               FROM per GROUP BY per.source) t),
    -- recent window, the planners together
    (SELECT jsonb_build_object('offered', COALESCE(sum(per.offered), 0)::int, 'used', COALESCE(sum(per.used), 0)::int,
                               'moved', COALESCE(sum(per.moved), 0)::int, 'refused', COALESCE(sum(per.refused), 0)::int,
                               'refused_by_reason', COALESCE((
                                 SELECT jsonb_object_agg(k, n) FROM (
                                   SELECT e.key k, sum(e.value::int)::int n
                                     FROM per p3, jsonb_each_text(p3.j -> 'refused_by_reason') e
                                    WHERE p3.recent AND p3.planner GROUP BY e.key) z), '{}'::jsonb))
       FROM per WHERE per.recent AND per.planner),
    -- the whole run, the planners together
    (SELECT jsonb_build_object('offered', COALESCE(sum(per.offered), 0)::int, 'used', COALESCE(sum(per.used), 0)::int,
                               'moved', COALESCE(sum(per.moved), 0)::int, 'refused', COALESCE(sum(per.refused), 0)::int)
       FROM per WHERE per.planner)
    INTO v_recent, v_run, v_plan, v_run_plan;

  v_off   := COALESCE((v_plan ->> 'offered')::int, 0);
  v_used  := COALESCE((v_plan ->> 'used')::int, 0);
  v_moved := COALESCE((v_plan ->> 'moved')::int, 0);
  v_lost  := COALESCE((v_plan -> 'refused_by_reason' ->> 'stall_occupied')::int, 0)
           + COALESCE((v_plan -> 'refused_by_reason' ->> 'stall_reserved')::int, 0);

  -- ── the lesson, one line, for the agent and the cockpit ──
  IF NOT v_live THEN
    v_code := 'run_ended';
    v_text := format('This run has ended. Planner offers over the run: %s made, %s used, %s moved to an equal charger, '
                     '%s refused.', v_run_plan ->> 'offered', v_run_plan ->> 'used', v_run_plan ->> 'moved',
                     v_run_plan ->> 'refused');
  ELSIF v_need = 0 THEN
    v_code := 'no_one_waiting';
    v_text := 'No car waits for a charger.';
  ELSIF v_need > v_free THEN
    v_code := 'more_cars_than_chargers';
    v_text := format('%s cars wait for %s free chargers. The planner plans only the next %s in the kernel''s service '
                     'order. An offer refused for stall_occupied or stall_reserved here is a capacity finding, not a '
                     'planner fault: the charger went to a car ahead in line.', v_need, v_free, v_batch);
  ELSIF v_lost > 0 THEN
    v_code := 'offers_lost_their_charger';
    v_text := format('%s of the last %s planner offers lost their charger before use and %s moved to an equal free '
                     'charger. %s free chargers for %s waiting cars.', v_lost, v_off, v_moved, v_free, v_need);
  ELSE
    v_code := 'chargers_free';
    v_text := format('%s free chargers for %s waiting cars. Planner offers in the last %s ticks: %s made, %s used.',
                     v_free, v_need, v_look, v_off, v_used);
  END IF;

  IF NOT COALESCE(p_detail, true) THEN
    RETURN jsonb_build_object(
      'ok', true, 'live', v_live, 'tick', v_tick, 'window_ticks', v_look,
      'chargers', (SELECT jsonb_object_agg(k.key, jsonb_build_object('free', k.value -> 'free', 'total', k.value -> 'total',
                                                                     'faulted', k.value -> 'faulted'))
                     FROM jsonb_each(COALESCE(v_chg, '{}'::jsonb)) k),
      'waiting_for_a_charger', v_need, 'batch_max_assets', v_batch,
      'planner_offers_recent', v_plan,
      'lesson', jsonb_build_object('code', v_code, 'text', v_text));
  END IF;

  -- ── the last refusals, and the car each charger went to ──
  SELECT COALESCE(jsonb_agg(z.j ORDER BY z.k DESC, z.pid), '[]'::jsonb) INTO v_refusals
    FROM (
      SELECT COALESCE(x.disposed_tick, x.tick_seq) AS k, x.proposal_id::text AS pid,
             jsonb_build_object(
               'tick', COALESCE(x.disposed_tick, x.tick_seq), 'source', x.source,
               'vehicle_id', x.entity_id, 'vehicle', COALESCE(vv.display_name, x.entity_id::text),
               'stall_id', st.id, 'stall', COALESCE(st.display_name, st.stall_code), 'kind', st.stall_type::text,
               'reason', COALESCE(x.disposition_reason, 'unstated'),
               'went_to', (SELECT jsonb_build_object('vehicle_id', d.entity_id,
                                                     'vehicle', COALESCE(dv.display_name, d.entity_id::text),
                                                     'tick', d.tick_seq,
                                                     -- the offer's own car already had the charger: a plan for a
                                                     -- car the kernel had just seated
                                                     'same_car', d.entity_id = x.entity_id,
                                                     'path', CASE WHEN d.enacted_action ->> 'source' IN
                                                                        (SELECT pp.source FROM ottoq_proposer_precedence pp WHERE pp.holds_tick)
                                                                  THEN 'planner'
                                                                  WHEN d.enacted_action ->> 'source' = 'greedy_constrained' THEN 'local_optimizer'
                                                                  ELSE 'kernel' END)
                             FROM ottoq_decisions d LEFT JOIN vehicles dv ON dv.id = d.entity_id
                            WHERE d.sim_run_id = p_sim_run_id
                              AND d.tick_seq BETWEEN COALESCE(x.disposed_tick, x.tick_seq) - 60 AND COALESCE(x.disposed_tick, x.tick_seq)
                              AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
                              AND d.enacted_action ->> 'stall_id' = st.id::text
                            ORDER BY d.tick_seq DESC, d.decision_seq DESC LIMIT 1)) AS j
        FROM ottoq_external_proposals x
        LEFT JOIN vehicles vv ON vv.id = x.entity_id
        LEFT JOIN stalls st ON st.id::text = x.proposal ->> 'stall_id'
       WHERE x.sim_run_id = p_sim_run_id AND x.action_context = 'stall_assignment' AND x.status = 'refused'
         AND COALESCE(x.proposal ->> 'abstain', '') NOT IN ('true','t','1')
       ORDER BY COALESCE(x.disposed_tick, x.tick_seq) DESC, x.proposal_id
       LIMIT 6) z;

  -- ── the last assignments that passed every layer ──
  SELECT COALESCE(jsonb_agg(z.j ORDER BY z.t DESC, z.s DESC), '[]'::jsonb) INTO v_dispatched
    FROM (
      SELECT d.tick_seq AS t, d.decision_seq AS s,
             jsonb_build_object(
               'tick', d.tick_seq, 'vehicle_id', d.entity_id, 'vehicle', COALESCE(dv.display_name, d.entity_id::text),
               'stall_id', st.id, 'stall', COALESCE(st.display_name, st.stall_code), 'kind', st.stall_type::text,
               'source', COALESCE(d.enacted_action ->> 'source', 'kernel'),
               'moved_from_offer', COALESCE(d.enacted_action ->> 'promotion_source' = 'adjacent_equivalent', false),
               'path', CASE WHEN d.enacted_action ->> 'source' IN
                                  (SELECT pp.source FROM ottoq_proposer_precedence pp WHERE pp.holds_tick) THEN 'planner'
                            WHEN d.enacted_action ->> 'source' = 'greedy_constrained' THEN 'local_optimizer'
                            ELSE 'kernel' END) AS j
        FROM ottoq_decisions d
        LEFT JOIN vehicles dv ON dv.id = d.entity_id
        LEFT JOIN stalls st ON st.id::text = d.enacted_action ->> 'stall_id'
       WHERE d.sim_run_id = p_sim_run_id AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
       ORDER BY d.tick_seq DESC, d.decision_seq DESC
       LIMIT 6) z;

  RETURN jsonb_build_object(
    'ok', true, 'live', v_live,
    'run', jsonb_build_object('sim_run_id', p_sim_run_id, 'status', v_status, 'tick', v_tick, 'clock', v_clock),
    'window_ticks', v_look,
    'chargers', COALESCE(v_chg, '{}'::jsonb),
    'chargers_free', v_free,
    'chargers_down', v_down,
    'queue', jsonb_build_object('waiting', v_waiting, 'waiting_for_a_charger', v_need,
                                'order', CASE v_seat WHEN 1 THEN 'fifo' WHEN 2 THEN 'greedy' ELSE 'otto_q' END,
                                'head', v_head),
    'batch', jsonb_build_object('max_assets', v_batch, 'priority', v_priority),
    'offers', jsonb_build_object('recent', v_recent, 'run', v_run, 'planners_recent', v_plan, 'planners_run', v_run_plan),
    'refusals', v_refusals,
    'dispatched', v_dispatched,
    'lesson', jsonb_build_object('code', v_code, 'text', v_text),
    'basis', jsonb_build_object(
      'chargers', 'dcfc and l2 stalls at the run''s depot. free = no car on it, no live reservation, OCPP charger Available '
                  'with a heartbeat inside 90 s of the sim clock, and no booking of the run covering the clock: the '
                  'decision frame''s own offerable (0265/0498). Read from the depot now, so they are this run''s only '
                  'while live is true.',
      'queue', 'ottoq_decide_tick''s stall-assignment cursor and order (0545/0551; seat 1 fifo, seat 2 greedy), less the '
               'one-tick first-refusal hold, the free-charger test on a staged car and the charging-staff limit. '
               'waiting_for_a_charger leaves out a car that already holds a live charger reservation.',
      'batch', 'max_assets = free chargers, 1..8; priority = the queue''s first 24 cars without a charger reservation.',
      'offers', 'ottoq_external_proposals for stall_assignment. offered excludes abstentions; moved = promoted at least '
                'once (0358 candidates or 0613 adjacent rescue); refused_by_reason is the disposer''s reason.',
      'refusals', 'went_to is the latest assignment of that charger, at most 60 ticks before the refusal; same_car means '
                  'the offer''s own car already had it.'));
EXCEPTION WHEN OTHERS THEN
  -- A read for advisors and a cockpit: a fault in it must never take the agent's board or the solver pass down.
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END
$fn$;

REVOKE ALL ON FUNCTION public.ottoq_run_learning(uuid, integer, boolean) FROM PUBLIC, anon, authenticated, service_role;

-- ── the safety gate (0405, 0560, 0606, 0609): write-free on its comment-stripped source, and the helpers it calls.
-- ottoq_policy_get is checked without set_config: its one set_config is 0533's transaction-local read witness. ──
DO $gate$
DECLARE v_src text; v_name text;
BEGIN
  FOR v_name, v_src IN
    SELECT p.oid::regprocedure::text,
           regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^' || chr(10) || ']*', '', 'g')
      FROM pg_proc p
     WHERE p.oid IN ('public.ottoq_run_learning(uuid,integer,boolean)'::regprocedure,
                     'public.ottoq_charge_wait_min(jsonb,timestamp with time zone,timestamp with time zone,uuid)'::regprocedure,
                     'public.ottoq_effective_target_soc_at(uuid,timestamp with time zone)'::regprocedure,
                     'public.ottoq_default_target_soc()'::regprocedure,
                     'public.ottoq_vehicle_fault_open(jsonb)'::regprocedure)
  LOOP
    IF v_src ~* '(INSERT[[:space:]]+INTO[[:space:]]|UPDATE[[:space:]]+[a-z_."]+[[:space:]]+SET[[:space:]]|DELETE[[:space:]]+FROM[[:space:]]|TRUNCATE[[:space:]]|nextval[[:space:]]*\(|set_config[[:space:]]*\()' THEN
      RAISE EXCEPTION '0613: % contains a write; the learning read must not be granted to anon', v_name;
    END IF;
  END LOOP;
  SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^' || chr(10) || ']*', '', 'g') INTO v_src
    FROM pg_proc p WHERE p.oid = 'public.ottoq_policy_get(uuid,text,numeric)'::regprocedure;
  IF v_src ~* '(INSERT[[:space:]]+INTO[[:space:]]|UPDATE[[:space:]]+[a-z_."]+[[:space:]]+SET[[:space:]]|DELETE[[:space:]]+FROM[[:space:]]|TRUNCATE[[:space:]]|nextval[[:space:]]*\()'
     OR (length(v_src) - length(replace(v_src, 'set_config', ''))) / length('set_config') <> 1
     OR strpos(v_src, '''ottoq.run_scope_reads''') = 0 THEN
    RAISE EXCEPTION '0613: ottoq_policy_get writes something besides its transaction-local read witness';
  END IF;
  IF (public.ottoq_run_learning(NULL) ->> 'error') IS DISTINCT FROM 'run_required' THEN
    RAISE EXCEPTION '0613: the learning read answers without a run';
  END IF;
END $gate$;

GRANT EXECUTE ON FUNCTION public.ottoq_run_learning(uuid, integer, boolean) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.ottoq_run_learning(uuid, integer, boolean) IS
'0613. What the planners learn inside one run (anon-executable, read-only, nothing stored): chargers by type across the three gates and the ones that are down, the kernel''s charge queue in the order it seats cars, the batch the solver should plan (max_assets = free chargers, priority = the queue''s head), each source''s offers (made, used, moved, refused by reason), the last refusals with the car each charger went to, the last assignments that passed every layer, and a one-line lesson. p_detail false returns the brief form the agent board carries.';

-- ═══ 2. ottoq_promote_proposal_candidates: the adjacent rescue ═════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_promote_proposal_candidates(p_sim_run_id uuid, p_tick_seq bigint DEFAULT NULL::bigint, p_sim_clock timestamp with time zone DEFAULT NULL::timestamp with time zone, p_max_promotions integer DEFAULT 3)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_clock   timestamptz;
  v_row     record;
  v_cand    uuid;
  v_cand_kw numeric;          -- 0359: the candidate's OWN load, or NULL for a bare uuid
  v_n       integer := 0;
  v_uuid_re constant text :=
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$';
BEGIN
  --: The disposer's clock resolution, copied so promotion and refusal judge
  --: feasibility against the SAME instant.
  SELECT COALESCE(p_sim_clock, r.sim_clock_current, clock_timestamp())
    INTO v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id = p_sim_run_id;
  v_clock := COALESCE(v_clock, p_sim_clock, clock_timestamp());

  FOR v_row IN
    SELECT p.proposal_id, p.entity_id, p.proposal,
           COALESCE((p.proposal->>'promotion_count')::int, 0) AS promotions,
           --: 0359. The vehicle's inlet and the PRIMARY's plug capacity: the two
           --: facts a promotion must respect. entity_id is the vehicle for a
           --: stall_assignment proposal.
           (SELECT v.inlet_type FROM public.vehicles v WHERE v.id = p.entity_id) AS inlet,
           (SELECT s.connector_max_kw FROM public.stalls s
             WHERE s.id = CASE WHEN COALESCE(p.proposal->>'stall_id','') ~ v_uuid_re
                               THEN (p.proposal->>'stall_id')::uuid ELSE NULL END) AS primary_kw,
           --: 0613. Whether the proposer ranked its own fallbacks, and the primary's
           --: kind, depot and place: what the adjacent rescue below matches on.
           (jsonb_typeof(p.proposal->'candidates') = 'array'
            AND jsonb_array_length(p.proposal->'candidates') > 0) AS has_candidates,
           ps.id AS primary_id, ps.stall_type AS primary_type, ps.depot_id AS primary_depot,
           ps.relative_x AS px, ps.relative_y AS py
      FROM public.ottoq_external_proposals p
      LEFT JOIN public.stalls ps
        ON ps.id = CASE WHEN COALESCE(p.proposal->>'stall_id','') ~ v_uuid_re
                        THEN (p.proposal->>'stall_id')::uuid ELSE NULL END
     WHERE p.sim_run_id = p_sim_run_id
       AND p.status = 'pending'
       AND p.action_context = 'stall_assignment'
       AND ((jsonb_typeof(p.proposal->'candidates') = 'array'
             AND jsonb_array_length(p.proposal->'candidates') > 0)
            --: 0613. A PLANNER'S OFFER WITH NO RANKED FALLBACKS: a source that
            --: declares holds_tick (the planners the kernel waits a tick for), not an
            --: abstention, naming a charge stall that exists.
            OR (p.source IN (SELECT pp.source FROM public.ottoq_proposer_precedence pp
                              WHERE pp.holds_tick)
                AND COALESCE(p.proposal->>'abstain', '') NOT IN ('true', 't', '1')
                AND ps.id IS NOT NULL
                AND ps.stall_type::text IN ('dcfc', 'l2')))
       AND COALESCE((p.proposal->>'promotion_count')::int, 0) < p_max_promotions
       --: only proposals whose CURRENT target is no longer feasible. A feasible
       --: primary is left alone: promotion is a rescue, not a re-rank.
       AND NOT EXISTS (
         SELECT 1
           FROM public.stalls s
           JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
          WHERE s.id = CASE WHEN COALESCE(p.proposal->>'stall_id','') ~ v_uuid_re
                            THEN (p.proposal->>'stall_id')::uuid ELSE NULL END
            AND s.current_vehicle_id IS NULL
            AND (s.reserved_by IS NULL OR s.reserved_by = p.entity_id
                 OR s.reservation_expires_at <= v_clock)
            AND c.station_state = 'Available'
            AND c.last_heartbeat_at >= v_clock - interval '90 seconds')
     --: 0613: content-ordered, never by proposal_id (gen_random_uuid differs between
     --: arms, 0238), so two offers that compete for one free charger resolve alike.
     ORDER BY p.tick_seq NULLS LAST, p.entity_id, p.source, p.proposal::text
  LOOP
    IF v_row.has_candidates THEN
    --: THE WALK. WITH ORDINALITY + ORDER BY ord makes "first feasible" mean first
    --: BY RANK. Each element is either a bare uuid string or an object carrying its
    --: own requested_kw -- 0359's whole point, because four L1 energy evaluators
    --: read requested_kw and a promotion that leaves it stale makes the shield
    --: judge a load the vehicle will not draw.
    SELECT c.cand, c.cand_kw
      INTO v_cand, v_cand_kw
      FROM (
        SELECT CASE
                 WHEN jsonb_typeof(e.value) = 'object' THEN e.value->>'stall_id'
                 ELSE e.value #>> '{}'
               END AS cand_txt,
               CASE
                 WHEN jsonb_typeof(e.value) = 'object'
                  AND (e.value->>'requested_kw') ~ '^[0-9]+(\.[0-9]+)?$'
                 THEN (e.value->>'requested_kw')::numeric
                 ELSE NULL
               END AS cand_kw,
               e.ord
          FROM jsonb_array_elements(v_row.proposal->'candidates')
               WITH ORDINALITY AS e(value, ord)) raw
      CROSS JOIN LATERAL (SELECT raw.cand_txt::uuid AS cand, raw.cand_kw, raw.ord) c
     WHERE raw.cand_txt ~ v_uuid_re
       AND c.cand IS DISTINCT FROM
             CASE WHEN COALESCE(v_row.proposal->>'stall_id','') ~ v_uuid_re
                  THEN (v_row.proposal->>'stall_id')::uuid ELSE NULL END
       --: 0359 (a). THE PLUG MUST FIT. The disposer's predicate never checked this
       --: because the proposer used to choose the stall itself.
       AND public.ottoq_inlet_fits_stall(v_row.inlet, c.cand)
       --: 0359 (b). THE LOAD MUST BE RIGHT. An object candidate brings its own kW.
       --: A bare uuid does not, so it is only promotable onto a plug of the SAME
       --: capacity, where the proposal's existing requested_kw stays valid. The
       --: contract refuses to guess a load.
       AND (c.cand_kw IS NOT NULL
            OR EXISTS (SELECT 1 FROM public.stalls s2
                        WHERE s2.id = c.cand
                          AND s2.connector_max_kw IS NOT DISTINCT FROM v_row.primary_kw))
       AND EXISTS (
         SELECT 1
           FROM public.stalls s
           JOIN public.ottoq_ocpp_chargers c2 ON c2.charger_id = s.ocpp_charger_id
          WHERE s.id = c.cand
            AND s.current_vehicle_id IS NULL
            AND (s.reserved_by IS NULL OR s.reserved_by = v_row.entity_id
                 OR s.reservation_expires_at <= v_clock)
            AND c2.station_state = 'Available'
            AND c2.last_heartbeat_at >= v_clock - interval '90 seconds')
     ORDER BY c.ord
     LIMIT 1;
    ELSE
      --: 0613. THE ADJACENT RESCUE. Chase, 2026-10-07: "a function where it finds an
      --: adjacent solution, such as a different L2 charger". The nearest EQUAL charger
      --: that is free across all three gates the selector asks
      --: (ottoq_l2_external_proposal): the same stall type and the same plug
      --: capacity, so the offer's requested_kw stays right without a guess (0359 b);
      --: the car's inlet fits (0359 a); no car on it and no live reservation for
      --: another car; its OCPP charger Available with a fresh heartbeat; no other
      --: car's booking covering the clock (0499); and no other car's pending offer
      --: naming it, so a rescue never takes a charger another plan is counting on.
      --: Nothing equal free: no move, and the disposer refuses the offer as before.
      SELECT s.id
        INTO v_cand
        FROM public.stalls s
        JOIN public.ottoq_ocpp_chargers c2 ON c2.charger_id = s.ocpp_charger_id
       WHERE s.depot_id = v_row.primary_depot
         AND s.stall_type = v_row.primary_type
         AND s.id <> v_row.primary_id
         AND s.connector_max_kw IS NOT DISTINCT FROM v_row.primary_kw
         AND public.ottoq_inlet_fits_stall(v_row.inlet, s.id)
         AND s.current_vehicle_id IS NULL
         AND (s.reserved_by IS NULL OR s.reserved_by = v_row.entity_id
              OR s.reservation_expires_at <= v_clock)
         AND c2.station_state = 'Available'
         AND c2.last_heartbeat_at >= v_clock - interval '90 seconds'
         AND NOT EXISTS (
           SELECT 1 FROM public.ottoq_stall_bookings b
            WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
              AND b.state IN ('held', 'active', 'done', 'interrupted')
              AND b.vehicle_id <> v_row.entity_id
              AND b.during @> v_clock)
         AND NOT EXISTS (
           SELECT 1 FROM public.ottoq_external_proposals o
            WHERE o.sim_run_id = p_sim_run_id
              AND o.status = 'pending'
              AND o.action_context = 'stall_assignment'
              AND o.entity_id <> v_row.entity_id
              AND COALESCE(o.proposal->>'abstain', '') NOT IN ('true', 't', '1')
              AND o.proposal->>'stall_id' = s.id::text)
       ORDER BY (s.relative_x - v_row.px) ^ 2 + (s.relative_y - v_row.py) ^ 2 NULLS LAST,
                s.stall_code, s.id
       LIMIT 1;
    END IF;

    IF v_cand IS NOT NULL THEN
      --: NO WALL CLOCK: ottoq_hash_proposals digests proposal::text, so a timestamp
      --: would differ between two arms of a pair. promoted_at_tick is deterministic.
      --: requested_kw is rewritten ONLY when the candidate supplied one; otherwise
      --: the (a)/(b) guards above have already proven the existing value still holds.
      UPDATE public.ottoq_external_proposals
         SET proposal = proposal
                        || jsonb_build_object(
                             'stall_id',         v_cand::text,
                             'promoted_from',    proposal->>'stall_id',
                             'promotion_count',  v_row.promotions + 1,
                             'promoted_at_tick', p_tick_seq)
                        || CASE WHEN v_cand_kw IS NOT NULL
                                THEN jsonb_build_object('requested_kw', v_cand_kw,
                                                        'requested_kw_promoted', true)
                                ELSE '{}'::jsonb END
                        --: 0613: said only by the rescue, so a candidate promotion's text is
                        --: what it was.
                        || CASE WHEN v_row.has_candidates THEN '{}'::jsonb
                                ELSE jsonb_build_object('promotion_source', 'adjacent_equivalent') END
       WHERE proposal_id = v_row.proposal_id;
      v_n := v_n + 1;
    END IF;

    v_cand := NULL; v_cand_kw := NULL;
  END LOOP;

  RETURN v_n;
END;
$function$;

-- ═══ 3. ottoq_agent_board_grounding: the planners' lesson reaches the agent layer ═════════════════════════════════
DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_agent_board_grounding(uuid,uuid,timestamp with time zone)'::regprocedure);
  a1 constant text := $a$       WHERE c.agent_writable)
  );
END
$a$;
  b1 constant text := $b$       WHERE c.agent_writable)
  )
  -- 0613: what the planners learned this run (the brief form of ottoq_run_learning): free chargers by type, the cars
  -- waiting for one, the solver's batch, its recent offers by outcome and a one-line lesson. Never raises.
  || jsonb_build_object('planner_learning', public.ottoq_run_learning(p_sim_run_id, 20, false));
END
$b$;
BEGIN
  IF (length(v_def) - length(replace(v_def, a1, ''))) / length(a1) <> 1 THEN
    RAISE EXCEPTION '0613 patch: the grounding''s closing anchor does not occur exactly once';
  END IF;
  EXECUTE replace(v_def, a1, b1);
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_run uuid; v_tick bigint; v_clock timestamptz; v_l jsonb; v_g jsonb;
  v_veh uuid; v_sa uuid; v_sb uuid; v_ca uuid; v_cb uuid; v_kind text; v_kw numeric;
  v_before text; v_after text; v_probe jsonb; v_moved_to uuid; v_pair record;
BEGIN
  -- V1: the grants. anon reads the learning; the rescue and the grounding keep the ACL they had (CREATE OR REPLACE
  -- and the EXECUTE above keep owner and ACL; neither is opened to anon).
  IF NOT has_function_privilege('anon', 'public.ottoq_run_learning(uuid,integer,boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION '0613 V1: the learning read is not executable by anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p
              WHERE p.oid IN ('public.ottoq_promote_proposal_candidates(uuid,bigint,timestamp with time zone,integer)'::regprocedure,
                              'public.ottoq_agent_board_grounding(uuid,uuid,timestamp with time zone)'::regprocedure)
                AND (p.proacl::text IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
                     OR p.proowner <> 'postgres'::regrole)) THEN
    RAISE EXCEPTION '0613 V1: the rescue or the grounding changed owner or ACL';
  END IF;

  -- V2: nothing on the tick path calls the learning read; only the agent board's grounding does.
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname IN ('public', 'ottoq', 'twin')
                AND p.proname NOT IN ('ottoq_run_learning', 'ottoq_agent_board_grounding')
                AND regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') ~* 'ottoq_run_learning') THEN
    RAISE EXCEPTION '0613 V2: a routine other than the agent board''s grounding calls ottoq_run_learning';
  END IF;

  -- V3: on the newest twin-depot run, the read answers and its parts agree with each other.
  SELECT r.sim_run_id, r.tick_count, r.sim_clock_current INTO v_run, v_tick, v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.sim_clock_current IS NOT NULL
   ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NOT NULL THEN
    v_l := public.ottoq_run_learning(v_run, 20, true);
    IF (v_l ->> 'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION '0613 V3: the learning read failed on run %: %', v_run, v_l; END IF;
    IF ((v_l ->> 'live')::boolean IS NOT TRUE) <> (v_l -> 'lesson' ->> 'code' = 'run_ended') THEN
      RAISE EXCEPTION '0613 V3: live and the lesson disagree on run %: %', v_run, v_l -> 'lesson';
    END IF;
    IF NOT (v_l -> 'chargers' ? 'dcfc' AND v_l -> 'chargers' ? 'l2') THEN
      RAISE EXCEPTION '0613 V3: the twin depot''s chargers are not both counted: %', v_l -> 'chargers';
    END IF;
    IF (v_l ->> 'chargers_free')::int <> (v_l -> 'chargers' -> 'dcfc' ->> 'free')::int + (v_l -> 'chargers' -> 'l2' ->> 'free')::int
       OR (v_l -> 'chargers' -> 'dcfc' ->> 'free')::int > (v_l -> 'chargers' -> 'dcfc' ->> 'total')::int
       OR (v_l -> 'batch' ->> 'max_assets')::int NOT BETWEEN 1 AND 8
       OR jsonb_array_length(v_l -> 'batch' -> 'priority') > 24
       OR (v_l -> 'queue' ->> 'waiting_for_a_charger')::int > (v_l -> 'queue' ->> 'waiting')::int
       OR jsonb_array_length(v_l -> 'chargers_down') <> (v_l -> 'chargers' -> 'dcfc' ->> 'faulted')::int + (v_l -> 'chargers' -> 'l2' ->> 'faulted')::int THEN
      RAISE EXCEPTION '0613 V3: the learning read disagrees with itself on run %: %', v_run, v_l;
    END IF;
    -- the queue's positions run 1..n, and the priority is the queue's order less the cars holding a charger
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_l -> 'queue' -> 'head') WITH ORDINALITY e(x, i)
                WHERE (e.x ->> 'pos')::int <> e.i) THEN
      RAISE EXCEPTION '0613 V3: queue positions are not 1..n on run %', v_run;
    END IF;
    -- the brief form is what the grounding carries
    v_g := public.ottoq_agent_board_grounding(v_run, '11111111-1111-1111-1111-111111111111', v_clock);
    IF (v_g -> 'planner_learning' ->> 'ok')::boolean IS NOT TRUE OR NOT (v_g -> 'planner_learning' ? 'lesson')
       OR NOT (v_g ? 'actuators') OR NOT (v_g ? 'queue') THEN
      RAISE EXCEPTION '0613 V3: the grounding lost a key or does not carry planner_learning: %', v_g - 'actuators';
    END IF;

    -- V4: THE RESCUE, proven on the live schema and rolled back. A planner offer names charger A; A's charger faults;
    -- an equal charger B (same type and plug capacity, the car's inlet fits, no car, no reservation, no booking at the
    -- clock) is Available with a fresh heartbeat. The offer must move off A onto an equal free charger, marked
    -- adjacent_equivalent, and stay pending. Everything inside the block is undone by the probe's own exception.
    FOR v_pair IN
      SELECT a.id AS sa, b.id AS sb, a.ocpp_charger_id AS ca, b.ocpp_charger_id AS cb,
             a.stall_type::text AS kind, a.connector_max_kw AS kw
        FROM public.stalls a
        JOIN public.stalls b ON b.depot_id = a.depot_id AND b.stall_type = a.stall_type AND b.id <> a.id
                            AND b.connector_max_kw IS NOT DISTINCT FROM a.connector_max_kw
       WHERE a.depot_id = '11111111-1111-1111-1111-111111111111' AND a.stall_type::text IN ('dcfc', 'l2')
         AND a.ocpp_charger_id IS NOT NULL AND b.ocpp_charger_id IS NOT NULL
         AND b.current_vehicle_id IS NULL
         AND (b.reserved_by IS NULL OR b.reservation_expires_at <= v_clock)
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings bk
                          WHERE bk.sim_run_id = v_run AND bk.stall_id = b.id
                            AND bk.state IN ('held', 'active', 'done', 'interrupted') AND bk.during @> v_clock)
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_external_proposals o
                          WHERE o.sim_run_id = v_run AND o.status = 'pending' AND o.proposal ->> 'stall_id' = b.id::text)
       ORDER BY a.stall_code, b.stall_code
    LOOP
      SELECT v.id INTO v_veh
        FROM public.vehicles v
       WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
         AND v.inlet_type IS NOT NULL
         AND public.ottoq_inlet_fits_stall(v.inlet_type, v_pair.sa) AND public.ottoq_inlet_fits_stall(v.inlet_type, v_pair.sb)
       ORDER BY v.id LIMIT 1;
      IF v_veh IS NOT NULL THEN
        v_sa := v_pair.sa; v_sb := v_pair.sb; v_ca := v_pair.ca; v_cb := v_pair.cb; v_kind := v_pair.kind; v_kw := v_pair.kw;
        EXIT;
      END IF;
    END LOOP;
    IF v_veh IS NULL THEN
      RAISE EXCEPTION '0613 V4: no car and pair of equal chargers to probe the rescue with on run %', v_run;
    END IF;
    SELECT string_agg(c.charger_id::text || ':' || c.station_state || ':' || COALESCE(c.last_heartbeat_at::text, '-'), ',' ORDER BY c.charger_id)
      INTO v_before FROM public.ottoq_ocpp_chargers c WHERE c.charger_id IN (v_ca, v_cb);
    BEGIN
      UPDATE public.ottoq_ocpp_chargers SET station_state = 'Faulted' WHERE charger_id = v_ca;
      UPDATE public.ottoq_ocpp_chargers SET station_state = 'Available', last_heartbeat_at = v_clock WHERE charger_id = v_cb;
      INSERT INTO public.ottoq_external_proposals (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal,
                                                   source, status, tick_seq, expires_at)
      VALUES (v_run, '11111111-1111-1111-1111-111111111111', 'stall_assignment', 'vehicle', v_veh,
              jsonb_build_object('verb', 'assign_stall', 'abstain', false, 'stall_id', v_sa::text, 'stall_type', v_kind,
                                 'vehicle_id', v_veh::text, 'requested_kw', v_kw, 'probe', '0613 V4'),
              'forward_lex', 'pending', v_tick, now() + interval '1 hour');
      PERFORM public.ottoq_promote_proposal_candidates(v_run, v_tick, v_clock);
      SELECT jsonb_build_object('status', p.status, 'stall_id', p.proposal ->> 'stall_id',
                                'promoted_from', p.proposal ->> 'promoted_from',
                                'promotion_source', p.proposal ->> 'promotion_source',
                                'kind', s.stall_type::text, 'kw', s.connector_max_kw)
        INTO v_probe
        FROM public.ottoq_external_proposals p LEFT JOIN public.stalls s ON s.id::text = p.proposal ->> 'stall_id'
       WHERE p.sim_run_id = v_run AND p.entity_id = v_veh AND p.proposal ->> 'probe' = '0613 V4';
      RAISE EXCEPTION USING ERRCODE = 'OQ613', MESSAGE = COALESCE(v_probe::text, '{"status": "probe row not found"}');
    EXCEPTION WHEN SQLSTATE 'OQ613' THEN
      v_probe := SQLERRM::jsonb;
    END;
    v_moved_to := (v_probe ->> 'stall_id')::uuid;
    IF v_probe ->> 'status' <> 'pending' OR v_moved_to = v_sa OR v_probe ->> 'promoted_from' <> v_sa::text
       OR v_probe ->> 'promotion_source' IS DISTINCT FROM 'adjacent_equivalent'
       OR v_probe ->> 'kind' <> v_kind OR (v_probe ->> 'kw')::numeric IS DISTINCT FROM v_kw THEN
      RAISE EXCEPTION '0613 V4: the rescue did not move the offer onto an equal free charger: % (from %)', v_probe, v_sa;
    END IF;
    SELECT string_agg(c.charger_id::text || ':' || c.station_state || ':' || COALESCE(c.last_heartbeat_at::text, '-'), ',' ORDER BY c.charger_id)
      INTO v_after FROM public.ottoq_ocpp_chargers c WHERE c.charger_id IN (v_ca, v_cb);
    IF EXISTS (SELECT 1 FROM public.ottoq_external_proposals p WHERE p.proposal ->> 'probe' = '0613 V4')
       OR v_after IS DISTINCT FROM v_before THEN
      RAISE EXCEPTION '0613 V4: the probe left a trace';
    END IF;
    RAISE NOTICE '0613 V4 on run %: offer for % moved % -> % (%; %)', v_run, v_veh, v_sa, v_moved_to, v_kind, v_kw;
  END IF;

  -- V5: the measurement behind forces_recert FALSE. No certification or A/B arm has ever carried an offer the rescue
  -- (or the candidate walk) acts on, so neither can move under this file.
  IF EXISTS (SELECT 1 FROM public.ottoq_external_proposals p JOIN public.ottoq_sim_runs r ON r.sim_run_id = p.sim_run_id
              WHERE r.run_by IN ('cert_harness', 'ab_harness') AND p.action_context = 'stall_assignment'
                AND (p.source IN (SELECT pp.source FROM public.ottoq_proposer_precedence pp WHERE pp.holds_tick)
                     OR jsonb_typeof(p.proposal -> 'candidates') = 'array')) THEN
    RAISE EXCEPTION '0613 V5: a certification or A/B arm carries a planner or candidate offer; classify forces_recert TRUE';
  END IF;
END $verify$;

-- Rollback: DROP FUNCTION public.ottoq_run_learning(uuid, integer, boolean); EXECUTE the two '0613_pre' definitions
-- from public.ottoq_schema_snapshots; DELETE FROM public.ottoq_cert_lineage
-- WHERE name = '0613_the_planners_learn_inside_the_run_where_their_offers_went'.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0613_the_planners_learn_inside_the_run_where_their_offers_went', false, false,
  'ottoq_run_learning (read-only, anon, nothing on the tick path calls it); ottoq_promote_proposal_candidates gains the adjacent rescue for a holds_tick offer with no candidates, and its loop sorts on content instead of proposal_id; the agent grounding carries planner_learning. FALSE/FALSE measured (V5): no cert_harness or ab_harness run has ever carried a holds_tick or candidate offer, so the loop body never runs in an arm.',
  now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
