-- migration-version: PENDING
-- migration-name:    the_agent_can_order_the_charge_line_and_the_decide_path_disposes
--
-- 0614  **The agent can propose who charges next and on which kind of charger, and the decide path disposes.** Chase,
--       2026-10-07, on the agent layer: *"Yes let's definitely implement the advanced agent build. That's the exact layer
--       of depth that I want throughout the software layer ... always go with highest and best and most robust depth of
--       build for strengthening our intelligence and OTTO-Q layer."* One dial, `agent_charge_order`, default 0
--       everywhere: at 0 nothing on the tick path changes, key for key. `ottoq_agentic_arm` does not set it in this file;
--       arming it on operator demo runs is 0615, a separate and revertible decision.
--
-- ══ §1 WHY (run 81787ef9, busy_day, measured 2026-10-07 12:36 PM CT; FINDINGS G315; CLAUDE.md rules 9 and 10) ═════════
--
--   The agent had no lever that mattered. On the live run, 76 agent passes: 38 answered (26 others were HTTP 429 and 11
--   HTTP 503 from the hosted model, 1 a timeout; the edge function's retries are separate work). Every answered pass set
--   the planners' objective to readiness_first, as had 2,261 of 2,261 answered passes over the last 10 days, which is
--   also the fallback's goal; its 84 "applied directives" were status notes (energy, return wave, service backlog, 28
--   each); it wrote no dial. So the depot made the same decisions whether the model answered or not.
--
--   Meanwhile the decision that does decide a busy day is made by a fixed key. With all 35 working chargers in use and 13
--   to 21 cars waiting (every one past its contract's 30-minute queue limit, 29-88 minutes), the charge cursor seats the
--   highest response ratio first (0545/0551) and the stall pick takes a fast charger by battery alone (soc < 45, or an
--   immediate dispatch). 0604 measured what that costs on night 1: OTTO-Q's seat spent 43.5 of 84.0 fast-charger hours
--   (52%) on cars that started at 80% or more, where a fast charger delivers what an L2 does, while low cars waited on
--   L2. Rule 9 names the lever this file gives the agent: when cars wait for chargers, one answer is *"better ordering of
--   who is served next. Never shorter charges."*
--
-- ══ §2 WHAT THIS ADDS ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Dials, catalogued, not agent-writable: `agent_charge_order` (0|1, default 0), `agent_charge_order_ttl_ticks`
--       (3-60, default 15: how long an order stands without a new one), `agent_charge_order_pin_wait_min` (30-480 sim
--       minutes, default 90: three times every contract's queue limit).
--   (b) `public.ottoq_agent_charge_orders`, an evidence ledger (no FK to the run, append-only, class=evidence) holding
--       every order the agent sends and what the kernel accepted of it, car by car.
--   (c) `public.ottoq_agent_charge_order_record(run, board_tick, chain_id, model, order)`: the agent's only door. It
--       records nothing unless the dial is 1 on OTTO-Q's seat of a running run. A car is accepted when it is waiting for a
--       charger now (the cursor's own membership); a duplicate, an unknown id or a car not waiting is dropped with its
--       reason. A charger kind the car cannot plug into at this depot becomes `either`. Ranks are 1..n in the agent's
--       order, counting only accepted cars.
--   (d) The kernel's reads of it, all total functions: `..._live(run, tick)` (the latest accepted order younger than the
--       ttl, as {vehicle: {rank, kind, order_id}}, or '{}'), `..._mode(run, depot, clock)` (which charger kinds are free
--       now: dcfc | l2 | both | none, by the frame's own `offerable` test), `..._key(order, vehicle, mode)` (the car's
--       rank, plus 1000 when it was named for the other kind than the only kind free) and
--       `ottoq_charge_queue_kernel_order(run, depot, clock)` (the kernel's own order of the charge line, as 0613 mirrors
--       it, so a seat made under an order records where the kernel itself would have put the car).
--   (e) `ottoq_decide_tick`, OTTO-Q's seat, under a live order: the charge cursor's ORDER BY gains two keys after the
--       immediate-dispatch key. First, a car that has waited the pin or longer goes ahead, in the kernel's own order;
--       then the cars the agent ranked, in its order, the ones named for the kind of charger now free first; then every
--       other car in the kernel's own order. The order the seat was made under goes into the decision's context.
--   (f) `ottoq_l2_propose_stall_assignment`: a car the order names for `dcfc` or `l2` wants that kind. Immediate dispatch
--       keeps the fast charger the rule gives it. Every candidate gate still applies, and a car still takes the other
--       kind when it is the only free one, so no charger idles for the agent.
--   (g) `ottoq_depot_queue` (the cockpits' queue positions) and `ottoq_run_learning` (the planners' batch priority, and a
--       new `agent_order` block) order the line the same way, so the planners plan the cars the kernel will seat.
--   (h) `ottoq_agent_board` carries `charge_queue` under the dial: the line's head in the kernel's order with each car's
--       charge minutes on each kind, wait against its contract, other work and the kernel's rule for its kind; the
--       chargers free, down and freeing soon; the cars inbound; and what the agent's last order did.
--   (i) `ottoq_agent_charge_order_usage(run, limit)`: what the orders did, read-only: seats made under an order, by
--       rank, pinned, unranked, the seats where the agent put a car ahead of the kernel's own order, and the kinds it
--       named that the car then took.
--
-- ══ §3 WHAT CANNOT HAPPEN, BY CONSTRUCTION ════════════════════════════════════════════════════════════════════════════
--
--   - A charge is never shortened and a target never lowered (rule 9): the order moves who is next, nothing else.
--   - An immediate dispatch is never put behind the agent's order: its key stays first.
--   - No car starves: a car waiting the pin or longer is seated ahead of the order, in the kernel's own order.
--   - No charger idles: a car named for the other kind still takes a free charger when no car named for it waits.
--   - No proposer writes an assignment: the order is a ranking the cursor reads; the cursor, the shield, the calendar
--     and the emission gate still decide every seat (CLAUDE.md 2.5, "agents propose, solver disposes").
--   - An order the agent stops refreshing expires after the ttl, and the kernel's own order resumes.
--   - A failure reading the order is swallowed with a warning, and the tick seats cars in the kernel's own order.
--
-- ══ §4 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   A live run keeps the depot moving between statements, so no check compares two statements' reads of it: V4 runs
--   the cockpits' queue before and after in ONE statement, the pre-image copied to pg_temp. P0: nothing in flight. P1:
--   the five functions patched are the bodies measured on 2026-10-07 (md5 of their source), and nothing this file
--   creates exists. Every anchor matches exactly once. V1 (comment-stripped): each added key is gated on the order being
--   live, the order is read once per tick inside a handler, the 0613 mirror's fragments are all still present, and the
--   stall pick's override is gated on the context key. V2: the key's truth table. V3: the charge-minutes estimate is
--   positive and faster on a fast charger. V4: the twin depot's charge queue, as the cockpits read it, is the same
--   before and after this file at the dial's default. V5: with the dial at 0 the agent's door records nothing. V6, on a
--   running twin run (skipped without one), inside a block that rolls itself back: arm the dial on the run, record an
--   order that reverses the head of the line, and the cockpits' queue then shows the agent's order where no car is
--   pinned or immediate; the board carries the queue; usage reads it. Executed by tests/test_agent_charge_order_sql.py
--   against stubs as well.
--
-- ══ §5 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE, as 0548 and 0570 were. Every certification arm, sweep arm and
--   baseline seat runs the dial at its default, and ottoq_agentic_arm refuses a cert_harness run. At 0 the tick's added
--   work is the dial read on OTTO-Q's seat; both added cursor keys are NULL for every car; the stall pick sees no
--   context key; the board and the learning read carry nothing new.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0614_pre'; then
--   DROP FUNCTION public.ottoq_agent_charge_order_usage(uuid, integer); DROP FUNCTION public.ottoq_agent_charge_queue_board(uuid, uuid, timestamptz);
--   DROP FUNCTION public.ottoq_agent_charge_order_record(uuid, bigint, text, text, jsonb);
--   DROP FUNCTION public.ottoq_agent_charge_order_live(uuid, bigint); DROP FUNCTION public.ottoq_agent_charge_order_mode(uuid, uuid, timestamptz);
--   DROP FUNCTION public.ottoq_agent_charge_order_key(jsonb, uuid, text); DROP FUNCTION public.ottoq_charge_queue_kernel_order(uuid, uuid, timestamptz);
--   DROP FUNCTION public.ottoq_charge_kind_compatible(uuid, uuid, text); DROP FUNCTION public.ottoq_charge_minutes_estimate(numeric, numeric, numeric, numeric, numeric);
--   the ledger stays (evidence); DELETE its registry row only with it.
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key LIKE 'agent_charge_order%';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0614_the_agent_can_order_the_charge_line_and_the_decide_path_disposes'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0614 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies this file patches are the ones it was written against; nothing it creates exists ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_decide_tick(uuid)',                                   '1595b2f51574023543dc1c6ed5c76aea'),
      ('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)',        '9f7981089f4b7051a472fb6b39ef9dac'),
      ('public.ottoq_depot_queue(uuid,uuid)',                              'b1988a81261ce4ba3295099e526df1cf'),
      ('public.ottoq_run_learning(uuid,integer,boolean)',                  'eb2e2386f5e808998e85c31b0a9a9392'),
      ('public.ottoq_agent_board(uuid)',                                   '5a538b7f20362f5849a19842f644c37d')
    ) AS t(sig, want) LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = r.sig::regprocedure) IS DISTINCT FROM r.want THEN
      RAISE EXCEPTION '0614 P1: % is not the body measured (md5 %); read it again', r.sig, r.want;
    END IF;
  END LOOP;
  IF to_regclass('public.ottoq_agent_charge_orders') IS NOT NULL
     OR to_regprocedure('public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key LIKE 'agent_charge_order%')
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                 WHERE name = '0614_the_agent_can_order_the_charge_line_and_the_decide_path_disposes') THEN
    RAISE EXCEPTION '0614 P1: already applied';
  END IF;
