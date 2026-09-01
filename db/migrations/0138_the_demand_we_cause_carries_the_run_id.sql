-- migration-version: 20260901003000
-- migration-name:    the_demand_we_cause_carries_the_run_id
-- 0138 -- splitting peak_site_kw into the number we can warrant and the number we cannot.
--
-- THE PROBLEM, from db/checks/0058. On four post-0137 pairs that all PASSED, on two columns both
-- GREEN at streak 2, peak_site_kw still differed between the two arms just certified identical:
--     busy_day  424242/12t  579.2 == 579.2   (twice)
--     normal_day 171717/12t 528.4 vs 532.2   and   528.7 vs 528.3
-- Measured on the 23:25 pair: EVERY load component -- total_ev_charging_kw, building_load_kw,
-- lighting_load_kw, solar_generation_kw -- is byte-identical at all twelve timestamps. ONLY
-- bess_output_kw differs. grid_import_kw = load - bess, so the KPI inherits the battery's wobble
-- and nothing else.
--
-- THE DIAGNOSIS THAT MATTERS. This is not a sixth residue defect. Rounds 3-5 already closed five
-- (0133, 0134, 0135, 0136, 0137). What remains is a CATEGORY ERROR in the metric itself:
-- peak_site_kw is defined over grid import, which is net of a battery that -- since 0136 put the
-- publication boundary back where CLAUDE.md 2.5 always specified it -- we do not command, do not
-- actuate, and only publish a forward schedule to. We were warranting a number whose value
-- depends on someone else's asset responding to a plan we merely suggest.
--
-- THE FIX. Two numbers, because there are genuinely two facts:
--   peak_site_kw          UNCHANGED. 15-min rolling max of grid_import_kw. This is what demand
--                         billing actually charges on, so it stays exactly as CLAUDE.md 2.9
--                         defines it and every existing consumer keeps its meaning. It is
--                         informational: its value depends on site storage behaviour.
--   peak_site_kw_demand   NEW. The identical 15-min rolling computation over the load OUR
--                         SCHEDULE CAUSES: ev + building + lighting - solar. Site net demand
--                         BEFORE storage. Every term is proven byte-identical across certified
--                         arms, so this number regenerates from its run ID.
-- The battery is the only excluded term, and it is excluded for exactly one reason: it is a site
-- asset we publish to rather than command.
--
-- WHY THE COMPONENTS AND NOT (grid_import + bess). Algebraically identical -- verified across 168
-- rows of the eight most recent certified runs, 142 composing to the cent and the other 26 within
-- 0.10 kW, which is per-column storage rounding at 1 dp, not disagreement. Computed from the
-- components the expression never touches bess_output_kw at all, so the non-deterministic term
-- cannot leak in through arithmetic. A metric that must be reproducible should not be defined in
-- terms of the one column that is not.
--
-- THE PROVENANCE BLOCK. "No number ships without a run ID" has until now been a rule applied by
-- whoever read the output. ottoq_kpi_five now DECLARES IT IN THE PAYLOAD: which figures are
-- reproducible from the run key and which are not, and why. A reader who does not know this
-- file's contents can still tell which numbers are warrantable. When the twin's battery is made
-- deterministic, the migration that does it moves peak_site_kw into the reproducible list -- the
-- declaration is a statement of fact about today, and it is meant to be updated, not to rot.
--
-- Blast radius, measured: peak_site_kw is referenced by ONE view (ottoq_kpi_peak_site_kw, left
-- untouched) and ONE function (ottoq_kpi_five). The two other functions that match the string --
-- ottoq_tick_invariance_reset_fleet and ottoq.ottoq_world_fingerprint -- match on the unrelated
-- column peak_demand_kw_15min, not on this KPI. Adding keys to a jsonb payload is backward
-- compatible; no existing key changes name, meaning or value.
--
-- Pre-image pin, read live 2026-09-01:
--   public.ottoq_kpi_five  943bccfa6ac2e103791116827b74c2a6

DO $pin$
DECLARE v_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_kpi_five' AND p.prokind = 'f';
  IF v_md5 <> '943bccfa6ac2e103791116827b74c2a6' THEN
    RAISE EXCEPTION '0138 abort: ottoq_kpi_five drifted (md5 %)', v_md5;
  END IF;
END
$pin$;

