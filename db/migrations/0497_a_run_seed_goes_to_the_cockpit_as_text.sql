-- migration-version: 20260926204519
-- migration-name:    a_run_seed_goes_to_the_cockpit_as_text
--
-- 0497  **The cockpits printed every run seed rounded (G230).** `db/checks/0368` §12.
--
-- ══ §1 WHAT WAS WRONG ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   An operator run's seed is a 64-bit integer (`ottoq_sim_runs.random_seed`, bigint). Four read functions put it in
--   their JSON as a number, which is exact as JSON and not once a browser parses it: JavaScript holds it as a double,
--   exact only to 2^53. So the twin cockpit's Runs tab showed validation run `394e1e83`'s seed 2336095663689336323 as
--   2336095663689336300, and `461c79fa`'s 5753109525808485125 as 5753109525808485000. The engine's own record
--   (the run row, `ottoq_kpi_five`'s `run_key`) is exact; what a person reads to reproduce the run was not.
--
-- ══ §2 WHAT THIS DOES ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_twin_run_list`, `ottoq_twin_run_context`, `ottoq_twin_snapshot` and `ottoq_twin_boot_manifest` send the seed
--   as text, and the boot manifest also turns the two integer `seed` keys inside the run's stored `boot_draw` into
--   strings (the boot splash prints one). The cockpit prints it as it comes (ottoyarddepot-sim#110 types it
--   `number | string`). No function in the
--   database reads these fields (the one caller, `ottoq_t4_coverage`, counts entities in the snapshot), so
--   forces_recert FALSE.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0497 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the four bodies this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_twin_run_list(integer)'::regprocedure)) <> '0a0acd795cd6017130915dfaba138ab7'
     OR md5(pg_get_functiondef('public.ottoq_twin_run_context(uuid)'::regprocedure)) <> 'f47e21b5a5bcc72c991a81110ba50df0'
     OR md5(pg_get_functiondef('public.ottoq_twin_snapshot(uuid)'::regprocedure)) <> '2aa3f6b92788785a9b3501f25d7a294f'
     OR md5(pg_get_functiondef('public.ottoq_twin_boot_manifest(uuid)'::regprocedure)) <> 'aa35365309f2bfe83b494a65c6bb47ef' THEN
    RAISE EXCEPTION '0497 P2: one of the four twin read functions is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0497_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_twin_run_list(integer)'::regprocedure, 'public.ottoq_twin_run_context(uuid)'::regprocedure,
                 'public.ottoq_twin_snapshot(uuid)'::regprocedure, 'public.ottoq_twin_boot_manifest(uuid)'::regprocedure);

DO $patch$
DECLARE
  r record;
  v_def text; n int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_twin_run_list(integer)',  $o$'seed',              sr.random_seed,$o$, $n$'seed',              sr.random_seed::text,$n$),
      ('public.ottoq_twin_run_context(uuid)',  $o$'seed',        r.random_seed,$o$,        $n$'seed',        r.random_seed::text,$n$),
      ('public.ottoq_twin_snapshot(uuid)',     $o$'seed',        v_run.random_seed,$o$,    $n$'seed',        v_run.random_seed::text,$n$),
      ('public.ottoq_twin_boot_manifest(uuid)', $o$'random_seed', r.random_seed,$o$,       $n$'random_seed', r.random_seed::text,$n$),
      ('public.ottoq_twin_boot_manifest(uuid)', $o$'boot_draw', r.payload->'boot_draw')$o$,
        $n$'boot_draw', regexp_replace((r.payload->'boot_draw')::text, '"seed": (-?[0-9]+)', '"seed": "\1"', 'g')::jsonb)$n$)
    ) t(fn, v_old, v_new)
  LOOP
    v_def := pg_get_functiondef(r.fn::regprocedure);
    n := (length(v_def) - length(replace(v_def, r.v_old, ''))) / length(r.v_old);
    IF n <> 1 THEN RAISE EXCEPTION '0497: % matched its seed line % times, not once', r.fn, n; END IF;
    EXECUTE replace(v_def, r.v_old, r.v_new);
  END LOOP;
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_run uuid; v_seed text; j jsonb;
BEGIN
  -- V1: each body sends the seed as text, once.
  IF position('sr.random_seed::text' IN pg_get_functiondef('public.ottoq_twin_run_list(integer)'::regprocedure)) = 0
     OR position('r.random_seed::text' IN pg_get_functiondef('public.ottoq_twin_run_context(uuid)'::regprocedure)) = 0
     OR position('v_run.random_seed::text' IN pg_get_functiondef('public.ottoq_twin_snapshot(uuid)'::regprocedure)) = 0
     OR position('r.random_seed::text' IN pg_get_functiondef('public.ottoq_twin_boot_manifest(uuid)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0497 V1: a twin read function still sends the seed as a number';
  END IF;
  -- V2: volatility, security definer and privileges kept (CREATE OR REPLACE keeps the ACL).
  IF (SELECT string_agg(p.proname::text || ':' || p.provolatile::text || ':' || p.prosecdef::text || ':' || array_to_string(p.proacl, ','), ' ' ORDER BY p.proname)
        FROM pg_proc p
       WHERE p.oid IN ('public.ottoq_twin_run_list(integer)'::regprocedure, 'public.ottoq_twin_run_context(uuid)'::regprocedure,
                       'public.ottoq_twin_snapshot(uuid)'::regprocedure, 'public.ottoq_twin_boot_manifest(uuid)'::regprocedure))
     <> 'ottoq_twin_boot_manifest:s:true:postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres,anon=X/postgres '
        'ottoq_twin_run_context:s:true:postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres,anon=X/postgres '
        'ottoq_twin_run_list:s:true:postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres '
        'ottoq_twin_snapshot:v:true:postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres' THEN
    RAISE EXCEPTION '0497 V2: a twin read function changed volatility or privileges';
  END IF;
  -- V3: on the newest operator run, every seed the run context, the boot manifest and the run list send is a string,
  -- and the run's own is exact.
  SELECT sim_run_id, random_seed::text INTO v_run, v_seed
    FROM public.ottoq_sim_runs WHERE run_by = 'operator_demo' ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NOT NULL THEN
    j := jsonb_path_query_first(public.ottoq_twin_run_context(v_run), '$.**.seed');
    IF jsonb_typeof(j) IS DISTINCT FROM 'string' OR j #>> '{}' IS DISTINCT FROM v_seed THEN
      RAISE EXCEPTION '0497 V3: the run context sends % for seed %', j, v_seed;
    END IF;
    j := jsonb_path_query_first(public.ottoq_twin_boot_manifest(v_run), '$.**.random_seed');
    IF jsonb_typeof(j) IS DISTINCT FROM 'string' OR j #>> '{}' IS DISTINCT FROM v_seed THEN
      RAISE EXCEPTION '0497 V3: the boot manifest sends % for seed %', j, v_seed;
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_path_query(public.ottoq_twin_boot_manifest(v_run), '$.**.seed') v WHERE jsonb_typeof(v) <> 'string')
       OR EXISTS (SELECT 1 FROM jsonb_path_query(public.ottoq_twin_run_list(30), '$.**.seed') v WHERE jsonb_typeof(v) NOT IN ('string','null')) THEN
      RAISE EXCEPTION '0497 V3: the boot draw or the run list still sends a seed as a number';
    END IF;
  END IF;
END $verify$;

-- Rollback: restore the four functions from ottoq_schema_snapshots label '0497_pre' (CREATE OR REPLACE, ACLs kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0497_a_run_seed_goes_to_the_cockpit_as_text', false,
  'ottoq_twin_run_list, ottoq_twin_run_context, ottoq_twin_snapshot and ottoq_twin_boot_manifest send the run seed '
  '(and the boot draw''s seeds) as text, so a 64-bit seed reaches a browser exact. Read functions with no caller in '
  'the certified path.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