END $premises$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0614_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_decide_tick(uuid)'::regprocedure,
                 'public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure,
                 'public.ottoq_depot_queue(uuid,uuid)'::regprocedure,
                 'public.ottoq_run_learning(uuid,integer,boolean)'::regprocedure,
                 'public.ottoq_agent_board(uuid)'::regprocedure);

-- V4's "before": the cockpits' queue as it is now, kept as a pg_temp copy so V4 compares old and new in one statement.
DO $v4pre$
BEGIN
  EXECUTE replace(pg_get_functiondef('public.ottoq_depot_queue(uuid,uuid)'::regprocedure),
                  'FUNCTION public.ottoq_depot_queue(', 'FUNCTION pg_temp.ottoq_depot_queue_0614_pre(');
END $v4pre$;

-- ══ (a) the dials ═════════════════════════════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, agent_writable, affects, description)
VALUES
 ('agent_charge_order', 0, 1, 0, false,
  'ottoq_decide_tick (charge cursor, seat 0); ottoq_l2_propose_stall_assignment; ottoq_depot_queue; ottoq_run_learning; ottoq_agent_board; ottoq_agent_charge_order_record',
  '0614: whether OTTO-Q''s seat takes the agent''s charge order. 0 (the default) = the kernel''s own order, as before. '
  '1 = under a live order (ottoq_agent_charge_orders, younger than agent_charge_order_ttl_ticks), the charge cursor seats '
  'immediate dispatches first, then cars waiting agent_charge_order_pin_wait_min or longer in the kernel''s order, then '
  'the cars the agent ranked (the ones named for the kind of charger now free first), then the rest in the kernel''s '
  'order; and a car named for dcfc or l2 prefers that kind. No charge is shortened and no charger idles. Set run-scoped '
  'by ottoq_agentic_arm (0615); never by the engine.'),
 ('agent_charge_order_ttl_ticks', 3, 60, 15, false,
  'ottoq_agent_charge_order_live',
  '0614: how many ticks an accepted agent charge order stands without a newer one. The agent fires every third tick and '
  'its advice lands a mean of 4.2 ticks late (CLAUDE.md 2.5), so 15 bridges one or two passes the hosted model refuses; '
  'after it the kernel''s own order resumes.'),
 ('agent_charge_order_pin_wait_min', 30, 480, 90, false,
  'ottoq_decide_tick (charge cursor, seat 0); ottoq_depot_queue; ottoq_run_learning',
  '0614: the fairness floor under an agent charge order, in sim minutes of a car''s whole wait for a charger '
  '(ottoq_charge_wait_min). A car that has waited this long goes ahead of the agent''s order, in the kernel''s own order, '
  'so no ranking can starve it. 90 = three times every contract''s 30-minute queue limit.');

-- ══ (b) the ledger ════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_agent_charge_orders (
  order_id      bigserial PRIMARY KEY,
  --: Durable historical keys. NO FOREIGN KEY to ottoq_sim_runs, deliberately (0340/0364): an evidence row must
  --: outlive ottoq_purge_prior_runs deleting the run it names.
  sim_run_id    uuid NOT NULL,
  depot_id      uuid,
  --: the tick the agent read its board at, and the run's tick when the kernel recorded the order
  board_tick    bigint,
  recorded_tick bigint NOT NULL,
  sim_clock     timestamptz,
  --: the agent pass's chain id (ottoq_decisions.proposed_action.agent_solver_chain_id): the pass and its order join here
  chain_id      text,
  model         text,
  status        text NOT NULL CHECK (status IN ('accepted', 'partial', 'rejected')),
  n_offered     integer NOT NULL,
  n_accepted    integer NOT NULL,
  --: [{vehicle_id, rank, kind, why, name, soc, wait_min, kernel_pos}] in rank order: what the kernel will read
  cars          jsonb NOT NULL,
  --: [{vehicle_id, reason}]: what it would not
  dropped       jsonb NOT NULL,
  why           text,
  recorded_at   timestamptz NOT NULL DEFAULT now(),
  source_kind   text NOT NULL DEFAULT 'live'
);

COMMENT ON TABLE public.ottoq_agent_charge_orders IS
'0614. One row per charge order the agent sent through ottoq_agent_charge_order_record: the cars it ranked for the next free chargers, the kind of charger it named for each, and what the kernel accepted. The charge cursor reads the latest accepted row younger than agent_charge_order_ttl_ticks (ottoq_agent_charge_order_live); a seat made under it carries {order_id, rank, kind, mode, pinned, wait_min, kernel_pos} in its decision''s context_frame, which is how ottoq_agent_charge_order_usage counts what the orders did. Class=evidence with NO foreign key to ottoq_sim_runs (0340/0364): what the agent asked and what the kernel did with it must outlive the purge. Append-only (override: ottoq.agent_charge_orders_unlock=on).';

CREATE INDEX ottoq_agent_charge_orders_live_idx
  ON public.ottoq_agent_charge_orders (sim_run_id, order_id DESC) WHERE status IN ('accepted', 'partial');
CREATE INDEX ottoq_agent_charge_orders_chain_idx
  ON public.ottoq_agent_charge_orders (sim_run_id, chain_id);

CREATE OR REPLACE FUNCTION public.ottoq_agent_charge_orders_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.agent_charge_orders_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION
    'ottoq_agent_charge_orders is append-only: % refused. Set ottoq.agent_charge_orders_unlock=on in the session to '
    'override, and say why in a migration.', TG_OP
    USING ERRCODE = '42501';
END $fn$;

CREATE TRIGGER ottoq_agent_charge_orders_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_agent_charge_orders
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_agent_charge_orders_append_only();

--: Read by the cockpits and the twin like the other ledgers; written only through the SECURITY DEFINER door below.
ALTER TABLE public.ottoq_agent_charge_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_agent_charge_orders_read ON public.ottoq_agent_charge_orders FOR SELECT USING (true);
REVOKE ALL ON public.ottoq_agent_charge_orders FROM anon, authenticated;
GRANT SELECT ON public.ottoq_agent_charge_orders TO anon, authenticated;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_agent_charge_orders', 'sim_run_id', 'evidence',
        '0614: every charge order the agent sent and what the kernel accepted, car by car. Evidence, not engine: what '
        'the agent asked and what the kernel did with it are the only record of whether the agent layer earns its place '
        '(CLAUDE.md rule 6''s both-directions rule, applied to the agent). NO foreign key to ottoq_sim_runs, as 0340 '
        'and 0364: check (b) asks for one from engine/stamp only.');

-- ══ (c) the charge-minutes estimate and the plug test ═════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_minutes_estimate(p_batt_kwh numeric, p_soc_from numeric, p_soc_to numeric,
                                                     p_charger_kw numeric, p_inlet_kw numeric)
RETURNS numeric
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0614: minutes to charge from p_soc_from to p_soc_to, for ORDERING and for the agent's board only. The power model is
  -- the stall pick's own (ottoq_l2_propose_stall_assignment's eff_kw): LEAST(charger kW, inlet kW), whole on a charger
  -- of 50 kW or less, and on a faster one 0.85 below 55%, 0.55 below 75%, 0.30 above, integrated across those bands.
  -- 0 when nothing is owed; NULL when the battery size is unknown.
  SELECT CASE
           WHEN p_batt_kwh IS NULL OR p_batt_kwh <= 0 THEN NULL
           WHEN p_soc_from IS NULL OR p_soc_to IS NULL OR p_soc_to <= p_soc_from THEN 0
           ELSE round(60 * COALESCE((
             SELECT sum((p_batt_kwh * (LEAST(p_soc_to, b.hi) - GREATEST(p_soc_from, b.lo)) / 100.0)
                        / NULLIF(LEAST(COALESCE(p_charger_kw, 50), COALESCE(p_inlet_kw, 250))
                                 * CASE WHEN COALESCE(p_charger_kw, 50) <= 50 THEN 1.0 ELSE b.f END, 0))
               FROM (VALUES (0::numeric, 55::numeric, 0.85::numeric), (55, 75, 0.55), (75, 101, 0.30)) b(lo, hi, f)
              WHERE LEAST(p_soc_to, b.hi) > GREATEST(p_soc_from, b.lo)), 0), 0)
         END
