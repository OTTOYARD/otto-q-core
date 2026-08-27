-- migration-version: 20260827200000
-- migration-name:    provenance_says_what_it_is
-- 0073 -- Two provenance fields stop lying. The SDR's data_source is derived from the depot's
-- feed mode instead of from whether a run id was passed; the twin stops labelling its own burn
-- model 'oem_telemetry'.
--
-- WHY THIS IS THE FIRST THING FIXED. CLAUDE.md 2.6 makes the ServiceDetailRecord the settlement
-- rail and the protocol claim -- "signed, tariffed, operator-attributed, asset-class-tagged".
-- A settlement record whose provenance field is wrong is worse than one with no provenance field,
-- because a reader trusts it. Both defects below are in the direction that mislabels REAL work as
-- simulated, or SIMULATED work as real. They are the two ends of the same lie.
--
-- ============================================================================================
-- DEFECT 1 -- every SDR the live path will ever write is stamped 'twin'.
--
-- 0043_schema_v2_service_objects.sql:366 decides provenance like this:
--
--     v_data_source text := CASE WHEN p_sim_run_id IS NULL THEN 'production' ELSE 'twin' END;
--
-- That reads as "no run id means real", which sounds right and is not, because THE ENGINE
-- CANNOT TICK WITHOUT A RUN. public.ottoq_cron_tick:12 returns early unless a running
-- ottoq_sim_runs row exists, and twin.ottoq_world_advance hard-requires
-- run_by='production_live' AND status='running'. So p_sim_run_id is non-null on every live tick,
-- and every SDR produced by live operation is stamped 'twin' -- including at a depot that has
-- already been switched to a real feed.
--
-- MEASURED ON PRODUCTION (gxdrc..., 2026-08-27), and the numbers make the point better than the
-- argument does:
--
--     data_source        production  51   twin  746
--     sim_run_id         null        51   set   746
--
-- The two distributions are IDENTICAL. `data_source` is not measuring provenance; it is
-- restating whether a run id was passed, in a different vocabulary. It carries no independent
-- information whatsoever, which is exactly what makes it dangerous -- it looks like evidence.
--
-- The 51 'production' rows are the C3 backfill (0043 sections 8.2/8.3 call ottoq_emit_sdr with
-- p_sim_run_id NULL over historical legs). They are correctly labelled by accident, not by
-- design: the same expression that mislabels live work happens to get the backfill right.
--
-- THE FIX reads the thing that actually knows: depots.feed_mode, 'sim' | 'external', per depot,
-- set by public.ottoq_ops_set_feed_mode. One depot is already 'external'. The emitter already
-- receives p_depot_id, so no signature change is needed; where it is null we resolve through the
-- vehicle's current or home depot. An unresolvable depot yields 'twin' -- the conservative
-- direction, because a record that wrongly claims to be simulated understates our evidence,
-- while one that wrongly claims to be production corrupts the settlement rail.
--
-- NOT BACKFILLED. The 746 existing 'twin' rows stay as they are. They were produced under
-- simulated physics and the label is correct for them; rewriting history to make a metric look
-- better is the opposite of what this file is for.
--
-- ============================================================================================
-- DEFECT 2 -- the twin writes its own arithmetic and calls it OEM telemetry.
--
-- twin.ottoq_sim_advance_deployed_telemetry:205 computes SoC from a burn model and writes
--
--     current_soc_source = 'oem_telemetry'
--
-- on a value no vehicle reported. 216 of 221 vehicles currently carry that label. A reader --
-- ours, an auditor's, or a model trained on this table -- cannot separate a real reading from an
-- invented one, which is precisely the separation the column exists to record.
--
-- The schema already had the right word and nobody used it. The CHECK constraint
-- vehicles_current_soc_source_check permits ('oem_telemetry','ocpp_meter','manual','estimated'),
-- and a burn model's output IS an estimate. So this is a one-word change with no constraint
-- change, no new vocabulary, and no migration of existing rows.
--
-- NOT BACKFILLED, for the same reason as above: those 216 rows were written by the burn model
-- and are about to be overwritten by the next tick anyway.
--
-- ============================================================================================
-- MECHANISM. Same self-verifying in-place patch as 0054-0072: anchor pre-verified read-only as
-- occurring exactly once, replacement applied by string substitution on pg_get_functiondef, and
-- a post-condition that RAISEs if the anchor survives or the replacement is absent.
--
-- Pre-image pins, read from production 2026-08-27:
--   public.ottoq_emit_sdr                          ab3903d4ffc9f274ba903dcd1e88ade9
--   twin.ottoq_sim_advance_deployed_telemetry      465ab3125fa2dbf9183fc31ff9f43573
-- Anchors pre-verified read-only: exactly one occurrence each, and zero cross-contamination
-- (the SDR anchor appears 0 times in the telemetry function and vice versa).

