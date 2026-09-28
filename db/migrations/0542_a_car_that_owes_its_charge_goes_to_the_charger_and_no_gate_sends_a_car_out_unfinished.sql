-- migration-version: 20260928003702
-- migration-name:    a_car_that_owes_its_charge_goes_to_the_charger_and_no_gate_sends_a_car_out_unfinished
--
-- 0542  **A car that still owes its charge goes to a charger, not to departure. The readiness gate never sends a car out
--        unfinished. The recall policy that let a car work past its maintenance interval is retired.**
--
-- ══ §1 WHY (CLAUDE.md rule 9; G267, G265 (a) and (c)) ═══════════════════════════════════════════════════════════════
--
--   G267, found on validation run c9d14225 (the first operator run under 0539), measured 2026-09-27 23:23 UTC:
--   **10 of the twin depot's 116 cars sat in `staged_for_departure` at 88-97% with a must-do charge to 100 pending,
--   from the first ten sim-minutes on.** They were not charged and were not sent out. The mechanism:
--     - the boot places cars in `charge_complete_holding` at their drawn SoC (15 of them on this seed);
--     - under 0539 a visit's target is 100, so a car at 91% owes a charge (`ottoq_derive_visit_needs`: must-do below
--       target - 1);
--     - `ottoq.ottoq_decide_wash_triage` decides what a `charge_complete_holding` car does next. It looks only at
--       cleaning and bay work, and with neither open it releases the car to `staged_for_departure`, svc_step `ready`;
--     - no charging path looks at `staged_for_departure`. The decide tick's charge cursor takes `arrived_at_gate` and
--       `staged_awaiting_service`. The readiness gate takes `staged_awaiting_service`/`need_deploy`. Reassessment takes
--       cars on their way in;
--     - both dispatchers refuse a car with an open must-do atom (`ottoq.ottoq_plan_dispatch_tick` and the decide tick's
--       redeployment).
--   So the car is never charged and never sent out: its need goes unmet and its day is lost. Before 0539 the same
--   boot cars carried targets of 85-90 and owed nothing, which is why the gap never showed.
--
--   G265 (a): escape hatch 3 of the readiness gate (`twin.ottoq_sim_advance_service_flow`). After
--   `deploy_gate_hard_cap_min` (240 sim-min) it released a held car to `staged_for_departure` with its needs still open.
--   It did not fire on ad106e55, and it is the one place the engine was built to send a car out unfinished.
--   Rule 9: "Queueing is allowed; sacrificing is not."
--
--   G265 (c): `interval_scheduled_v1` (recall implementation 3, parked since 0448) recalls a car for interval
--   maintenance only once it is `recall_interval_hard_overdue_mult` times past the interval. In other words, it keeps
--   a car working past its maintenance interval to keep it productive.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq.ottoq_decide_wash_triage`: a car with an open must-do charge atom is staged for its charge. It goes to
--       `staged_awaiting_service` with svc_step `need_charge`, and the decision is `stage_for_charge`. Bay work still
--       comes first (`need_service`, and the readiness gate routes the charge after it). The charge now comes before
--       any cleaning hold, because cabin work runs at the charger during the charge (G236). The decide tick's charge
--       cursor takes the car when a charger is free. The verdict records `owes_charge`.
--   (b) `twin.ottoq_sim_advance_service_flow`, hatch 3: past the hard cap the car stays held on its remedy like any
--       other hold, flagged `deploy_gate_hard_cap`. The first tick past the cap raises one critical
--       `twin.deploy_gate_escalated` event, and `escalated_at` on the run's hold stamp keeps it to one. The summary
--       counts these cars as `held_past_hard_cap`. Nothing releases a car with its needs open.
--   (c) `interval_scheduled_v1` is retired. Its status is `retired` (the status check now admits that value).
--       `ottoq_evaluate_return_need` refuses a retired implementation in any run (SQLSTATE OQ211), and the catalog's
--       `recall_implementation_id` ceiling is 2. The evaluator function stays, unused.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   (a) runs in every arm's tick (`twin.ottoq_sim_wash_triage`). An arm with a charged-and-holding car below 99% now
--   stages it for a charge instead of releasing it, so certified digests and dial arms can move.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0542 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: each function is the one measured (md5 of its source, 2026-09-27 23:30 UTC), and the facts §1 rests on ──
DO $premises$
DECLARE r record; v_def text; v_st int; v_p2 int; v_en int;
  c_a1 CONSTANT text := 'IF v_held_min >= v_hardcap THEN';
  c_a2 CONSTANT text := 'IF v_held_min >= v_patience_dep THEN v_esc_gate := v_esc_gate + 1; END IF;';
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('ottoq.ottoq_decide_wash_triage(uuid,uuid,jsonb,integer,integer,timestamp with time zone)',        'b2d3b6489a792b5de15899a09c57fd76'),
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)',                 'fa46bec89d4e11d966c8e8452ce63bae'),
      ('public.ottoq_evaluate_return_need(uuid,uuid,timestamp with time zone,numeric,numeric)',           '956ab728a0820b05057338550b26d7b7')
    ) AS t(sig, want) LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = r.sig::regprocedure) <> r.want THEN
      RAISE EXCEPTION '0542 P2: % is not the function measured', r.sig;
    END IF;
  END LOOP;
  -- hatch 3 is the block measured: one hard-cap branch, and its extent md5-identical to the one read
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  IF (length(v_def) - length(replace(v_def, c_a1, ''))) / length(c_a1) <> 1
     OR (length(v_def) - length(replace(v_def, c_a2, ''))) / length(c_a2) <> 1 THEN
    RAISE EXCEPTION '0542 P2: hatch 3''s anchors are not each found once';
  END IF;
  v_st := strpos(v_def, c_a1); v_p2 := strpos(v_def, c_a2);
  v_en := v_p2 + length(c_a2) + strpos(substr(v_def, v_p2 + length(c_a2)), 'END IF;') - 1 + length('END IF;') - 1;
  IF md5(substr(v_def, v_st, v_en - v_st + 1)) <> '77f7fcbdbe9031bf239759803ff3b290' THEN
    RAISE EXCEPTION '0542 P2: hatch 3 is not the block measured';
  END IF;
  -- implementation 3 is the parked interval_scheduled_v1, nothing selects it outside a run scope, and no live experiment does
  IF (SELECT implementation || '/' || status FROM public.ottoq_recall_implementations WHERE impl_id = 3)
       IS DISTINCT FROM 'interval_scheduled_v1/parked' THEN
    RAISE EXCEPTION '0542 P2: recall implementation 3 is not the parked interval_scheduled_v1';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params
              WHERE param_key = 'recall_implementation_id' AND scope_type <> 'run' AND param_value = 3) THEN
    RAISE EXCEPTION '0542 P2: a global or depot scope selects interval_scheduled_v1';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_dial_experiments
              WHERE param_key = 'recall_implementation_id' AND status = 'active') THEN
    RAISE EXCEPTION '0542 P2: an active dial experiment varies the recall implementation';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params p JOIN public.ottoq_sim_runs sr ON sr.sim_run_id = p.scope_id
              WHERE p.param_key = 'recall_implementation_id' AND p.scope_type = 'run' AND p.param_value = 3
                AND sr.status = 'running') THEN
    RAISE EXCEPTION '0542 P2: a running run selects interval_scheduled_v1';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0542_pre', 'function', f.sch, f.obj, pg_get_functiondef(f.sig::regprocedure), md5(pg_get_functiondef(f.sig::regprocedure))
  FROM (VALUES ('ottoq',  'ottoq_decide_wash_triage',        'ottoq.ottoq_decide_wash_triage(uuid,uuid,jsonb,integer,integer,timestamp with time zone)'),
               ('twin',   'ottoq_sim_advance_service_flow',  'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'),
               ('public', 'ottoq_evaluate_return_need',      'public.ottoq_evaluate_return_need(uuid,uuid,timestamp with time zone,numeric,numeric)')
       ) AS f(sch, obj, sig);

-- ── (a) the triage stages a car that owes its charge for the charge ──
DO $triage$
DECLARE v_def text; r record; n int;
BEGIN
  v_def := pg_get_functiondef('ottoq.ottoq_decide_wash_triage(uuid,uuid,jsonb,integer,integer,timestamp with time zone)'::regprocedure);
  FOR r IN SELECT * FROM (VALUES
      (1, $o1$  v_deferrable jsonb; v_atoms jsonb; v_urgency text;
$o1$,
          $n1$  v_deferrable jsonb; v_atoms jsonb; v_urgency text;
  v_owes_charge    boolean := false;   -- 0542 (G267)
$n1$),
      (2, $o2$  SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(p_manifest) e
$o2$,
          $n2$  -- 0542 (G267, CLAUDE.md rule 9): a car that still owes its must-do charge is not ready to leave. Released, it
  -- sat in staged_for_departure where no charging path looks and neither dispatcher takes a car with open must-do
  -- work: 10 boot cars at 88-97% on c9d14225, charged by nobody and sent out by nobody. It goes to its charge.
  v_owes_charge := v_atoms IS NOT NULL AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_atoms) a
     WHERE a->>'svc' = 'charge' AND COALESCE((a->>'must_do')::boolean,false)
       AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'));

  SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(p_manifest) e
$n2$),
      (3, $o3$  ELSIF NOT v_has_mustdo_clean THEN
$o3$,
          $n3$  ELSIF v_owes_charge THEN
    -- 0542 (G267): to the charge queue. The decide tick's charge cursor takes a staged_awaiting_service car below its
    -- target when a charger is free, and cabin work runs at the charger during the charge (G236).
    v_decision   := 'stage_for_charge';
    v_next_state := 'staged_awaiting_service';
    v_svc_step   := 'need_charge';
  ELSIF NOT v_has_mustdo_clean THEN
$n3$),
      (4, $o4$    'has_defer_bay', v_has_defer_bay, 'wash_cap', p_wash_cap,
$o4$,
          $n4$    'has_defer_bay', v_has_defer_bay, 'owes_charge', v_owes_charge, 'wash_cap', p_wash_cap,
$n4$)
    ) AS t(k, o, nw) ORDER BY k LOOP
    n := (length(v_def) - length(replace(v_def, r.o, ''))) / length(r.o);
    IF n <> 1 THEN RAISE EXCEPTION '0542 (a) patch %: the text matches % times, not 1', r.k, n; END IF;
    v_def := replace(v_def, r.o, r.nw);
  END LOOP;
  EXECUTE v_def;
END $triage$;

-- ── (b) hatch 3 holds and escalates; it never releases ──
DO $hatch$
DECLARE v_def text; v_st int; v_p2 int; v_en int; r record; n int;
  c_a1 CONSTANT text := 'IF v_held_min >= v_hardcap THEN';
  c_a2 CONSTANT text := 'IF v_held_min >= v_patience_dep THEN v_esc_gate := v_esc_gate + 1; END IF;';
  c_new CONSTANT text := $new$IF v_held_min >= v_hardcap THEN
            -- 0542 (G265 (a), CLAUDE.md rule 9): hatch 3 no longer releases. Past the hard cap the car stays held on its
            -- remedy like any other hold, and the first tick past the cap escalates it to a person: one critical event,
            -- kept to one by `escalated_at` on this run's hold stamp. A car the depot cannot finish is a capacity or
            -- defect finding, never a reason to send it out with its needs open. v_override counts these cars now.
            v_override := v_override + 1;
            IF NOT ((v_rec.config #>> '{deploy_gate,run}') = p_sim_run_id::text
                    AND (v_rec.config #>> '{deploy_gate,escalated_at}') IS NOT NULL) THEN
              PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'deploy_ready_gate',
                p_event_type := 'twin.deploy_gate_escalated', p_entity_type := 'vehicle', p_entity_id := v_rec.id,
                p_payload := jsonb_build_object('held_min', round(v_held_min,1), 'hard_cap_min', v_hardcap,
                  'reason', v_reason, 'remedy', v_remedy, 'soc', v_rec.current_soc, 'ready_soc', v_rec.ready_soc,
                  'missing', to_jsonb(v_missing),
                  'note', 'held past the hard cap with its needs open: a person must look. The car is not released (CLAUDE.md rule 9)'),
                p_severity := 'critical', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
            END IF;
          END IF;
          UPDATE vehicles
             SET config = jsonb_set(config, '{svc_step}', to_jsonb(v_remedy))
                        || jsonb_build_object('deploy_gate', jsonb_build_object(
                             'held_since', v_since, 'run', p_sim_run_id, 'held_min', round(v_held_min,1),   /* 0447 */
                             'reason', v_reason, 'remedy', v_remedy,
                             'soc', v_rec.current_soc, 'ready_soc', v_rec.ready_soc,
                             'missing', to_jsonb(v_missing),
                             'card_must_do_now', to_jsonb(COALESCE(v_rec.card_must, ARRAY[]::text[])),
                             'fits_window', v_rec.fits_window,
                             'minutes_to_deploy', v_rec.minutes_to_deploy)
                           || CASE WHEN v_held_min >= v_hardcap   /* 0542 */
                                   THEN jsonb_build_object('escalated_at',
                                          COALESCE(CASE WHEN (v_rec.config #>> '{deploy_gate,run}') = p_sim_run_id::text
                                                        THEN v_rec.config #> '{deploy_gate,escalated_at}' END,
                                                   to_jsonb(p_sim_clock_now)))
                                   ELSE '{}'::jsonb END)
                        || CASE WHEN v_held_min >= v_hardcap
                                THEN jsonb_build_object('flagged_issue', true,
                                                        'flagged_issue_type', 'deploy_gate_hard_cap')
                                WHEN v_held_min >= v_patience_dep
                                THEN jsonb_build_object('flagged_issue', true,
                                                        'flagged_issue_type', 'deploy_gate_stuck')
                                ELSE '{}'::jsonb END
           WHERE id = v_rec.id;   -- last_state_change deliberately UNTOUCHED (queue order + patience metric)
          v_held := v_held + 1;
          IF v_held_min >= v_patience_dep THEN v_esc_gate := v_esc_gate + 1; END IF;$new$;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  v_st := strpos(v_def, c_a1); v_p2 := strpos(v_def, c_a2);
  v_en := v_p2 + length(c_a2) + strpos(substr(v_def, v_p2 + length(c_a2)), 'END IF;') - 1 + length('END IF;') - 1;
  IF md5(substr(v_def, v_st, v_en - v_st + 1)) <> '77f7fcbdbe9031bf239759803ff3b290' THEN
    RAISE EXCEPTION '0542 (b): hatch 3 is not the block measured';
  END IF;
  v_def := substr(v_def, 1, v_st - 1) || c_new || substr(v_def, v_en + 1);
  -- the summary counts held cars past the cap, and the header comment says what hatch 3 does now
  FOR r IN SELECT * FROM (VALUES
      (1, $o1$'overridden', v_override$o1$, $n1$'held_past_hard_cap', v_override$n1$),
      (2, $o2$  -- ESCAPE HATCHES — nothing can sit forever:$o2$,
          $n2$  -- ESCAPE HATCHES — nothing sits unseen:$n2$),
      (3, $o3$  --      → released anyway, stamped config.deploy_gate_override with a CRITICAL audit
  --      event. Loud and countable, never silent.$o3$,
          $n3$  --      → 0542 (CLAUDE.md rule 9): NOT released. The car stays held on its remedy, flagged
  --      deploy_gate_hard_cap, with one CRITICAL twin.deploy_gate_escalated event for a
  --      person. Hatch 3 used to release it with its needs open; no path does that now.$n3$)
    ) AS t(k, o, nw) ORDER BY k LOOP
    n := (length(v_def) - length(replace(v_def, r.o, ''))) / length(r.o);
    IF n <> 1 THEN RAISE EXCEPTION '0542 (b) patch %: the text matches % times, not 1', r.k, n; END IF;
    v_def := replace(v_def, r.o, r.nw);
  END LOOP;
  EXECUTE v_def;
END $hatch$;

-- ── (c) interval_scheduled_v1 is retired ──
ALTER TABLE public.ottoq_recall_implementations DROP CONSTRAINT ottoq_recall_implementations_status_check;
ALTER TABLE public.ottoq_recall_implementations ADD CONSTRAINT ottoq_recall_implementations_status_check
  CHECK (status = ANY (ARRAY['active'::text, 'parked'::text, 'retired'::text]));
UPDATE public.ottoq_recall_implementations
   SET status = 'retired',
       note = note || ' RETIRED by 0542 (CLAUDE.md rule 9): it kept a car working past its maintenance interval, up to '
                   || 'recall_interval_hard_overdue_mult x the interval, before recalling it. ottoq_evaluate_return_need '
                   || 'refuses it in any run (OQ211). The evaluator function stays, unused.'
 WHERE impl_id = 3;
UPDATE public.ottoq_policy_param_catalog
   SET max_value = 2,
       description = description || ' 0542: 3 (interval_scheduled_v1) is RETIRED under CLAUDE.md rule 9 (it let a car work '
                                 || 'past its maintenance interval before recall), so the ceiling is 2 and the resolver '
                                 || 'refuses it in any run.'
 WHERE param_key = 'recall_implementation_id';
UPDATE public.ottoq_policy_param_catalog
   SET description = description || ' 0542 (CLAUDE.md rule 9): past this many sim-minutes the hold is NOT released. The car '
                                 || 'stays held on its remedy, flagged deploy_gate_hard_cap, and one critical '
                                 || 'twin.deploy_gate_escalated event asks a person to look.'
 WHERE param_key = 'deploy_gate_hard_cap_min';

DO $resolver$
DECLARE v_def text; v_old text; v_new text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_evaluate_return_need(uuid,uuid,timestamp with time zone,numeric,numeric)'::regprocedure);
  v_old := $o$  IF v_impl.status IS DISTINCT FROM 'active'
     AND EXISTS$o$;
  v_new := $n$  -- 0542 (CLAUDE.md rule 9): a retired implementation decides no recall, in any run.
  IF v_impl.status = 'retired' THEN
    RAISE EXCEPTION USING ERRCODE = 'OQ211',
      MESSAGE = format('ottoq_evaluate_return_need: recall implementation %L is retired and decides no recall in any run', v_impl.implementation),
      HINT = 'Set recall_implementation_id to an active implementation.';
  END IF;

  IF v_impl.status IS DISTINCT FROM 'active'
     AND EXISTS$n$;
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0542 (c): the status check matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $resolver$;

-- ── V1 (comment-stripped): each function says what §2 says it says ──
DO $verify$
DECLARE
  r record; v_src text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('ottoq.ottoq_decide_wash_triage(uuid,uuid,jsonb,integer,integer,timestamp with time zone)',
       ARRAY['ELSIF v_owes_charge THEN', 'v_svc_step   := ''need_charge'';', '''owes_charge'', v_owes_charge',
             'a->>''svc'' = ''charge'' AND COALESCE((a->>''must_do'')::boolean,false)'],
       ARRAY[]::text[]),
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)',
       ARRAY['twin.deploy_gate_escalated', 'deploy_gate_hard_cap', '''held_past_hard_cap'', v_override', '''escalated_at'''],
       ARRAY['twin.deploy_gate_override', 'deploy_gate_override', '''overridden''']),
      ('public.ottoq_evaluate_return_need(uuid,uuid,timestamp with time zone,numeric,numeric)',
       ARRAY['IF v_impl.status = ''retired'' THEN', 'OQ211'], ARRAY[]::text[])
    ) AS t(sig, must, mustnt) LOOP
    v_src := regexp_replace(regexp_replace(pg_get_functiondef(r.sig::regprocedure), '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
    IF EXISTS (SELECT 1 FROM unnest(r.must) m WHERE position(m IN v_src) = 0) THEN
      RAISE EXCEPTION '0542 V1: % lacks one of %', r.sig, r.must;
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(r.mustnt) m WHERE position(m IN v_src) > 0) THEN
      RAISE EXCEPTION '0542 V1: % still carries one of %', r.sig, r.mustnt;
    END IF;
  END LOOP;
  -- the gate's hard-cap branch writes no departure. Two mentions are left, the ready branch's release and the tick's own
  -- count of ready cars; before 0542 there were three, and hatch 3 was the third
  v_src := regexp_replace(regexp_replace(pg_get_functiondef(
             'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF (SELECT count(*) FROM regexp_matches(v_src, 'current_state\s*=\s*''staged_for_departure''', 'g')) <> 2 THEN
    RAISE EXCEPTION '0542 V1: the service flow writes staged_for_departure % times, not 2',
      (SELECT count(*) FROM regexp_matches(v_src, 'current_state\s*=\s*''staged_for_departure''', 'g'));
  END IF;
  IF (SELECT status FROM public.ottoq_recall_implementations WHERE impl_id = 3) <> 'retired'
     OR (SELECT max_value FROM public.ottoq_policy_param_catalog WHERE param_key = 'recall_implementation_id') <> 2 THEN
    RAISE EXCEPTION '0542 V1: interval_scheduled_v1 is not retired';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0542_a_car_that_owes_its_charge_goes_to_the_charger_and_no_gate_sends_a_car_out_unfinished', true, true,
  'Rule 9 (G267, G265 a and c): the wash triage stages a car that still owes its must-do charge for the charge instead of '
  'releasing it to staged_for_departure, where nothing charged it and nothing sent it out; the readiness gate''s hatch 3 '
  'holds a car past the hard cap and escalates it once instead of releasing it unfinished; interval_scheduled_v1 is '
  'retired. The triage runs in every arm''s tick, so an arm with a charged-and-holding car below 99% now charges it.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back.
--   (a) The triage, called directly on a probe visit at a depot with no running run (so the visit's run is NULL): a car
--       owing its charge is staged for it, and the same car with the charge done is released as before.
--   (b) The gate, on the ended validation run c9d14225: a twin car held 300 minutes (past the 240 cap) with a must-do
--       walkaround open stays staged_awaiting_service, is flagged deploy_gate_hard_cap, and raises exactly one escalation
--       over two ticks.
--   (c) The resolver refuses implementation 3 in a run (OQ211) and still answers on implementation 1.
DO $v3$
DECLARE
  v_msg text; v_car uuid; v_fake uuid := '00000000-0000-4000-8000-000000000542';
  v_run uuid := 'c9d14225-a7e6-4cf8-b4b7-7b652db9b283'; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_clock timestamptz; v_visit uuid; v1 jsonb; v2 jsonb; v_gate uuid; v_state text; v_cfg jsonb; v_esc int;
  v_state2 text; v_esc2 int; v_ovr int; v_code text; v_ok boolean;
BEGIN
  BEGIN
    -- (a)
    SELECT v.id INTO v_car FROM public.vehicles v WHERE v.category = 'autonomous' ORDER BY v.id LIMIT 1;
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, status)
    VALUES (v_car, NULL, v_fake, now(), '0542_v3_triage',
            '[{"svc":"charge","must_do":true,"deferrable":false,"status":"pending","concurrency":"anchor","target_soc":100}]'::jsonb,
            'open')
    RETURNING visit_id INTO v_visit;
    v1 := ottoq.ottoq_decide_wash_triage(v_car, v_fake, '[]'::jsonb, 3, 0, now());
    UPDATE public.ottoq_visit_needs SET atoms = jsonb_set(atoms, '{0,status}', '"done"') WHERE visit_id = v_visit;
    v2 := ottoq.ottoq_decide_wash_triage(v_car, v_fake, '[]'::jsonb, 3, 0, now());
    IF v1->>'decision' IS DISTINCT FROM 'stage_for_charge' OR v1->>'next_state' IS DISTINCT FROM 'staged_awaiting_service'
       OR v1->>'svc_step' IS DISTINCT FROM 'need_charge' OR (v1->>'owes_charge')::boolean IS NOT TRUE
       OR (v1->>'released_delta')::int <> 0 THEN
      RAISE EXCEPTION '0542 V3 FAILED (a): a car owing its charge reads %', v1;
    END IF;
    IF v2->>'decision' IS DISTINCT FROM 'release' OR v2->>'next_state' IS DISTINCT FROM 'staged_for_departure'
       OR (v2->>'owes_charge')::boolean IS NOT FALSE THEN
      RAISE EXCEPTION '0542 V3 FAILED (a): the same car with its charge done reads %', v2;
    END IF;

    -- (b)
    SELECT r.sim_clock_current INTO v_clock FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run;
    IF v_clock IS NULL THEN RAISE EXCEPTION '0542 V3 (b): run % is gone; point (b) at a run that exists', v_run; END IF;
    SELECT v.id INTO v_gate FROM public.vehicles v
     WHERE v.home_depot_id = v_twin AND v.category = 'autonomous' ORDER BY v.id LIMIT 1;
    -- the probe visit is the car's only open work in the run, and the car is full, so the one thing holding it is the
    -- walkaround (lane exterior: remedy need_deploy, held in place)
    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id = v_gate AND sim_run_id = v_run AND status IN ('open', 'in_progress');
    UPDATE public.vehicles
       SET current_state = 'staged_awaiting_service'::vehicle_state, current_soc = 100,
           config = (COALESCE(config, '{}'::jsonb) - 'flagged_issue' - 'flagged_issue_type')
                    || jsonb_build_object('svc_step', 'need_deploy',
                         'deploy_gate', jsonb_build_object('run', v_run, 'held_since', v_clock - interval '300 minutes'))
     WHERE id = v_gate;
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, status)
    VALUES (v_gate, v_run, v_twin, v_clock - interval '300 minutes', '0542_v3_gate',
            '[{"svc":"perimeter_walkaround","must_do":true,"deferrable":false,"status":"pending","concurrency":"exterior","est_min":12}]'::jsonb,
            'open');
    -- the service flow carries no search_path of its own; ottoq_sim_advance_tick calls it under this one (undone with
    -- this block's rollback)
    PERFORM set_config('search_path', 'twin, ottoq, public, extensions', true);
    PERFORM * FROM twin.ottoq_sim_advance_service_flow(p_sim_run_id := v_run, p_sim_clock_now := v_clock,
                                                       p_tick_minutes := 30, p_depot_id := v_twin);
    SELECT v.current_state::text, v.config INTO v_state, v_cfg FROM public.vehicles v WHERE v.id = v_gate;
    SELECT count(*) INTO v_esc FROM public.ottoq_events e
     WHERE e.sim_run_id = v_run AND e.entity_id = v_gate AND e.event_type = 'twin.deploy_gate_escalated';
    PERFORM * FROM twin.ottoq_sim_advance_service_flow(p_sim_run_id := v_run, p_sim_clock_now := v_clock + interval '30 minutes',
                                                       p_tick_minutes := 30, p_depot_id := v_twin);
    SELECT v.current_state::text INTO v_state2 FROM public.vehicles v WHERE v.id = v_gate;
    SELECT count(*) FILTER (WHERE e.event_type = 'twin.deploy_gate_escalated'),
           count(*) FILTER (WHERE e.event_type = 'twin.deploy_gate_override')
      INTO v_esc2, v_ovr
      FROM public.ottoq_events e WHERE e.sim_run_id = v_run AND e.entity_id = v_gate;
    IF v_state IS DISTINCT FROM 'staged_awaiting_service' OR v_cfg->>'svc_step' IS DISTINCT FROM 'need_deploy'
       OR v_cfg->>'flagged_issue_type' IS DISTINCT FROM 'deploy_gate_hard_cap'
       OR (v_cfg #>> '{deploy_gate,escalated_at}') IS NULL OR v_esc <> 1
       OR v_state2 IS DISTINCT FROM 'staged_awaiting_service' OR v_esc2 <> 1 OR v_ovr <> 0 THEN
      RAISE EXCEPTION '0542 V3 FAILED (b): after 300 min held the car reads %/% flag % escalated_at % with % escalation(s); a tick later %, % escalation(s), % release(s)',
        v_state, v_cfg->>'svc_step', v_cfg->>'flagged_issue_type', v_cfg #>> '{deploy_gate,escalated_at}', v_esc,
        v_state2, v_esc2, v_ovr;
    END IF;

    -- (c)
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value)
    VALUES ('run', v_run, 'recall_implementation_id', 3)
    ON CONFLICT DO NOTHING;
    UPDATE public.ottoq_policy_params SET param_value = 3
     WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'recall_implementation_id';
    BEGIN
      PERFORM * FROM public.ottoq_evaluate_return_need(v_gate, v_run, v_clock, 60, 50);
      v_code := 'none';
    EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE;
    END;
    IF v_code IS DISTINCT FROM 'OQ211' THEN
      RAISE EXCEPTION '0542 V3 FAILED (c): implementation 3 in a run raised %, not OQ211', v_code;
    END IF;
    UPDATE public.ottoq_policy_params SET param_value = 1
     WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'recall_implementation_id';
    BEGIN
      PERFORM * FROM public.ottoq_evaluate_return_need(v_gate, v_run, v_clock, 60, 50);
      v_ok := true;
    EXCEPTION WHEN OTHERS THEN v_ok := false; v_code := SQLSTATE || ' ' || SQLERRM;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION '0542 V3 FAILED (c): implementation 1 no longer answers: %', v_code; END IF;

    RAISE EXCEPTION '0542 V3 PASSED: a car owing its charge is %/% (with it done: %); a car held 300 min is %, flagged %, escalated once over two ticks (% event), released 0 times; implementation 3 raises OQ211 and 1 answers',
      v1->>'decision', v1->>'svc_step', v2->>'decision', v_state2, v_cfg->>'flagged_issue_type', v_esc2;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0542 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0542 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the three `definition`s in ottoq_schema_snapshots WHERE label = '0542_pre' as they are; set
--   ottoq_recall_implementations impl 3 back to 'parked' (strip the 0542 sentence from its note) and restore the status
--   check to ('active','parked'); set recall_implementation_id's catalog ceiling back to 3; strip the 0542 sentences from
--   the two catalog descriptions.
COMMIT;