$fn$;

CREATE FUNCTION public.ottoq_charge_kind_compatible(p_vehicle_id uuid, p_depot_id uuid, p_kind text)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
  -- 0614: does this depot have a charger of p_kind this car can plug into at all (not whether one is free)? The plug
  -- predicate is the stall pick's own (ottoq_l2_propose_stall_assignment).
  SELECT EXISTS (
    SELECT 1 FROM vehicles v JOIN stalls s ON s.depot_id = p_depot_id AND s.stall_type::text = p_kind
     WHERE v.id = p_vehicle_id
       AND (v.inlet_type IS NULL OR s.connector_type = v.inlet_type
            OR (s.connector_type = 'Multi' AND v.inlet_type = ANY(COALESCE(s.supported_inlet_types, ARRAY[]::text[])))
            OR (s.connector_type = 'NACS'  AND v.inlet_type IN ('NACS','Tesla_Proprietary'))))
$fn$;

-- ══ (d) the kernel's own order, and the reads of the agent's ═══════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_queue_kernel_order(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz)
RETURNS TABLE(vehicle_id uuid, kernel_pos integer, wait_min numeric, gap numeric, immediate boolean, soc numeric,
              visit_target numeric, holds_charger boolean)
LANGUAGE sql STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
  -- 0614: the charge line in the order OTTO-Q's seat of ottoq_decide_tick serves it, as 0613's ottoq_run_learning
  -- mirrors it: the cursor's membership and keys (immediate dispatch, then the response ratio of 0545/0551, then
  -- battery, then id), less the one-tick first-refusal hold, the free-charger test on a staged car and the
  -- charging-staff limit, which hold a car back from a tick without moving its place.
  WITH q AS (
    SELECT v.id, v.current_soc,
           COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
                      WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                        AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                          = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                      ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), public.ottoq_default_target_soc()) AS visit_target,
           COALESCE((SELECT vn.urgency = 'immediate_dispatch' FROM ottoq_visit_needs vn
                      WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                        AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                          = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                      ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), false) AS immediate,
           public.ottoq_charge_wait_min(v.config, v.last_state_change, p_clock, p_sim_run_id) AS wait_min,
           GREATEST(public.ottoq_effective_target_soc_at(v.id, p_clock) - v.current_soc, 1) AS gap,
           EXISTS (SELECT 1 FROM stalls s2
                    WHERE s2.reserved_by = v.id AND s2.reservation_expires_at > p_clock
                      AND s2.stall_type::text IN ('dcfc','l2')) AS holds_charger
      FROM vehicles v
     WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
       AND NOT public.ottoq_vehicle_fault_open(v.config)
       AND v.current_state::text IN ('arrived_at_gate','staged_awaiting_service'))
  SELECT q.id, (row_number() OVER (ORDER BY q.immediate DESC, (q.wait_min + q.gap) / q.gap DESC NULLS LAST,
                                            q.current_soc ASC, q.id))::int,
         q.wait_min, q.gap, q.immediate, q.current_soc, q.visit_target, q.holds_charger
    FROM q
   WHERE q.current_soc < q.visit_target - 1
$fn$;

