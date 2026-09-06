-- =====================================================================
-- 0201  The priors are part of the world, and the verdict now names
--       them
-- =====================================================================
-- forces_recert = FALSE. Four harness functions change, one is new, no
-- engine function is touched (A0 pins every body).
--
-- THE FINDING (db/checks/0115, round 19)
-- ---------------------------------------------------------------------
-- cron job 2 (ottoq-twin-ingest-weekly, Sundays 04:00 UTC) ran at
-- 04:05:25 UTC on 2026-09-06, between round-19 pair 2 and pair 3, and
-- refit the NOAA ambient-temperature and precipitation grids and the
-- EIA grid-demand grid and hourly shape in ottoq_calibration_*. The twin
-- draws its weather and grid cards from those grids
-- (ottoq_sample_calibrated inside ottoq_twin_deal). Pairs 1-2 reproduced
-- round 18 to the byte; pairs 3-7 all passed and all moved. The
-- reproducibility key (scenario + seed + policy + depot) did not include
-- the priors, so the instrument could see that a canon moved and could
-- not say why.
--
-- THREE MOVES
-- ---------------------------------------------------------------------
-- 1. public.ottoq_calibration_fingerprint(): md5 over the CONTENT of the
--    four calibration tables (grids, fit parameters, bounds, profile
--    data, correlations, dataset ranges). fitted_at / ingested_at are
--    excluded on purpose: a refit that lands the same numbers is not a
--    change to the world.
-- 2. The fingerprint rides in the boot image
--    (ottoq_boot_state_fingerprint -> 'calibration'), so it is also in
--    endst; the pair copies it into each arm as h_cal and its equality
--    hears it (two arms on different priors is a FAILED pair, not a
--    passed one); ottoq_cert_matrix carries canon_cal (NULL-lenient for
--    verdicts written before this migration, like canon_prop). A moved
--    canon with a moved canon_cal is attributed by the instrument.
-- 3. ottoq_twin_ingest_refresh() refuses to run while a certification
--    round is scheduled (a cron job named r<N>_*) or a pair is in flight,
--    logs a WARNING and returns. The weekly refit waits a week; a
--    certification never runs on shifting priors. Versioning the
--    datasets and pinning the version on the run row is G14 (c), later.
-- =====================================================================

BEGIN;

CREATE TEMP TABLE pin_0201 ON COMMIT DROP AS
SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
       md5(pg_get_functiondef(p.oid)) AS h
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p');

CREATE TEMP TABLE pre_0201 ON COMMIT DROP AS
SELECT has_function_privilege('anon',          'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE') AS m_anon,
       has_function_privilege('authenticated', 'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE') AS m_auth,
       has_function_privilege('service_role',  'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE') AS m_svc,
       (SELECT proacl::text FROM pg_proc WHERE oid = 'public.ottoq_twin_ingest_refresh()'::regprocedure) AS ingest_acl;

-- ---------------------------------------------------------------------
-- 1. The fingerprint.
-- ---------------------------------------------------------------------
CREATE FUNCTION public.ottoq_calibration_fingerprint()
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  -- 0201. The world's priors as one hash: what the twin can draw from.
  -- Content only; timestamps are deliberately left out.
  WITH d AS (
    SELECT md5(COALESCE(string_agg(
             dataset_code||'|'||variable_name||'|'||COALESCE(segment,'-')||'|'||COALESCE(quantile_grid::text,'-')
             ||'|'||COALESCE(hard_min::text,'-')||'|'||COALESCE(hard_max::text,'-')
             ||'|'||COALESCE(best_fit_family,'-')||'|'||COALESCE(best_fit_parameters::text,'-'),
             E'\n' ORDER BY dataset_code, variable_name, segment), '')) AS h
      FROM public.ottoq_calibration_distributions),
  p AS (
    SELECT md5(COALESCE(string_agg(
             dataset_code||'|'||profile_name||'|'||COALESCE(profile_kind,'-')||'|'||COALESCE(profile_data::text,'-')
             ||'|'||COALESCE(normalization,'-'),
             E'\n' ORDER BY dataset_code, profile_name, profile_kind), '')) AS h
      FROM public.ottoq_calibration_profiles),
  c AS (
    SELECT md5(COALESCE(string_agg(
             dataset_code||'|'||variable_a||'|'||variable_b||'|'||COALESCE(coefficient::text,'-')||'|'||COALESCE(method,'-'),
             E'\n' ORDER BY dataset_code, variable_a, variable_b), '')) AS h
      FROM public.ottoq_calibration_correlations),
  s AS (
    SELECT md5(COALESCE(string_agg(
             dataset_code||'|'||COALESCE(record_count::text,'-')||'|'||COALESCE(date_range_start::text,'-')
             ||'|'||COALESCE(date_range_end::text,'-'),
             E'\n' ORDER BY dataset_code), '')) AS h
      FROM public.ottoq_calibration_datasets)
  SELECT md5(d.h || '#' || p.h || '#' || c.h || '#' || s.h) FROM d, p, c, s;
