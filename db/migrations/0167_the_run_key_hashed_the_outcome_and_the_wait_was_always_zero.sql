-- 0167  The run key hashed the outcome, and the wait was always zero.
--       Instrument + KPI only; no engine function is touched. forces_recert = false.
--
-- Two defects, both found by reading the first flagship certification pair run
-- after today's engine fixes (sim_run_seq 1748/1749, pair passed and equal).
--
-- DEFECT 1 - the reproducibility key was not reproducible.
--   ottoq_run_archives.config_hash was md5(ottoq_sim_runs.payload::text). The
--   payload is the run's OUTCOME, not its configuration: it carries
--   boot_draw.drawn_at (wall clock), boot_draw.draw_ms, need_profiles.ms, and
--   inbound_forecast.sim_run_id. So two arms of the SAME pair - byte-identical
--   on commands, decisions, bookings, energy and end state - were handed
--   DIFFERENT config_hashes. Measured on both pairs: 1658/1659 gave
--   17c661d3 / e6e1cfce, and 1748/1749 gave e55954bf / f8d2a9b4.
--   0072 section 6a named this and it was not built; this builds it.
--
--   The company rule is "no number ships without a run ID." A key that changes
--   when nothing about the configuration changed cannot carry that rule.
--
--   Fix: config_hash is md5 over a canonical INPUT projection - scenario, seed,
--   policy, depot, ticks, tick interval, pinned sim clock, time scale, and the
--   EFFECTIVE policy parameters resolved exactly as ottoq_policy_get resolves
--   them (run -> depot -> global). The projection is stored alongside the hash
--   as config_key, so a reader can see WHY two runs differ rather than only
--   THAT they differ. Verified before applying: all four runs above collapse to
--   the single key d011095c4b5f8492c1630bb79d6bc086.
--
--   That collapse exposes the second half of the problem. 1658/1659 ran on the
--   pre-0155 engine and measured peak 500.3 kW; 1748/1749 ran on the post-0155
--   engine and measured 919.6 kW. Same configuration, different engine, and the
--   key could not tell them apart. So the archive also stamps engine_hash - md5
--   over the applied migration set at archive time. Configuration and engine are
--   two axes and the key now carries both. Pre-0167 archives keep engine_hash
--   NULL: which engine produced them is not reconstructable, and guessing it
--   would be worse than admitting it.
--
-- DEFECT 2 - p95_time_to_service could not return a non-zero number.
--   CLAUDE.md 2.9 defines the KPI as "recall-complete -> first op ACTIVE". The
--   view measured actual_return_at -> min(lower(ottoq_stall_bookings.during)):
--   the CALENDAR CLAIM, not the physical start. The twin stamps
--   actual_return_at = p_sim_clock_now and the decide path books on that same
--   tick with during starting at that same instant, so the difference was
--   exactly zero for 116 of 116 returns on run 25944bde. Reported p95: 0.0 min,
--   returns_unserved: 0. A check that cannot fail is not a check, and this one
--   is one of the five canonical KPIs.
--
--   Fix: measure to ottoq_itinerary_legs.actual_start_sim - when an operation
--   actually went active - excluding taxi (the inter-point move) and stage
--   (parking), which are not service. Same run, measured before applying:
--   p95 210.0 min, mean 65.2, max 270.0, 17 of 116 genuinely instant. That is a
--   number that can move when the engine improves, which is the point of a KPI.
--
--   This reads the physical side of "assignment plus verification, always." The
--   old view read only the assignment side and called it service.
--
-- ALSO - ottoq_kpi_five's provenance told a live falsehood. It declared
--   peak_site_kw not reproducible, citing a twin battery "not yet
--   deterministic". Measured over the last 40 certified pairs: peak_site_kw
--   equal in 40, differing in 0; peak_site_kw_demand equal in 40, differing in
--   0. 0072 section 6a already flagged the text as stale. Corrected here with
--   the count, so the claim is falsifiable rather than asserted.

-- ---------------------------------------------------------------- 1. the key