DO $do$
DECLARE
  v_oid oid; v_src text; v_new text; v_cnt int;

  v_sdr_old text := E'CASE WHEN p_sim_run_id IS NULL THEN ''production'' ELSE ''twin'' END';
  --: Reads the depot's declared feed mode. p_depot_id when the caller knows it, otherwise the
  --: vehicle's current depot, otherwise its home depot. Unresolvable => 'twin' (conservative).
  v_sdr_new text := E'COALESCE((SELECT CASE WHEN d.feed_mode = ''external'' THEN ''production'' ELSE ''twin'' END'
                  || E' FROM public.depots d WHERE d.id = COALESCE(p_depot_id,'
                  || E' (SELECT COALESCE(v.current_depot_id, v.home_depot_id) FROM public.vehicles v WHERE v.id = p_vehicle_id))), ''twin'')';

  v_soc_old text := E'current_soc_source = ''oem_telemetry''';
  --: 'estimated' is already permitted by vehicles_current_soc_source_check. A burn model's
  --: output is an estimate; saying so costs nothing and makes the column mean something.
  v_soc_new text := E'current_soc_source = ''estimated''';
BEGIN
  -- ---------- DEFECT 1: public.ottoq_emit_sdr ----------
  SELECT p.oid INTO STRICT v_oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_emit_sdr';

  v_src := pg_get_functiondef(v_oid);

  v_cnt := (length(v_src) - length(replace(v_src, v_sdr_old, ''))) / length(v_sdr_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0073 abort: ottoq_emit_sdr anchor found % times, expected exactly 1', v_cnt;
  END IF;

  v_new := replace(v_src, v_sdr_old, v_sdr_new);
  EXECUTE v_new;

  v_src := pg_get_functiondef(v_oid);
  IF position(v_sdr_old in v_src) > 0 THEN
    RAISE EXCEPTION '0073 abort: ottoq_emit_sdr still carries the run-id provenance expression';
  END IF;
  IF position('d.feed_mode' in v_src) = 0 THEN
    RAISE EXCEPTION '0073 abort: ottoq_emit_sdr does not read depots.feed_mode after patch';
  END IF;

  -- ---------- DEFECT 2: twin.ottoq_sim_advance_deployed_telemetry ----------
  SELECT p.oid INTO STRICT v_oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_deployed_telemetry';

  v_src := pg_get_functiondef(v_oid);

  v_cnt := (length(v_src) - length(replace(v_src, v_soc_old, ''))) / length(v_soc_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0073 abort: deployed_telemetry anchor found % times, expected exactly 1', v_cnt;
  END IF;

  v_new := replace(v_src, v_soc_old, v_soc_new);
  EXECUTE v_new;

  v_src := pg_get_functiondef(v_oid);
  IF position(v_soc_old in v_src) > 0 THEN
    RAISE EXCEPTION '0073 abort: the twin still labels its burn model oem_telemetry';
  END IF;
  IF position(v_soc_new in v_src) = 0 THEN
    RAISE EXCEPTION '0073 abort: deployed_telemetry does not carry the estimated label after patch';
  END IF;

  RAISE NOTICE '0073 applied: SDR provenance reads depots.feed_mode; twin SoC labelled estimated.';
END
$do$;

-- ============================================================================================
-- VERIFICATION -- run after apply. Both must hold.
--
--   -- 1. A depot on a real feed now produces 'production' records; a sim depot still 'twin'.
--   --    (Nothing to assert until the next completion at each depot; this is the query to run.)
--   SELECT d.feed_mode, s.data_source, count(*)
--     FROM public.ottoq_service_detail_records s
--     JOIN public.depots d ON d.id = s.depot_id
--    WHERE s.created_at > now() - interval '1 day'
--    GROUP BY 1,2 ORDER BY 1,2;
--
--   -- 2. No vehicle claims OEM telemetry it never received. After one tick this should be
--   --    'estimated' for every twin-driven vehicle.
--   SELECT current_soc_source, count(*) FROM public.vehicles GROUP BY 1 ORDER BY 1;
--
-- WHAT WOULD PROVE THIS WRONG: an SDR stamped 'production' at a depot whose feed_mode is 'sim'.
-- That is the failure this migration must never introduce, and it is why the unresolvable-depot
-- fallback is 'twin' rather than 'production'.
