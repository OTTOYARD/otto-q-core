-- migration-version: 20260927050956
-- migration-name:    the_cards_say_who_did_the_work
--
-- 0512  **The cockpits can say that the charger's sensors did an inspection, and that a cleaning need is waiting on
--       the triage's verdict (G236, the display half).** `db/checks/0377`.
--
-- ══ §1 WHAT WAS MISSING ════════════════════════════════════════════════════════════════════════════════════════
--
--   0511 has the charger's sensors perform the interior inspection, and a triage check that judges only the cabin,
--   during the charge, and marks the atom `performed_by = 'charger_sensors'`. Neither cockpit read carries that key:
--   `ottoq_twin_snapshot` builds each open visit's atoms from `svc`, `status`, `must_do` and `est_min` only, and
--   `ottoq_depot_cards` builds a card's needs from `svc`, `status`, `done_at` and `must_do`. So PULSE and OrchestrAV
--   show an inspection the sensors are doing exactly as they show one a technician is doing. Nor can they say that an
--   interior tidy is on hold for the triage's verdict (`confirm_required`) rather than for a technician, or what the
--   verdict was (`triage_verdict`: confirm, clear, escalate).
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   Each atom in both reads also carries `performed_by`, `awaiting_triage` (a pending need that waits on the triage
--   check's verdict) and `triage_verdict`. The snapshot writes the keys on every atom, as it does `est_min`; the cards
--   strip nulls, as they already do, so a key appears only when it has a value. `ottoq_depot_cards` moves to contract
--   1.4. Nothing else changes, and nothing is read that only a simulation knows: the three keys are the engine's own
--   record of what it did.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   Both are cockpit read functions. Their only callers are two other reads (`ottoq_t4_coverage`,
--   `ottoq_vehicle_card`), and no certified atom reads any of them.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0512 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the bodies this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_twin_snapshot(uuid)'::regprocedure)) <> '5ec0eda63b3534952266025dfe2163d6' THEN
    RAISE EXCEPTION '0512 P2: public.ottoq_twin_snapshot is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('public.ottoq_depot_cards(uuid,uuid)'::regprocedure)) <> '7f78fd14264338787cf6871bde475382' THEN
    RAISE EXCEPTION '0512 P2: public.ottoq_depot_cards is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0512_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_twin_snapshot(uuid)'::regprocedure, 'public.ottoq_depot_cards(uuid,uuid)'::regprocedure);

-- (1) the twin snapshot's atoms
DO $patch1$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_twin_snapshot(uuid)'::regprocedure);
  v_old text := $o$                       'must_do', COALESCE((a.value->>'must_do')::boolean, false),$o$;
  v_new text := $n$                       'must_do', COALESCE((a.value->>'must_do')::boolean, false),
                       -- 0512 (G236): who performed it (charger_sensors; absent for a technician), whether it waits
                       -- on the triage check's verdict, and the verdict once given
                       'performed_by', a.value->>'performed_by',
                       'awaiting_triage', COALESCE((a.value->>'confirm_required')::boolean, false)
                                          AND lower(COALESCE(a.value->>'status','pending')) = 'pending',
                       'triage_verdict', a.value->>'triage_verdict',$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0512: the snapshot''s atom matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch1$;

-- (2) the cards' needs, contract 1.4
DO $patch2$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_depot_cards(uuid,uuid)'::regprocedure);
  v_pairs text[][] := ARRAY[
    [$o1$                                 'done_at', a->>'done_at', 'must_do', (a->>'must_do')::boolean)))$o1$,
     $n1$                                 'done_at', a->>'done_at', 'must_do', (a->>'must_do')::boolean,
                                 /* 1.4 (0512, G236): who did it, whether it waits on the triage's verdict, the verdict */
                                 'performed_by', a->>'performed_by',
                                 'awaiting_triage', CASE WHEN COALESCE((a->>'confirm_required')::boolean, false)
                                                          AND COALESCE(a->>'status','pending') = 'pending' THEN true END,
                                 'triage_verdict', a->>'triage_verdict')))$n1$],
    [$o2$  'contract_version', '1.3',$o2$,
     $n2$  'contract_version', '1.4',$n2$]];
  i int; n int;
