-- migration-version: 20261018112725
-- migration-name:    a_repair_waits_for_its_green_light_at_every_door
--
-- 0753  **A repair waits for its technician's green-light at every door.** (G467)
--       OTTO-Q plans every fault repair as needing a technician's green-light before the car goes back to work
--       (ottoq.ottoq_derive_visit_needs writes the fault_repair atom with requires_tech_greenlight), and the decide's
--       redeploy door holds such a car until a green-light approved since its visit opened exists. Nothing asks for one
--       after a bay repair, so that door can never let the car go; and the deploy planner's door
--       (ottoq.ottoq_plan_dispatch_tick, which the twin's auto-dispatch departs), the twin's dispatcher and the dispatch
--       trigger all test the one departure test, public.ottoq_departure_clear, which never asks. So every repaired car
--       leaves through the planner's door with no green-light. Research wing, rule 10: under a dial, measured in the
--       twin, then a certified change.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-18 between 1:03 and 1:30 AM CT; db/checks/0457) ═══════════════════════════════
--
--   The derive marks fault_repair requires_tech_greenlight; the escalation of a triaged cosmetic flag marks its repair
--   the same way, (1). The decide's redeployment cursor holds a car whose open visit carries such an atom until an
--   approved tech_greenlight approval created after the visit exists, (2). The only raisers of a tech_greenlight are
--   twin.ottoq_sim_advance_visit_atoms, in its sim-only completion branch for work done in place (no green-light atom is
--   work done in place), and ottoq.ottoq_stage_advance_approval, which nothing in the database calls; the approvals table
--   held no tech_greenlight row when read before 12:49 AM CT, (3). public.ottoq_departure_clear (ac79f1b4) never names a
--   green-light, and every other door goes through it: ottoq.ottoq_plan_dispatch_tick, twin.ottoq_sim_dispatch_vehicle,
--   public.ottoq_refuse_unfinished_departure (0544, the dispatch insert's trigger) and the departure recheck, (4).
--   What it has let through on the twin's runs is counted in db/checks/0457 §5, after the sweep window.
--
-- ══ §2 WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Dial repair_needs_its_green_light (0..1, default 0; not agent-writable).
--   (b) The question. An AFTER UPDATE OF atoms trigger on ottoq_visit_needs, firing only when a done atom that requires
--       a green-light is on the visit: with the dial on for the visit's run, each such atom done by this update asks
--       the crew (approval_type tech_greenlight, the visit's id, priority high), unless the car already has a question
--       pending or one approved since its visit opened. At a depot the twin feeds, the question is the twin's own (as
--       twin.ottoq_sim_advance_visit_atoms raises one): decide_after 15-60 minutes after the repair by its seeded
--       technician delay and expires_at 120 minutes after it, so the twin's technician answers it (92% approve). At a
--       depot a real feed drives, decide_after is the repair's end and it never expires, so a person answers it (0751).
--   (c) A declined green-light re-opens the repair. An AFTER UPDATE OF status trigger on ottoq_ops_approvals, for a
--       pending tech_greenlight turned declined, with the dial on: each done green-light atom on its visit goes back to
--       pending with the decline recorded on it, so the departure test holds the car and the recheck sends it back to the
--       service bay (its remedy for open service-bay work), where it is repaired again and asked again.
--   (d) public.ottoq_departure_clear, one anchored insertion: with the dial on, a car whose open visit carries a done
--       atom that requires a green-light is not clear until one approved since the visit opened exists, the decide's own
--       condition. So every door holds it alike, and the recheck leaves it parked where it is: its remedy CASE names a
--       fault, a charge and open bay work, and a car waiting for its green-light has none of them.
--   (e) Sweep repairgl_busy_2026_10_18: arm 82's cell (dcfc40_2026_10_17 / dcfc10.otto_q, busy_day from 6 AM CT for 12
--       hours at 5 sim-minutes a tick, value_2026_09_30's first seed) with the dial, priority 16, arm budget 3,000 s. It
--       pairs with arm 82 (43301561).
--   Rule 9: this only ever holds a car longer or sends it back to more work; it releases nothing. Queueing, not
--   sacrifice. Not changed: who decides a green-light (the twin's technician at a twin-fed depot, a person at a real
--   one), the decide's own hold, what a repair is or how long it takes.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, and no run live at the twin depot (V3 starts a probe run there). P1 the departure test is the
--   body read (ac79f1b4); the decide still holds a car on an unapproved green-light; the derive still marks fault_repair;
--   the approvals table takes tech_greenlight and has no trigger of this file's; 0751 is applied, so a real depot's
--   question is never drawn on; the seeded draw exists; nothing of this file exists; arm 82's cell is as read. P2 not
--   already applied. Pre-image to ottoq_schema_snapshots as '0753_pre'. The anchor matches once. V1 the departure test
--   less its insertion is its pre-image. V2 the trigger functions return at once at the dial's default. V3 on live, in a
--   block rolled back by its own raise, on a probe run at the twin depot with the dial on: a car otherwise clear whose
--   repair is marked done is asked (the twin's times), is not clear until the question is approved, and is clear after;
--   a declined question re-opens its repair; with the depot switched to external the question is a person's (decide now,
--   no expiry); with the dial off nothing is asked and the departure test is today's; nothing is left behind. V4 the
--   dial is catalogued as declared and the sweep's cell is arm 82's plus the dial.
--   tests/test_repair_green_light_sql.py executes (b), (c) and the patched departure test on the scratch PostgreSQL
--   against the live departure test, atom marker, scan (as 0751 leaves it) and seeded draw (md5 asserted).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. At the dial's default the departure test returns what it did (V1:
--   its body less the insertion is its pre-image, and the insertion is true when the dial is below 1), the question
--   trigger fires only on a visit carrying a done green-light atom and returns before writing, and the decline trigger
--   returns before writing (V2, V3). No certification arm, canon cell or dial experiment sets the dial.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0753_pre'; DROP TRIGGER
--   trg_0753_ask_repair_green_light ON public.ottoq_visit_needs; DROP TRIGGER trg_0753_reopen_declined_repair ON
--   public.ottoq_ops_approvals; DROP FUNCTION public.ottoq_ask_repair_green_light(),
--   public.ottoq_reopen_declined_repair(); if no arm has run, DELETE the sweep repairgl_busy_2026_10_18 and its cell and
--   the dial's catalog row; DELETE FROM public.ottoq_cert_lineage
--   WHERE name = '0753_a_repair_waits_for_its_green_light_at_every_door'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight, no run live at the twin depot ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0753 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
              WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
                AND r.status IN ('initializing', 'running', 'paused')) THEN
    RAISE EXCEPTION '0753 P0: a run is live at the twin depot';
  END IF;