$function$;
COMMENT ON FUNCTION public.ottoq_calibration_fingerprint() IS
  '0201: md5 over the content of ottoq_calibration_distributions/profiles/correlations/datasets (no timestamps). Rides in the boot image as calibration.h, in each certification arm as h_cal, and in ottoq_cert_matrix as canon_cal.';

-- ---------------------------------------------------------------------
-- 2a. The boot image carries it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_boot_state_fingerprint(p_depot uuid, p_run uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
WITH vn AS (
  SELECT (t.sim_run_id IS NOT NULL AND t.sim_run_id <> p_run) AS fgn, t.status::text AS st,
         md5((to_jsonb(t) - 'visit_id' - 'sim_run_id' - 'created_at' - 'updated_at' - 'meta')::text) AS h
  FROM public.ottoq_visit_needs t WHERE t.depot_id = p_depot
), bk AS (
  SELECT (t.sim_run_id IS NOT NULL AND t.sim_run_id <> p_run) AS fgn, t.state::text AS st,
         md5(((to_jsonb(t) - 'booking_id' - 'sim_run_id' - 'decision_id' - 'leg_id'
              - 'visit_id' - 'booked_at' - 'created_at' - 'updated_at' - 'why')
              || jsonb_build_object('why', public.ottoq_scrub_ids(t.why)))::text) AS h
  FROM public.ottoq_stall_bookings t
  WHERE EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = t.stall_id AND s.depot_id = p_depot)
), lg AS (
  SELECT (t.sim_run_id IS NOT NULL AND t.sim_run_id <> p_run) AS fgn, t.status::text AS st,
         md5((to_jsonb(t) - 'leg_id' - 'itinerary_id' - 'sim_run_id' - 'created_at')::text) AS h
  FROM public.ottoq_itinerary_legs t
  WHERE EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id = t.vehicle_id AND v.home_depot_id = p_depot)
), dp AS (
  SELECT (t.sim_run_id IS NOT NULL AND t.sim_run_id <> p_run) AS fgn, t.status::text AS st,
         md5(((to_jsonb(t) - 'dispatch_id' - 'sim_run_id' - 'created_at' - 'return_evidence')
              || jsonb_build_object('return_evidence',
                   t.return_evidence #- '{appointment,correlation_id}'))::text) AS h
  FROM public.ottoq_vehicle_dispatches t
  WHERE EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id = t.vehicle_id AND v.home_depot_id = p_depot)
), ch AS (
  SELECT md5((to_jsonb(t) - 'created_at' - 'updated_at' - 'last_fault_payload')::text) AS h
  FROM public.ottoq_ocpp_chargers t WHERE t.depot_id = p_depot
)
SELECT jsonb_build_object(
  'visit_needs', jsonb_build_object(
    'vis', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM vn WHERE NOT fgn),
    'fgn', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM vn WHERE fgn AND st IN ('open','in_progress','carried_over'))),
  'bookings', jsonb_build_object(
    'vis', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM bk WHERE NOT fgn),
    'fgn', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM bk WHERE fgn AND st IN ('held','active','interrupted'))),
  'legs', jsonb_build_object(
    'vis', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM lg WHERE NOT fgn),
    'fgn', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM lg WHERE fgn AND st IN ('planned','active','in_progress'))),
  'dispatches', jsonb_build_object(
    'vis', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM dp WHERE NOT fgn),
    'fgn', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM dp WHERE fgn AND st IN ('active','returning'))),
  'chargers', jsonb_build_object(
    'world', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM ch)),
  -- 0201: the priors the twin draws from are part of the world it boots into
  'calibration', jsonb_build_object('h', public.ottoq_calibration_fingerprint()))
$function$;

-- ---------------------------------------------------------------------
-- 2b. The pair copies it into each arm and its equality hears it.
--     Everything else is byte-for-byte the 0199 body.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_determinism_pair(p_seed bigint, p_ticks integer DEFAULT 12, p_scenario text DEFAULT 'busy_day'::text, p_depot uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid, p_sim_start timestamp with time zone DEFAULT '2026-09-01 02:00:00+00'::timestamp with time zone, p_arm_budget_s integer DEFAULT 240)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_arm int; v_run uuid; v_t0 timestamptz;
  v_clock timestamptz; v_status text; v_ticks int;
  v_boot jsonb;
  v_h jsonb; v_arms jsonb[] := '{}';
  v_equal boolean; v_verdict jsonb;
  v_complete boolean; v_outcome text;
  v_scen_depot uuid;