BEGIN
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0512: cards patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch2$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_snap  text := pg_get_functiondef('public.ottoq_twin_snapshot(uuid)'::regprocedure);
  v_cards text := pg_get_functiondef('public.ottoq_depot_cards(uuid,uuid)'::regprocedure);
BEGIN
  -- V1: each body carries its change once.
  IF (length(v_snap) - length(replace(v_snap, '''awaiting_triage'', COALESCE((a.value->>''confirm_required'')::boolean, false)', '')))
       / length('''awaiting_triage'', COALESCE((a.value->>''confirm_required'')::boolean, false)') <> 1
     OR position('''performed_by'', a.value->>''performed_by''' IN v_snap) = 0
     OR position('''triage_verdict'', a.value->>''triage_verdict''' IN v_snap) = 0
     OR (length(v_cards) - length(replace(v_cards, '''performed_by'', a->>''performed_by''', '')))
       / length('''performed_by'', a->>''performed_by''') <> 1
     OR position('''awaiting_triage'', CASE WHEN COALESCE((a->>''confirm_required'')::boolean, false)' IN v_cards) = 0
     OR position('''contract_version'', ''1.4''' IN v_cards) = 0
     OR position('''contract_version'', ''1.3''' IN v_cards) > 0 THEN
    RAISE EXCEPTION '0512 V1: a patched body is not the body this file leaves';
  END IF;
  -- V2: privileges, security definer, volatility and settings kept (CREATE OR REPLACE keeps the ACL).
  IF (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'public.ottoq_twin_snapshot(uuid)'::regprocedure)
       <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres'
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_twin_snapshot(uuid)'::regprocedure)
     OR (SELECT provolatile FROM pg_proc WHERE oid = 'public.ottoq_twin_snapshot(uuid)'::regprocedure) <> 'v'
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = 'public.ottoq_twin_snapshot(uuid)'::regprocedure)
       <> 'search_path=twin, ottoq, public, extensions'
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'public.ottoq_depot_cards(uuid,uuid)'::regprocedure)
       <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres,anon=X/postgres'
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_depot_cards(uuid,uuid)'::regprocedure)
     OR (SELECT provolatile FROM pg_proc WHERE oid = 'public.ottoq_depot_cards(uuid,uuid)'::regprocedure) <> 's'
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = 'public.ottoq_depot_cards(uuid,uuid)'::regprocedure)
       <> 'search_path=twin, ottoq, public, extensions' THEN
    RAISE EXCEPTION '0512 V2: a patched function''s privileges or settings changed';
  END IF;
END $verify$;

-- V3: on the newest stopped operator run (marked running inside this block only), then rolled back: one open visit
--   planted with an inspection the sensors are doing and an interior tidy waiting on the triage. The snapshot carries
--   the three keys on every atom, with those two values; the car's card carries them on its needs, contract 1.4.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_depot uuid := '11111111-1111-1111-1111-111111111111'; v_visit uuid; v_vehicle uuid;
  v_snap jsonb; v_cards jsonb; a jsonb; n_keys int; n_atoms int;
BEGIN
  BEGIN
    SELECT sr.sim_run_id INTO v_run FROM public.ottoq_sim_runs sr
     WHERE sr.depot_id = v_depot AND sr.validation_status IS NULL AND sr.status = 'completed'
       AND sr.sim_clock_current IS NOT NULL
     ORDER BY sr.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0512 V3 FAILED: no stopped operator run to plant on'; END IF;
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    SELECT vn.visit_id, vn.vehicle_id INTO v_visit, v_vehicle FROM public.ottoq_visit_needs vn
      JOIN public.vehicles v ON v.id = vn.vehicle_id AND v.current_depot_id = v_depot AND v.home_depot_id = v_depot
                            AND v.category = 'autonomous'
     WHERE vn.sim_run_id = v_run
     ORDER BY vn.created_at DESC, vn.visit_id LIMIT 1;
    IF v_visit IS NULL THEN RAISE EXCEPTION '0512 V3 FAILED: the run has no visit to plant on'; END IF;
    UPDATE public.ottoq_visit_needs SET status = 'closed'
     WHERE sim_run_id = v_run AND vehicle_id = v_vehicle AND visit_id <> v_visit AND status IN ('open','in_progress');
    UPDATE public.ottoq_visit_needs SET status = 'in_progress', created_at = now(),
           atoms = jsonb_build_array(
             jsonb_build_object('svc','interior_inspection','status','in_progress','must_do',true,'est_min',4,
                                'concurrency','cabin','performed_by','charger_sensors'),
             jsonb_build_object('svc','interior_tidy','must_do',true,'est_min',4,'concurrency','cabin',
                                'confidence',0.6,'confirm_required',true),
             jsonb_build_object('svc','charge','status','in_progress','must_do',true,'est_min',40,'concurrency','anchor'))
     WHERE visit_id = v_visit;

    v_snap := public.ottoq_twin_snapshot(v_run);
    SELECT count(*), count(*) FILTER (WHERE x ? 'performed_by' AND x ? 'awaiting_triage' AND x ? 'triage_verdict')
      INTO n_atoms, n_keys
      FROM jsonb_array_elements(COALESCE(v_snap #> '{fleet,vehicles}', v_snap -> 'vehicles', '[]'::jsonb)) veh,
           jsonb_array_elements(COALESCE(veh -> 'visit' -> 'atoms', '[]'::jsonb)) x;
    SELECT x INTO a FROM jsonb_array_elements(COALESCE(v_snap #> '{fleet,vehicles}', v_snap -> 'vehicles', '[]'::jsonb)) veh,
                         jsonb_array_elements(COALESCE(veh -> 'visit' -> 'atoms', '[]'::jsonb)) x
     WHERE veh->>'id' = v_vehicle::text AND x->>'svc' = 'interior_inspection';
    IF n_atoms = 0 OR n_keys <> n_atoms OR a->>'performed_by' IS DISTINCT FROM 'charger_sensors'
       OR (a->>'awaiting_triage')::boolean THEN
      RAISE EXCEPTION '0512 V3 FAILED (snapshot): % of % atoms carry the keys; the planted inspection reads %', n_keys, n_atoms, a;
    END IF;
    SELECT x INTO a FROM jsonb_array_elements(COALESCE(v_snap #> '{fleet,vehicles}', v_snap -> 'vehicles', '[]'::jsonb)) veh,
                         jsonb_array_elements(COALESCE(veh -> 'visit' -> 'atoms', '[]'::jsonb)) x
     WHERE veh->>'id' = v_vehicle::text AND x->>'svc' = 'interior_tidy';
    IF NOT COALESCE((a->>'awaiting_triage')::boolean, false) OR a->>'performed_by' IS NOT NULL THEN
      RAISE EXCEPTION '0512 V3 FAILED (snapshot): the planted tidy reads %', a;
    END IF;

    v_cards := public.ottoq_depot_cards(v_depot, NULL);
    SELECT n INTO a FROM jsonb_array_elements(v_cards -> 'vehicles') veh, jsonb_array_elements(veh #> '{card,needs}') n
     WHERE veh->>'vehicle_id' = v_vehicle::text AND n->>'svc' = 'interior_inspection';
    IF v_cards->>'contract_version' IS DISTINCT FROM '1.4' OR a->>'performed_by' IS DISTINCT FROM 'charger_sensors'
       OR a ? 'awaiting_triage' THEN
      RAISE EXCEPTION '0512 V3 FAILED (cards): contract %, the planted inspection reads %', v_cards->>'contract_version', a;
    END IF;
    SELECT n INTO a FROM jsonb_array_elements(v_cards -> 'vehicles') veh, jsonb_array_elements(veh #> '{card,needs}') n
     WHERE veh->>'vehicle_id' = v_vehicle::text AND n->>'svc' = 'interior_tidy';
    IF a->>'awaiting_triage' IS DISTINCT FROM 'true' OR a ? 'performed_by' THEN
      RAISE EXCEPTION '0512 V3 FAILED (cards): the planted tidy reads %', a;
    END IF;

    RAISE EXCEPTION '0512 V3 PASSED: the snapshot carries the three keys on all % atoms, the sensors'' inspection and the tidy awaiting triage read as planted; the cards are contract 1.4 with the same two needs, nulls stripped', n_atoms;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0512 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0512 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: restore the two functions from ottoq_schema_snapshots label '0512_pre' (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0512_the_cards_say_who_did_the_work', false,
  'Cockpit reads only: ottoq_twin_snapshot''s atoms and ottoq_depot_cards'' needs (contract 1.4) carry performed_by, '
  'awaiting_triage and triage_verdict. Their callers are two other reads; no certified atom reads any of them.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