CREATE FUNCTION public.ottoq_agent_charge_order_live(p_sim_run_id uuid, p_tick bigint)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
  -- 0614: the agent's latest accepted charge order on this run that is no older than agent_charge_order_ttl_ticks at
  -- tick p_tick (and not recorded after it), as {vehicle_id: {rank, kind, order_id}}; '{}' when there is none.
  SELECT COALESCE((
    SELECT jsonb_object_agg(c ->> 'vehicle_id',
                            jsonb_build_object('rank', c -> 'rank', 'kind', c ->> 'kind', 'order_id', o.order_id))
      FROM (SELECT x.order_id, x.cars FROM ottoq_agent_charge_orders x
             WHERE x.sim_run_id = p_sim_run_id AND x.status IN ('accepted', 'partial')
               AND x.recorded_tick <= p_tick
               AND x.recorded_tick >= p_tick
                   - GREATEST(1, COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_ttl_ticks', 15), 15))::bigint
             ORDER BY x.order_id DESC LIMIT 1) o
      CROSS JOIN LATERAL jsonb_array_elements(o.cars) c
     WHERE c ->> 'vehicle_id' IS NOT NULL), '{}'::jsonb)
$fn$;

CREATE FUNCTION public.ottoq_agent_charge_order_mode(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz)
RETURNS text
LANGUAGE sql STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
  -- 0614: which kinds of charger are free right now, by the decision frame's own `offerable` test (0265/0498, as
  -- 0613's ottoq_run_learning counts them): no car on it, no live reservation, the OCPP charger Available with a
  -- heartbeat inside 90 s of the clock, and no booking of the run covering the clock. dcfc | l2 | both | none.
  WITH f AS (
    SELECT st.stall_type::text AS kind
      FROM stalls st JOIN ottoq_ocpp_chargers c ON c.charger_id = st.ocpp_charger_id
     WHERE st.depot_id = p_depot_id AND st.stall_type::text IN ('dcfc','l2')
       AND st.current_vehicle_id IS NULL
       AND NOT (st.reserved_by IS NOT NULL AND COALESCE(st.reservation_expires_at, 'infinity'::timestamptz) > p_clock)
       AND c.station_state = 'Available' AND c.last_heartbeat_at >= p_clock - interval '90 seconds'
       AND NOT EXISTS (SELECT 1 FROM ottoq_stall_bookings b
                        WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = st.id
                          AND b.state IN ('held','active','done','interrupted') AND b.during @> p_clock))
  SELECT CASE WHEN bool_or(f.kind = 'dcfc') AND bool_or(f.kind = 'l2') THEN 'both'
              WHEN bool_or(f.kind = 'dcfc') THEN 'dcfc'
              WHEN bool_or(f.kind = 'l2') THEN 'l2'
              ELSE 'none' END
    FROM f
$fn$;

CREATE FUNCTION public.ottoq_agent_charge_order_key(p_order jsonb, p_vehicle_id uuid, p_mode text)
RETURNS integer
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0614: the car's place in the agent's charge order, for the cursor's ORDER BY: its rank, plus 1000 when the order
  -- named it for the other kind than the only kind of charger free now (so a free fast charger goes first to the cars
  -- named for one, and still to a car named for an L2 when none of those waits). NULL when the order does not name the
  -- car. Total: a rank that is not a whole number reads as 999.
  SELECT CASE
           WHEN p_order IS NULL OR p_vehicle_id IS NULL OR NOT (p_order ? p_vehicle_id::text) THEN NULL
           ELSE CASE WHEN (p_order -> p_vehicle_id::text ->> 'rank') ~ '^[0-9]{1,6}$'
                     THEN (p_order -> p_vehicle_id::text ->> 'rank')::int ELSE 999 END
                + CASE WHEN p_mode = 'dcfc' AND p_order -> p_vehicle_id::text ->> 'kind' = 'l2'   THEN 1000
                       WHEN p_mode = 'l2'   AND p_order -> p_vehicle_id::text ->> 'kind' = 'dcfc' THEN 1000
                       ELSE 0 END
         END
$fn$;

-- ══ (c, again) the agent's door ═══════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_agent_charge_order_record(p_sim_run_id uuid, p_board_tick bigint, p_chain_id text,
                                                       p_model text, p_order jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_run record; v_q jsonb := '{}'::jsonb; v_cars jsonb := '[]'::jsonb; v_dropped jsonb := '[]'::jsonb;
  v_seen text[] := ARRAY[]::text[]; v_rank int := 0; v_n int := 0; e jsonb; v_id uuid; v_kind text; v_info jsonb;
  v_status text; v_order_id bigint; v_why text;
BEGIN
  SELECT r.sim_run_id, r.depot_id, r.tick_count, r.sim_clock_current, r.status INTO v_run
    FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF v_run.sim_run_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'run_not_found'); END IF;
  IF v_run.status IS DISTINCT FROM 'running' THEN
    RETURN jsonb_build_object('ok', false, 'skipped', 'run_not_running');
  END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order', 0), 0) < 1 THEN
    RETURN jsonb_build_object('ok', false, 'skipped', 'agent_charge_order is 0 for this run');
  END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'proposer_seat', 0), 0) <> 0 THEN
    RETURN jsonb_build_object('ok', false, 'skipped', 'a baseline seat owns this run');
  END IF;

  -- the line as the kernel holds it now: an order is accepted only for cars in it
  SELECT COALESCE(jsonb_object_agg(k.vehicle_id::text, jsonb_build_object(
           'kernel_pos', k.kernel_pos, 'wait_min', round(k.wait_min, 1), 'soc', round(k.soc, 1),
           'name', COALESCE(v.display_name, k.vehicle_id::text))), '{}'::jsonb)
    INTO v_q
    FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current) k
    JOIN vehicles v ON v.id = k.vehicle_id;

  v_why := left(btrim(COALESCE(p_order ->> 'why', '')), 400);
  IF jsonb_typeof(p_order -> 'cars') IS DISTINCT FROM 'array' THEN
    v_dropped := jsonb_build_array(jsonb_build_object('reason', 'no cars array'));
  ELSE
    FOR e IN SELECT x.value FROM jsonb_array_elements(p_order -> 'cars') WITH ORDINALITY x(value, i) ORDER BY x.i LIMIT 40
    LOOP
      v_n := v_n + 1;
      v_id := NULL;
      IF jsonb_typeof(e) = 'object' AND (e ->> 'vehicle_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        v_id := (e ->> 'vehicle_id')::uuid;
      END IF;
      IF v_id IS NULL THEN
        v_dropped := v_dropped || jsonb_build_object('vehicle_id', left(COALESCE(e ->> 'vehicle_id', e::text), 60), 'reason', 'not_a_vehicle_id');
        CONTINUE;
      END IF;
      IF v_id::text = ANY (v_seen) THEN
        v_dropped := v_dropped || jsonb_build_object('vehicle_id', v_id, 'reason', 'duplicate');
        CONTINUE;
      END IF;
      v_seen := v_seen || v_id::text;
      v_info := v_q -> v_id::text;
      IF v_info IS NULL THEN
        v_dropped := v_dropped || jsonb_build_object('vehicle_id', v_id, 'reason', 'not_waiting_for_a_charger');
        CONTINUE;
      END IF;
      v_kind := lower(COALESCE(e ->> 'kind', 'either'));
      IF v_kind NOT IN ('dcfc', 'l2', 'either') THEN v_kind := 'either'; END IF;
      -- a kind the car cannot plug into here is the kernel's to pick, not a reason to drop the car
      IF v_kind <> 'either' AND NOT public.ottoq_charge_kind_compatible(v_id, v_run.depot_id, v_kind) THEN
        v_kind := 'either';
      END IF;
      v_rank := v_rank + 1;
      v_cars := v_cars || jsonb_build_object(
        'vehicle_id', v_id, 'rank', v_rank, 'kind', v_kind, 'why', left(btrim(COALESCE(e ->> 'why', '')), 200),
        'name', v_info -> 'name', 'soc', v_info -> 'soc', 'wait_min', v_info -> 'wait_min',
        'kernel_pos', v_info -> 'kernel_pos');
    END LOOP;
  END IF;

  v_status := CASE WHEN v_rank = 0 THEN 'rejected' WHEN v_rank < v_n THEN 'partial' ELSE 'accepted' END;
  INSERT INTO ottoq_agent_charge_orders
    (sim_run_id, depot_id, board_tick, recorded_tick, sim_clock, chain_id, model, status, n_offered, n_accepted,
     cars, dropped, why)
  VALUES (p_sim_run_id, v_run.depot_id, p_board_tick, COALESCE(v_run.tick_count, 0), v_run.sim_clock_current,
          left(p_chain_id, 80), left(p_model, 120), v_status, v_n, v_rank, v_cars, v_dropped, NULLIF(v_why, ''))
  RETURNING order_id INTO v_order_id;

  RETURN jsonb_build_object(
    'ok', true, 'order_id', v_order_id, 'status', v_status, 'offered', v_n, 'accepted', v_rank,
    'dropped', v_dropped, 'queue', (SELECT count(*) FROM jsonb_object_keys(v_q)),
    'recorded_tick', COALESCE(v_run.tick_count, 0),
    'ttl_ticks', COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_ttl_ticks', 15), 15),
    'pin_wait_min', COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_pin_wait_min', 90), 90));
EXCEPTION WHEN OTHERS THEN
  -- the agent's pass reads this receipt; a fault here must say so and never take the pass down
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_agent_charge_order_record(uuid, bigint, text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_agent_charge_order_record(uuid, bigint, text, text, jsonb) TO service_role;

-- ══ (i) what the orders did ═══════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_agent_charge_order_usage(p_sim_run_id uuid, p_limit integer DEFAULT 20)
RETURNS jsonb
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
  -- 0614: what the agent's charge orders did on one run, read-only. A seat is a stall_assignment the decide path
  -- enacted while an order was live (its context_frame carries agent_charge_order). by_rank = the agent's order seated
  -- it (not pinned); pinned = the fairness floor seated it ahead of the order; unranked = the order did not name it;
  -- moved_ahead = seated by rank while the kernel's own order had it behind as many cars as were seated that tick;
  -- kind_followed = it took the kind the order named.
  WITH o AS (
    SELECT x.order_id, x.chain_id, x.recorded_tick, x.status, x.n_offered, x.n_accepted
      FROM ottoq_agent_charge_orders x WHERE x.sim_run_id = p_sim_run_id
  ), s AS (
    SELECT d.tick_seq,
           CASE WHEN (d.context_frame -> 'agent_charge_order' ->> 'order_id') ~ '^[0-9]+$'
                THEN (d.context_frame -> 'agent_charge_order' ->> 'order_id')::bigint END AS order_id,
           COALESCE((d.context_frame -> 'agent_charge_order' ->> 'pinned')::boolean, false) AS pinned,
           d.context_frame -> 'agent_charge_order' ->> 'kind' AS kind,
           (d.context_frame -> 'agent_charge_order' ->> 'rank') AS rank,
           CASE WHEN (d.context_frame -> 'agent_charge_order' ->> 'kernel_pos') ~ '^[0-9]+$'
                THEN (d.context_frame -> 'agent_charge_order' ->> 'kernel_pos')::int END AS kernel_pos,
           COALESCE(d.enacted_action ->> 'stall_type', d.proposed_action ->> 'stall_type') AS took,
           count(*) OVER (PARTITION BY d.tick_seq) AS seats_in_tick
      FROM ottoq_decisions d
     WHERE d.sim_run_id = p_sim_run_id AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
       AND d.context_frame ? 'agent_charge_order'
  ), t AS (
    SELECT s.*, (NOT s.pinned AND s.rank IS NOT NULL) AS by_rank FROM s
  )
  SELECT jsonb_build_object(
    'orders', (SELECT count(*) FROM o),
    'orders_accepted', (SELECT count(*) FROM o WHERE o.status IN ('accepted', 'partial')),
    'cars_ranked', (SELECT COALESCE(sum(o.n_accepted), 0) FROM o),
    'seats_under_order', (SELECT count(*) FROM t),
    'seats_by_rank', (SELECT count(*) FROM t WHERE t.by_rank),
    'seats_pinned', (SELECT count(*) FROM t WHERE t.pinned),
    'seats_unranked', (SELECT count(*) FROM t WHERE NOT t.pinned AND t.rank IS NULL),
    'moved_ahead', (SELECT count(*) FROM t WHERE t.by_rank AND t.kernel_pos > t.seats_in_tick),
    'kind_named', (SELECT count(*) FROM t WHERE t.kind IN ('dcfc', 'l2')),
    'kind_followed', (SELECT count(*) FROM t WHERE t.kind IN ('dcfc', 'l2') AND t.took = t.kind),
    'by_order', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'order_id', o.order_id, 'chain_id', o.chain_id, 'recorded_tick', o.recorded_tick, 'status', o.status,
               'offered', o.n_offered, 'accepted', o.n_accepted,
               'seats', (SELECT count(*) FROM t WHERE t.order_id = o.order_id),
               'seats_by_rank', (SELECT count(*) FROM t WHERE t.order_id = o.order_id AND t.by_rank),
               'moved_ahead', (SELECT count(*) FROM t WHERE t.order_id = o.order_id AND t.by_rank
                                                       AND t.kernel_pos > t.seats_in_tick))
             ORDER BY o.order_id DESC)
        FROM (SELECT * FROM o ORDER BY o.order_id DESC LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 200))) o), '[]'::jsonb))
$fn$;

GRANT EXECUTE ON FUNCTION public.ottoq_agent_charge_order_usage(uuid, integer) TO anon, authenticated, service_role;