-- Part A. The demand we cause: identical rolling shape to ottoq_kpi_peak_site_kw, over the load
-- our schedule creates rather than over grid import net of a battery we do not command.
CREATE OR REPLACE VIEW public.ottoq_kpi_peak_site_kw_demand AS
  WITH rolling AS (
    SELECT s.sim_run_id,
           s."timestamp",
           avg( COALESCE(s.total_ev_charging_kw,0)
              + COALESCE(s.building_load_kw,0)
              + COALESCE(s.lighting_load_kw,0)
              - COALESCE(s.solar_generation_kw,0) )
             OVER (PARTITION BY s.sim_run_id, s.depot_id
                   ORDER BY s."timestamp"
                   RANGE BETWEEN '00:15:00'::interval PRECEDING AND CURRENT ROW) AS kw_15min
      FROM public.site_energy_snapshots s
  )
  SELECT sim_run_id,
         round(max(kw_15min), 1) AS peak_site_kw_demand_15min,
         count(*)                AS snapshots
    FROM rolling
   GROUP BY sim_run_id;

COMMENT ON VIEW public.ottoq_kpi_peak_site_kw_demand IS
  '0138: site net demand BEFORE storage -- ev + building + lighting - solar, 15-min rolling, '
  'max per run. Every term is proven byte-identical across certified pair arms, so this figure '
  'regenerates from its run ID. Its sibling ottoq_kpi_peak_site_kw measures grid import NET of '
  'site-owned storage: the true demand-billing basis, but dependent on an asset OTTO-Q publishes '
  'a schedule to and never commands. See db/checks/0058.';

-- Part B. Report both, and say in the payload which one carries a run ID.
CREATE OR REPLACE FUNCTION public.ottoq_kpi_five(p_run uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object(
    'sim_run_id', p_run,
    'run_key', (SELECT jsonb_build_object(
                  'policy_name', a.policy, 'pack_id', a.pack_id,
                  'scenario_seed', a.random_seed, 'config_hash', a.config_hash,
                  'scenario', a.scenario)
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
    /* 0138: the credibility rule, stated in the payload instead of assumed by the reader. */
    'provenance', jsonb_build_object(
      'reproducible_from_run_id', jsonb_build_array(
         'asset_hours_available_per_day', 'service_point_turns_per_point_per_day',
         'peak_site_kw_demand', 'touch_events_per_turn', 'p95_time_to_service_min'),
      'not_reproducible', jsonb_build_array('peak_site_kw'),
      'why', 'peak_site_kw is grid import NET of site-owned storage. OTTO-Q publishes a forward '
             'demand schedule to that storage and never commands it, and the twin battery it '
             'models is not yet deterministic, so two certified-identical arms can differ on '
             'this figure. peak_site_kw_demand measures the same window over the load the '
             'schedule causes and does regenerate. See db/checks/0058.',
      'evidence', 'db/checks/0058')
  );
$function$;

-- Post-condition: both figures present, the old one unchanged in name and source, the new one
-- wired to the new view, and the provenance block telling the truth about which is which.
DO $verify$
DECLARE v_src text; v_code text;
BEGIN
  IF to_regclass('public.ottoq_kpi_peak_site_kw_demand') IS NULL THEN
    RAISE EXCEPTION '0138 abort: demand view missing';
  END IF;
  IF to_regclass('public.ottoq_kpi_peak_site_kw') IS NULL THEN
    RAISE EXCEPTION '0138 abort: the billing view was dropped, not preserved';
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_kpi_five' AND p.prokind = 'f';
  IF v_src NOT LIKE '%/* 0138 */%' THEN RAISE EXCEPTION '0138 abort: marker missing'; END IF;

  /* Comments stripped before symbol assertions -- the 0136/0137 lesson: a well-documented
     migration is exactly the one whose prose contains the strings its own checks look for. */
  v_code := regexp_replace(v_src, '/\*.*?\*/', '', 'g');
  IF v_code NOT LIKE '%ottoq_kpi_peak_site_kw_demand%' THEN
    RAISE EXCEPTION '0138 abort: kpi_five does not read the demand view';
  END IF;
  IF v_code NOT LIKE '%public.ottoq_kpi_peak_site_kw WHERE%' THEN
    RAISE EXCEPTION '0138 abort: kpi_five lost the original billing figure';
  END IF;
  IF v_code NOT LIKE '%not_reproducible%' THEN
    RAISE EXCEPTION '0138 abort: provenance block missing';
  END IF;

  -- The demand view must not reference the battery at all. That is the whole point.
  IF pg_get_viewdef('public.ottoq_kpi_peak_site_kw_demand'::regclass, true) ILIKE '%bess%' THEN
    RAISE EXCEPTION '0138 abort: the demand metric references storage';
  END IF;

  RAISE NOTICE '0138 verified: both figures reported, demand metric is storage-free, provenance declared.';
END
$verify$;
