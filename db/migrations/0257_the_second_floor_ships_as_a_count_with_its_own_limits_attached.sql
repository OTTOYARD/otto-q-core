-- migration-version: PENDING
-- migration-name: 0257_the_second_floor_ships_as_a_count_with_its_own_limits_attached
-- ===========================================================================
-- 0257  THE SECOND FLOOR SHIPS AS A COUNT, WITH ITS OWN LIMITS ATTACHED
-- ===========================================================================
-- probe:          db/checks/0177, db/checks/0178; BUILD_QUEUE 4g, 4h; follows 0213, 0176
-- forces_recert:  FALSE -- and the migration asserts that, rather than claiming it.
--                 Two NEW read-only functions. No existing object is replaced, no
--                 column is added, nothing a fingerprint hashes is touched. A6 pins
--                 ottoq.ottoq_world_fingerprint and public.ottoq_determinism_pair by
--                 md5 so "FALSE" is a measurement, not an assurance.
--
-- Safe to apply while a round is in flight in principle -- it adds functions nobody
-- calls yet -- but the pre-flight is kept anyway, because "in principle" is how a
-- round gets invalidated.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS SHIPS, AND WHY IT IS NOT WHAT 0171 SAID WAS POSSIBLE
-- ---------------------------------------------------------------------------
--
-- intent_v1 declares eleven lexicographic objectives and TWO floors: readiness and
-- service_completion. db/checks/0171 found readiness buildable and service_completion
-- BLOCKED, on the measurement that all 107,055 ottoq_visit_needs rows read 'superseded'
-- and 'complete' never appears. db/checks/0177 showed the measurement was right and the
-- conclusion wrong: the work record is atoms[].status, one level down inside the same
-- row. 247 of 549 atoms are done in a run whose every row says 'superseded'.
--
-- So the floor is computable, and the first floor already has a house shape to copy:
-- public.ottoq_kpi_dispatch_readiness(p_run) returns jsonb, reports its own horizon, and
-- carries `due_beyond_horizon` and an `end_soc_source` caveat string so a caller cannot
-- quote the number without the thing that bounds it. This follows that shape exactly.
--
-- THE TWO LIMITS THAT TRAVEL WITH THE NUMBER, because they are not optional:
--
--   1. THREE COMPLETION SHAPES (0177 §3). Of 247 done atoms in run 5d00244c:
--      103 EXECUTED (started_at + ends_at + done_at), 80 CREDITED (done_at only),
--      64 SATISFIED (closed_at + closed_by, no done_at at all) -- and all 64 of the
--      third shape are `charge`. A completion COUNT is valid across all three. A
--      DURATION exists for 41.7% of completed work and for charge 0%. The function
--      therefore publishes the shape census and pct_of_done_with_a_duration in the same
--      object, and says in `duration_source` which shapes may not be cited. This is
--      0189's rule and 0172's lesson: a figure ships with its denominator or not at all.
--
--   2. AN UNDECLARED SERVICE (0178). The live operation catalog is
--      public.service_cadence_policy -- 15 services, each with a lane, all active,
--      eight readers -- and it covers 15 of the 16 `svc` values atoms actually use.
--      perimeter_walkaround is in neither catalog. So the per-run object carries
--      `undeclared_services`, and it is NOT empty today. An instrument that reported a
--      clean vocabulary here would be the G25/G28 defect again: a column called green
--      because the comparison was narrower than the claim.
--
-- AND THE REASON IT IS SHIPPABLE AT ALL, measured rather than argued (0177 §2): across
-- four round-38 pairs both arms agree EXACTLY on atoms/must_do/done, while the value
-- VARIES with seed and scenario (must_do completion 57.7 / 54.9 / 56.8 / 56.7%).
-- Reproducible AND sensitive. A3 below pins that property on one pair, so a future
-- change that makes this metric arm-dependent fails here instead of in a deck.
--
-- WHY A FUNCTION AND NOT A TABLE. Nothing is persisted. The atoms are already in the
-- run's own rows, already run-scoped, already inside the retention and purge discipline
-- 0251 made honest. A derived table would need registering in the run-scope registry and
-- would go stale; a STABLE function over the run's own rows cannot.
--
-- WHAT THIS DELIBERATELY DOES NOT DO. It does not wire the metric into
-- ottoq_kpi_five (that is CLAUDE.md 2.9's fixed five, and adding a sixth is a separate
-- decision with a CLI and a CI gate attached), it does not touch the charge satisfaction
-- path that fails to stamp a duration (BUILD_QUEUE 4h), and it does not declare
-- perimeter_walkaround in the catalog -- declaring an operation nothing performs would
-- hide 0178's finding rather than fix it.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- P. NOTHING IN FLIGHT. pg_stat_activity only.
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND query ILIKE '%ottoq_determinism_pair%';
  IF v_n > 0 THEN
    RAISE EXCEPTION 'P FAILED: % certification pair(s) in flight', v_n;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 1. The floor. Shape copied from ottoq_kpi_dispatch_readiness: jsonb out, caveats in.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_kpi_service_completion(p_run uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  WITH a AS (
    SELECT (e->>'svc') AS svc,
           COALESCE(e->>'status','never_started') AS st,
           COALESCE((e->>'must_do')::boolean,false) AS must_do,
           ((e->>'started_at') IS NOT NULL AND (e->>'ends_at') IS NOT NULL) AS timeable,
           ((e->>'done_at')   IS NOT NULL) AS has_done_at,
           ((e->>'closed_at') IS NOT NULL) AS has_closed_at
      FROM public.ottoq_visit_needs vn,
           jsonb_array_elements(COALESCE(vn.atoms,'[]'::jsonb)) e
     WHERE vn.sim_run_id = p_run)
  SELECT jsonb_build_object(
    'sim_run_id',   p_run,
    'atoms',        count(*),
    'must_do',      count(*) FILTER (WHERE must_do),
    'must_do_done', count(*) FILTER (WHERE must_do AND st='done'),
    'service_completion_pct',
       CASE WHEN count(*) FILTER (WHERE must_do) = 0 THEN NULL
            ELSE round(100.0 * count(*) FILTER (WHERE must_do AND st='done')
                       / count(*) FILTER (WHERE must_do), 1) END,
    'optional',      count(*) FILTER (WHERE NOT must_do),
    'optional_done', count(*) FILTER (WHERE NOT must_do AND st='done'),
    'by_state', jsonb_build_object(
       'done',          count(*) FILTER (WHERE st='done'),
       'never_started', count(*) FILTER (WHERE st='never_started'),
       'in_progress',   count(*) FILTER (WHERE st='in_progress'),
       'open',          count(*) FILTER (WHERE st='open'),
       'cancelled',     count(*) FILTER (WHERE st='cancelled')),
    'completion_shapes', jsonb_build_object(
       'executed',  count(*) FILTER (WHERE st='done' AND timeable),
       'credited',  count(*) FILTER (WHERE st='done' AND NOT timeable AND has_done_at),
       'satisfied', count(*) FILTER (WHERE st='done' AND NOT timeable AND NOT has_done_at AND has_closed_at),
       'unknown',   count(*) FILTER (WHERE st='done' AND NOT timeable AND NOT has_done_at AND NOT has_closed_at)),
    'pct_of_done_with_a_duration',
       CASE WHEN count(*) FILTER (WHERE st='done') = 0 THEN NULL
            ELSE round(100.0 * count(*) FILTER (WHERE st='done' AND timeable)
                       / count(*) FILTER (WHERE st='done'), 1) END,
    'undeclared_services',
       COALESCE((SELECT jsonb_agg(DISTINCT a2.svc) FROM a a2
                  WHERE a2.svc IS NOT NULL
                    AND NOT EXISTS (SELECT 1 FROM public.service_cadence_policy p
                                     WHERE p.svc = a2.svc AND p.is_active)), '[]'::jsonb),
    'duration_source',
       'atoms[].started_at/ends_at, present only for the EXECUTED shape. CREDITED atoms carry done_at alone and SATISFIED atoms (every charge in every run measured) carry only closed_at, so no duration or tardiness figure may cite them. db/checks/0177 section 3.',
    'vocabulary_source',
       'public.service_cadence_policy (is_active). NOT service_definitions, which is a fallback consulted only by ottoq_svc_to_stall_type. db/checks/0178.')
    FROM a;
$function$;

-- ---------------------------------------------------------------------------
-- 2. The vocabulary pin, both directions, shaped on ottoq_assert_kpi_touch_vocabulary.
--    It RAISES rather than returning a clean row when it has nothing to pin against.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_assert_service_vocabulary()
 RETURNS TABLE(declared integer, observed integer, undeclared text[], never_observed text[])
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_declared int; v_observed int;
BEGIN
  SELECT count(*) INTO v_declared FROM public.service_cadence_policy WHERE is_active;
  IF v_declared = 0 THEN
    RAISE EXCEPTION 'ottoq_assert_service_vocabulary: the live catalog (service_cadence_policy, '
                    'is_active) holds 0 rows -- there is nothing to pin against and this '
                    'function must not report a clean vocabulary';
  END IF;

  SELECT count(DISTINCT (e->>'svc')) INTO v_observed
    FROM public.ottoq_visit_needs vn,
         jsonb_array_elements(COALESCE(vn.atoms,'[]'::jsonb)) e
   WHERE (e->>'svc') IS NOT NULL;
  IF v_observed = 0 THEN
    RAISE EXCEPTION 'ottoq_assert_service_vocabulary: no atom anywhere names a service -- '
                    'the comparison is empty and a clean answer would be meaningless';
  END IF;

  RETURN QUERY
  WITH obs AS (
    SELECT DISTINCT (e->>'svc') AS svc
      FROM public.ottoq_visit_needs vn,
           jsonb_array_elements(COALESCE(vn.atoms,'[]'::jsonb)) e
     WHERE (e->>'svc') IS NOT NULL)
  SELECT v_declared, v_observed,
         COALESCE((SELECT array_agg(o.svc ORDER BY o.svc) FROM obs o
                    WHERE NOT EXISTS (SELECT 1 FROM public.service_cadence_policy p
                                       WHERE p.svc = o.svc AND p.is_active)), '{}'::text[]),
         COALESCE((SELECT array_agg(DISTINCT p.svc ORDER BY p.svc)
                     FROM public.service_cadence_policy p
                    WHERE p.is_active
                      AND NOT EXISTS (SELECT 1 FROM obs o WHERE o.svc = p.svc)), '{}'::text[]);
END
$function$;

-- ---------------------------------------------------------------------------
-- 3. Classify. FALSE, and A6 proves it.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
('0257_the_second_floor_ships_as_a_count_with_its_own_limits_attached', false,
 'Adds two NEW read-only functions: ottoq_kpi_service_completion(run) -> jsonb (intent_v1''s second '
 'floor, computed from atoms[].status per db/checks/0177) and ottoq_assert_service_vocabulary() '
 '(the catalog pin, shaped on 0213''s touch-vocabulary assertion). Replaces no existing object, adds '
 'no column, touches nothing any fingerprint hashes -- A6 pins ottoq_world_fingerprint and '
 'ottoq_determinism_pair by md5. No canon can move, so no recert is owed.')
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 4. Assertions.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_a jsonb; v_b jsonb; v_undecl text[]; v_decl int; v_obs int;
  k_a uuid := '5d00244c-10c8-4ffc-b6c0-20dff04024bb';
  k_b uuid := '6545cc5b-2deb-4174-b549-28ccd1677947';
BEGIN
  -- A1. Both functions exist, STABLE, with the declared return type.
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='ottoq_kpi_service_completion'
                    AND p.provolatile='s' AND p.prorettype='jsonb'::regtype) THEN
    RAISE EXCEPTION 'A1 FAILED: ottoq_kpi_service_completion missing or not STABLE jsonb';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='ottoq_assert_service_vocabulary'
                    AND p.provolatile='s') THEN
    RAISE EXCEPTION 'A1 FAILED: ottoq_assert_service_vocabulary missing or not STABLE';
  END IF;

  -- A2. THE BEHAVIOURAL PIN. Run 5d00244c (busy_day/424242/12t, 14:29 UTC 2026-09-12),
  --     measured by hand in db/checks/0177 before this function existed.
  v_a := public.ottoq_kpi_service_completion(k_a);
  IF (v_a->>'atoms')::int <> 549 OR (v_a->>'must_do')::int <> 386
     OR (v_a->>'must_do_done')::int <> 219
     OR (v_a->>'service_completion_pct')::numeric <> 56.7
     OR (v_a->'completion_shapes'->>'executed')::int  <> 103
     OR (v_a->'completion_shapes'->>'credited')::int  <> 80
     OR (v_a->'completion_shapes'->>'satisfied')::int <> 64
     OR (v_a->'completion_shapes'->>'unknown')::int   <> 0
     OR (v_a->>'pct_of_done_with_a_duration')::numeric <> 41.7 THEN
    RAISE EXCEPTION 'A2 FAILED: run % returned %, not 0177''s hand-measured figures', k_a, v_a;
  END IF;

  -- A3. THE PROPERTY THAT MAKES IT SHIPPABLE. The paired arm must produce a
  --     byte-identical object apart from its own run id. A change that makes this
  --     metric arm-dependent fails here rather than in a deck.
  v_b := public.ottoq_kpi_service_completion(k_b);
  IF (v_a - 'sim_run_id') <> (v_b - 'sim_run_id') THEN
    RAISE EXCEPTION 'A3 FAILED: the two arms of one pair disagree. arm_a % arm_b %', v_a, v_b;
  END IF;

  -- A4. The instrument must NOT report a clean vocabulary, because it is not clean.
  --     perimeter_walkaround is declared in neither catalog (db/checks/0178).
  IF NOT (v_a->'undeclared_services' ? 'perimeter_walkaround') THEN
    RAISE EXCEPTION 'A4 FAILED: undeclared_services is % -- either 0178 was fixed without '
                    'updating this assertion, or the check is blind', v_a->'undeclared_services';
  END IF;

  -- A5. The pin answers in both directions and agrees with the per-run object.
  SELECT declared, observed, undeclared INTO v_decl, v_obs, v_undecl
    FROM public.ottoq_assert_service_vocabulary();
  IF v_decl < 1 OR v_obs < 1 THEN
    RAISE EXCEPTION 'A5 FAILED: pin returned declared=% observed=%', v_decl, v_obs;
  END IF;
  IF NOT ('perimeter_walkaround' = ANY(v_undecl)) THEN
    RAISE EXCEPTION 'A5 FAILED: the global pin does not see what the per-run object sees. %', v_undecl;
  END IF;

  -- A6. forces_recert=FALSE is a MEASUREMENT. Nothing hashed moved.
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='ottoq' AND p.proname='ottoq_world_fingerprint')
     <> '945fa4b9e7bfd0d1c027fd92dc85fa06' THEN
    RAISE EXCEPTION 'A6 FAILED: ottoq_world_fingerprint moved -- this migration may not claim forces_recert=FALSE';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair')
     <> '8a35b8c874fed154cc216140faec0274' THEN
    RAISE EXCEPTION 'A6 FAILED: ottoq_determinism_pair moved -- this migration may not claim forces_recert=FALSE';
  END IF;

  RAISE NOTICE '0257 OK: run=% service_completion_pct=% duration_coverage_pct=% undeclared=%',
    k_a, (v_a->>'service_completion_pct'), (v_a->>'pct_of_done_with_a_duration'),
    (v_a->'undeclared_services');
END $$;

-- ---------------------------------------------------------------------------
-- 5. Snapshot the two new objects and report the floor, which must NOT have moved.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0257_post', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_kpi_service_completion','ottoq_assert_service_vocabulary');

SELECT public.ottoq_kpi_service_completion('5d00244c-10c8-4ffc-b6c0-20dff04024bb'::uuid) AS floor_two,
       public.ottoq_cert_recert_floor() AS recert_floor_unchanged;