-- ══ (h) the agent's view of the line ══════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_agent_charge_queue_board(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz)
RETURNS jsonb
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
  -- 0614: the charge line as the agent needs it to order it, read-only. The head 24 cars in the kernel's own order,
  -- each with what it owes (to rule 9's one target, ottoq_effective_target_soc_at), the minutes that charge takes on
  -- each kind of charger here (ottoq_charge_minutes_estimate on the depot's fastest charger of the kind), its whole wait
  -- against its contract's queue limit, its other open work, the kernel's own rule for its kind, and whether it can
  -- plug into each kind at all. Then the chargers: free and down by kind, and the in-use ones that free soonest.
  WITH k AS (
    SELECT * FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, p_depot_id, p_clock) WHERE kernel_pos <= 24
  ), kw AS (
    SELECT max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'dcfc') AS dcfc_kw,
           max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'l2')   AS l2_kw
      FROM stalls s WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc','l2')
  ), cars AS (
    SELECT k.kernel_pos, jsonb_build_object(
             'vehicle_id', v.id, 'name', COALESCE(v.display_name, v.id::text),
             'operator', fo.name,
             'soc', round(k.soc, 1),
             'target', round(public.ottoq_effective_target_soc_at(v.id, p_clock), 0),
             'kwh_owed', round(COALESCE(v.battery_capacity_kwh, 0)
                               * GREATEST(public.ottoq_effective_target_soc_at(v.id, p_clock) - k.soc, 0) / 100.0, 1),
             'min_on_dcfc', public.ottoq_charge_minutes_estimate(v.battery_capacity_kwh, k.soc,
                              public.ottoq_effective_target_soc_at(v.id, p_clock), (SELECT dcfc_kw FROM kw), v.inlet_max_kw),
             'min_on_l2', public.ottoq_charge_minutes_estimate(v.battery_capacity_kwh, k.soc,
                              public.ottoq_effective_target_soc_at(v.id, p_clock), (SELECT l2_kw FROM kw), v.inlet_max_kw),
             'wait_min', round(k.wait_min, 0),
             'contract_wait_limit_min', sla.max_queue_wait_minutes,
             'over_limit_min', CASE WHEN sla.max_queue_wait_minutes IS NOT NULL
                                    THEN GREATEST(round(k.wait_min - sla.max_queue_wait_minutes, 0), 0) END,
             'urgency', vn.urgency,
             'due_in_min', CASE WHEN vn.dispatch_due_at IS NOT NULL
                                THEN round(extract(epoch FROM (vn.dispatch_due_at - p_clock)) / 60.0, 0) END,
             'other_work', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                       'svc', a ->> 'svc', 'min', a -> 'est_min',
                                       'where', CASE WHEN a ->> 'concurrency' = 'bay' THEN 'bay' ELSE 'in_place' END)
                                       ORDER BY a ->> 'svc')
                                       FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
                                      WHERE a ->> 'svc' NOT IN ('charge', 'readiness_check')
                                        AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled')), '[]'::jsonb),
             'rule_kind', CASE WHEN k.soc < 45 OR k.immediate THEN 'dcfc' ELSE 'l2' END,
             'dcfc_ok', public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'dcfc'),
             'l2_ok', public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2'),
             'holds_charger', k.holds_charger,
             'kernel_pos', k.kernel_pos) AS j
      FROM k JOIN vehicles v ON v.id = k.vehicle_id
      LEFT JOIN fleet_operators fo ON fo.id = v.fleet_operator_id
      LEFT JOIN LATERAL (SELECT s.max_queue_wait_minutes FROM ottoq_fleet_operator_slas s
                          WHERE s.fleet_operator_id = v.fleet_operator_id AND s.status = 'active'
                            AND s.effective_from <= p_clock AND (s.effective_until IS NULL OR s.effective_until > p_clock)
                          ORDER BY s.version DESC LIMIT 1) sla ON true
      LEFT JOIN LATERAL (SELECT vn.urgency, vn.dispatch_due_at, vn.atoms FROM ottoq_visit_needs vn
                          WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                            AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                              = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                          ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) vn ON true
  ), st AS (
    SELECT s.id, s.stall_type::text AS kind, COALESCE(s.display_name, s.stall_code) AS name, s.connector_max_kw,
           s.current_vehicle_id,
           COALESCE(c.station_state = 'Faulted', false) AS faulted,
           (s.current_vehicle_id IS NULL
            AND NOT (s.reserved_by IS NOT NULL AND COALESCE(s.reservation_expires_at, 'infinity'::timestamptz) > p_clock)
            AND c.station_state = 'Available' AND c.last_heartbeat_at >= p_clock - interval '90 seconds'
            AND NOT EXISTS (SELECT 1 FROM ottoq_stall_bookings b
                             WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
                               AND b.state IN ('held','active','done','interrupted') AND b.during @> p_clock)) AS free
      FROM stalls s LEFT JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc','l2')
  ), soon AS (
    SELECT st.kind, st.name, COALESCE(v.display_name, v.id::text) AS car,
           public.ottoq_charge_minutes_estimate(v.battery_capacity_kwh, v.current_soc,
             public.ottoq_effective_target_soc_at(v.id, p_clock), st.connector_max_kw, v.inlet_max_kw) AS in_min
      FROM st JOIN vehicles v ON v.id = st.current_vehicle_id
     WHERE v.current_state::text IN ('charging_dcfc', 'charging_l2')
  )
  SELECT jsonb_build_object(
    'pin_wait_min', COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_pin_wait_min', 90), 90),
    'ttl_ticks', COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_ttl_ticks', 15), 15),
    'chargers', jsonb_build_object(
      'free', jsonb_build_object('dcfc', (SELECT count(*) FROM st WHERE st.kind = 'dcfc' AND st.free),
                                 'l2',   (SELECT count(*) FROM st WHERE st.kind = 'l2' AND st.free)),
      'down', jsonb_build_object('dcfc', (SELECT count(*) FROM st WHERE st.kind = 'dcfc' AND st.faulted),
                                 'l2',   (SELECT count(*) FROM st WHERE st.kind = 'l2' AND st.faulted)),
      'total', jsonb_build_object('dcfc', (SELECT count(*) FROM st WHERE st.kind = 'dcfc'),
                                  'l2',   (SELECT count(*) FROM st WHERE st.kind = 'l2')),
      'kw', jsonb_build_object('dcfc', (SELECT dcfc_kw FROM kw), 'l2', (SELECT l2_kw FROM kw)),
      'freeing_soonest', COALESCE((SELECT jsonb_agg(jsonb_build_object('kind', x.kind, 'stall', x.name, 'car', x.car,
                                                                       'in_min', x.in_min) ORDER BY x.in_min, x.name)
                                     FROM (SELECT * FROM soon ORDER BY soon.in_min NULLS LAST, soon.name LIMIT 8) x),
                                  '[]'::jsonb)),
    'waiting', (SELECT count(*) FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, p_depot_id, p_clock)),
    'cars', COALESCE((SELECT jsonb_agg(cars.j ORDER BY cars.kernel_pos) FROM cars), '[]'::jsonb),
    'last_order', (
      SELECT jsonb_build_object('order_id', x.order_id, 'status', x.status, 'offered', x.n_offered,
                                'accepted', x.n_accepted, 'dropped', x.dropped,
                                'age_ticks', COALESCE((SELECT r.tick_count FROM ottoq_sim_runs r
                                                        WHERE r.sim_run_id = p_sim_run_id), x.recorded_tick) - x.recorded_tick)
        FROM ottoq_agent_charge_orders x WHERE x.sim_run_id = p_sim_run_id
       ORDER BY x.order_id DESC LIMIT 1),
    'usage', public.ottoq_agent_charge_order_usage(p_sim_run_id, 3))
$fn$;

-- ══ (e) the charge cursor, OTTO-Q's seat ══════════════════════════════════════════════════════════════════════════════
DO $tick$
DECLARE v_def text; n int; c_old text; c_new text;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);

  -- 1. the order's variables
  c_old := $old1$  v_seat int; /* 0261 */
$old1$;
  c_new := $new1$  v_seat int; /* 0261 */
  v_ao_order jsonb := '{}'::jsonb; v_ao_on boolean := false; v_ao_pin numeric := 90; v_ao_mode text := 'none';  /* 0614 */
  v_ao_kpos jsonb := '{}'::jsonb; v_ao_order_id bigint; v_ao_wait numeric;                                       /* 0614 */
$new1$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0614 tick (1): the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_def, c_old, c_new);

  -- 2. read the order once, before the cursor; the cursor carries what the seat's context needs
  c_old := $old2$  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       -- P2 RIGHT OF FIRST REFUSAL (2026-08-02). Hold this vehicle out of the local
