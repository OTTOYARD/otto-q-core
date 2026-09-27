-- migration-version: 20260927161230
-- migration-name:    the_learners_arms_start_through_the_operators_door
--
-- 0531  **G256: the dial experiments' arms start the way the operator's day starts. They started in a busy day that met
--       98.8% of its demand, while the operator's met 37% (db/checks/0397 §3), so no dial verdict to date was measured
--       where the operator's day is decided. And the operator's fleet deal stamped the wall clock into two sim-clock
--       columns, so its service-patience clock ran late by however long after the sim start the run was started.**
--
-- ══ §1 WHAT WAS DIFFERENT ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   The operator starts through `ottoq_sim_run_scenario`: `twin.ottoq_sim_seed_fleet(depot, seed, start hour)` deals
--   the start hour's share staged for departure (busy_day at 8 AM: 91 of 116), 55% of the rest AT THE GATE at 12-47%
--   SoC (17) and the others held or awaiting service; `ottoq_variability_instantiate` gives the run busy_day's template
--   (the arrival drain as SoC points per hour out, trip duration x0.3, DTC x7, idle x1.9, incidents x0.4); the
--   scenario's fleet overrides (maintenance intervals x0.01/x0.02, wear phase, five policy overrides); a prime at the
--   hour-shaped fraction (46 out, 13 of them inbound). `ottoq_dial_pair` reset the fleet offline at 85-99%
--   (`ottoq_tick_invariance_reset_fleet`), started through `twin.ottoq_sim_start_run` (a 0.55 cold-start prime) and
--   primed again at 0.70: all 116 primed, 81 on the road at 8 AM, none at the gate, no profile row -- so
--   `ottoq_profile_rate_mult` read 1 for every rate. On the same hours the operator's cars went out 55 minutes and used
--   37 points a trip, 199-208 returns in nine hours; the arm's went out 4.7 hours and used 31, 116 returns.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `twin.ottoq_sim_seed_fleet(depot, seed, hour, as_of)`: the deal on a named clock. The three places it wrote
--       now() -- `current_soc_updated_at`, the staggered `last_state_change` and the chargers' `last_heartbeat_at` --
--       and the default hour read `as_of`. The three-argument form delegates with NULL, which reads now(): unchanged
--       for any other caller.
--   (b) `ottoq_sim_run_scenario` deals on the run's own start clock. Every reader of `last_state_change` computes a
--       dwell as the SIM clock minus it (the service flow's patience, the service priority's dwell, the L2 proposer),
--       and 0065 moved the cert arms' stamp to the sim domain for exactly that reason. The operator's deal stamped
--       now() - up to 90 minutes: 6e0352a0 was started 97 minutes after its sim start, so every dealt car's state
--       began up to 97 sim-minutes in the future and its patience clock ran that far late. A run started in the
--       afternoon for an 8 AM sim start would have run hours late. Now the stagger ends at the sim start.
--   (c) `ottoq_dial_pair`'s arms start through `ottoq_sim_run_scenario` after the canonical reset (which still owns the
--       chargers, the battery, the tethers and the config whitelist, identically for both arms), with the tagging GUC
--       cleared first so the deal's and the prime's events belong to the arm's run as they do on an operator run, and
--       pinned to the run after; the experiment's cadence is set on the run as before (0520); the second 0.70 prime is
--       gone; the arm writes its world fingerprint into the payload as `twin.ottoq_sim_start_run` did (0093), so the
--       pair's `fp` atom keeps comparing the arms, and `arm_start` says which door it came through.
--   `ottoq_ab_pair`, `ottoq_tick_invariance_arm` and the determinism pairs still start through the twin's own door: the
--   canon is a fixed world by design and is not the learner.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   The certification pairs (`ottoq_determinism_pair`, its replay, the tick-invariance arm) call neither function
--   changed here. Every dial arm's world changes, so every dial experiment's pairs restart from this file's apply.

BEGIN;

