-- =====================================================================
-- 0199  The verdict hears the proposers, and the floor hears every
--       recert
-- =====================================================================
-- forces_recert = FALSE. Three harness functions change and two are
-- new; no decide-path function is touched (A0 pins every body). What a
-- certified pair MEANS gets stricter, and the retro-check below shows
-- every pair at the current floor already meets the stricter meaning.
--
-- PART 1 -- G4: h_prop and h_defr (the proposal stream in the verdict)
-- ---------------------------------------------------------------------
-- "Agents propose, solver disposes" is only provable if the verdict can
-- see what was proposed. It could not. The pair hashed commands,
-- decisions, events, bookings and energy commands, and never the
-- ottoq_external_proposals rows or the ottoq_cuopt_deferrals rows. The
-- proposer quiesce (0152) covers cuOpt only: the two internal proposers,
-- greedy_constrained and ottoq_service_priority, write two to six
-- proposals into every certification arm today, and nothing checked
-- that both arms got the same ones.
--
-- Measured before changing anything (every pair since 2026-09-01 with
-- both arm rows still present, the hash below computed retroactively):
--
--   day        pairs  passed  prop_eq  defr_eq  disagreeing
--   09-01        59      41       57       59   15:10 busy_day/424242/12t
--                                                PASSED with 4 vs 3 proposals
--   09-02        37      37       37       37
--   09-03        50      50       50       50
--   09-04        22      18       19       22   three, all already FAILED
--   09-05        21      21       21       21
--
-- The 15:10 pair on Sep 1 is the finding: the verdict said passed while
-- arm A carried two greedy_constrained proposals and arm B one. It
-- predates the proposer quiesce (0152, Sep 2 12:13) and the recert
-- floor, so no standing certificate rests on it -- but the instrument
-- that let it pass is the instrument in use today. Since the floor: 58
-- passed pairs at the old floor, 7 at the corrected one, zero
-- disagreements on either stream. That is why forces_recert is FALSE:
-- the stricter verdict, applied to the same rows the pairs hashed,
-- changes no outcome inside the certified window.
--
-- The two hashes live in named functions so the pair, the assertions
-- and every future check compute exactly one definition:
--   ottoq_hash_proposals(run)  content multiset of the run's proposals:
--                              action_context, entity_type, entity_id,
--                              source, declared_source, status, payload.
--                              proposal_id, created_at and expires_at
--                              are wall-clock or random and excluded;
--                              payload keys were censused across all
--                              three proposers (13,948 rows) and carry
--                              no timestamp or request id.
--   ottoq_hash_deferrals(run)  vehicle_id, state, armed_at_tick,
--                              armed_at_sim, spent_at_tick,
--                              cleared_at_tick, defer_count.
--                              armed_at_real and net_request_id are
--                              wall-clock / pg_net and excluded.
-- Every nullable field is COALESCEd: a NULL inside a concatenation
-- makes the whole row NULL and string_agg silently drops it.
--
-- PART 2 -- the recert floor was stale
-- ---------------------------------------------------------------------
-- ottoq_cert_recert_floor() reads supabase_migrations.schema_migrations
-- and treats an unclassified migration as forces_recert. Migrations
-- 0192 through 0197 -- all six classified forces_recert = TRUE in
-- ottoq_cert_lineage, applied 2026-09-04 15:00 through 2026-09-05 17:36
-- UTC -- went in through the SQL endpoint and never received a
-- schema_migrations row. The floor stayed at 2026-09-03 17:16:37 (the
-- watermark sweep) through six recerts. The streak arithmetic survived
-- by accident: five of the six moved a canon, which breaks the streak
-- at that pair anyway. 0197 did not move a canon, so round 16 and 17
-- pairs kept counting toward "green" after a decide-path change that
-- should have restarted the count. Round 18 was the first round after
-- 0197; round 19 is the second and is what "green" needs.
--
-- Fix: the floor is the later of the schema_migrations-derived value
-- and max(classified_at) over lineage rows with forces_recert. After
-- this migration the floor reads 2026-09-05 17:36:10 (0197's apply).
--
-- Consequence, stated plainly: db/checks/0113 declared Part A MET on
-- rounds 16 and 17 at a floor of Sep 3. The values it cites are right
-- and unchanged (round 18 reproduced every one of them). The green
-- flag at the corrected floor needs two consecutive passes after 0197:
-- round 18 is one; round 19, scheduled the moment this applies, is the
-- other. A correction is appended to 0113, not written over it.
--
-- PART 3 -- the matrix carries the two new canons
-- ---------------------------------------------------------------------
-- ottoq_cert_matrix gains canon_prop and canon_defr (appended, so every
-- SELECT * and every named-column reader keeps working) and compares
-- them across pairs on the canon. A verdict written before this
-- migration has no h_prop; such a pair is neither on nor off the
-- proposal canon and is not knocked off by it. Pairs from here on are
-- held to it. RETURNS TABLE cannot be altered in place, so the function
-- is dropped and recreated; it has no dependents (pg_depend, verified)
-- and is not SECURITY DEFINER, so 0198's posture is unaffected. Its
-- execute privileges are asserted equal for anon, authenticated and
-- service_role before and after.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Pin every function body and the pre-state we will compare against.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE pin_0199 ON COMMIT DROP AS
SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
       md5(pg_get_functiondef(p.oid)) AS h
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p');

CREATE TEMP TABLE pre_0199 ON COMMIT DROP AS
SELECT public.ottoq_cert_recert_floor() AS old_floor,
       has_function_privilege('anon',          'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE') AS m_anon,
       has_function_privilege('authenticated', 'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE') AS m_auth,
       has_function_privilege('service_role',  'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE') AS m_svc;

-- ---------------------------------------------------------------------
-- 1. The two hash definitions. One place, used by the pair, the
--    assertions below, and every check that follows.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_hash_proposals(p_run uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $function$
  -- 0199. The run's proposal stream as a content multiset. Order is by
  -- content, not by arrival: created_at is a wall clock. Every nullable
  -- field is COALESCEd so a NULL cannot drop a row from the hash.
  SELECT md5(COALESCE(string_agg(
           COALESCE(p.action_context,'-') || '|' || COALESCE(p.entity_type,'-') || '|' || COALESCE(p.entity_id::text,'-')
           || '|' || COALESCE(p.source,'-') || '|' || COALESCE(p.declared_source,'-') || '|' || COALESCE(p.status,'-')
           || '|' || COALESCE(p.proposal::text,'-'),
           E'\n' ORDER BY COALESCE(p.action_context,'-'), COALESCE(p.entity_type,'-'), COALESCE(p.entity_id::text,'-'),
                          COALESCE(p.source,'-'), COALESCE(p.declared_source,'-'), COALESCE(p.status,'-'),
                          COALESCE(p.proposal::text,'-')), ''))
    FROM public.ottoq_external_proposals p
   WHERE p.sim_run_id = p_run;
$function$;
COMMENT ON FUNCTION public.ottoq_hash_proposals(uuid) IS
  '0199: md5 over the run''s ottoq_external_proposals as a content multiset (action_context, entity_type, entity_id, source, declared_source, status, proposal). Excludes proposal_id, created_at, expires_at. This is h_prop in the pair verdict.';

CREATE OR REPLACE FUNCTION public.ottoq_hash_deferrals(p_run uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $function$
  -- 0199. The run's cuOpt deferral ledger. One row per (run, vehicle).
  -- armed_at_real and net_request_id are wall clock and pg_net, excluded.
  SELECT md5(COALESCE(string_agg(
           d.vehicle_id::text || '|' || COALESCE(d.state,'-') || '|' || COALESCE(d.armed_at_tick::text,'-')
           || '|' || COALESCE(to_char(d.armed_at_sim AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'),'-')
           || '|' || COALESCE(d.spent_at_tick::text,'-') || '|' || COALESCE(d.cleared_at_tick::text,'-')
           || '|' || COALESCE(d.defer_count::text,'-'),
           E'\n' ORDER BY d.vehicle_id, COALESCE(d.state,'-'), d.armed_at_tick, d.armed_at_sim,
                          d.spent_at_tick, d.cleared_at_tick, d.defer_count), ''))
    FROM public.ottoq_cuopt_deferrals d
   WHERE d.sim_run_id = p_run;
$function$;
COMMENT ON FUNCTION public.ottoq_hash_deferrals(uuid) IS
  '0199: md5 over the run''s ottoq_cuopt_deferrals (vehicle_id, state, armed_at_tick, armed_at_sim, spent_at_tick, cleared_at_tick, defer_count). Excludes armed_at_real, net_request_id. This is h_defr in the pair verdict.';

-- ---------------------------------------------------------------------
-- 2. The pair: two more hashes in each arm, two more terms in equality.
--    Everything else is byte-for-byte the 0196 body.
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
      'h_defr', public.ottoq_hash_deferrals(v_run))
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
-- 3. The floor: the later of what schema_migrations says and what the
--    lineage says. A recert applied through the SQL endpoint now counts.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_cert_recert_floor()
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'supabase_migrations', 'extensions'
AS $function$
  SELECT GREATEST(
    -- migrations registered by the CLI/apply_migration path; an unclassified one forces recert
    (SELECT max(make_timestamptz(
              substr(m.version,1,4)::int,  substr(m.version,5,2)::int,
              substr(m.version,7,2)::int,  substr(m.version,9,2)::int,
              substr(m.version,11,2)::int, substr(m.version,13,2)::numeric, 'UTC'))
       FROM supabase_migrations.schema_migrations m
       LEFT JOIN public.ottoq_cert_lineage l ON l.name = m.name
      WHERE COALESCE(l.forces_recert, true)
        AND m.version ~ '^[0-9]{14}$'),
    -- 0199: migrations applied through the SQL endpoint have no schema_migrations
    -- row; their lineage classification is the only record and it must count.
    (SELECT max(l.classified_at)
       FROM public.ottoq_cert_lineage l
      WHERE l.forces_recert));
$function$;

-- ---------------------------------------------------------------------
-- 4. The matrix: canon_prop and canon_defr appended; pre-0199 verdicts
--    (no h_prop) are neither on nor off the new canons.
-- ---------------------------------------------------------------------
DROP FUNCTION public.ottoq_cert_matrix(timestamp with time zone);
CREATE FUNCTION public.ottoq_cert_matrix(p_since timestamp with time zone DEFAULT (now() - '30 days'::interval))
 RETURNS TABLE(depot uuid, seed bigint, ticks integer, scenario text, pairs_seen integer, consecutive_passes integer, green boolean, last_pair_at timestamp with time zone, canon_fp text, canon_cmd text, canon_dec text, canon_evt text, canon_bkg text, canon_nrg text, last_run_a uuid, last_run_b uuid, history text, stale boolean, recert_floor timestamp with time zone, inconclusive_pairs integer, canon_prop text, canon_defr text)
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
         rk.c_fp, rk.c_cmd, rk.c_dec, rk.c_evt, rk.c_bkg, rk.c_nrg, rk.c_prop, rk.c_defr
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
          AND (r.c_defr IS NULL OR k.c_defr IS NULL OR r.c_defr = k.c_defr)) AS on_canon
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
       l.c_prop, l.c_defr
  FROM hist h
  JOIN streak s ON s.c_depot = h.c_depot AND s.c_seed = h.c_seed AND s.c_ticks = h.c_ticks AND s.c_scen = h.c_scen
  JOIN ranked l ON l.c_depot = h.c_depot AND l.c_seed = h.c_seed AND l.c_ticks = h.c_ticks
               AND l.c_scen = h.c_scen AND l.rn = 1
  LEFT JOIN inc i ON i.c_depot = h.c_depot AND i.c_seed = h.c_seed AND i.c_ticks = h.c_ticks AND i.c_scen = h.c_scen
  CROSS JOIN fl
 ORDER BY h.c_depot, h.c_ticks DESC, h.c_scen, h.c_seed;
$function$;

-- =====================================================================
-- ASSERTIONS
-- =====================================================================
DO $assert$
DECLARE
  v_changed text[]; v_new text[];
  v_old_floor timestamptz; v_new_floor timestamptz; v_lineage_max timestamptz;
  v_src text; v_n int; v_names text;
  v_a uuid; v_b uuid; v_green_cols text; v_green int; v_stale int; v_hashed int;
BEGIN
  -- ── A0. THE PIN. Exactly three harness bodies changed, exactly two new.
  SELECT array_agg(a.sig ORDER BY a.sig) INTO v_changed
    FROM pin_0199 a
    JOIN (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
                 md5(pg_get_functiondef(p.oid)) AS h
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b USING (sig)
   WHERE a.h <> b.h;
  IF v_changed IS DISTINCT FROM ARRAY[
       'public.ottoq_cert_matrix(p_since timestamp with time zone)',
       'public.ottoq_cert_recert_floor()',
       'public.ottoq_determinism_pair(p_seed bigint, p_ticks integer, p_scenario text, p_depot uuid, p_sim_start timestamp with time zone, p_arm_budget_s integer)'] THEN
    RAISE EXCEPTION '0199 A0 FAILED: function bodies changed = % -- only the three harness functions may change', v_changed;
  END IF;
  SELECT array_agg(b.sig ORDER BY b.sig) INTO v_new
    FROM (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b
    LEFT JOIN pin_0199 a USING (sig)
   WHERE a.sig IS NULL;
  IF v_new IS DISTINCT FROM ARRAY['public.ottoq_hash_deferrals(p_run uuid)','public.ottoq_hash_proposals(p_run uuid)'] THEN
    RAISE EXCEPTION '0199 A0 FAILED: new functions = %, expected only the two hash definitions', v_new;
  END IF;
  SELECT count(*) INTO v_n FROM pin_0199 a
   WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                      WHERE n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' = a.sig);
  IF v_n <> 0 THEN RAISE EXCEPTION '0199 A0 FAILED: % function(s) disappeared', v_n; END IF;
  RAISE NOTICE '0199 A0: three harness bodies changed, two hash functions new, nothing else moved, nothing removed';

  -- ── A1. The floor moved to 0197's classification and no further.
  SELECT old_floor INTO v_old_floor FROM pre_0199;
  v_new_floor := public.ottoq_cert_recert_floor();
  SELECT max(classified_at) INTO v_lineage_max FROM public.ottoq_cert_lineage WHERE forces_recert;
  IF v_new_floor IS DISTINCT FROM v_lineage_max THEN
    RAISE EXCEPTION '0199 A1 FAILED: floor % != max forces_recert classified_at %', v_new_floor, v_lineage_max;
  END IF;
  IF v_new_floor <= v_old_floor THEN
    RAISE EXCEPTION '0199 A1 FAILED: floor did not move (old %, new %)', v_old_floor, v_new_floor;
  END IF;
  IF v_lineage_max <> (SELECT classified_at FROM public.ottoq_cert_lineage WHERE name LIKE '0197\_%') THEN
    RAISE EXCEPTION '0199 A1 FAILED: the newest forces_recert row is not 0197 (%)', v_lineage_max;
  END IF;
  RAISE NOTICE '0199 A1: recert floor % -> % (0197 apply)', v_old_floor, v_new_floor;

  -- ── A2. The pair hashes the two streams and its equality hears them.
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'public.ottoq_determinism_pair'::regproc;
  IF v_src !~ $q$'h_prop', public.ottoq_hash_proposals\(v_run\)$q$
     OR v_src !~ $q$'h_defr', public.ottoq_hash_deferrals\(v_run\)$q$
     OR v_src !~ $q$\(v_arms\[1\]->>'h_prop'\) = \(v_arms\[2\]->>'h_prop'\)$q$
     OR v_src !~ $q$\(v_arms\[1\]->>'h_defr'\) = \(v_arms\[2\]->>'h_defr'\)$q$ THEN
    RAISE EXCEPTION '0199 A2 FAILED: the pair does not hash both streams into the arm AND the equality';
  END IF;
  IF public.ottoq_hash_proposals('00000000-0000-4000-8000-000000000000') <> md5('')
     OR public.ottoq_hash_deferrals('00000000-0000-4000-8000-000000000000') <> md5('') THEN
    RAISE EXCEPTION '0199 A2 FAILED: an empty stream must hash to md5 of the empty string';
  END IF;
  RAISE NOTICE '0199 A2: h_prop and h_defr are in the arm object and in v_equal; empty streams hash to %', left(md5(''),8);

  -- ── A3. RETRO-CHECK. (a) At the corrected floor every non-inconclusive pair
  --     with both arm rows present agrees on both streams. (b) The Sep 1 15:10
  --     pair that PASSED with 4 vs 3 proposals is told apart by the new hash --
  --     the instrument can fail, on real rows.
  SELECT count(*), string_agg(to_char(t0,'MM-DD HH24:MI')||' '||col, ', ') INTO v_n, v_names
    FROM (SELECT DISTINCT ON (r.validation_notes) r.started_at t0, r.validation_notes::jsonb vn
            FROM public.ottoq_sim_runs r
           WHERE r.run_by = 'cert_harness' AND r.started_at >= v_new_floor
             AND r.validation_status IN ('passed','failed')
             AND r.validation_notes LIKE '{%equal%') p
    CROSS JOIN LATERAL (SELECT (vn->>'scenario')||'/'||(vn->>'seed')||'/'||(vn->>'ticks')||'t' col,
                               (vn->'arm_a'->>'run')::uuid a, (vn->'arm_b'->>'run')::uuid b) x
   WHERE EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = x.a)
     AND EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = x.b)
     AND (public.ottoq_hash_proposals(x.a) <> public.ottoq_hash_proposals(x.b)
          OR public.ottoq_hash_deferrals(x.a) <> public.ottoq_hash_deferrals(x.b));
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0199 A3(a) FAILED: % pair(s) at the corrected floor disagree on proposals or deferrals: %', v_n, v_names;
  END IF;
  SELECT count(*) INTO v_n
    FROM (SELECT DISTINCT ON (r.validation_notes) r.started_at FROM public.ottoq_sim_runs r
           WHERE r.run_by = 'cert_harness' AND r.started_at >= v_new_floor
             AND r.validation_status IN ('passed','failed') AND r.validation_notes LIKE '{%equal%') p;
  IF v_n < 7 THEN
    RAISE EXCEPTION '0199 A3(a) FAILED: expected round 18''s seven pairs at the corrected floor, found %', v_n;
  END IF;
  RAISE NOTICE '0199 A3(a): % pairs at the corrected floor, zero disagreements on h_prop or h_defr', v_n;

  SELECT (vn->'arm_a'->>'run')::uuid, (vn->'arm_b'->>'run')::uuid INTO v_a, v_b
    FROM (SELECT r.validation_notes::jsonb vn FROM public.ottoq_sim_runs r
           WHERE r.started_at >= '2026-09-01 15:09+00' AND r.started_at < '2026-09-01 15:12+00'
             AND r.validation_status = 'passed' AND r.validation_notes LIKE '{%equal%'
             AND r.validation_notes::jsonb->>'scenario' = 'busy_day' AND r.validation_notes::jsonb->>'seed' = '424242'
           ORDER BY r.started_at LIMIT 1) s;
  IF v_a IS NULL THEN
    RAISE EXCEPTION '0199 A3(b) FAILED: the Sep 1 15:10 busy_day/424242 pair is not present';
  END IF;
  IF public.ottoq_hash_proposals(v_a) = public.ottoq_hash_proposals(v_b) THEN
    RAISE EXCEPTION '0199 A3(b) FAILED: the pair that passed with 4 vs 3 proposals hashes equal -- the instrument cannot fail';
  END IF;
  RAISE NOTICE '0199 A3(b): the Sep 1 15:10 pair (passed, 4 vs 3 proposals) is told apart: % vs %',
    left(public.ottoq_hash_proposals(v_a),8), left(public.ottoq_hash_proposals(v_b),8);

  -- ── A4. The matrix at the corrected floor: six flagship columns, none stale,
  --     canon_prop/canon_defr present as columns and NULL (pre-instrument), and
  --     exactly ONE column green -- normal_day/171717/12t, which ran twice in
  --     round 18. The other five have one pass since 0197 and need round 19.
  SELECT count(*), count(*) FILTER (WHERE green),
         string_agg(CASE WHEN green THEN scenario||'/'||seed||'/'||ticks||'t' END, ','),
         count(*) FILTER (WHERE stale),
         count(*) FILTER (WHERE canon_prop IS NOT NULL OR canon_defr IS NOT NULL)
    INTO v_n, v_green, v_green_cols, v_stale, v_hashed
    FROM public.ottoq_cert_matrix(v_new_floor)
   WHERE depot = '11111111-1111-1111-1111-111111111111';
  IF v_n <> 6 THEN RAISE EXCEPTION '0199 A4 FAILED: expected six flagship columns at the corrected floor, found %', v_n; END IF;
  IF v_stale <> 0 THEN RAISE EXCEPTION '0199 A4 FAILED: % flagship column(s) stale at the corrected floor', v_stale; END IF;
  IF v_hashed <> 0 THEN RAISE EXCEPTION '0199 A4 FAILED: % column(s) carry a proposal/deferral canon before any pair hashed one', v_hashed; END IF;
  IF v_green <> 1 OR v_green_cols IS DISTINCT FROM 'normal_day/171717/12t' THEN
    RAISE EXCEPTION '0199 A4 FAILED: green columns = % (%), expected exactly normal_day/171717/12t', v_green, v_green_cols;
  END IF;
  SELECT count(*), string_agg(scenario||'/'||seed||'/'||ticks||'t='||consecutive_passes, ',') INTO v_n, v_names
    FROM public.ottoq_cert_matrix(v_new_floor)
   WHERE depot = '11111111-1111-1111-1111-111111111111' AND NOT green AND consecutive_passes <> 1;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0199 A4 FAILED: non-green columns must show exactly one pass since 0197: %', v_names;
  END IF;
  RAISE NOTICE '0199 A4: six flagship columns at floor %, one green (normal_day twins), five at one pass awaiting round 19', v_new_floor;

  -- ── A5. Recreating the matrix did not change who may run it.
  IF (SELECT m_anon FROM pre_0199) IS DISTINCT FROM has_function_privilege('anon',          'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE')
     OR (SELECT m_auth FROM pre_0199) IS DISTINCT FROM has_function_privilege('authenticated', 'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE')
     OR (SELECT m_svc FROM pre_0199) IS DISTINCT FROM has_function_privilege('service_role',  'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION '0199 A5 FAILED: ottoq_cert_matrix execute privileges changed across the recreate';
  END IF;
  RAISE NOTICE '0199 A5: ottoq_cert_matrix keeps its execute privileges for anon, authenticated, service_role';

  RAISE NOTICE '0199: all assertions passed';
END $assert$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0199_the_verdict_hears_the_proposers_and_the_floor_hears_every_recert', FALSE,
  'G4 + two instrument defects. (1) The pair verdict now hashes the run''s ottoq_external_proposals (h_prop) and ottoq_cuopt_deferrals '
  '(h_defr) through two named functions, ottoq_hash_proposals/ottoq_hash_deferrals, and its equality hears both. Before this, a pair could '
  'pass while the arms proposed different things: 2026-09-01 15:10 busy_day/424242/12t passed with 4 vs 3 proposals (pre-quiesce, pre-floor). '
  'Retro-check on the rows the pairs hashed: since 2026-09-01, 189 pairs, every passed pair inside the certified window agrees on both streams; '
  'at the corrected floor 7 of 7. That is why forces_recert is FALSE. (2) ottoq_cert_recert_floor read only supabase_migrations; 0192-0197 '
  '(all forces_recert) were applied through the SQL endpoint and never registered, so the floor sat at 2026-09-03 17:16 through six recerts. '
  'It now also reads max(classified_at) over forces_recert lineage rows and moves to 0197''s apply, 2026-09-05 17:36:10. Consequence: at the '
  'corrected floor only round 18 counts; green needs round 19, scheduled at apply. db/checks/0113''s Part A MET is corrected by appendix, '
  'its values unchanged. (3) ottoq_cert_matrix gains canon_prop/canon_defr (appended columns; pre-0199 verdicts are NULL and neither on nor '
  'off those canons). A0 pins every function body: three harness functions changed, two new, no decide-path function touched.',
  now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

COMMIT;

-- =====================================================================
-- APPLIED 2026-09-06 03:39:23 UTC (10:39 PM CT, Sep 5) -- one
-- transaction as postgres, first attempt, every assertion passed. No
-- pair was scheduled or in flight (checked at 03:37 UTC: 0 jobs, 0
-- backends, 0 running runs).
--
-- Measured after COMMIT (the SQL endpoint returns no NOTICEs):
--
--   ottoq_cert_recert_floor()      2026-09-03 17:16:37  ->  2026-09-05 17:36:10.84
--                                  (the watermark sweep)    (0197's apply)
--   ottoq_determinism_pair body    md5 8e6f58f5...  ->  856aa0c0...
--   new functions                  ottoq_hash_proposals(uuid),
--                                  ottoq_hash_deferrals(uuid); not
--                                  SECURITY DEFINER, default execute
--                                  (anon/authenticated/service_role),
--                                  read-only over tables anon already
--                                  SELECTs
--   ottoq_cert_matrix acl          unchanged across the recreate
--   lineage                        forces_recert = false, 03:39:23 UTC
--
--   matrix at the corrected floor, flagship:
--     busy_day/171717/12t    pairs 1  consec 1  green f  canon_prop NULL
--     busy_day/171717/24t    pairs 1  consec 1  green f  canon_prop NULL
--     busy_day/314159/12t    pairs 1  consec 1  green f  canon_prop NULL
--     busy_day/424242/12t    pairs 1  consec 1  green f  canon_prop NULL
--     busy_day/424242/24t    pairs 1  consec 1  green f  canon_prop NULL
--     normal_day/171717/12t  pairs 2  consec 2  green T  canon_prop NULL
--   Five columns are one round short of green at the corrected floor.
--   That is the honest reading after 0197, and it is what round 19 is
--   for. canon_prop/canon_defr are NULL until a pair hashes them live.
--
--   the Sep 1 15:10 pair, under the new hash:  69bc0a43 vs 2c2555fa
--   (arm A four proposals, arm B three; the verdict at the time: passed)
--
-- Retro values for rounds 14-18 (computed now with the two functions,
-- over the rows those arms wrote; every arm pair agrees, and the two
-- round-14/15 busy_day/314159/12t pairs that FAILED on other hashes
-- also disagree on h_prop -- the bay-queue coin 0195 removed showed up
-- in the proposals too):
--
--   column                 h_prop     h_defr     rounds
--   busy_day/171717/12t    142ee120   d41d8cd9   r14-r18 identical
--   busy_day/171717/24t    142ee120   d41d8cd9   r14-r18 identical
--   busy_day/314159/12t    b32df53d   d41d8cd9   r14-r18 identical (arms
--                                                 disagree in r14, r15: failed)
--   busy_day/424242/12t    f77e42b1   d41d8cd9   r14-r18 identical
--   busy_day/424242/24t    5f0d8281 -> 62b9301c  moved r14 -> r15 with h_cmd
--                                                 (0195), then r15-r18 identical
--   normal_day/171717/12t  83527ba2   d41d8cd9   r14-r18 identical
--   d41d8cd9 = md5('') : no deferral rows in any certification arm since
--   the 0152 quiesce, as designed.
--
-- ROUND 19 scheduled at 03:40:20 UTC, jobs 386-392, same seven pairs
-- and order as round 18, p_arm_budget_s = 1800, each self-unschedules:
--   03:43  r19_c2_busy_314159_12t       10:43 PM CT
--   03:56  r19_c1_busy_171717_12t       10:56 PM CT
--   04:09  r19_c3_normal_171717_12t     11:09 PM CT
--   04:22  r19_c3dup_normal_171717_12t  11:22 PM CT
--   04:35  r19_c4_busy_424242_12t       11:35 PM CT
--   04:48  r19_c5_busy_171717_24t       11:48 PM CT
--   05:11  r19_c6_busy_424242_24t       12:11 AM CT (Sep 6)
-- Expected done by ~05:35 UTC (12:35 AM CT).
--
-- PREDICTIONS, written before any round-19 pair exists:
--   1. seven of seven pass, both arms complete.
--   2. every h_cmd, h_dec, h_evt, h_bkg, h_nrg, endst and boot equals
--      round 18 -- 0199 changed no engine function (A0).
--   3. every arm pair carries h_prop and h_defr, and they equal the retro
--      values above: 142ee120 / 142ee120 / b32df53d / f77e42b1 /
--      62b9301c / 83527ba2 for h_prop; d41d8cd9 for every h_defr.
--   4. after the round, all six flagship columns read green at the
--      corrected floor with consecutive_passes = 2 (normal_day 4), and
--      canon_prop / canon_defr are populated for all six.
-- A moved h_prop with an unmoved h_cmd would mean the proposers are not
-- deterministic while the disposer is -- a Part-B finding, and it would
-- be said so.
-- =====================================================================

-- =====================================================================
-- CORRECTION appended 2026-09-06 15:40 UTC (10:40 AM CT), after round 19
-- was read (db/checks/0115). Nothing above is rewritten.
-- ---------------------------------------------------------------------
-- Prediction 1  MET. Seven of seven, both arms complete.
-- Prediction 2  NOT MET for five of seven pairs, and not because of
--               this migration: cron job 2 (weekly calibration ingest)
--               ran at 04:05:25 UTC, between pair 2 and pair 3, and
--               refit the NOAA temperature/precipitation grids and the
--               EIA grid-demand grid. The two pairs that ran before it
--               equal round 18 on every field; every pair after it
--               moved. The A0 pin holds: no engine function changed.
-- Prediction 3  NOT MET, and it could not have been met as written:
--               0198 began recording declared_source on proposals that
--               go through the submitter, and this migration hashes it.
--               The retro values were computed over pre-0198 rows.
--               Hashing round-19 pair 1 with declared_source blanked
--               gives b32df53d, the retro value, exactly. The live
--               values (2b86847e, 2574c54f, 940d3890, 029cad7d,
--               2574c54f, bea94486) are the first proposal canons.
-- Prediction 4  PARTLY. canon_prop / canon_defr populated on all six
--               columns. Green on three (171717/12t, 314159/12t,
--               normal_day); one pass at the new priors on the other
--               three.
-- Lesson for the instrument: the reproducibility key does not include
-- the calibration priors the twin draws from. G14 / 0201 adds a
-- calibration fingerprint to the boot image, the arm and the matrix,
-- and blocks the ingest under a certification.
-- =====================================================================