$old2$;
  c_new := $new2$  /* 0614: THE AGENT'S CHARGE ORDER, READ ONCE PER TICK. OTTO-Q's seat only, and only when this run's
     agent_charge_order dial is 1 and the agent's latest accepted order is younger than its ttl. Without one every
     variable keeps its default and the cursor's ORDER BY below is the one before 0614, key for key. A failure here is
     swallowed: the tick seats cars in the kernel's own order. */
  IF v_seat = 0 THEN
    BEGIN
      IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order', 0), 0) >= 1 THEN
        v_ao_order := COALESCE(public.ottoq_agent_charge_order_live(p_sim_run_id, v_tick), '{}'::jsonb);
        v_ao_on := (v_ao_order <> '{}'::jsonb);
        IF v_ao_on THEN
          v_ao_pin := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_pin_wait_min', 90), 90);
          v_ao_mode := COALESCE(public.ottoq_agent_charge_order_mode(p_sim_run_id, v_depot, v_clock), 'none');
          SELECT max((e.value ->> 'order_id')::bigint) INTO v_ao_order_id FROM jsonb_each(v_ao_order) e;
          SELECT COALESCE(jsonb_object_agg(k.vehicle_id::text, k.kernel_pos), '{}'::jsonb) INTO v_ao_kpos
            FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, v_depot, v_clock) k;
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0614 agent charge order read: % %', SQLSTATE, SQLERRM;
      v_ao_order := '{}'::jsonb; v_ao_on := false; v_ao_mode := 'none'; v_ao_kpos := '{}'::jsonb; v_ao_order_id := NULL;
    END;
  END IF;

  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id, v.config AS ao_config, v.last_state_change AS ao_lsc
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       -- P2 RIGHT OF FIRST REFUSAL (2026-08-02). Hold this vehicle out of the local
$new2$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0614 tick (2): the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_def, c_old, c_new);

  -- 3. the two keys, after the immediate-dispatch key
  c_old := $old3$                 ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), false) DESC,
              /* 0546 (G271): a car with no open visit is not an immediate dispatch.$old3$;
  c_new := $new3$                 ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), false) DESC,
              /* 0614: under a live agent charge order, a car that has waited the pin or longer goes first, in the
                 kernel's own order (the keys below); then the cars the agent ranked, in its order, the ones named for
                 the kind of charger free now first; then every other car, in the kernel's own order. Both keys are
                 NULL for every car without a live order, so they sort nothing. */
              CASE WHEN v_ao_on THEN public.ottoq_charge_wait_min(v.config, v.last_state_change, v_clock, p_sim_run_id) >= v_ao_pin END DESC NULLS LAST,
              CASE WHEN v_ao_on AND public.ottoq_charge_wait_min(v.config, v.last_state_change, v_clock, p_sim_run_id) < v_ao_pin
                   THEN public.ottoq_agent_charge_order_key(v_ao_order, v.id, v_ao_mode) END ASC NULLS LAST,
              /* 0546 (G271): a car with no open visit is not an immediate dispatch.$new3$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0614 tick (3): the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_def, c_old, c_new);

  -- 4. the seat records the order it was made under, and the stall pick reads the kind
  c_old := $old4$    v_ctx := ottoq_build_decision_context('stall_assignment','vehicle',v_req.vehicle_id,v_depot,v_clock);
    v_proposal := ottoq_honour_reservation_proposal(p_sim_run_id, v_req.vehicle_id, v_depot, v_ctx);
$old4$;
  c_new := $new4$    v_ctx := ottoq_build_decision_context('stall_assignment','vehicle',v_req.vehicle_id,v_depot,v_clock);
    IF v_ao_on THEN  /* 0614: the order this seat is made under, for the stall pick and for the record */
      v_ao_wait := public.ottoq_charge_wait_min(v_req.ao_config, v_req.ao_lsc, v_clock, p_sim_run_id);
      v_ctx := v_ctx || jsonb_build_object('agent_charge_order', jsonb_build_object(
                 'order_id', v_ao_order_id,
                 'rank', v_ao_order -> v_req.vehicle_id::text -> 'rank',
                 'kind', v_ao_order -> v_req.vehicle_id::text ->> 'kind',
                 'mode', v_ao_mode,
                 'pinned', COALESCE(v_ao_wait >= v_ao_pin, false),
                 'wait_min', round(v_ao_wait, 1),
                 'kernel_pos', v_ao_kpos -> v_req.vehicle_id::text));
    END IF;
    v_proposal := ottoq_honour_reservation_proposal(p_sim_run_id, v_req.vehicle_id, v_depot, v_ctx);
$new4$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0614 tick (4): the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_def, c_old, c_new);

  EXECUTE v_def;
END $tick$;

-- ══ (f) the stall pick reads the kind ═════════════════════════════════════════════════════════════════════════════════
DO $pick$
DECLARE v_def text; n int; c_old text; c_new text;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure);
  c_old := $old$  v_want_type := CASE WHEN v_soc < 45 OR v_urgency = 'immediate_dispatch' THEN 'dcfc' ELSE 'l2' END;
$old$;
  c_new := $new$  v_want_type := CASE WHEN v_soc < 45 OR v_urgency = 'immediate_dispatch' THEN 'dcfc' ELSE 'l2' END;
  /* 0614: a live agent charge order that names this car for dcfc or l2 sets the kind it wants. An immediate dispatch
     keeps the fast charger the rule gives it, and 'either' leaves the rule's answer. Only the preference moves: every
     candidate gate below still applies, and a free charger of the other kind is still taken when it is the only one. */
  IF p_context ? 'agent_charge_order' AND COALESCE(v_urgency, '') <> 'immediate_dispatch'
     AND (p_context -> 'agent_charge_order' ->> 'kind') IN ('dcfc', 'l2') THEN
    v_want_type := p_context -> 'agent_charge_order' ->> 'kind';
  END IF;
$new$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0614 pick: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $pick$;

-- ══ (g) the cockpits' queue ═══════════════════════════════════════════════════════════════════════════════════════════
DO $queue$
DECLARE v_def text; n int; c_old text; c_new text;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_depot_queue(uuid,uuid)'::regprocedure);

  c_old := $old1$           COALESCE(public.ottoq_policy_get(p_sim_run_id, 'proposer_seat', 0), 0)::int AS seat),
$old1$;
  c_new := $new1$           COALESCE(public.ottoq_policy_get(p_sim_run_id, 'proposer_seat', 0), 0)::int AS seat,
           -- 0614: the agent's charge order, read as the cursor reads it (OTTO-Q's seat, dial 1, live order)
           CASE WHEN COALESCE(public.ottoq_policy_get(p_sim_run_id, 'proposer_seat', 0), 0) = 0
                     AND COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order', 0), 0) >= 1
                THEN public.ottoq_agent_charge_order_live(p_sim_run_id,
                       (SELECT r.tick_count FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id))
                ELSE '{}'::jsonb END AS ao_order,
           COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_pin_wait_min', 90), 90) AS ao_pin),
  ao AS (
    SELECT z.ao_order, z.ao_pin, (z.ao_order <> '{}'::jsonb) AS ao_on,
           CASE WHEN z.ao_order <> '{}'::jsonb
                THEN public.ottoq_agent_charge_order_mode(p_sim_run_id, p_depot_id, z.clock) ELSE 'none' END AS ao_mode
      FROM z),
$new1$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0614 queue (1): the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_def, c_old, c_new);

  c_old := $old2$           public.ottoq_charge_wait_since(v.config, v.last_state_change, p_sim_run_id) AS waiting_since,
$old2$;
  c_new := $new2$           public.ottoq_charge_wait_since(v.config, v.last_state_change, p_sim_run_id) AS waiting_since,
           public.ottoq_charge_wait_min(v.config, v.last_state_change, (SELECT clock FROM z), p_sim_run_id) AS wait_min,  -- 0614
$new2$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0614 queue (2): the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_def, c_old, c_new);

  c_old := $old3$           (row_number() OVER (ORDER BY c.is_immediate DESC,
$old3$;
  c_new := $new3$           (row_number() OVER (ORDER BY c.is_immediate DESC,
                                        -- 0614: the cursor's two keys under a live agent charge order
                                        CASE WHEN (SELECT ao_on FROM ao) THEN c.wait_min >= (SELECT ao_pin FROM ao) END DESC NULLS LAST,
                                        CASE WHEN (SELECT ao_on FROM ao) AND c.wait_min < (SELECT ao_pin FROM ao)
                                             THEN public.ottoq_agent_charge_order_key((SELECT ao_order FROM ao), c.id, (SELECT ao_mode FROM ao)) END ASC NULLS LAST,
$new3$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0614 queue (3): the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_def, c_old, c_new);

  EXECUTE v_def;
END $queue$;

-- ══ (g) the planners' batch, and what the orders did ══════════════════════════════════════════════════════════════════
DO $learning$
DECLARE v_def text; n int; c_old text; c_new text;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_run_learning(uuid,integer,boolean)'::regprocedure);

  c_old := $old1$  v_code text; v_text text;
$old1$;
  c_new := $new1$  v_code text; v_text text;
  v_ao jsonb := '{}'::jsonb; v_ao_on boolean := false; v_ao_pin numeric := 90; v_ao_mode text := 'none';  -- 0614
  v_agent jsonb;                                                                                         -- 0614
$new1$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0614 learning (1): the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_def, c_old, c_new);

  c_old := $old2$  v_live  := (v_status = 'running');
$old2$;
  c_new := $new2$  v_live  := (v_status = 'running');
  -- 0614: the agent's charge order, read as ottoq_decide_tick reads it, so the batch is the cars the kernel will seat
  IF v_seat = 0 AND COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order', 0), 0) >= 1 THEN
    v_ao := COALESCE(public.ottoq_agent_charge_order_live(p_sim_run_id, v_tick), '{}'::jsonb);
    v_ao_on := (v_ao <> '{}'::jsonb);
    IF v_ao_on THEN
      v_ao_pin := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_pin_wait_min', 90), 90);
      v_ao_mode := COALESCE(public.ottoq_agent_charge_order_mode(p_sim_run_id, v_depot, v_clock), 'none');
    END IF;
  END IF;
$new2$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0614 learning (2): the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_def, c_old, c_new);

  c_old := $old3$             ORDER BY q.immediate DESC,
$old3$;
  c_new := $new3$             ORDER BY q.immediate DESC,
                      -- 0614: the cursor's two keys under a live agent charge order
                      CASE WHEN v_ao_on THEN q.wait_min >= v_ao_pin END DESC NULLS LAST,
                      CASE WHEN v_ao_on AND q.wait_min < v_ao_pin
                           THEN public.ottoq_agent_charge_order_key(v_ao, q.id, v_ao_mode) END ASC NULLS LAST,
$new3$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0614 learning (3): the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_def, c_old, c_new);

  c_old := $old4$                  'the offer''s own car already had it.'));