CREATE OR REPLACE FUNCTION public.ottoq_run_config_key(p_run uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
  SELECT jsonb_build_object(
    'scenario',              r.scenario_code,
    'seed',                  r.random_seed,
    'policy',                r.policy,
    'depot',                 r.depot_id,
    'ticks',                 r.tick_count,
    'tick_interval_seconds', r.tick_interval_seconds,
    'sim_clock_start',       r.sim_clock_start,
    'time_scale',            r.time_scale,
    -- effective params, resolved run -> depot -> global exactly as
    -- ottoq_policy_get resolves them. Keyed by param_key only, so the
    -- projection is id-blind and two arms of a pair agree.
    'params', COALESCE((
      SELECT jsonb_object_agg(pk.param_key, (
               SELECT p.param_value FROM public.ottoq_policy_params p
                WHERE p.param_key = pk.param_key
                  AND ((p.scope_type='run'   AND p.scope_id = r.sim_run_id)
                    OR (p.scope_type='depot' AND p.scope_id = r.depot_id)
                    OR  p.scope_type='global')
                ORDER BY CASE p.scope_type WHEN 'run' THEN 0 WHEN 'depot' THEN 1 ELSE 2 END
                LIMIT 1))
        FROM (SELECT DISTINCT param_key FROM public.ottoq_policy_params) pk), '{}'::jsonb)
  )
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run;
$fn$;

COMMENT ON FUNCTION public.ottoq_run_config_key(uuid) IS
  'Canonical INPUT projection of a run: what you would need to reproduce it. Never the outcome. 0167.';

CREATE OR REPLACE FUNCTION public.ottoq_run_config_hash(p_run uuid)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$ SELECT md5(public.ottoq_run_config_key(p_run)::text); $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_engine_hash()
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public','extensions'
AS $fn$
  SELECT md5(string_agg(version, ',' ORDER BY version))
    FROM supabase_migrations.schema_migrations;
$fn$;

COMMENT ON FUNCTION public.ottoq_engine_hash() IS
  'md5 over the applied migration set - which engine is running. The second axis of the run key. 0167.';

-- ------------------------------------------------------- 2. the archive columns

ALTER TABLE public.ottoq_run_archives
  ADD COLUMN IF NOT EXISTS engine_hash text,
  ADD COLUMN IF NOT EXISTS config_key  jsonb;

COMMENT ON COLUMN public.ottoq_run_archives.engine_hash IS
  'ottoq_engine_hash() at archive time. NULL for runs archived before 0167 - not reconstructable. 0167.';
COMMENT ON COLUMN public.ottoq_run_archives.config_key IS
  'The ottoq_run_config_key projection config_hash was taken over. Self-describing key. 0167.';

-- --------------------------------------------------- 3. the archive writers

DO $patch$
DECLARE v_src text; v_before text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE p.prokind='f' AND n.nspname='public' AND p.proname='ottoq_archive_run';

  -- (a) the column list
  v_before := 'playback_mode, speed_x, metrics, run_payload, config_hash)';
  v_n := (length(v_src) - length(replace(v_src, v_before, ''))) / length(v_before);
  IF v_n <> 1 THEN RAISE EXCEPTION '0167a: column-list anchor must occur exactly once, found %', v_n; END IF;
  v_src := replace(v_src, v_before,
    'playback_mode, speed_x, metrics, run_payload, config_hash, engine_hash, config_key)');

  -- (b) the VALUES tail
  v_before := 'v_metrics, v_run.payload, md5(v_run.payload::text))';
  v_n := (length(v_src) - length(replace(v_src, v_before, ''))) / length(v_before);
  IF v_n <> 1 THEN RAISE EXCEPTION '0167b: values anchor must occur exactly once, found %', v_n; END IF;
  v_src := replace(v_src, v_before,
    'v_metrics, v_run.payload, public.ottoq_run_config_hash(p_sim_run_id), '
    || 'public.ottoq_engine_hash(), public.ottoq_run_config_key(p_sim_run_id))');

  -- (c) the upsert SET
  v_before := 'run_payload = EXCLUDED.run_payload, config_hash = EXCLUDED.config_hash;';
  v_n := (length(v_src) - length(replace(v_src, v_before, ''))) / length(v_before);
  IF v_n <> 1 THEN RAISE EXCEPTION '0167c: upsert anchor must occur exactly once, found %', v_n; END IF;
  v_src := replace(v_src, v_before,
    'run_payload = EXCLUDED.run_payload, config_hash = EXCLUDED.config_hash, '
    || 'engine_hash = EXCLUDED.engine_hash, config_key = EXCLUDED.config_key;');

  -- (d) the returned reproducible_from
  v_before := '''depot_id'', v_run.depot_id, ''config_hash'', md5(v_run.payload::text)),';
  v_n := (length(v_src) - length(replace(v_src, v_before, ''))) / length(v_before);
  IF v_n <> 1 THEN RAISE EXCEPTION '0167d: reproducible_from anchor must occur exactly once, found %', v_n; END IF;
  v_src := replace(v_src, v_before,
    '''depot_id'', v_run.depot_id, ''config_hash'', public.ottoq_run_config_hash(p_sim_run_id), '
    || '''engine_hash'', public.ottoq_engine_hash()),');

  EXECUTE v_src;
END $patch$;

CREATE OR REPLACE FUNCTION public.ottoq_run_archive_stamp(p_run uuid, p_pack text DEFAULT 'robotaxi'::text, p_config jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_key_json jsonb; v_hash text; v_key jsonb;
BEGIN
  -- 0167: default to the canonical input projection. An explicit p_config still
  -- wins, so a caller can key a run by a configuration the run row cannot express.
  v_key_json := COALESCE(p_config, public.ottoq_run_config_key(p_run));
  v_hash     := md5(v_key_json::text);

  UPDATE ottoq_run_archives
     SET pack_id = p_pack, config_hash = v_hash, config_key = v_key_json,
         engine_hash = COALESCE(engine_hash, public.ottoq_engine_hash())
   WHERE sim_run_id = p_run;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'run % is not archived; archive it first (no parallel table)', p_run;
  END IF;

  SELECT jsonb_build_object('sim_run_id', p_run, 'policy_name', a.policy,
                            'pack_id', a.pack_id, 'scenario_seed', a.random_seed,
                            'config_hash', a.config_hash, 'engine_hash', a.engine_hash)
    INTO v_key FROM ottoq_run_archives a WHERE a.sim_run_id = p_run;
  RETURN v_key;
END;
$function$;

-- Backfill config_key/config_hash so the archive is self-consistent under one
-- formula. engine_hash stays NULL for these. Caveat, stated rather than hidden:
-- a run whose run-scoped ottoq_policy_params rows have since been purged will
-- resolve those params to depot/global today, so its backfilled key describes
-- the run's configuration as the surviving evidence reports it.
UPDATE public.ottoq_run_archives a
   SET config_key  = public.ottoq_run_config_key(a.sim_run_id),
       config_hash = public.ottoq_run_config_hash(a.sim_run_id)
 WHERE EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = a.sim_run_id);

-- --------------------------------------------- 4. time to service, physically

CREATE OR REPLACE VIEW public.ottoq_kpi_p95_time_to_service AS
WITH pairs AS (
  SELECT d.sim_run_id, d.vehicle_id, d.actual_return_at,
         (SELECT min(l.actual_start_sim)
            FROM ottoq_itinerary_legs l
           WHERE l.sim_run_id = d.sim_run_id
             AND l.vehicle_id = d.vehicle_id
             AND l.leg_type NOT IN ('taxi','stage')   -- moves and parking are not service
             AND l.actual_start_sim IS NOT NULL
             AND l.actual_start_sim >= d.actual_return_at) AS first_op_active_at
    FROM ottoq_vehicle_dispatches d
   WHERE d.actual_return_at IS NOT NULL
)
-- Column ORDER is fixed by the pre-0167 view: CREATE OR REPLACE VIEW may append
-- columns but may not rename or reorder them. New measures go on the end.
SELECT sim_run_id,
       round(percentile_cont(0.95) WITHIN GROUP (
         ORDER BY EXTRACT(epoch FROM first_op_active_at - actual_return_at)/60.0)::numeric, 1)
         AS p95_time_to_service_min,
       count(*) FILTER (WHERE first_op_active_at IS NOT NULL) AS returns_measured,
       count(*) FILTER (WHERE first_op_active_at IS NULL)     AS returns_unserved,
       round(percentile_cont(0.50) WITHIN GROUP (
         ORDER BY EXTRACT(epoch FROM first_op_active_at - actual_return_at)/60.0)::numeric, 1)
         AS p50_time_to_service_min,
       round(max(EXTRACT(epoch FROM first_op_active_at - actual_return_at)/60.0)::numeric, 1)
         AS max_time_to_service_min
  FROM pairs
 GROUP BY sim_run_id;

COMMENT ON VIEW public.ottoq_kpi_p95_time_to_service IS
  'CLAUDE.md 2.9 KPI 5: recall-complete -> first op ACTIVE. Measures ottoq_itinerary_legs.actual_start_sim (the physical start), never lower(booking.during) (the calendar claim), which made this KPI structurally zero before 0167.';

-- --------------------------------------------------- 5. the five, told honestly

CREATE OR REPLACE FUNCTION public.ottoq_kpi_five(p_run uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object(
    'sim_run_id', p_run,
    'run_key', (SELECT jsonb_build_object(
                  'policy_name', a.policy, 'pack_id', a.pack_id,
                  'scenario_seed', a.random_seed, 'config_hash', a.config_hash,
                  'engine_hash', a.engine_hash, 'scenario', a.scenario)
                  FROM public.ottoq_run_archives a WHERE a.sim_run_id = p_run),
    'asset_hours_available_per_day',
      COALESCE((SELECT jsonb_object_agg(day, asset_hours_available ORDER BY day)
         FROM public.ottoq_kpi_asset_hours_available_per_day WHERE sim_run_id = p_run), '{}'::jsonb),
    'service_point_turns_per_point_per_day',
      COALESCE((SELECT jsonb_object_agg(day, turns_per_point_per_day ORDER BY day)
         FROM public.ottoq_kpi_service_point_turns WHERE sim_run_id = p_run), '{}'::jsonb),
    'peak_site_kw',
      (SELECT peak_site_kw_15min FROM public.ottoq_kpi_peak_site_kw WHERE sim_run_id = p_run),
    'peak_site_kw_demand',   /* 0138 */
      (SELECT peak_site_kw_demand_15min FROM public.ottoq_kpi_peak_site_kw_demand WHERE sim_run_id = p_run),
    'touch_events_per_turn',
      (SELECT touch_events_per_turn FROM public.ottoq_kpi_touch_events_per_turn WHERE sim_run_id = p_run),
    'p95_time_to_service_min',
      (SELECT p95_time_to_service_min FROM public.ottoq_kpi_p95_time_to_service WHERE sim_run_id = p_run),
    'p50_time_to_service_min',   /* 0167 */
      (SELECT p50_time_to_service_min FROM public.ottoq_kpi_p95_time_to_service WHERE sim_run_id = p_run),
    'returns_unserved',          /* 0167 */
      (SELECT returns_unserved FROM public.ottoq_kpi_p95_time_to_service WHERE sim_run_id = p_run),
    'provenance', jsonb_build_object(
      'reproducible_from_run_id', jsonb_build_array(
         'asset_hours_available_per_day', 'service_point_turns_per_point_per_day',
         'peak_site_kw', 'peak_site_kw_demand', 'touch_events_per_turn',
         'p95_time_to_service_min', 'p50_time_to_service_min', 'returns_unserved'),
      'not_reproducible', '[]'::jsonb,
      'why', 'peak_site_kw was carried as not-reproducible on the argument that it is grid import net of a twin battery that was not deterministic. Measured over the last 40 certified determinism pairs at 0167: peak_site_kw equal in 40, differing in 0; peak_site_kw_demand equal in 40, differing in 0. The old text was stale and is retired. Re-run that count before quoting this line.',
      'evidence', 'db/checks/0077; count re-runnable from ottoq_kpi_peak_site_kw joined to the arm pairs in ottoq_sim_runs.validation_notes',
      'run_key_note', 'config_hash keys the CONFIGURATION (ottoq_run_config_key: scenario, seed, policy, depot, horizon, clock, effective params). engine_hash keys the ENGINE (applied migration set). Two runs sharing config_hash but not engine_hash are the same experiment on different code. NULL engine_hash means archived before 0167.')
  );
$function$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_run_key_hashed_the_outcome_and_the_wait_was_always_zero', false,
        'Instrument/KPI only. config_hash moves from md5(outcome payload) to md5(canonical input projection) and gains engine_hash; p95_time_to_service moves from the calendar claim to the physical op start; ottoq_kpi_five provenance corrected against a 40-pair count. No engine function is touched.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
