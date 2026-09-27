-- migration-version: 20260927005114
-- migration-name:    a_vehicle_card_ends_the_current_step_when_it_will_end
--
-- 0507  **A vehicle card said a charge ran "until 4:51 PM" for a charge that started at 9:51 AM and would end near
--       1 PM (G232, the display half).** `db/checks/0374` §7.
--
-- ══ §1 WHAT WAS WRONG (measured 2026-09-27 on validation run 5344fc12, live) ═══════════════════════════════════
--
--   `public.ottoq_depot_cards` gives the current step its plan's `planned_end`, and PULSE and OrchestrAV print it as
--   "Now: <step> until <time>". A step that starts well away from its plan keeps the plan's end: the planned window of
--   a charge anchored where the planner expected a charger to free up. At sim 10:35 AM, 10 of 25 active L2 charges
--   had started 30 or more minutes before their planned start, and their "until" was off by up to 242 minutes (one
--   detail step by 287). Tesla-AV-049 read "Now: Level 2 charge until 4:51 PM" and "Next: Readiness check at 1:01 PM"
--   on the same card: planned 1:45-4:51 PM, started 9:51 AM, a 3 h 6 min charge. The card's own progress bar already
--   measured from the actual start and the planned duration, so the bar and the time disagreed.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The current step also carries `expected_end`: its actual start plus its planned duration, the same two numbers
--   the progress bar divides, or its planned end when either is missing. `planned_end` is unchanged. Contract 1.2
--   (0506, applied minutes earlier and read by no deployed client yet) now also means this field.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   A read function for the cockpits: nothing certified reads it.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0507 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured (0506's) ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_depot_cards(uuid,uuid)'::regprocedure))
     <> '70c24167e4074faaa89bd52bfc5db081' THEN
    RAISE EXCEPTION '0507 P2: public.ottoq_depot_cards is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0507_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_depot_cards(uuid,uuid)'::regprocedure;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_depot_cards(uuid,uuid)'::regprocedure);
  v_old text := $o$'actual_start', l.actual_start_sim,
        'progress_pct'$o$;
  v_new text := $n$'actual_start', l.actual_start_sim,
        /* 0507 (G232): when the step will end from when it started, as the progress bar measures */
        'expected_end', CASE WHEN l.actual_start_sim IS NOT NULL AND l.planned_duration_s IS NOT NULL
                             THEN l.actual_start_sim + make_interval(secs => l.planned_duration_s)
                             ELSE l.planned_end_sim END,
        'progress_pct'$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0507: the current step matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f   regprocedure := 'public.ottoq_depot_cards(uuid,uuid)'::regprocedure;
  v_def text := pg_get_functiondef('public.ottoq_depot_cards(uuid,uuid)'::regprocedure);
BEGIN
  -- V1: the current step carries expected_end, once, and 0506's fields are still there.
  IF (length(v_def) - length(replace(v_def, '''expected_end''', ''))) / length('''expected_end''') <> 1
     OR (length(v_def) - length(replace(v_def, '''atom'', l.duration_basis->>''atom''', ''))) / length('''atom'', l.duration_basis->>''atom''') <> 3
     OR position('''overdue_min''' IN v_def) = 0
     OR position('''contract_version'', ''1.2''' IN v_def) = 0 THEN
    RAISE EXCEPTION '0507 V1: public.ottoq_depot_cards is not the body this file leaves';
  END IF;
  -- V2: privileges, security definer, volatility and search path kept (CREATE OR REPLACE keeps the ACL).
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT provolatile FROM pg_proc WHERE oid = v_f) <> 's'
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f)
          <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres,anon=X/postgres'
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = v_f) <> 'search_path=twin, ottoq, public, extensions' THEN
    RAISE EXCEPTION '0507 V2: public.ottoq_depot_cards''s privileges or settings changed';
  END IF;
END $verify$;

-- V3: on the live run, if there is one: every current step with an actual start and a planned duration carries
-- expected_end = actual start + duration. With no live run V3 is skipped, loudly.
DO $v3$
DECLARE
  v_cards jsonb; v_cur int; v_ok int;
BEGIN
  v_cards := public.ottoq_depot_cards('11111111-1111-1111-1111-111111111111', NULL);
  IF v_cards->>'sim_run_id' IS NULL THEN
    RAISE NOTICE '0507 V3 SKIPPED: no live run at the twin depot to read cards from';
    RETURN;
  END IF;
  SELECT count(*), count(*) FILTER (WHERE (st->>'expected_end')::timestamptz IS NOT NULL)
    INTO v_cur, v_ok
    FROM jsonb_array_elements(v_cards->'vehicles') veh, jsonb_array_elements(COALESCE(veh->'card'->'steps', '[]'::jsonb)) st
   WHERE st->>'status' = 'current';
  IF v_cur = 0 OR v_ok <> v_cur THEN
    RAISE EXCEPTION '0507 V3 FAILED: % current steps, % with expected_end', v_cur, v_ok;
  END IF;
  RAISE NOTICE '0507 V3 PASSED: % current steps, all with expected_end', v_cur;
END $v3$;

-- Rollback: restore public.ottoq_depot_cards from ottoq_schema_snapshots label '0507_pre' (CREATE OR REPLACE, ACL
-- kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0507_a_vehicle_card_ends_the_current_step_when_it_will_end', false,
  'ottoq_depot_cards: the current step carries expected_end, its actual start plus its planned duration (else its '
  'planned end). A cockpit read function; nothing certified reads it.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