EXCEPTION WHEN OTHERS THEN
$old4$;
  c_new := $new4$                  'the offer''s own car already had it.'))
    -- 0614: the agent's charge order, only while the dial is on (so at the default this answer is the one before):
    -- the order live now, if any, and what the orders did
    || CASE WHEN COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order', 0), 0) >= 1 THEN
         jsonb_build_object('agent_order', jsonb_build_object(
           'live', v_ao_on, 'mode', v_ao_mode, 'pin_wait_min', v_ao_pin,
           'order', (SELECT jsonb_build_object('order_id', x.order_id, 'chain_id', x.chain_id, 'recorded_tick', x.recorded_tick,
                                               'age_ticks', v_tick - x.recorded_tick, 'status', x.status,
                                               'offered', x.n_offered, 'accepted', x.n_accepted, 'why', x.why,
                                               'head', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                                                                 'rank', c -> 'rank', 'vehicle_id', c -> 'vehicle_id',
                                                                 'vehicle', c -> 'name', 'kind', c -> 'kind',
                                                                 'why', c -> 'why', 'kernel_pos', c -> 'kernel_pos')
                                                                 ORDER BY (c ->> 'rank')::int), '[]'::jsonb)
                                                          FROM jsonb_array_elements(x.cars) c
                                                         WHERE (c ->> 'rank') ~ '^[0-9]+$' AND (c ->> 'rank')::int <= 8))
                       FROM ottoq_agent_charge_orders x WHERE x.sim_run_id = p_sim_run_id
                      ORDER BY x.order_id DESC LIMIT 1),
           'usage', public.ottoq_agent_charge_order_usage(p_sim_run_id, 20)))
         ELSE '{}'::jsonb END;
EXCEPTION WHEN OTHERS THEN
$new4$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0614 learning (4): the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_def, c_old, c_new);

  c_old := $old5$               'waiting_for_a_charger leaves out a car that already holds a live charger reservation.',
$old5$;
  c_new := $new5$               'waiting_for_a_charger leaves out a car that already holds a live charger reservation. Under a live '
               'agent charge order (0614) the order is the cursor''s: immediate dispatch, then cars waited past the pin, '
               'then the agent''s ranking (the kind free now first), then the kernel''s ratio.',
$new5$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0614 learning (5): the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_def, c_old, c_new);

  EXECUTE v_def;
END $learning$;

-- ══ (h) the board carries the line ════════════════════════════════════════════════════════════════════════════════════
DO $board$
DECLARE v_def text; n int; c_old text; c_new text;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_agent_board(uuid)'::regprocedure);
  c_old := $old$  RETURN v_board;
END; $function$$old$;
  c_new := $new$  --: 0614. THE CHARGE LINE, so the agent can order it. Gated and concatenated like 0342/0350/0432: at the
  --: default of 0 the key is absent, and a baseline seat never carries it.
  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_charge_order',0),0) >= 1
     AND COALESCE(ottoq_policy_get(p_sim_run_id,'proposer_seat',0),0) = 0 THEN
    v_board := v_board || jsonb_build_object('charge_queue',
                 public.ottoq_agent_charge_queue_board(p_sim_run_id, v_depot, v_clock));
  END IF;

  RETURN v_board;
END; $function$$new$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0614 board: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $board$;

-- ══ V1: the patches, comment-stripped ═════════════════════════════════════════════════════════════════════════════════
DO $v1$
DECLARE v_tick text; v_pick text; v_q text; v_l text; v_b text;
BEGIN
  -- two passes, as 0551's V1: one alternation of both comment forms makes the whole pattern greedy in PostgreSQL's
  -- regex engine, and the block-comment arm then runs from the first /* to the last */ (measured: 96,673 -> 5,107).
  v_tick := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure), '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  v_pick := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure), '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  v_q    := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_depot_queue(uuid,uuid)'::regprocedure), '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  v_l    := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_run_learning(uuid,integer,boolean)'::regprocedure), '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  v_b    := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_agent_board(uuid)'::regprocedure), '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  -- each added cursor key is gated on the order being live
  IF v_tick !~ 'CASE WHEN v_ao_on THEN public\.ottoq_charge_wait_min\(v\.config, v\.last_state_change, v_clock, p_sim_run_id\) >= v_ao_pin END DESC NULLS LAST'
     OR v_tick !~ 'CASE WHEN v_ao_on AND public\.ottoq_charge_wait_min\(v\.config, v\.last_state_change, v_clock, p_sim_run_id\) < v_ao_pin\s+THEN public\.ottoq_agent_charge_order_key\(v_ao_order, v\.id, v_ao_mode\) END ASC NULLS LAST' THEN
    RAISE EXCEPTION '0614 V1: the cursor keys are not the gated ones';
  END IF;
  -- the order is read once, under OTTO-Q's seat and the dial, inside a handler
  IF (length(v_tick) - length(replace(v_tick, 'ottoq_agent_charge_order_live(', ''))) / length('ottoq_agent_charge_order_live(') <> 1
     OR v_tick !~ 'IF v_seat = 0 THEN\s+BEGIN\s+IF COALESCE\(public\.ottoq_policy_get\(p_sim_run_id, ''agent_charge_order'', 0\), 0\) >= 1 THEN'
     OR v_tick !~ 'EXCEPTION WHEN OTHERS THEN\s+RAISE WARNING ''0614 agent charge order read' THEN
    RAISE EXCEPTION '0614 V1: the order is not read once, gated, inside a handler';
  END IF;
  -- the fragments 0613's mirror pins are all still present, verbatim
  IF strpos(v_tick, 'AND NOT public.ottoq_vehicle_fault_open(v.config)') = 0
     OR strpos(v_tick, 'CASE WHEN v_seat = 1 THEN v.last_state_change END ASC NULLS FIRST,') = 0
     OR strpos(v_tick, 'CASE WHEN v_seat = 2 THEN v.current_soc END ASC,') = 0
     OR strpos(v_tick, '+ GREATEST(public.ottoq_effective_target_soc_at(v.id, v_clock) - v.current_soc, 1))') = 0
     OR strpos(v_tick, 'v.current_soc ASC, v.id') = 0 THEN
    RAISE EXCEPTION '0614 V1: a fragment 0613 mirrors is gone from the cursor';
  END IF;
  -- the immediate-dispatch key still comes before the order's keys
  IF strpos(v_tick, 'ORDER BY COALESCE((SELECT vn.urgency = ''immediate_dispatch'' FROM ottoq_visit_needs vn')
     > strpos(v_tick, 'CASE WHEN v_ao_on THEN public.ottoq_charge_wait_min') THEN
    RAISE EXCEPTION '0614 V1: the order''s keys come before immediate dispatch';
  END IF;
  -- the stall pick's override is gated on the context key and spares an immediate dispatch
  IF v_pick !~ 'IF p_context \? ''agent_charge_order'' AND COALESCE\(v_urgency, ''''\) <> ''immediate_dispatch''' THEN
    RAISE EXCEPTION '0614 V1: the stall pick''s override is not gated';
  END IF;
  IF strpos(v_q, 'ottoq_agent_charge_order_key((SELECT ao_order FROM ao), c.id, (SELECT ao_mode FROM ao))') = 0
     OR strpos(v_l, 'ottoq_agent_charge_order_key(v_ao, q.id, v_ao_mode)') = 0
     OR strpos(v_b, '''charge_queue''') = 0 THEN
    RAISE EXCEPTION '0614 V1: a mirror or the board is missing its part';
  END IF;
END $v1$;

-- ══ V2: the key's truth table; V3: the estimate ═══════════════════════════════════════════════════════════════════════
DO $v2$
DECLARE a uuid := 'aaaaaaaa-0000-4000-8000-000000000001'; b uuid := 'aaaaaaaa-0000-4000-8000-000000000002';
  o jsonb;