-- ── P0: no pair in flight (0513's one probe), and no live run: V3 starts two arms through the operator's door, which
--    stops a live run at the depot ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0531 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused')) THEN
    RAISE EXCEPTION '0531 P0: a run is live';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
DECLARE v_seed text; v_run text; v_pair text; v_n int;
BEGIN
  IF to_regprocedure('twin.ottoq_sim_seed_fleet(uuid,bigint,integer,timestamp with time zone)') IS NOT NULL THEN
    RAISE EXCEPTION '0531 P2: the four-argument deal already exists';
  END IF;
  v_seed := pg_get_functiondef('twin.ottoq_sim_seed_fleet(uuid,bigint,integer)'::regprocedure);
  v_run  := pg_get_functiondef('public.ottoq_sim_run_scenario(text,bigint,text,timestamp with time zone)'::regprocedure);
  v_pair := pg_get_functiondef('public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure);
  -- the deal writes the wall clock in exactly four places outside comments: the default hour, the SoC stamp, the
  -- stagger and the heartbeat
  v_n := (SELECT count(*) FROM regexp_matches(regexp_replace(regexp_replace(v_seed, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g'),
                                              'now\(\)', 'gi'));
  IF v_n <> 4 THEN RAISE EXCEPTION '0531 P2: the deal names now() % times outside comments, not 4', v_n; END IF;
  -- its one caller is the operator's start; the other doors do not deal
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname IN ('public', 'ottoq', 'twin') AND p.proname <> 'ottoq_sim_seed_fleet'
         AND regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'ottoq_sim_seed_fleet\s*\(') <> 1 THEN
    RAISE EXCEPTION '0531 P2: the deal has a caller other than ottoq_sim_run_scenario';
  END IF;
  IF position('PERFORM ottoq_sim_seed_fleet(v_scenario.default_depot_id, v_seed, v_start_hour);' IN v_run) = 0 THEN
    RAISE EXCEPTION '0531 P2: the operator''s start does not deal as measured';
  END IF;
  IF position('v_run := twin.ottoq_sim_start_run(x.scenario, x.sim_start, 2 * x.sim_min_per_tick, p_seed, ''ab_harness'');' IN v_pair) = 0
     OR position('BEGIN PERFORM twin.ottoq_sim_prime_deployment(v_run, x.sim_start, 0.70);' IN v_pair) = 0 THEN
    RAISE EXCEPTION '0531 P2: the dial pair does not start its arms as measured';
  END IF;
  -- every active experiment's scenario is one the operator's door can start, on the experiment's depot
  IF EXISTS (SELECT 1 FROM public.ottoq_dial_experiments x
              WHERE x.status = 'active'
                AND NOT EXISTS (SELECT 1 FROM public.ottoq_sim_scenarios s WHERE s.scenario_code = x.scenario
                                   AND s.status = 'available' AND s.default_depot_id = x.depot_id)) THEN
    RAISE EXCEPTION '0531 P2: an active dial experiment names a scenario the operator''s door cannot start on its depot';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0531_pre', 'function', f.sch, f.obj, pg_get_functiondef(f.sig::regprocedure), md5(pg_get_functiondef(f.sig::regprocedure))
  FROM (VALUES ('twin',   'ottoq_sim_seed_fleet',   'twin.ottoq_sim_seed_fleet(uuid,bigint,integer)'),
               ('public', 'ottoq_sim_run_scenario', 'public.ottoq_sim_run_scenario(text,bigint,text,timestamp with time zone)'),
               ('public', 'ottoq_dial_pair',        'public.ottoq_dial_pair(uuid,bigint,integer)')) AS f(sch, obj, sig);

-- ── (a) the deal on a named clock, built from the three-argument body so the two cannot drift ──
DO $deal$
DECLARE
  v_def text; v_new text; n int;
  p text[][] := ARRAY[
    ARRAY['CREATE OR REPLACE FUNCTION twin.ottoq_sim_seed_fleet(p_depot_id uuid, p_seed bigint DEFAULT 42, p_hour integer DEFAULT NULL::integer)',
          'CREATE FUNCTION twin.ottoq_sim_seed_fleet(p_depot_id uuid, p_seed bigint, p_hour integer, p_as_of timestamp with time zone)'],
    ARRAY['  v_seed BIGINT := COALESCE(p_seed, 42);',
          E'  -- 0531 (G256): the deal on a named clock. NULL is the wall clock, as the three-argument form always was.\n'
          || '  v_as_of TIMESTAMPTZ := COALESCE(p_as_of, NOW());' || E'\n' || '  v_seed BIGINT := COALESCE(p_seed, 42);'],
    ARRAY['EXTRACT(HOUR FROM (NOW() AT TIME ZONE ''America/Chicago''))', 'EXTRACT(HOUR FROM (v_as_of AT TIME ZONE ''America/Chicago''))'],
    ARRAY['current_soc_updated_at = NOW()', 'current_soc_updated_at = v_as_of'],
    ARRAY['last_state_change = NOW() - ((r.stagger * 90)::text || '' minutes'')::interval',
          'last_state_change = v_as_of - ((r.stagger * 90)::text || '' minutes'')::interval'],
    ARRAY['last_heartbeat_at = NOW()', 'last_heartbeat_at = v_as_of']];
  i int;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_seed_fleet(uuid,bigint,integer)'::regprocedure);
  v_new := v_def;
  FOR i IN 1 .. array_length(p, 1) LOOP
    n := (length(v_new) - length(replace(v_new, p[i][1], ''))) / length(p[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0531 (a): patch % matched % times, not once', i, n; END IF;
    v_new := replace(v_new, p[i][1], p[i][2]);
  END LOOP;
  -- the one now() left outside comments is the NULL fallback
  n := (SELECT count(*) FROM regexp_matches(regexp_replace(regexp_replace(v_new, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g'),
                                            'now\(\)', 'gi'));
  IF n <> 1 THEN RAISE EXCEPTION '0531 (a): the new deal names now() % times outside comments, not once', n; END IF;
  EXECUTE v_new;
END $deal$;

COMMENT ON FUNCTION twin.ottoq_sim_seed_fleet(uuid, bigint, integer, timestamp with time zone) IS
  '0531 (G256). The operator''s fleet deal on a named clock: the start hour''s share staged for departure, 55% of the rest '
  'at the gate at 12-47%, the others held or awaiting service, every timestamp it writes read from p_as_of (NULL: now()). '
  'ottoq_sim_run_scenario passes the run''s sim start; the dial pair''s arms start through it.';

CREATE OR REPLACE FUNCTION twin.ottoq_sim_seed_fleet(p_depot_id uuid, p_seed bigint DEFAULT 42, p_hour integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  -- 0531 (G256): the body moved to the four-argument form, which reads its clock from p_as_of; NULL reads now(), which is
  -- what this form always wrote, so a caller of this form sees no change.
  PERFORM twin.ottoq_sim_seed_fleet(p_depot_id, p_seed, p_hour, NULL::timestamptz);
END
$function$;

-- ── (b) the operator's start deals on the run's own clock ──
DO $run$
DECLARE
  v_def text; n int;
  v_old text := 'PERFORM ottoq_sim_seed_fleet(v_scenario.default_depot_id, v_seed, v_start_hour);';
  v_new text := $n$-- 0531 (G256): dealt on the run's own start clock. It was now(): every reader of last_state_change takes a dwell
    -- as the SIM clock minus it, and a car dealt at the wall clock began its state in the sim's future.
    PERFORM twin.ottoq_sim_seed_fleet(v_scenario.default_depot_id, v_seed, v_start_hour, v_start);$n$;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_sim_run_scenario(text,bigint,text,timestamp with time zone)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0531 (b): the deal call matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $run$;

-- ── (c) the dial pair's arms start through the operator's door ──
DO $pair$
DECLARE
  v_def text; n int;
  v_old1 text := $o$    -- 0520 (G240): the experiment's cadence, time_scale = 2 x sim-minutes per tick on a 30-second tick (30 -> 60)
    v_run := twin.ottoq_sim_start_run(x.scenario, x.sim_start, 2 * x.sim_min_per_tick, p_seed, 'ab_harness');$o$;
  v_new1 text := $n$    -- 0531 (G256): THE OPERATOR'S DOOR. The arm starts as the operator's day starts -- the start hour's deal, the
    -- scenario's template and fleet overrides, the hour-shaped prime -- on the world the reset above made canonical, so
    -- both arms are dealt the same cars. It was twin.ottoq_sim_start_run and a second prime at 0.70: 81 cars out at
    -- 8 AM, none at the gate, no template -- a busy day that met 98.8% of its demand where the operator's met 37%
    -- (db/checks/0397 §3). The tagging GUC is cleared first, as an operator's transaction begins, so the deal's and the
    -- prime's events belong to this arm's run (ottoq.ottoq_active_sim_run_id finds it), and pinned to it after (0092).
    PERFORM set_config('ottoq.sim_run_id', '', true);
    v_run := public.ottoq_sim_run_scenario(x.scenario, p_seed, 'ab_harness', x.sim_start);
    PERFORM set_config('ottoq.sim_run_id', v_run::text, true);
    -- 0520 (G240): the experiment's cadence, time_scale = 2 x sim-minutes per tick on a 30-second tick (30 -> 60)
    UPDATE public.ottoq_sim_runs SET time_scale = 2 * x.sim_min_per_tick, tick_interval_seconds = 30 WHERE sim_run_id = v_run;
    -- the world fingerprint twin.ottoq_sim_start_run wrote (0093), so the pair's `fp` atom still compares the arms
    UPDATE public.ottoq_sim_runs
       SET payload = COALESCE(payload, '{}'::jsonb)
                  || jsonb_build_object('world_fingerprint', ottoq.ottoq_world_fingerprint(x.depot_id),
                                        'arm_start', '0531:operator_door')
     WHERE sim_run_id = v_run;$n$;
  v_old2 text := $o$    BEGIN PERFORM twin.ottoq_sim_prime_deployment(v_run, x.sim_start, 0.70);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'dial_pair arm % prime failed: %', v_arm, SQLERRM; END;
$o$;
  v_new2 text := $n$    -- 0531 (G256): no second prime; the operator's door primed the arm at the scenario's hour-shaped fraction.
$n$;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, v_old1, ''))) / length(v_old1);
  IF n <> 1 THEN RAISE EXCEPTION '0531 (c): the start matched % times, not once', n; END IF;
  n := (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2);
  IF n <> 1 THEN RAISE EXCEPTION '0531 (c): the second prime matched % times, not once', n; END IF;
  EXECUTE replace(replace(v_def, v_old1, v_new1), v_old2, v_new2);
END $pair$;

DO $verify$
DECLARE v_run text; v_pair text; v_three text;
BEGIN
  v_run   := pg_get_functiondef('public.ottoq_sim_run_scenario(text,bigint,text,timestamp with time zone)'::regprocedure);
  v_pair  := pg_get_functiondef('public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure);
  v_three := pg_get_functiondef('twin.ottoq_sim_seed_fleet(uuid,bigint,integer)'::regprocedure);
  -- V1: the operator deals on its start clock; the pair starts through the operator's door, once, with no second prime
  -- and no twin start; the three-argument deal delegates
  -- (read with comments stripped: a call a comment swallowed would still be found in the raw text)
  IF position('PERFORM twin.ottoq_sim_seed_fleet(v_scenario.default_depot_id, v_seed, v_start_hour, v_start);'
              IN regexp_replace(v_run, '--[^\n]*', '', 'g')) = 0
     OR (length(v_pair) - length(replace(v_pair, 'public.ottoq_sim_run_scenario(x.scenario, p_seed, ''ab_harness'', x.sim_start)', '')))
          / length('public.ottoq_sim_run_scenario(x.scenario, p_seed, ''ab_harness'', x.sim_start)') <> 1
     OR regexp_replace(v_pair, '--[^\n]*', '', 'g') ~ 'ottoq_sim_start_run\s*\('
     OR regexp_replace(v_pair, '--[^\n]*', '', 'g') ~ 'ottoq_sim_prime_deployment\s*\('
     OR position('PERFORM twin.ottoq_sim_seed_fleet(p_depot_id, p_seed, p_hour, NULL::timestamptz);'
                 IN regexp_replace(v_three, '--[^\n]*', '', 'g')) = 0
     OR position('v_run := public.ottoq_sim_run_scenario(x.scenario, p_seed, ''ab_harness'', x.sim_start);'
                 IN regexp_replace(v_pair, '--[^\n]*', '', 'g')) = 0 THEN
    RAISE EXCEPTION '0531 V1: the start, the pair or the delegate is not as intended';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0531_the_learners_arms_start_through_the_operators_door', false, true,
  'G256: the dial pair''s arms start through the operator''s door (ottoq_sim_run_scenario) instead of the twin''s start '
  'and a 0.70 prime, and the operator''s fleet deal is stamped on the run''s sim start instead of the wall clock. Every '
  'dial arm''s world changes (the busy day the learner measured met 98.8% of its demand; the operator''s met 37%). The '
  'certification pairs call neither function changed.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back: (a) two arms started exactly as the patched pair starts them -- the canonical reset, the tagging GUC
--     cleared, the operator's door, the GUC pinned, the cadence, the world fingerprint -- are the same world (equal boot
--     and world fingerprints) and each came through the door: a profile row, the scenario's overrides applied, a deal
--     with cars at the gate, 46 primed, the experiment's cadence, and a state event for every car of the fleet at the
--     arm's first clock (the supply gap's timeline premise, 0530). (b) The deal on a named clock leaves no car's state
--     beginning after it, staggers them over the 90 minutes before it, and stamps every SoC reading and charger heartbeat
--     with it. The whole pair, ticks and scoring included, is 0398 §1: a 12-tick pair of a planted experiment took 57 s
--     in this file's dry run, too close to one statement's limit to run inside the apply.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_arm int; v_fleet int; v_boot jsonb[] := '{}'; v_fp text[] := '{}'; r record; v_arms text := '';
  v_depot uuid := '11111111-1111-1111-1111-111111111111'; v_clock timestamptz := '2026-09-01 13:00:00+00';
  v_seed bigint := 531531; v_late int; v_early int; v_soc int; v_hb int;
BEGIN
  BEGIN
    SELECT count(*) INTO v_fleet FROM public.vehicles WHERE home_depot_id = v_depot AND category = 'autonomous';
    FOR v_arm IN 1..2 LOOP
      PERFORM set_config('ottoq.sim_run_id', 'none', true);
      PERFORM public.ottoq_tick_invariance_reset_fleet(v_depot, v_seed, v_clock);
      PERFORM set_config('ottoq.sim_run_id', '', true);
      v_run := public.ottoq_sim_run_scenario('busy_day', v_seed, 'ab_harness', v_clock);
      PERFORM set_config('ottoq.sim_run_id', v_run::text, true);
      UPDATE public.ottoq_sim_runs SET time_scale = 12, tick_interval_seconds = 30 WHERE sim_run_id = v_run;
      UPDATE public.ottoq_sim_runs
         SET payload = COALESCE(payload, '{}'::jsonb)
                    || jsonb_build_object('world_fingerprint', ottoq.ottoq_world_fingerprint(v_depot), 'arm_start', '0531:operator_door')
       WHERE sim_run_id = v_run;
      v_boot := v_boot || public.ottoq_boot_state_fingerprint(v_depot, v_run);
      SELECT s.payload, s.time_scale,
             (SELECT count(*) FROM public.ottoq_variability_profiles vp WHERE vp.sim_run_id = s.sim_run_id) AS profiles,
             (SELECT count(DISTINCT e.entity_id) FROM public.ottoq_events e
               WHERE e.sim_run_id = s.sim_run_id AND (e.event_type || '') = 'vehicle.state_changed'
                 AND e.payload->'diff' ? 'current_state' AND e.sim_clock_at <= s.sim_clock_start + interval '1 minute') AS cars_at_t0
        INTO r FROM public.ottoq_sim_runs s WHERE s.sim_run_id = v_run;
      v_fp := v_fp || (r.payload->>'world_fingerprint');
      IF r.profiles <> 1 OR NOT COALESCE((r.payload->'scenario_overrides'->>'ok')::boolean, false)
         OR COALESCE((r.payload->'boot_prime'->'state_histogram'->>'arrived_at_gate')::int, 0) = 0
         OR COALESCE((r.payload->'boot_prime'->>'primed')::int, 0) <> 46
         OR r.payload->>'world_fingerprint' IS NULL OR r.time_scale <> 12 OR r.cars_at_t0 <> v_fleet THEN
        RAISE EXCEPTION '0531 V3 FAILED (a): arm % reads profiles %, overrides %, deal %, primed %, fp %, scale %, cars at t0 % of %',
          v_arm, r.profiles, r.payload->'scenario_overrides'->>'ok', r.payload->'boot_prime'->'state_histogram',
          r.payload->'boot_prime'->>'primed', r.payload->>'world_fingerprint', r.time_scale, r.cars_at_t0, v_fleet;
      END IF;
      v_arms := v_arms || format(' arm %s: deal %s, primed %s;', v_arm, r.payload->'boot_prime'->'state_histogram',
                                 r.payload->'boot_prime'->>'primed');
      PERFORM public.ottoq_sim_stop_and_reset(v_run, '0531_v3');
    END LOOP;
    PERFORM set_config('ottoq.sim_run_id', 'none', true);
    IF v_boot[1] IS DISTINCT FROM v_boot[2] OR v_fp[1] IS DISTINCT FROM v_fp[2] THEN
      RAISE EXCEPTION '0531 V3 FAILED (a): the two arms'' worlds differ (boot fingerprints equal: %, world fingerprints equal: %)',
        v_boot[1] = v_boot[2], v_fp[1] = v_fp[2];
    END IF;

    -- (b) the deal on a named clock, alone, on the world the arms left
    PERFORM twin.ottoq_sim_seed_fleet(v_depot, v_seed, 8, v_clock);
    SELECT count(*) FILTER (WHERE last_state_change > v_clock),
           count(*) FILTER (WHERE last_state_change < v_clock - interval '90 minutes'),
           count(*) FILTER (WHERE current_soc_updated_at IS DISTINCT FROM v_clock)
      INTO v_late, v_early, v_soc
      FROM public.vehicles WHERE home_depot_id = v_depot AND category = 'autonomous';
    SELECT count(*) FILTER (WHERE last_heartbeat_at IS DISTINCT FROM v_clock) INTO v_hb
      FROM public.ottoq_ocpp_chargers WHERE depot_id = v_depot;
    IF v_late + v_early + v_soc + v_hb > 0 THEN
      RAISE EXCEPTION '0531 V3 FAILED (b): after the clock %, before the stagger %, SoC stamps off %, heartbeats off %',
        v_late, v_early, v_soc, v_hb;
    END IF;

    RAISE EXCEPTION '0531 V3 PASSED: two arms through the operator''s door, boot and world fingerprints equal;% every car of % has a state at t0; the deal on the sim clock leaves 0 cars after it and 0 stamps off',
      v_arms, v_fleet;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0531 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0531 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the three `definition`s in ottoq_schema_snapshots WHERE label = '0531_pre' as they are; then
--   DROP FUNCTION twin.ottoq_sim_seed_fleet(uuid, bigint, integer, timestamp with time zone).
COMMIT;