BEGIN
  /* 0175: THE PAIR AND THE SCENARIO MUST NAME THE SAME WORLD.
     p_depot drives the fleet reset and both fingerprints; the run row's
     depot comes from the scenario (twin.ottoq_sim_start_run reads
     v_scenario.depot_id). Nothing made them agree, so a pair could reset
     and fingerprint depot A while ticking depot B and never say so.
     Refused before either arm is created, so a mismatch costs nothing
     and this guard can never alter a canon. */
  SELECT s.depot_id INTO v_scen_depot
    FROM public.ottoq_scenarios s
   WHERE s.scenario_code = p_scenario AND s.status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'determinism_pair: no active scenario %', p_scenario
      USING ERRCODE = 'P0001';
  END IF;
  IF v_scen_depot IS DISTINCT FROM p_depot THEN
    RAISE EXCEPTION 'determinism_pair: scenario % is bound to depot %, but the pair was told to run depot %. The arms would tick one world and be fingerprinted against another.',
      p_scenario, COALESCE(v_scen_depot::text, '(none)'), p_depot
      USING ERRCODE = 'P0001';
  END IF;

  FOR v_arm IN 1..2 LOOP
    PERFORM public.ottoq_tick_invariance_reset_fleet(p_depot, p_seed, p_sim_start);
    v_run := twin.ottoq_sim_start_run(p_scenario, p_sim_start, 60, p_seed, 'cert_harness');
    /* 0152: a certification arm runs the deterministic core alone. Run-scoped, so a
       later global re-enable of the proposer cannot reach inside a cert (0056). */
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
    VALUES ('run', v_run, 'cuopt_propose_enabled', 0, '0152_cert_quiesce'),
           ('run', v_run, 'cuopt_first_refusal_max_defers', 0, '0152_cert_quiesce')
    ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = 0, updated_by = '0152_cert_quiesce';
    BEGIN PERFORM twin.ottoq_sim_prime_deployment(v_run, p_sim_start, 0.70);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'determinism_pair arm % prime failed: %', v_arm, SQLERRM; END;

    -- 0125: the boot image, captured before the first tick. Diagnostic, not verdict.
    v_boot := public.ottoq_boot_state_fingerprint(p_depot, v_run);

    v_t0 := clock_timestamp();
    LOOP
      SELECT sim_clock_current, status, tick_count INTO v_clock, v_status, v_ticks
        FROM ottoq_sim_runs WHERE sim_run_id = v_run;
      EXIT WHEN v_status <> 'running' OR v_ticks >= p_ticks;
      EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) >= p_arm_budget_s;
      PERFORM public.ottoq_sim_advance_tick(v_run);
    END LOOP;

    SELECT jsonb_build_object(
      'run', v_run, 'ticks', r.tick_count, 'clock', r.sim_clock_current,
      'complete', (r.tick_count >= p_ticks),
      'fp', r.payload->>'world_fingerprint',
      'boot', v_boot,
      'endst', public.ottoq_boot_state_fingerprint(p_depot, v_run),
      'h_cmd', (SELECT md5(COALESCE(string_agg(
          issued_at::text||'|'||vehicle_id::text||'|'||command_type||'|'||COALESCE(payload->>'stall_id','-')||'|'||status||'|'||COALESCE(reason_code,'-'),
          E'\n' ORDER BY issued_at, vehicle_id, command_type, COALESCE(payload->>'stall_id','-'), status, COALESCE(reason_code,'-')), ''))
        FROM ottoq_vehicle_commands c WHERE c.sim_run_id = v_run),
      'h_dec', (SELECT md5(COALESCE(string_agg(
          sim_clock::text||'|'||tick_seq::text||'|'||action_context||'|'||entity_id::text||'|'||outcome_status
          ||'|'||COALESCE(enacted_action->>'verb', proposed_action->>'verb','-')||'|'||COALESCE(proposed_action->>'stall_id','-'),
          E'\n' ORDER BY sim_clock, tick_seq, action_context, entity_id, outcome_status,
                        COALESCE(enacted_action->>'verb', proposed_action->>'verb','-'), COALESCE(proposed_action->>'stall_id','-')), ''))
        FROM ottoq_decisions d WHERE d.sim_run_id = v_run),
      'h_evt', (SELECT md5(COALESCE(string_agg(
          event_type||'|'||CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                                THEN '-' ELSE COALESCE(entity_id::text,'-') END,
          E'\n' ORDER BY event_type,
                        CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                             THEN '-' ELSE COALESCE(entity_id::text,'-') END), ''))
        FROM ottoq_events e WHERE e.sim_run_id = v_run),
      'h_bkg', (SELECT md5(COALESCE(string_agg(
          lower(during)::text||'|'||upper(during)::text||'|'||vehicle_id::text||'|'||stall_id::text||'|'||purpose||'|'||state,
          E'\n' ORDER BY lower(during), upper(during), vehicle_id, stall_id, purpose, state), ''))
        FROM ottoq_stall_bookings k WHERE k.sim_run_id = v_run),
      'h_nrg', (SELECT md5(COALESCE(string_agg(
          COALESCE(c.tick_seq::text,'-')||'|'||c.command_type||'|'||COALESCE(c.source,'-')
          ||'|'||COALESCE(c.setpoint_kw::text,'-')||'|'||COALESCE(c.horizon_min::text,'-')
          ||'|'||to_char(c.issued_at AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US')
          ||'|'||COALESCE(c.reason::text,'-'),
          E'\n' ORDER BY c.tick_seq, c.command_type, COALESCE(c.source,'-'), c.setpoint_kw, c.horizon_min, c.issued_at, c.reason::text), ''))
        FROM ottoq_energy_commands c WHERE c.sim_run_id = v_run),
      /* 0199: the proposal stream and the deferral ledger. Agents propose;
         the verdict must see what they proposed, or "solver disposes" is
         an assertion rather than a measurement. */
      'h_prop', public.ottoq_hash_proposals(v_run),
      'h_defr', public.ottoq_hash_deferrals(v_run),
      /* 0201: the priors this arm booted on. Two arms on different priors
         are two different worlds, and the verdict says so. */
      'h_cal', v_boot->'calibration'->>'h')
      INTO v_h
      FROM ottoq_sim_runs r WHERE r.sim_run_id = v_run;
    v_arms := v_arms || v_h;

    PERFORM public.ottoq_sim_stop_and_reset(v_run, 'determinism_arm_complete');
  END LOOP;

  v_equal := (v_arms[1]->>'fp')    = (v_arms[2]->>'fp')
         AND (v_arms[1]->>'h_cmd') = (v_arms[2]->>'h_cmd')
         AND (v_arms[1]->>'h_dec') = (v_arms[2]->>'h_dec')
         AND (v_arms[1]->>'h_evt') = (v_arms[2]->>'h_evt')
         AND (v_arms[1]->>'h_bkg') = (v_arms[2]->>'h_bkg')
         AND (v_arms[1]->>'h_nrg') = (v_arms[2]->>'h_nrg')
         AND (v_arms[1]->>'h_prop') = (v_arms[2]->>'h_prop')   -- 0199
         AND (v_arms[1]->>'h_defr') = (v_arms[2]->>'h_defr')   -- 0199
         AND (v_arms[1]->>'h_cal')  = (v_arms[2]->>'h_cal')    -- 0201
         AND (v_arms[1]->>'ticks') = (v_arms[2]->>'ticks')
         AND (v_arms[1]->'endst')  = (v_arms[2]->'endst');

  v_complete := COALESCE((v_arms[1]->>'complete')::boolean, false)
            AND COALESCE((v_arms[2]->>'complete')::boolean, false);

  v_outcome := CASE WHEN NOT v_complete THEN 'inconclusive'
                    WHEN v_equal        THEN 'passed'
                    ELSE                     'failed' END;

  v_verdict := jsonb_build_object(
    'equal', v_equal, 'outcome', v_outcome, 'complete', v_complete,
    'seed', p_seed, 'ticks', p_ticks, 'scenario', p_scenario,
    'arm_a', v_arms[1], 'arm_b', v_arms[2]);

  -- The verdict survives a dropped client: it lives on both run rows.
  UPDATE ottoq_sim_runs
     SET validation_status = v_outcome,
         validation_notes  = v_verdict::text
   WHERE sim_run_id IN ((v_arms[1]->>'run')::uuid, (v_arms[2]->>'run')::uuid);

  RETURN v_verdict;
END
$function$;

-- ---------------------------------------------------------------------
-- 2c. The matrix carries canon_cal (appended; pre-0201 verdicts are NULL
--     and neither on nor off it).
-- ---------------------------------------------------------------------
DROP FUNCTION public.ottoq_cert_matrix(timestamp with time zone);
CREATE FUNCTION public.ottoq_cert_matrix(p_since timestamp with time zone DEFAULT (now() - '30 days'::interval))
 RETURNS TABLE(depot uuid, seed bigint, ticks integer, scenario text, pairs_seen integer, consecutive_passes integer, green boolean, last_pair_at timestamp with time zone, canon_fp text, canon_cmd text, canon_dec text, canon_evt text, canon_bkg text, canon_nrg text, last_run_a uuid, last_run_b uuid, history text, stale boolean, recert_floor timestamp with time zone, inconclusive_pairs integer, canon_prop text, canon_defr text, canon_cal text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $function$
WITH fl AS (
  SELECT public.ottoq_cert_recert_floor() AS rf
), pair AS (
  SELECT DISTINCT ON (r.depot_id, r.started_at)
         r.depot_id                              AS c_depot,
         r.started_at                            AS t0,
         r.validation_status                     AS st,
         (r.validation_status = 'passed')        AS ok,
         (r.validation_notes::jsonb)             AS j
    FROM public.ottoq_sim_runs r
   WHERE r.run_by = 'cert_harness'
     AND r.started_at >= p_since
     AND r.validation_status IS NOT NULL
     AND r.validation_notes IS NOT NULL
     AND jsonb_typeof((r.validation_notes::jsonb) -> 'arm_a') = 'object'
   ORDER BY r.depot_id, r.started_at, r.sim_run_id
), keyed AS (
  SELECT p.c_depot, p.t0, p.ok, p.st,
         (p.j->>'seed')::bigint                    AS c_seed,
         COALESCE((p.j->>'ticks')::int, -1)        AS c_ticks,
         COALESCE(p.j->>'scenario', '?')           AS c_scen,
         p.j->'arm_a'->>'fp'                       AS c_fp,
         p.j->'arm_a'->>'h_cmd'                    AS c_cmd,
         p.j->'arm_a'->>'h_dec'                    AS c_dec,
         p.j->'arm_a'->>'h_evt'                    AS c_evt,
         p.j->'arm_a'->>'h_bkg'                    AS c_bkg,
         p.j->'arm_a'->>'h_nrg'                    AS c_nrg,
         p.j->'arm_a'->>'h_prop'                   AS c_prop,   -- 0199; NULL before 0199
         p.j->'arm_a'->>'h_defr'                   AS c_defr,   -- 0199; NULL before 0199
         p.j->'arm_a'->>'h_cal'                    AS c_cal,    -- 0201; NULL before 0201
         (p.j->'arm_a'->>'run')::uuid              AS c_run_a,
         (p.j->'arm_b'->>'run')::uuid              AS c_run_b
    FROM pair p
), inc AS (
  SELECT c_depot, c_seed, c_ticks, c_scen, count(*)::int AS n_inc
    FROM keyed WHERE st = 'inconclusive'
   GROUP BY c_depot, c_seed, c_ticks, c_scen
), col AS (
  SELECT * FROM keyed WHERE st <> 'inconclusive'
), ranked AS (
  SELECT c.*, row_number() OVER (PARTITION BY c.c_depot, c.c_seed, c.c_ticks, c.c_scen
                                 ORDER BY c.t0 DESC, c.c_run_a DESC) AS rn
    FROM col c
), canon AS (
  SELECT rk.c_depot, rk.c_seed, rk.c_ticks, rk.c_scen,
         rk.c_fp, rk.c_cmd, rk.c_dec, rk.c_evt, rk.c_bkg, rk.c_nrg, rk.c_prop, rk.c_defr, rk.c_cal
    FROM ranked rk WHERE rk.rn = 1
), marked AS (
  SELECT r.c_depot, r.c_seed, r.c_ticks, r.c_scen, r.rn,
         (r.ok
          AND r.t0 >= fl.rf
          AND r.c_fp  IS NOT DISTINCT FROM k.c_fp
          AND r.c_cmd IS NOT DISTINCT FROM k.c_cmd
          AND r.c_dec IS NOT DISTINCT FROM k.c_dec
          AND r.c_evt IS NOT DISTINCT FROM k.c_evt
          AND r.c_bkg IS NOT DISTINCT FROM k.c_bkg
          AND r.c_nrg IS NOT DISTINCT FROM k.c_nrg
          -- 0199: a pair hashed before the instrument existed cannot be judged by it
          AND (r.c_prop IS NULL OR k.c_prop IS NULL OR r.c_prop = k.c_prop)
          AND (r.c_defr IS NULL OR k.c_defr IS NULL OR r.c_defr = k.c_defr)
          -- 0201: same rule for the priors fingerprint
          AND (r.c_cal  IS NULL OR k.c_cal  IS NULL OR r.c_cal  = k.c_cal)) AS on_canon
    FROM ranked r
    JOIN canon k ON k.c_depot = r.c_depot AND k.c_seed = r.c_seed
                AND k.c_ticks = r.c_ticks AND k.c_scen = r.c_scen
    CROSS JOIN fl
), streak AS (
  SELECT x.c_depot, x.c_seed, x.c_ticks, x.c_scen,
         count(*) FILTER (WHERE x.unbroken)::int AS n_pass
    FROM (
      SELECT m.c_depot, m.c_seed, m.c_ticks, m.c_scen,
             bool_and(m.on_canon) OVER (PARTITION BY m.c_depot, m.c_seed, m.c_ticks, m.c_scen
                                        ORDER BY m.rn
                                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS unbroken
        FROM marked m
    ) x
   GROUP BY x.c_depot, x.c_seed, x.c_ticks, x.c_scen
), hist AS (
  SELECT c.c_depot, c.c_seed, c.c_ticks, c.c_scen,
         string_agg(CASE WHEN c.ok THEN 'P' ELSE 'f' END, '' ORDER BY c.t0) AS h_hist,
         count(*)::int AS n_pairs
    FROM col c GROUP BY c.c_depot, c.c_seed, c.c_ticks, c.c_scen
)
SELECT h.c_depot, h.c_seed, h.c_ticks, h.c_scen, h.n_pairs,
       COALESCE(s.n_pass, 0),
       (COALESCE(s.n_pass, 0) >= 2 AND l.t0 >= fl.rf),
       l.t0, l.c_fp, l.c_cmd, l.c_dec, l.c_evt, l.c_bkg, l.c_nrg, l.c_run_a, l.c_run_b,
       h.h_hist,
       (l.t0 < fl.rf),
       fl.rf,
       COALESCE(i.n_inc, 0),
       l.c_prop, l.c_defr, l.c_cal
  FROM hist h
  JOIN streak s ON s.c_depot = h.c_depot AND s.c_seed = h.c_seed AND s.c_ticks = h.c_ticks AND s.c_scen = h.c_scen
  JOIN ranked l ON l.c_depot = h.c_depot AND l.c_seed = h.c_seed AND l.c_ticks = h.c_ticks
               AND l.c_scen = h.c_scen AND l.rn = 1
  LEFT JOIN inc i ON i.c_depot = h.c_depot AND i.c_seed = h.c_seed AND i.c_ticks = h.c_ticks AND i.c_scen = h.c_scen
  CROSS JOIN fl
 ORDER BY h.c_depot, h.c_ticks DESC, h.c_scen, h.c_seed;
$function$;

-- ---------------------------------------------------------------------
-- 3. The ingest waits for the certification, never the other way round.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_twin_ingest_refresh()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_anon text; v_eia text; v_noaa text;
  base text := 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-twin-ingest';
BEGIN
  /* 0201. A refit moves the priors the twin draws from. It must never land
     under a certification round (db/checks/0115: round 19, 04:05:25 UTC).
     A round is "in progress" from the moment its first job is scheduled
     (jobs are named r<N>_...) until the last pair's backend has finished. */
  IF EXISTS (SELECT 1 FROM cron.job j WHERE j.jobname ~ '^r[0-9]+_')
     OR EXISTS (SELECT 1 FROM pg_stat_activity a
                 WHERE a.query ILIKE '%ottoq_determinism_pair%' AND a.pid <> pg_backend_pid() AND a.state <> 'idle') THEN
    RAISE WARNING 'twin_ingest_refresh: deferred -- a certification round is scheduled or in flight (0201)';
    RETURN;
  END IF;

  SELECT decrypted_secret INTO v_anon FROM vault.decrypted_secrets WHERE name='ottoq_anon_key' LIMIT 1;
  SELECT decrypted_secret INTO v_eia  FROM vault.decrypted_secrets WHERE name='eia_api_key'    LIMIT 1;
  SELECT decrypted_secret INTO v_noaa FROM vault.decrypted_secrets WHERE name='noaa_cdo_token' LIMIT 1;
  IF v_anon IS NULL THEN RAISE WARNING 'twin_ingest_refresh: anon key missing from vault'; RETURN; END IF;

  IF v_eia IS NOT NULL THEN
    PERFORM net.http_post(url := base,
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_anon,'apikey',v_anon),
      body := jsonb_build_object('source','eia','eia_key',v_eia), timeout_milliseconds := 120000);
  END IF;
  IF v_noaa IS NOT NULL THEN
    PERFORM net.http_post(url := base,
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_anon,'apikey',v_anon),
      body := jsonb_build_object('source','noaa','noaa_token',v_noaa), timeout_milliseconds := 120000);
  END IF;
END $function$;

-- =====================================================================
-- ASSERTIONS
-- =====================================================================
DO $assert$
DECLARE
  v_changed text[]; v_new text[]; v_n int; v_src text;
  v_fp1 text; v_fp2 text; v_fp3 text; v_boot jsonb; v_run uuid;
  v_q_before bigint; v_q_after bigint; v_msg text;
BEGIN
  -- ── A0. THE PIN. Four harness bodies changed, one new, nothing else.
  SELECT array_agg(a.sig ORDER BY a.sig) INTO v_changed
    FROM pin_0201 a
    JOIN (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
                 md5(pg_get_functiondef(p.oid)) AS h
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b USING (sig)
   WHERE a.h <> b.h;
  IF v_changed IS DISTINCT FROM ARRAY[
       'public.ottoq_boot_state_fingerprint(p_depot uuid, p_run uuid)',
       'public.ottoq_cert_matrix(p_since timestamp with time zone)',
       'public.ottoq_determinism_pair(p_seed bigint, p_ticks integer, p_scenario text, p_depot uuid, p_sim_start timestamp with time zone, p_arm_budget_s integer)',
       'public.ottoq_twin_ingest_refresh()'] THEN
    RAISE EXCEPTION '0201 A0 FAILED: function bodies changed = %', v_changed;
  END IF;
  SELECT array_agg(b.sig ORDER BY b.sig) INTO v_new
    FROM (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b
    LEFT JOIN pin_0201 a USING (sig)
   WHERE a.sig IS NULL;
  IF v_new IS DISTINCT FROM ARRAY['public.ottoq_calibration_fingerprint()'] THEN
    RAISE EXCEPTION '0201 A0 FAILED: new functions = %', v_new;
  END IF;
  RAISE NOTICE '0201 A0: four harness bodies changed, one fingerprint function new';

  -- ── A1. The fingerprint is stable, content-sensitive, and equals the value
  --     measured when this file was written (15:35 UTC 09-06, after the 04:05
  --     refit). A different value here means the priors moved again since.
  v_fp1 := public.ottoq_calibration_fingerprint();
  v_fp2 := public.ottoq_calibration_fingerprint();
  IF v_fp1 IS NULL OR v_fp1 <> v_fp2 THEN RAISE EXCEPTION '0201 A1 FAILED: fingerprint unstable or NULL (% / %)', v_fp1, v_fp2; END IF;
  IF v_fp1 <> '11a246262ff7a2c929483b1ee0a7cd2d' THEN
    RAISE EXCEPTION '0201 A1 FAILED: fingerprint % != 11a246262ff7a2c929483b1ee0a7cd2d measured at write time -- the priors moved again; re-measure before applying', v_fp1;
  END IF;
  BEGIN
    UPDATE public.ottoq_calibration_distributions
       SET quantile_grid[1] = quantile_grid[1] + 1
     WHERE variable_name = 'ambient_temp_c' AND segment = 'global';
    IF NOT FOUND THEN RAISE EXCEPTION '0201 A1 FIXTURE: no ambient_temp_c/global distribution'; END IF;
    v_fp3 := public.ottoq_calibration_fingerprint();
    RAISE EXCEPTION USING ERRCODE = 'P0201', MESSAGE = v_fp3;
  EXCEPTION WHEN SQLSTATE 'P0201' THEN v_fp3 := SQLERRM;
  END;
  IF v_fp3 = v_fp1 THEN RAISE EXCEPTION '0201 A1 FAILED: editing a quantile grid did not move the fingerprint'; END IF;
  IF public.ottoq_calibration_fingerprint() <> v_fp1 THEN RAISE EXCEPTION '0201 A1 FAILED: the probe edit leaked'; END IF;
  RAISE NOTICE '0201 A1: fingerprint % stable, moves on a one-degree edit (% rolled back)', left(v_fp1,8), left(v_fp3,8);

  -- ── A2. The boot image carries it, on the flagship, on a real run.
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'completed'
   ORDER BY started_at DESC, sim_run_id DESC LIMIT 1;
  v_boot := public.ottoq_boot_state_fingerprint('11111111-1111-1111-1111-111111111111', v_run);
  IF v_boot->'calibration'->>'h' IS DISTINCT FROM v_fp1 THEN
    RAISE EXCEPTION '0201 A2 FAILED: boot image calibration.h = %, expected %', v_boot->'calibration'->>'h', v_fp1;
  END IF;
  IF NOT (v_boot ? 'chargers' AND v_boot ? 'visit_needs' AND v_boot ? 'bookings' AND v_boot ? 'legs' AND v_boot ? 'dispatches') THEN
    RAISE EXCEPTION '0201 A2 FAILED: boot image lost a key: %', (SELECT string_agg(k, ',') FROM jsonb_object_keys(v_boot) k);
  END IF;
  RAISE NOTICE '0201 A2: boot image carries calibration.h = %', left(v_fp1,8);

  -- ── A3. The pair copies it and its equality hears it.
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'public.ottoq_determinism_pair'::regproc;
  IF v_src !~ $q$'h_cal', v_boot->'calibration'->>'h'$q$
     OR v_src !~ $q$\(v_arms\[1\]->>'h_cal'\)\s*=\s*\(v_arms\[2\]->>'h_cal'\)$q$ THEN
    RAISE EXCEPTION '0201 A3 FAILED: the pair does not carry h_cal into the arm AND the equality';
  END IF;
  RAISE NOTICE '0201 A3: h_cal is in the arm object and in v_equal';

  -- ── A4. THE GUARD, LIVE AND ROLLED BACK: with a certification job scheduled the
  --     ingest posts nothing. The probe job is scheduled and the whole block rolls
  --     back; the queue is counted before and after.
  BEGIN
    PERFORM cron.schedule('r99_probe_0201', '0 0 1 1 *', 'SELECT 1');
    SELECT count(*) INTO v_q_before FROM net.http_request_queue;
    PERFORM public.ottoq_twin_ingest_refresh();
    SELECT count(*) INTO v_q_after FROM net.http_request_queue;
    RAISE EXCEPTION USING ERRCODE = 'P0201', MESSAGE = v_q_before::text || '|' || v_q_after::text;
  EXCEPTION WHEN SQLSTATE 'P0201' THEN v_msg := SQLERRM;
  END;
  IF split_part(v_msg, '|', 1) <> split_part(v_msg, '|', 2) THEN
    RAISE EXCEPTION '0201 A4 FAILED: the ingest posted with a certification job scheduled (queue % -> %)', split_part(v_msg,'|',1), split_part(v_msg,'|',2);
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'r99_probe_0201') THEN
    RAISE EXCEPTION '0201 A4 FAILED: the probe job survived the rollback';
  END IF;
  -- and structurally: the guard precedes the first vault read
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'public.ottoq_twin_ingest_refresh()'::regprocedure;
  IF position('certification round is scheduled' in v_src) = 0
     OR position('certification round is scheduled' in v_src) > position('vault.decrypted_secrets' in v_src) THEN
    RAISE EXCEPTION '0201 A4 FAILED: the guard is missing or sits after the vault read';
  END IF;
  RAISE NOTICE '0201 A4: ingest deferred under a scheduled certification job; nothing queued; probe job rolled back';

  -- ── A5. Privileges preserved across the matrix recreate and the ingest replace.
  IF (SELECT m_anon FROM pre_0201) IS DISTINCT FROM has_function_privilege('anon',          'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE')
     OR (SELECT m_auth FROM pre_0201) IS DISTINCT FROM has_function_privilege('authenticated', 'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE')
     OR (SELECT m_svc FROM pre_0201) IS DISTINCT FROM has_function_privilege('service_role',  'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION '0201 A5 FAILED: ottoq_cert_matrix execute privileges changed across the recreate';
  END IF;
  IF (SELECT ingest_acl FROM pre_0201) IS DISTINCT FROM (SELECT proacl::text FROM pg_proc WHERE oid = 'public.ottoq_twin_ingest_refresh()'::regprocedure) THEN
    RAISE EXCEPTION '0201 A5 FAILED: ottoq_twin_ingest_refresh acl changed';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_calibration_fingerprint()', 'EXECUTE') AND
     (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_calibration_fingerprint()'::regprocedure) THEN
    RAISE EXCEPTION '0201 A5 FAILED: the fingerprint function must not be SECURITY DEFINER with anon execute';
  END IF;
  -- the matrix still answers, with the new column
  SELECT count(*) INTO v_n FROM public.ottoq_cert_matrix(public.ottoq_cert_recert_floor()) m
   WHERE m.depot = '11111111-1111-1111-1111-111111111111' AND m.canon_cal IS NULL;
  IF v_n <> 6 THEN RAISE EXCEPTION '0201 A5 FAILED: expected six flagship columns with canon_cal NULL (pre-instrument), got %', v_n; END IF;
  RAISE NOTICE '0201 A5: privileges preserved; matrix answers with canon_cal (NULL until a pair carries it)';

  RAISE NOTICE '0201: all assertions passed';
END $assert$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0201_the_priors_are_part_of_the_world_and_the_verdict_now_names_them', FALSE,
  'G14 (db/checks/0115). Round 19: the weekly calibration ingest ran at 04:05:25 UTC between pair 2 and pair 3 and refit the NOAA '
  'temperature/precipitation and EIA grid-demand grids the twin draws from; pairs before it reproduced round 18 to the byte, pairs after '
  'it all passed and all moved, and the instrument could not say why because the priors are not in the reproducibility key. '
  'Moves: (1) ottoq_calibration_fingerprint() = md5 over the content of the four calibration tables (no timestamps); (2) it rides in '
  'the boot image (calibration.h), in each arm as h_cal (in v_equal: two arms on different priors is a failed pair), and in '
  'ottoq_cert_matrix as canon_cal (NULL-lenient for older verdicts); (3) ottoq_twin_ingest_refresh refuses to post while a '
  'certification job (r<N>_*) is scheduled or a pair is in flight. A0 pins every body: four harness functions changed, one new, no '
  'engine function touched. A1 fingerprint stable and moves on a one-degree grid edit (rolled back); A4 the guard, live, posts nothing '
  'with a probe job scheduled. forces_recert FALSE: nothing the engine executes changed. Versioning the datasets and pinning the '
  'version on the run row remains open (G14 c).',
  now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

COMMIT;

-- =====================================================================
-- APPLIED 2026-09-06 15:40:59 UTC (10:40 AM CT) -- one transaction as
-- postgres, first attempt. The SQL endpoint's client timed out at 60 s
-- while the transaction was still running (A2 hashes the flagship's
-- 78k visit rows through the boot image); the transaction completed and
-- committed on the server. Verified after the fact, at 15:42 UTC:
--
--   lineage row                       present, 15:40:59.42
--   ottoq_calibration_fingerprint()   present; value 11a246262ff7a2c929483b1ee0a7cd2d
--                                     (the post-refit priors; A1 pinned it)
--   ottoq_cert_matrix                 returns canon_cal
--   ottoq_determinism_pair            carries h_cal in the arm and in v_equal
--   ottoq_twin_ingest_refresh         carries the guard ahead of the vault read
--   r99_probe_0201 cron job           absent (A4 rolled back)
--   probe grid edit                   absent (fingerprint unchanged)
--
-- Every A-notice is invisible through the endpoint; the checks above are
-- the record. Lesson for the next apply: anything that may run past 60 s
-- goes through a one-shot pg_cron job and is read from the ledger.
--
-- From round 20 on every arm carries h_cal; the first pair after this
-- migration writes the first canon_cal. The ingest job stays on its
-- Sunday 04:00 UTC schedule and now stands down under a certification.
-- =====================================================================