BEGIN
  o := jsonb_build_object(a::text, jsonb_build_object('rank', 2, 'kind', 'l2'),
                          b::text, jsonb_build_object('rank', 5, 'kind', 'dcfc'));
  IF public.ottoq_agent_charge_order_key(o, a, 'dcfc') IS DISTINCT FROM 1002
     OR public.ottoq_agent_charge_order_key(o, a, 'l2') IS DISTINCT FROM 2
     OR public.ottoq_agent_charge_order_key(o, a, 'both') IS DISTINCT FROM 2
     OR public.ottoq_agent_charge_order_key(o, b, 'l2') IS DISTINCT FROM 1005
     OR public.ottoq_agent_charge_order_key(o, b, 'dcfc') IS DISTINCT FROM 5
     OR public.ottoq_agent_charge_order_key(o, 'aaaaaaaa-0000-4000-8000-000000000003', 'dcfc') IS NOT NULL
     OR public.ottoq_agent_charge_order_key(NULL, a, 'dcfc') IS NOT NULL
     OR public.ottoq_agent_charge_order_key(jsonb_build_object(a::text, jsonb_build_object('rank', 'x')), a, 'none') IS DISTINCT FROM 999 THEN
    RAISE EXCEPTION '0614 V2: the key''s truth table is wrong';
  END IF;
  -- 75 kWh from 49% to 100%: positive on both, faster on a 150 kW fast charger than on a 19 kW L2
  IF NOT (public.ottoq_charge_minutes_estimate(75, 49, 100, 150, 250) > 0
          AND public.ottoq_charge_minutes_estimate(75, 49, 100, 150, 250)
              < public.ottoq_charge_minutes_estimate(75, 49, 100, 19.2, 250))
     OR public.ottoq_charge_minutes_estimate(75, 100, 100, 150, 250) <> 0
     OR public.ottoq_charge_minutes_estimate(NULL, 49, 100, 150, 250) IS NOT NULL THEN
    RAISE EXCEPTION '0614 V3: the charge-minutes estimate is wrong';
  END IF;
END $v2$;

-- ══ V4: at the dial's default the cockpits' queue is the one before this file; V5: the door records nothing ═══════════
DO $v4$
DECLARE v_run uuid; v_diff int; v_r jsonb; v_rows bigint;
BEGIN
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'running'
   ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE '0614 V4/V5: no running twin run; skipped';
    RETURN;
  END IF;
  IF COALESCE(public.ottoq_policy_get(v_run, 'agent_charge_order', 0), 0) <> 0 THEN
    RAISE EXCEPTION '0614 V4: the dial is already set on run %', v_run;
  END IF;
  SELECT count(*) INTO v_diff FROM (
    WITH a AS (SELECT q.queue_kind, q.queue_position, q.vehicle_id
                 FROM pg_temp.ottoq_depot_queue_0614_pre('11111111-1111-1111-1111-111111111111', v_run) q),
         b AS (SELECT q.queue_kind, q.queue_position, q.vehicle_id
                 FROM public.ottoq_depot_queue('11111111-1111-1111-1111-111111111111', v_run) q)
    (SELECT * FROM a EXCEPT ALL SELECT * FROM b) UNION ALL (SELECT * FROM b EXCEPT ALL SELECT * FROM a)) d;
  IF v_diff <> 0 THEN
    RAISE EXCEPTION '0614 V4: at the default the cockpits'' queue moved (% rows differ) on run %', v_diff, v_run;
  END IF;
  SELECT count(*) INTO v_rows FROM public.ottoq_agent_charge_orders;
  v_r := public.ottoq_agent_charge_order_record(v_run, 0, 'v5', 'v5', '{"cars":[]}'::jsonb);
  IF COALESCE(v_r ->> 'skipped', '') <> 'agent_charge_order is 0 for this run'
     OR (SELECT count(*) FROM public.ottoq_agent_charge_orders) <> v_rows THEN
    RAISE EXCEPTION '0614 V5: with the dial at 0 the door answered % or wrote a row', v_r;
  END IF;
  RAISE NOTICE '0614 V4/V5 on run %: queue unchanged at the default; the door refused (%)', v_run, v_r ->> 'skipped';
END $v4$;

-- ══ V6: on a running twin run, armed inside a block that rolls itself back ═══════════════════════════════════════════
DO $v6$
DECLARE v_run uuid; v_head uuid[]; v_got uuid[]; v_want uuid[]; v_ord jsonb := '[]'::jsonb; v_r jsonb;
  v_board jsonb; v_use jsonb; v_msg text; v_clock timestamptz; i int;
BEGIN
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'running'
     AND COALESCE(public.ottoq_policy_get(r.sim_run_id, 'proposer_seat', 0), 0) = 0
   ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE NOTICE '0614 V6: no running twin run on OTTO-Q''s seat; skipped'; RETURN; END IF;
  BEGIN
    PERFORM public.ottoq_policy_set('run', v_run, 'agent_charge_order', 1, 'migration:0614:V6');
    SELECT r.sim_clock_current INTO v_clock FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run;
    -- the line's head that is neither immediate nor near the pin, reversed
    SELECT array_agg(k.vehicle_id ORDER BY k.kernel_pos DESC) INTO v_head
      FROM (SELECT k.* FROM public.ottoq_charge_queue_kernel_order(v_run, '11111111-1111-1111-1111-111111111111', v_clock) k
             WHERE NOT k.immediate AND k.wait_min < 75 ORDER BY k.kernel_pos LIMIT 4) k;
    IF COALESCE(array_length(v_head, 1), 0) < 2 THEN
      RAISE EXCEPTION 'v6_rollback:skip:fewer than two unpinned cars in line';
    END IF;
    FOR i IN 1 .. array_length(v_head, 1) LOOP
      v_ord := v_ord || jsonb_build_object('vehicle_id', v_head[i], 'kind', 'either', 'why', 'V6 probe');
    END LOOP;
    v_ord := v_ord || jsonb_build_object('vehicle_id', v_head[1], 'kind', 'either')    -- a duplicate
                   || jsonb_build_object('vehicle_id', 'not-a-car', 'kind', 'dcfc');   -- junk
    v_r := public.ottoq_agent_charge_order_record(v_run, 0, 'v6', 'v6', jsonb_build_object('cars', v_ord, 'why', 'V6 probe'));
    IF NOT COALESCE((v_r ->> 'ok')::boolean, false) OR v_r ->> 'status' <> 'partial'
       OR COALESCE((v_r ->> 'accepted')::int, 0) < 1
       OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_r -> 'dropped') d WHERE d ->> 'reason' = 'duplicate')
       OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_r -> 'dropped') d WHERE d ->> 'reason' = 'not_a_vehicle_id') THEN
      RAISE EXCEPTION 'v6_rollback:fail:the door answered %', v_r;
    END IF;
    -- the cockpits' queue holds the head cars still in line in the agent's order (a tick may have seated one)
    SELECT array_agg(q.vehicle_id ORDER BY q.queue_position) INTO v_got
      FROM public.ottoq_depot_queue('11111111-1111-1111-1111-111111111111', v_run) q
     WHERE q.queue_kind = 'charge' AND q.vehicle_id = ANY (v_head);
    v_want := ARRAY(SELECT u.h FROM unnest(v_head) WITH ORDINALITY u(h, i) WHERE u.h = ANY (COALESCE(v_got, ARRAY[]::uuid[])) ORDER BY u.i);
    IF COALESCE(v_got, ARRAY[]::uuid[]) IS DISTINCT FROM v_want THEN
      RAISE EXCEPTION 'v6_rollback:fail:the cockpits'' queue holds % where the order says %', v_got, v_want;
    END IF;
    v_board := public.ottoq_agent_charge_queue_board(v_run, '11111111-1111-1111-1111-111111111111', v_clock);
    v_use := public.ottoq_agent_charge_order_usage(v_run, 5);
    IF jsonb_typeof(v_board -> 'cars') <> 'array' OR jsonb_array_length(v_board -> 'cars') > 24
       OR (v_board -> 'last_order' ->> 'order_id') IS NULL OR COALESCE((v_use ->> 'orders')::int, 0) < 1 THEN
      RAISE EXCEPTION 'v6_rollback:fail:board % / usage %', left(v_board::text, 300), v_use;
    END IF;
    RAISE EXCEPTION 'v6_rollback:pass:% of % head cars still in line, in the agent''s order; board % cars; usage % orders',
      COALESCE(array_length(v_got, 1), 0), array_length(v_head, 1), jsonb_array_length(v_board -> 'cars'), v_use ->> 'orders';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg LIKE 'v6_rollback:pass:%' OR v_msg LIKE 'v6_rollback:skip:%' THEN
      RAISE NOTICE '0614 V6 (rolled back): %', v_msg;
    ELSE
      RAISE EXCEPTION '0614 V6: %', v_msg;
    END IF;
  END;
  IF COALESCE(public.ottoq_policy_get(v_run, 'agent_charge_order', 0), 0) <> 0 THEN
    RAISE EXCEPTION '0614 V6: the probe''s dial outlived its block';
  END IF;
END $v6$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0614_the_agent_can_order_the_charge_line_and_the_decide_path_disposes', false, false,
  'agent_charge_order (default 0): under a live agent charge order, OTTO-Q''s charge cursor seats immediate dispatches, '
  'then cars waited past the pin, then the agent''s ranking (the kind free now first), then the kernel''s ratio; the stall '
  'pick prefers the kind the order names; the cockpits'' queue and the planners'' batch mirror it; the board carries the '
  'line. FALSE/FALSE: every certification, sweep and baseline arm runs the dial at 0 (ottoq_agentic_arm refuses '
  'cert_harness), where both cursor keys are NULL for every car, the stall pick sees no context key, and the board and the '
  'learning read carry nothing new; V4 measured the cockpits'' queue unchanged at the default.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