END $inflight$;

-- ── P1: the bodies read, the hold, the mark, the table, 0751, nothing of this file, arm 82's cell ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_departure_clear(uuid,uuid,timestamp with time zone,boolean)'))
     IS DISTINCT FROM 'ac79f1b4109f9eae3e821fdc20e6dca0' THEN
    RAISE EXCEPTION '0753 P1: public.ottoq_departure_clear is not the body read (md5 ac79f1b4)';
  END IF;
  IF position('AND COALESCE((a3->>''requires_tech_greenlight'')::boolean,false)' IN
              (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_decide_tick(uuid)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0753 P1: the decide no longer holds a car on an unapproved green-light';
  END IF;
  IF position('''svc'',''fault_repair''' IN
              (SELECT prosrc FROM pg_proc
                WHERE oid = 'ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)'::regprocedure)) = 0
     OR position('''requires_tech_greenlight'',true' IN
              (SELECT prosrc FROM pg_proc
                WHERE oid = 'ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0753 P1: the derive no longer marks its repairs as needing a green-light';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.ottoq_ops_approvals'::regclass
                    AND conname = 'ottoq_ops_approvals_approval_type_check'
                    AND pg_get_constraintdef(oid) LIKE '%tech_greenlight%') THEN
    RAISE EXCEPTION '0753 P1: the approvals table does not take tech_greenlight';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0751_in_production_only_a_person_answers_a_technician_question') THEN
    RAISE EXCEPTION '0753 P1: 0751 is not applied, so a real depot''s question could be drawn on';
  END IF;
  IF to_regprocedure('twin.ottoq_sim_seeded_random(bigint,text)') IS NULL
     OR to_regprocedure('public.ottoq_policy_get(uuid,text,numeric)') IS NULL THEN
    RAISE EXCEPTION '0753 P1: the seeded draw or the policy reader is missing';
  END IF;
  IF to_regprocedure('public.ottoq_ask_repair_green_light()') IS NOT NULL
     OR to_regprocedure('public.ottoq_reopen_declined_repair()') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgname IN ('trg_0753_ask_repair_green_light', 'trg_0753_reopen_declined_repair'))
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'repair_needs_its_green_light')
     OR EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'repairgl_busy_2026_10_18') THEN
    RAISE EXCEPTION '0753 P1: a function, trigger, the dial or the sweep of this file already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                  WHERE s.sweep_code = 'dcfc40_2026_10_17' AND c.cell_code = 'dcfc10.otto_q'
                    AND c.buildout_code = 'dcfc10' AND s.scenario = 'busy_day'
                    AND s.sim_start = '2026-09-01 11:00:00+00' AND s.ticks = 144 AND s.sim_min_per_tick = 5
                    AND (c.fixed_params ->> 'deploy_peak_fraction')::numeric = 0.9
                    AND c.fixed_params - 'deploy_peak_fraction' = '{}'::jsonb) THEN
    RAISE EXCEPTION '0753 P1: arm 82''s cell (dcfc40_2026_10_17 / dcfc10.otto_q) is not as read';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0753_a_repair_waits_for_its_green_light_at_every_door') THEN
    RAISE EXCEPTION '0753 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0753_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_departure_clear(uuid,uuid,timestamp with time zone,boolean)'::regprocedure;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('repair_needs_its_green_light',
        '0753 (G467): 1 = a repair that needs a technician''s green-light (every fault repair, and an escalated cosmetic '
        'repair) asks for one when it is done, the one departure test holds the car until one approved since its visit '
        'opened exists, at every door, and a declined one re-opens the repair. At a twin-fed depot the twin''s technician '
        'answers; at a real one a person does (0751). 0 = as before 0753: nothing asks, only the decide''s redeploy door '
        'waits, and the planner''s door lets the car go. Research days only until certified.',
        0, 0, 1, 'public.ottoq_departure_clear, public.ottoq_ask_repair_green_light, public.ottoq_reopen_declined_repair',
        false);

-- ── (b) the question ──
CREATE FUNCTION public.ottoq_ask_repair_green_light()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
-- 0753 (G467): a repair that needs a technician's green-light asks for one when it is done. Before 0753 nothing asked
-- after a bay repair, so the decide's redeploy door, which waits for one, could never let the car go, and the deploy
-- planner's door, which does not wait, always did. AFTER UPDATE OF atoms on ottoq_visit_needs, on a visit carrying a done
-- green-light atom. SECURITY DEFINER, so whoever marks the repair done, the question can be written; and a question that
-- cannot be written is a warning, never the repair's: the departure test then holds the car with nothing asked, which
-- the warning names.
DECLARE
  v_a jsonb; v_svc text; v_done timestamptz; v_twin boolean; v_seed bigint;
BEGIN
  IF NEW.sim_run_id IS NULL
     OR COALESCE(public.ottoq_policy_get(NEW.sim_run_id, 'repair_needs_its_green_light', 0), 0) < 1 THEN
    RETURN NULL;
  END IF;
  FOR v_a IN SELECT e.value FROM jsonb_array_elements(NEW.atoms) AS e LOOP
    CONTINUE WHEN NOT COALESCE((v_a ->> 'requires_tech_greenlight')::boolean, false)
               OR COALESCE(v_a ->> 'status', 'pending') <> 'done';
    v_svc := v_a ->> 'svc';
    -- done by this update: the same service was not done with this done_at before it
    CONTINUE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(OLD.atoms) AS o
                           WHERE o.value ->> 'svc' = v_svc AND COALESCE(o.value ->> 'status', 'pending') = 'done'
                             AND o.value ->> 'done_at' IS NOT DISTINCT FROM v_a ->> 'done_at');
    -- one question at a time for the car, and none once one made since this visit opened was approved
    CONTINUE WHEN EXISTS (SELECT 1 FROM public.ottoq_ops_approvals ap
                           WHERE ap.vehicle_id = NEW.vehicle_id AND ap.approval_type = 'tech_greenlight'
                             AND (ap.status = 'pending' OR (ap.status = 'approved' AND ap.created_at >= NEW.created_at)));
    SELECT COALESCE(NULLIF(v_a ->> 'done_at', '')::timestamptz, r.sim_clock_current), COALESCE(r.random_seed, 42)
      INTO v_done, v_seed
      FROM public.ottoq_sim_runs r WHERE r.sim_run_id = NEW.sim_run_id;
    SELECT COALESCE(d.feed_mode, 'sim') = 'sim' INTO v_twin FROM public.depots d WHERE d.id = NEW.depot_id;
    v_twin := COALESCE(v_twin, true);
    BEGIN
      INSERT INTO public.ottoq_ops_approvals (approval_type, vehicle_id, visit_id, sim_run_id, depot_id, payload,
                                             requested_at, decide_after, expires_at, priority)
      VALUES ('tech_greenlight', NEW.vehicle_id, NEW.visit_id, NEW.sim_run_id, NEW.depot_id,
              jsonb_build_object('svc', v_svc, 'est_min', v_a ->> 'est_min', 'repaired_at', v_done, 'asked_by', '0753'),
              v_done,
              -- the twin's own technician delay, drawn as twin.ottoq_sim_advance_visit_atoms draws it; a person now
              CASE WHEN v_twin
                   THEN v_done + ((15 + floor(twin.ottoq_sim_seeded_random(v_seed, NEW.vehicle_id::text || ':glDelay') * 45))::text
                                  || ' minutes')::interval
                   ELSE v_done END,
              CASE WHEN v_twin THEN v_done + interval '120 minutes' ELSE 'infinity'::timestamptz END,
              'high');
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0753 green-light question (vehicle % visit % svc %): % %', NEW.vehicle_id, NEW.visit_id, v_svc,
                    SQLSTATE, SQLERRM;
    END;
  END LOOP;
  RETURN NULL;
END
$fn$;
REVOKE ALL ON FUNCTION public.ottoq_ask_repair_green_light() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER trg_0753_ask_repair_green_light
  AFTER UPDATE OF atoms ON public.ottoq_visit_needs
  FOR EACH ROW
  WHEN (NEW.atoms @> '[{"requires_tech_greenlight": true, "status": "done"}]'::jsonb AND NEW.atoms IS DISTINCT FROM OLD.atoms)
  EXECUTE FUNCTION public.ottoq_ask_repair_green_light();

-- ── (c) a declined green-light re-opens the repair ──
CREATE FUNCTION public.ottoq_reopen_declined_repair()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
-- 0753 (G467): a technician who declines a repair's green-light has not accepted the repair, so it is done again: each
-- done green-light atom on the question's visit goes back to pending, the decline recorded on it. The departure test
-- then holds the car on open work, and the recheck sends it back to the service bay. AFTER UPDATE OF status on
-- ottoq_ops_approvals, for a pending tech_greenlight turned declined. SECURITY DEFINER, as the question's trigger; a
-- re-open that cannot be written is a warning, and the car is still held, by its unapproved green-light.
DECLARE v_atoms jsonb; v_new jsonb := '[]'::jsonb; v_a jsonb; v_n int := 0;
BEGIN
  IF NEW.sim_run_id IS NULL OR NEW.visit_id IS NULL
     OR COALESCE(public.ottoq_policy_get(NEW.sim_run_id, 'repair_needs_its_green_light', 0), 0) < 1 THEN
    RETURN NULL;
  END IF;
  SELECT vn.atoms INTO v_atoms FROM public.ottoq_visit_needs vn
   WHERE vn.visit_id = NEW.visit_id AND vn.status IN ('open', 'in_progress');
  IF v_atoms IS NULL THEN
    RETURN NULL;
  END IF;
  FOR v_a IN SELECT e.value FROM jsonb_array_elements(v_atoms) AS e LOOP
    IF COALESCE((v_a ->> 'requires_tech_greenlight')::boolean, false) AND COALESCE(v_a ->> 'status', 'pending') = 'done' THEN
      v_a := (v_a - 'done_at' - 'started_at' - 'ends_at' - 'performed_by')
             || jsonb_build_object('status', 'pending',
                  'reopened', COALESCE(v_a -> 'reopened', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
                      'at', NEW.decided_at, 'reason', 'green_light_declined', 'approval_id', NEW.approval_id,
                      'decided_by', NEW.decided_by, 'done_at', v_a -> 'done_at')));
      v_n := v_n + 1;
    END IF;
    v_new := v_new || jsonb_build_array(v_a);
  END LOOP;
  IF v_n > 0 THEN
    BEGIN
      UPDATE public.ottoq_visit_needs SET atoms = v_new WHERE visit_id = NEW.visit_id;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0753 re-open after a declined green-light (visit %): % %', NEW.visit_id, SQLSTATE, SQLERRM;
    END;
  END IF;
  RETURN NULL;
END
$fn$;
REVOKE ALL ON FUNCTION public.ottoq_reopen_declined_repair() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER trg_0753_reopen_declined_repair
  AFTER UPDATE OF status ON public.ottoq_ops_approvals
  FOR EACH ROW
  WHEN (NEW.approval_type = 'tech_greenlight' AND NEW.status = 'declined' AND OLD.status = 'pending')
  EXECUTE FUNCTION public.ottoq_reopen_declined_repair();

-- ── (d) the departure test ──
CREATE TEMP TABLE _0753_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0753_patch VALUES
  (1, $o1$     AND NOT public.ottoq_owner_departure_blocked(v.id, p_sim_run_id, p_clock)
$o1$,
   $n1$     AND NOT public.ottoq_owner_departure_blocked(v.id, p_sim_run_id, p_clock)
     -- 0753 (G467): with repair_needs_its_green_light on, a repair done on its open visit that needs a technician's
     -- green-light has one approved since the visit opened, as the decide's own redeploy door has always asked
     AND (COALESCE(public.ottoq_policy_get(p_sim_run_id, 'repair_needs_its_green_light', 0), 0) < 1
          OR NOT EXISTS (
               SELECT 1
                 FROM public.ottoq_visit_needs vg
                 CROSS JOIN LATERAL jsonb_array_elements(vg.atoms) g
                WHERE vg.vehicle_id = v.id
                  AND COALESCE(vg.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                    = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                  AND vg.status IN ('open', 'in_progress')
                  AND COALESCE((g->>'requires_tech_greenlight')::boolean, false)
                  AND COALESCE(g->>'status', 'pending') = 'done'
                  AND NOT EXISTS (SELECT 1 FROM public.ottoq_ops_approvals ap
                                   WHERE ap.vehicle_id = v.id AND ap.approval_type = 'tech_greenlight'
                                     AND ap.status = 'approved' AND ap.created_at >= vg.created_at)))
$n1$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_departure_clear(uuid,uuid,timestamp with time zone,boolean)'::regprocedure);
  FOR p IN SELECT * FROM _0753_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0753: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_departure_clear(uuid,uuid,timestamp with time zone,boolean)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0753: the departure test is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the patched departure test less its insertion is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'public.ottoq_departure_clear(uuid,uuid,timestamp with time zone,boolean)'::regprocedure;
  FOR p IN SELECT * FROM _0753_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM 'ac79f1b4109f9eae3e821fdc20e6dca0' THEN
    RAISE EXCEPTION '0753 V1: the departure test less its insertion is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2 and V3: on live, rolled back by its own raise ──
DO $v3$
DECLARE
  v_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_t0 constant timestamptz := '2031-01-01 12:00:00+00';
  v_t1 constant timestamptz := '2031-01-01 13:00:00+00';
  v_src uuid; v_run uuid := gen_random_uuid(); v_car uuid; v_soc int; v_state text; v_visit uuid; v_q uuid; r record;
BEGIN
  SELECT x.sim_run_id INTO v_src FROM public.ottoq_sim_runs x
   WHERE x.depot_id = v_depot AND x.status = 'completed' ORDER BY x.started_at DESC LIMIT 1;
  SELECT v.id, v.current_soc, v.current_state::text INTO v_car, v_soc, v_state FROM public.vehicles v
   WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
   ORDER BY (v.robotic_tether_until IS NOT NULL), v.id LIMIT 1;
  IF v_src IS NULL OR v_car IS NULL THEN
    RAISE EXCEPTION '0753 V3: no completed run or car at the twin depot to probe with';
  END IF;
  BEGIN
    INSERT INTO public.ottoq_sim_runs (sim_run_id, scenario_id, scenario_code, depot_id, status, started_at,
                                       sim_clock_start, sim_clock_current, sim_clock_end, random_seed, run_by, policy)
    SELECT v_run, x.scenario_id, x.scenario_code, v_depot, 'running', now(), v_t0, v_t1, v_t1 + interval '1 day', 42,
           '0753_v3_probe', 'otto_q'
      FROM public.ottoq_sim_runs x WHERE x.sim_run_id = v_src;
    -- the car is otherwise clear: full, no fault, no owner hold
    UPDATE public.vehicles SET current_soc = 100, config = COALESCE(config, '{}'::jsonb) - 'exception' WHERE id = v_car;
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, status, source)
    VALUES (v_car, v_run, v_depot, v_t0, '0753_v3_probe',
            jsonb_build_array(jsonb_build_object('svc', 'fault_repair', 'status', 'pending', 'must_do', true,
                                                 'concurrency', 'bay', 'requires_bay', 'service_bay',
                                                 'requires_tech_greenlight', true, 'est_min', 60)),
            'in_progress', '0753_v3_probe')
    RETURNING visit_id INTO v_visit;

    -- V2: the dial at its default: the repair asks nothing, and the departure test is today's
    PERFORM public.ottoq_mark_visit_atoms_done(v_car, ARRAY['fault_repair'], v_t1);
    IF EXISTS (SELECT 1 FROM public.ottoq_ops_approvals a WHERE a.sim_run_id = v_run)
       OR NOT public.ottoq_departure_clear(v_car, v_run, v_t1, false) THEN
      RAISE EXCEPTION '0753 V2: at the dial''s default a repair asked, or the departure test changed';
    END IF;

    -- V3: the dial on, a fresh repair: asked with the twin's times, held until approved
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
    VALUES ('run', v_run, 'repair_needs_its_green_light', 1, '0753 V3 probe, rolled back', now());
    UPDATE public.ottoq_visit_needs
       SET atoms = jsonb_build_array(jsonb_build_object('svc', 'fault_repair', 'status', 'pending', 'must_do', true,
                                                        'concurrency', 'bay', 'requires_bay', 'service_bay',
                                                        'requires_tech_greenlight', true, 'est_min', 60))
     WHERE visit_id = v_visit;
    PERFORM public.ottoq_mark_visit_atoms_done(v_car, ARRAY['fault_repair'], v_t1);
    SELECT a.approval_id, a.status, a.decide_after, a.expires_at, a.visit_id, a.payload ->> 'asked_by' AS asked_by INTO r
      FROM public.ottoq_ops_approvals a WHERE a.sim_run_id = v_run AND a.approval_type = 'tech_greenlight';
    IF r.approval_id IS NULL OR r.status <> 'pending' OR r.visit_id <> v_visit OR r.asked_by <> '0753'
       OR r.decide_after < v_t1 + interval '15 minutes' OR r.decide_after > v_t1 + interval '60 minutes'
       OR r.expires_at <> v_t1 + interval '120 minutes' THEN
      RAISE EXCEPTION '0753 V3: the repair did not ask with the twin''s times (%)', row_to_json(r);
    END IF;
    v_q := r.approval_id;
    IF public.ottoq_departure_clear(v_car, v_run, v_t1, false) THEN
      RAISE EXCEPTION '0753 V3: a repair awaiting its green-light was clear to leave';
    END IF;
    UPDATE public.ottoq_ops_approvals SET status = 'approved', decided_at = v_t1, decided_by = '0753 V3 probe'
     WHERE approval_id = v_q;
    IF NOT public.ottoq_departure_clear(v_car, v_run, v_t1, false) THEN
      RAISE EXCEPTION '0753 V3: an approved green-light did not clear the car';
    END IF;

    -- a declined green-light re-opens the repair
    UPDATE public.ottoq_ops_approvals SET status = 'pending', decided_at = NULL, decided_by = NULL WHERE approval_id = v_q;
    UPDATE public.ottoq_ops_approvals SET status = 'declined', decided_at = v_t1, decided_by = '0753 V3 probe'
     WHERE approval_id = v_q;
    SELECT a ->> 'status' AS status, a -> 'reopened' -> 0 ->> 'reason' AS reason INTO r
      FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a WHERE vn.visit_id = v_visit;
    IF r.status <> 'pending' OR r.reason IS DISTINCT FROM 'green_light_declined'
       OR public.ottoq_departure_clear(v_car, v_run, v_t1, false) THEN
      RAISE EXCEPTION '0753 V3: a declined green-light did not re-open the repair (%)', row_to_json(r);
    END IF;

    -- at a depot a real feed drives, the question is a person's: asked now, no expiry
    UPDATE public.depots SET feed_mode = 'external' WHERE id = v_depot;
    PERFORM public.ottoq_mark_visit_atoms_done(v_car, ARRAY['fault_repair'], v_t1 + interval '30 minutes');
    SELECT a.decide_after, a.expires_at INTO r FROM public.ottoq_ops_approvals a
     WHERE a.sim_run_id = v_run AND a.approval_type = 'tech_greenlight' AND a.status = 'pending';
    IF r.decide_after IS DISTINCT FROM v_t1 + interval '30 minutes' OR r.expires_at <> 'infinity'::timestamptz THEN
      RAISE EXCEPTION '0753 V3: a real depot''s question is not a person''s (%)', row_to_json(r);
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'OT753', MESSAGE = 'probe passed';
  EXCEPTION WHEN SQLSTATE 'OT753' THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = v_run)
     OR EXISTS (SELECT 1 FROM public.ottoq_visit_needs WHERE visit_key = '0753_v3_probe')
     OR (SELECT d.feed_mode FROM public.depots d WHERE d.id = v_depot) IS DISTINCT FROM 'sim'
     OR (SELECT v.current_soc FROM public.vehicles v WHERE v.id = v_car) IS DISTINCT FROM v_soc THEN
    RAISE EXCEPTION '0753 V3: the probe left something behind';
  END IF;
END $v3$;

-- ── (e) the pair: arm 82's cell with the dial ──
INSERT INTO public.ottoq_throughput_sweeps (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick,
                                            seeds, replicates, priority, arm_budget_s, status, notes)
VALUES ('repairgl_busy_2026_10_18',
        'A repair waits for its technician''s green-light at every door: arm 82''s busy day with repair_needs_its_green_light',
        '11111111-1111-1111-1111-111111111111', 'busy_day', '2026-09-01 11:00:00+00', 144, 5,
        ARRAY[686364201590009433]::bigint[], 0, 16, 3000, 'active',
        '0753 (G467). Pairs with arm 82 (dcfc40_2026_10_17 / dcfc10.otto_q, run 43301561) on value_2026_09_30''s first '
        'seed; it differs only by the dial. Readout: db/checks/0457''s queries on both runs.');
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, 'dcfc10.otto_q.repair_green_light', 1, 'otto_q', 'dcfc10',
       '{"deploy_peak_fraction": 0.90, "repair_needs_its_green_light": 1}'::jsonb
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'repairgl_busy_2026_10_18';

-- ── V4: the dial and the cell ──
DO $v4$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'repair_needs_its_green_light' AND default_value = 0 AND min_value = 0
                    AND max_value = 1 AND NOT COALESCE(agent_writable, false)) THEN
    RAISE EXCEPTION '0753 V4: the dial is not catalogued 0..1, default 0, not agent-writable';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'repairgl_busy_2026_10_18') <> 1
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                     JOIN public.ottoq_throughput_sweep_cells c82 ON c82.cell_code = 'dcfc10.otto_q'
                     JOIN public.ottoq_throughput_sweeps s82 ON s82.sweep_id = c82.sweep_id
                                                            AND s82.sweep_code = 'dcfc40_2026_10_17'
                     WHERE s.sweep_code = 'repairgl_busy_2026_10_18'
                       AND c.buildout_code = c82.buildout_code AND c.seat = c82.seat
                       AND (s.scenario, s.sim_start, s.ticks, s.sim_min_per_tick, s.seeds[1])
                         = (s82.scenario, s82.sim_start, s82.ticks, s82.sim_min_per_tick, s82.seeds[1])
                       AND c.fixed_params - 'repair_needs_its_green_light' = c82.fixed_params
                       AND c.fixed_params ->> 'repair_needs_its_green_light' = '1') THEN
    RAISE EXCEPTION '0753 V4: the sweep''s cell is not arm 82''s plus the dial';
  END IF;
END $v4$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0753_a_repair_waits_for_its_green_light_at_every_door', false, false,
        'G467. Dial repair_needs_its_green_light (default 0). A trigger on ottoq_visit_needs asks for a technician''s '
        'green-light when a repair that needs one is done (the twin''s times at a twin-fed depot, a person''s at a real '
        'one); public.ottoq_departure_clear, one anchored insertion, holds the car at every door until one approved since '
        'its visit opened exists; a trigger on ottoq_ops_approvals re-opens the repair when one is declined. At 0 the '
        'departure test returns what it did (V1) and both triggers return before writing (V2). Sweep '
        'repairgl_busy_2026_10_18 (arm 82''s cell plus the dial, one seed, priority 16). No certification arm, canon cell '
        'or dial experiment sets the dial.',
        now());

COMMIT;

-- ══ APPLIED 2026-10-18 11:27:25 UTC (6:27 AM CT), ledger version 20261018112725 ══════════════════════════════════════
--
--   Dry-run first on live, read at 11:26:11 UTC (6:26 AM CT): the executable part in one execute_sql ending in a block
--   that raises, so it rolled back. Every premise and check passed, V3's probe run, its repair, its question, its
--   approval and decline and its real-feed question included, and the departure test after it read
--   d5e4d262f68870a3b8d72e113fe68d45. Then through apply_migration after 0751, with nothing in flight and no run live at
--   the twin depot (the file's own P0 at the apply; read after). The text sent, BEGIN through COMMIT and one newline, is
--   25,586 characters, md5 737b2ac591effcad3ac53732c14a2860, equal to the ledger's statements[1] read back; its
--   executable part is 25,570 characters, md5 8737d09e6668b923c45073a5984a751b, equal to this file's.
--   public.ottoq_departure_clear is now md5 d5e4d262f68870a3b8d72e113fe68d45 (prosrc) and names
--   repair_needs_its_green_light. Sweep repairgl_busy_2026_10_18 is queued (one cell, priority 16).
